import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

SupabaseClient get sb => Supabase.instance.client;

class Api {
  // ---------- Comptes ----------
  static Future<Profil?> monProfil() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return null;
    final r = await sb.from('profils').select().eq('id', uid).maybeSingle();
    return r == null ? null : Profil.fromMap(r);
  }

  static Future<List<Profil>> livreurs() async {
    final r = await sb
        .from('profils')
        .select()
        .eq('role', 'livreur')
        .eq('actif', true)
        .order('nom');
    return r.map(Profil.fromMap).toList();
  }

  // ---------- Réglages ----------
  static Future<Reglages> reglages() async =>
      Reglages.fromMap(await sb.from('reglages').select().eq('id', 1).single());

  static Future<void> enregistrerReglages(Reglages r) => sb.from('reglages').update({
        'nom_restaurant': r.nomRestaurant,
        'telephone': r.telephone,
        'frais_livraison': r.fraisLivraison,
        'ouvert': r.ouvert,
      }).eq('id', 1);

  // ---------- Menu ----------
  static Stream<List<Plat>> platsEnDirect() => sb
      .from('plats')
      .stream(primaryKey: ['id'])
      .order('ordre', ascending: true)
      .map((rows) => rows.map(Plat.fromMap).toList()
        ..sort((a, b) => a.ordre != b.ordre
            ? a.ordre.compareTo(b.ordre)
            : a.nom.compareTo(b.nom)));

  static Future<void> enregistrerPlat(String? id, Map<String, dynamic> data) async {
    if (id == null) {
      await sb.from('plats').insert(data);
    } else {
      await sb.from('plats').update(data).eq('id', id);
    }
  }

  static Future<void> supprimerPlat(String id) => sb.from('plats').delete().eq('id', id);

  static Future<String> envoyerPhoto(Uint8List octets, String extension) async {
    var ext = extension.toLowerCase();
    if (ext == 'jpeg') ext = 'jpg';
    final chemin = 'plat_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await sb.storage.from('plats').uploadBinary(
          chemin,
          octets,
          fileOptions: FileOptions(
            contentType: ext == 'jpg' ? 'image/jpeg' : 'image/$ext',
            upsert: true,
          ),
        );
    return sb.storage.from('plats').getPublicUrl(chemin);
  }

  // ---------- Commandes (tablette) ----------
  static Stream<List<Commande>> commandesDuService() => sb
      .from('commandes')
      .stream(primaryKey: ['id'])
      .gte('created_at', debutService().toUtc().toIso8601String())
      .order('created_at', ascending: true)
      .map((rows) => rows.map(Commande.fromMap).toList());

  static Future<void> changerStatut(String id, String statut, {String? motif}) =>
      sb.from('commandes').update({
        'statut': statut,
        if (statut == 'echec') 'motif_echec': motif,
      }).eq('id', id);

  static Future<void> confierAuLivreur(String id, String livreurId) => sb
      .from('commandes')
      .update({'livreur_id': livreurId, 'statut': 'en_livraison'}).eq('id', id);

  static Future<int> creerCommande({
    required String type,
    required String statut,
    required List<Article> articles,
    required int frais,
    String? nom,
    String? tel,
    String? adresse,
    String? note,
  }) async {
    final sous = articles.fold<int>(0, (s, a) => s + a.sousTotal);
    final r = await sb
        .from('commandes')
        .insert({
          'source': 'sur_place',
          'type': type,
          'statut': statut,
          'client_nom': nom,
          'client_tel': tel,
          'adresse': adresse,
          'note': note,
          'articles': articles.map((a) => a.toMap()).toList(),
          'sous_total': sous,
          'frais_livraison': frais,
          'total': sous + frais,
        })
        .select('numero')
        .single();
    return (r['numero'] as num).toInt();
  }

  static Future<List<Commande>> commandesEntre(DateTime debut, DateTime fin) async {
    final r = await sb
        .from('commandes')
        .select()
        .gte('created_at', debut.toUtc().toIso8601String())
        .lt('created_at', fin.toUtc().toIso8601String())
        .order('created_at');
    return r.map(Commande.fromMap).toList();
  }

  // ---------- Livreur ----------
  static Stream<List<Commande>> mesCommandes(String uid) => sb
      .from('commandes')
      .stream(primaryKey: ['id'])
      .eq('livreur_id', uid)
      .order('created_at', ascending: true)
      .map((rows) => rows.map(Commande.fromMap).toList());

  static Future<void> majLivraison(String id, String statut, {String? motif}) =>
      sb.rpc('maj_livraison', params: {'p_id': id, 'p_statut': statut, 'p_motif': motif});
}
