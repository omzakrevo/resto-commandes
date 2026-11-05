-- =====================================================================
--  RESTO COMMANDES — Base Supabase
--  À exécuter en entier dans Supabase > SQL Editor (une seule fois).
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. TABLES
-- ---------------------------------------------------------------------

-- Comptes du personnel (tablette = admin ou caisse, téléphone = livreur)
create table if not exists public.profils (
  id          uuid primary key references auth.users(id) on delete cascade,
  nom         text not null,
  telephone   text,
  role        text not null check (role in ('admin', 'caisse', 'livreur')),
  actif       boolean not null default true,
  created_at  timestamptz not null default now()
);

-- Réglages du restaurant (une seule ligne, id = 1)
create table if not exists public.reglages (
  id               int primary key default 1 check (id = 1),
  nom_restaurant   text not null default 'Shawarma',
  telephone        text,
  frais_livraison  int  not null default 0 check (frais_livraison >= 0),
  ouvert           boolean not null default true
);
insert into public.reglages (id) values (1) on conflict do nothing;

-- Menu
create table if not exists public.plats (
  id           uuid primary key default gen_random_uuid(),
  nom          text not null,
  description  text,
  prix         int  not null check (prix >= 0),
  photo_url    text,
  disponible   boolean not null default true,
  ordre        int  not null default 0,
  created_at   timestamptz not null default now()
);

-- Commandes (les articles sont copiés dans la commande : nom + prix du moment)
create table if not exists public.commandes (
  id               uuid primary key default gen_random_uuid(),
  numero           bigint generated always as identity,
  code_suivi       text not null unique
                     default upper(substr(md5(gen_random_uuid()::text), 1, 6)),
  source           text not null default 'en_ligne'
                     check (source in ('en_ligne', 'sur_place')),
  type             text not null
                     check (type in ('livraison', 'emporter', 'sur_place')),
  statut           text not null default 'nouvelle'
                     check (statut in ('nouvelle', 'preparation', 'prete',
                                       'en_livraison', 'livree', 'echec',
                                       'servie', 'annulee')),
  client_nom       text,
  client_tel       text,
  adresse          text,
  lat              double precision,
  lng              double precision,
  note             text,
  articles         jsonb not null default '[]'::jsonb,
  sous_total       int not null default 0,
  frais_livraison  int not null default 0,
  total            int not null default 0,
  livreur_id       uuid references public.profils(id),
  motif_echec      text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  terminee_at      timestamptz
);
create index if not exists commandes_created_idx on public.commandes (created_at desc);
create index if not exists commandes_livreur_idx on public.commandes (livreur_id);

-- ---------------------------------------------------------------------
-- 2. HORODATAGE AUTOMATIQUE
-- ---------------------------------------------------------------------
create or replace function public.maj_horodatage()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  if new.statut in ('livree', 'servie', 'echec', 'annulee')
     and (tg_op = 'INSERT' or old.statut is distinct from new.statut) then
    new.terminee_at := now();
  end if;
  return new;
end $$;

drop trigger if exists trg_commandes_maj on public.commandes;
create trigger trg_commandes_maj
  before insert or update on public.commandes
  for each row execute function public.maj_horodatage();

-- ---------------------------------------------------------------------
-- 3. SÉCURITÉ (RLS)
-- ---------------------------------------------------------------------
create or replace function public.mon_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.profils where id = auth.uid() and actif
$$;

alter table public.profils   enable row level security;
alter table public.reglages  enable row level security;
alter table public.plats     enable row level security;
alter table public.commandes enable row level security;

-- Profils : chacun voit le sien, le personnel voit tout le monde
drop policy if exists profils_lecture on public.profils;
create policy profils_lecture on public.profils for select to authenticated
  using (id = auth.uid() or public.mon_role() in ('admin', 'caisse'));

-- Réglages : lecture publique, modification par l'admin
drop policy if exists reglages_lecture on public.reglages;
create policy reglages_lecture on public.reglages for select to anon, authenticated
  using (true);
drop policy if exists reglages_admin on public.reglages;
create policy reglages_admin on public.reglages for update to authenticated
  using (public.mon_role() = 'admin') with check (public.mon_role() = 'admin');

-- Plats : le public voit les plats disponibles, l'admin gère le menu
drop policy if exists plats_public on public.plats;
create policy plats_public on public.plats for select to anon
  using (disponible);
drop policy if exists plats_personnel on public.plats;
create policy plats_personnel on public.plats for select to authenticated
  using (true);
drop policy if exists plats_admin on public.plats;
create policy plats_admin on public.plats for all to authenticated
  using (public.mon_role() = 'admin') with check (public.mon_role() = 'admin');

-- Commandes : la tablette gère tout ; le livreur voit seulement les siennes.
-- Le public n'a AUCUN accès direct : il passe par les fonctions ci-dessous.
drop policy if exists commandes_personnel on public.commandes;
create policy commandes_personnel on public.commandes for all to authenticated
  using (public.mon_role() in ('admin', 'caisse'))
  with check (public.mon_role() in ('admin', 'caisse'));
drop policy if exists commandes_livreur on public.commandes;
create policy commandes_livreur on public.commandes for select to authenticated
  using (livreur_id = auth.uid());

-- ---------------------------------------------------------------------
-- 4. FONCTIONS APPELÉES PAR LA PAGE CLIENT ET LE LIVREUR
-- ---------------------------------------------------------------------

-- Le client passe sa commande (les prix sont recalculés côté serveur)
create or replace function public.passer_commande(
  p_nom      text,
  p_tel      text,
  p_type     text,
  p_adresse  text,
  p_note     text,
  p_lat      double precision,
  p_lng      double precision,
  p_articles jsonb
) returns json
language plpgsql security definer set search_path = public as $$
declare
  r          public.reglages;
  p          public.plats;
  a          jsonb;
  q          int;
  v_articles jsonb := '[]'::jsonb;
  v_sous     int := 0;
  v_frais    int := 0;
  c          public.commandes;
