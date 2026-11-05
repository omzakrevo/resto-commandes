# Resto Commandes — commandes, cuisine et livraisons

Tout est géré depuis GitHub. La base de données est ton **Supabase auto-hébergé sur le VPS**.

| Pièce | Pour qui | Où |
|---|---|---|
| Page de commande | Les clients | GitHub Pages : `https://<compte>.github.io/<dépôt>/` |
| App web tablette / livreur | Le restaurant, les livreurs | GitHub Pages : `…/<dépôt>/app/` |
| APK Android (même app) | Tablette + téléphones livreurs | GitHub › Releases › `latest` |
| Base de données | — | Supabase sur le VPS (`supabase/schema.sql`) |

L'app tablette/livreur existe en **deux formes** : l'APK à installer, ou la version web à ouvrir
dans Chrome, sans rien installer. Le compte utilisé pour se connecter décide de l'écran affiché.

## Le parcours d'une commande

```
Client (lien) ─► NOUVELLE ─► EN PRÉPARATION ─► PRÊTE ─► EN LIVRAISON ─► LIVRÉE
                 (sonnerie)   tablette          tablette  tablette choisit  livreur
                                                          le livreur        (ou ÉCHEC + motif)
Sur place : « Encaisser et valider » → SERVIE directement.
À emporter : … → PRÊTE → « Remise au client » → SERVIE.
```

L'onglet **Bilan** de la tablette montre, pour la journée : le montant encaissé, les commandes livrées,
les échecs, les commandes pas terminées, l'argent à récupérer chez chaque livreur et les plats vendus.

## Mise en route

### 1. Base de données (Supabase sur le VPS)
1. Ouvrir Supabase Studio sur le VPS › **SQL Editor** › coller `supabase/schema.sql` › Run.
   (Autre option : le workflow **Installer / mettre à jour la base** avec le secret `DATABASE_URL`.)
2. **Authentication › Users › Add user** : créer un compte par appareil, avec *Auto confirm* coché.
3. Donner un rôle à chaque compte :
   ```sql
   insert into public.profils (id, nom, role)
   select id, 'Tablette', 'admin' from auth.users where email = 'tablette@monresto.bf';

   insert into public.profils (id, nom, telephone, role)
   select id, 'Moussa', '70000000', 'livreur' from auth.users where email = 'moussa@monresto.bf';
   ```
   Rôles : `admin` (tablette + menu), `caisse` (tablette sans le menu), `livreur`.

> **HTTPS obligatoire.** GitHub Pages est en `https://`. Les navigateurs et Android bloquent donc
> un Supabase en `http://IP:8000`. Il faut un sous-domaine avec certificat, par exemple
> `https://supabase.mondomaine.com`, derrière Nginx ou Caddy avec Let's Encrypt, qui pointe vers Kong (port 8000).

### 2. Variables GitHub
Dépôt › **Settings › Secrets and variables › Actions › Variables** :
- `SUPABASE_URL` : l'adresse HTTPS de ton Supabase
- `SUPABASE_KEY` : la valeur `ANON_KEY` du fichier `.env` de ton Supabase (jamais la `SERVICE_ROLE_KEY`)

Ensuite, dans **Settings › Pages**, choisir Source = **GitHub Actions**.

### 3. Compiler
Chaque `push` sur `main` (ou **Actions › Compiler et publier › Run workflow**) :
analyse le code → publie la page client + l'app web sur Pages → publie `resto-commandes.apk` dans Releases.

Sans les variables, le site est publié en **mode démonstration** (faux menu), ce qui permet de le montrer au restaurant.

## Travailler en local
```bash
cd app
flutter run --dart-define=SUPABASE_URL=https://supabase.mondomaine.com --dart-define=SUPABASE_KEY=xxx
```

## À savoir
- Les prix sont recalculés par la base : un client ne peut pas les modifier depuis le lien.
- Le public ne peut ni lire ni modifier les commandes. Un livreur ne voit que les siennes.
- L'interrupteur **Ouvert/Fermé** (onglet Menu) bloque les commandes en ligne.
- La journée commence à 6 h (`heureDebutService` dans `app/lib/config.dart`).
- Paiement à la livraison ou au retrait. Le montant encaissé correspond aux commandes *Livrées* et *Servies*.
- L'APK est signé avec la clé de debug Flutter. C'est suffisant pour l'installer directement, mais il faudra une clé dédiée pour le Play Store.
- Domaine perso pour Pages : si tu en ajoutes un, retire `/<dépôt>` du `--base-href` dans le workflow.