begin
  select * into r from public.reglages where id = 1;
  if not r.ouvert then
    raise exception 'Le restaurant est fermé pour le moment.';
  end if;
  if coalesce(trim(p_nom), '') = ''
     or coalesce(length(regexp_replace(p_tel, '\D', '', 'g')), 0) < 8 then
    raise exception 'Nom et numéro de téléphone obligatoires.';
  end if;
  if p_type not in ('livraison', 'emporter') then
    raise exception 'Type de commande invalide.';
  end if;
  if p_type = 'livraison' and coalesce(trim(p_adresse), '') = '' and p_lat is null then
    raise exception 'Indiquez votre adresse ou partagez votre position.';
  end if;
  if jsonb_typeof(p_articles) is distinct from 'array' then
    raise exception 'Panier invalide.';
  end if;

  for a in select value from jsonb_array_elements(p_articles) loop
    q := least(greatest(coalesce((a->>'qte')::int, 0), 0), 50);
    continue when q = 0;
    select * into p from public.plats
      where id = (a->>'plat_id')::uuid and disponible;
    if not found then
      raise exception 'Un plat de votre panier n''est plus disponible.';
    end if;
    v_articles := v_articles || jsonb_build_array(jsonb_build_object(
      'plat_id', p.id, 'nom', p.nom, 'prix', p.prix, 'qte', q));
    v_sous := v_sous + p.prix * q;
  end loop;

  if jsonb_array_length(v_articles) = 0 then
    raise exception 'Votre panier est vide.';
  end if;
  if p_type = 'livraison' then
    v_frais := r.frais_livraison;
  end if;

  insert into public.commandes
    (source, type, client_nom, client_tel, adresse, lat, lng, note,
     articles, sous_total, frais_livraison, total)
  values
    ('en_ligne', p_type, trim(p_nom), trim(p_tel), nullif(trim(p_adresse), ''),
     p_lat, p_lng, nullif(trim(p_note), ''),
     v_articles, v_sous, v_frais, v_sous + v_frais)
  returning * into c;

  return json_build_object('numero', c.numero, 'code', c.code_suivi, 'total', c.total);
end $$;

-- Le client suit sa commande avec son code
create or replace function public.suivi_commande(p_code text)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'numero', numero, 'statut', statut, 'type', type,
    'total', total, 'created_at', created_at, 'motif', motif_echec)
  from public.commandes
  where code_suivi = upper(trim(p_code))
$$;

-- Le livreur valide (ou signale un échec) sur SES commandes uniquement
create or replace function public.maj_livraison(
  p_id uuid, p_statut text, p_motif text default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_statut not in ('livree', 'echec') then
    raise exception 'Statut invalide.';
  end if;
  update public.commandes
     set statut = p_statut,
         motif_echec = case when p_statut = 'echec' then p_motif else null end
   where id = p_id
     and livreur_id = auth.uid()
     and statut = 'en_livraison';
  if not found then
    raise exception 'Commande introuvable ou déjà traitée.';
  end if;
end $$;

revoke all on function public.passer_commande(text, text, text, text, text, double precision, double precision, jsonb) from public;
revoke all on function public.suivi_commande(text) from public;
revoke all on function public.maj_livraison(uuid, text, text) from public, anon;
grant execute on function public.passer_commande(text, text, text, text, text, double precision, double precision, jsonb) to anon, authenticated;
grant execute on function public.suivi_commande(text) to anon, authenticated;
grant execute on function public.maj_livraison(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 5. TEMPS RÉEL (la tablette et le livreur sont notifiés instantanément)
-- ---------------------------------------------------------------------
do $$
begin
  begin
    alter publication supabase_realtime add table public.commandes;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.plats;
  exception when duplicate_object then null;
  end;
end $$;

-- ---------------------------------------------------------------------
-- 6. PHOTOS DES PLATS (Storage)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('plats', 'plats', true)
on conflict (id) do nothing;

drop policy if exists "plats photos ajout" on storage.objects;
create policy "plats photos ajout" on storage.objects for insert to authenticated
  with check (bucket_id = 'plats' and public.mon_role() = 'admin');
drop policy if exists "plats photos modif" on storage.objects;
create policy "plats photos modif" on storage.objects for update to authenticated
  using (bucket_id = 'plats' and public.mon_role() = 'admin');
drop policy if exists "plats photos suppr" on storage.objects;
create policy "plats photos suppr" on storage.objects for delete to authenticated
  using (bucket_id = 'plats' and public.mon_role() = 'admin');

-- ---------------------------------------------------------------------
-- 7. DONNÉES DE DÉPART (à modifier ensuite depuis la tablette)
-- ---------------------------------------------------------------------
insert into public.plats (nom, description, prix, ordre)
select 'Shawarma poulet', 'Pain, poulet grillé, crudités, sauce maison', 1500, 1
where not exists (select 1 from public.plats);

-- =====================================================================
--  COMPTES DU PERSONNEL
--  1) Supabase > Authentication > Users > "Add user" (e-mail + mot de passe,
--     cocher "Auto confirm").
--  2) Puis exécuter, en adaptant e-mail / nom / rôle :
--
--  insert into public.profils (id, nom, role)
--  select id, 'Tablette caisse', 'admin' from auth.users where email = 'tablette@monresto.bf';
--
--  insert into public.profils (id, nom, telephone, role)
--  select id, 'Moussa', '70000000', 'livreur' from auth.users where email = 'moussa@monresto.bf';
-- =====================================================================
