import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'config.dart';

final _nf = NumberFormat.decimalPattern('fr');
String fcfa(num v) => '${_nf.format(v)} F';
String heure(DateTime d) => DateFormat.Hm('fr_FR').format(d);

/// Début de la journée de service qui contient [d] (par défaut : maintenant).
DateTime debutService([DateTime? d]) {
  final n = d ?? DateTime.now();
  var debut = DateTime(n.year, n.month, n.day, heureDebutService);
  if (n.isBefore(debut)) debut = debut.subtract(const Duration(days: 1));
  return debut;
}

class StatutInfo {
  final String label;
  final Color couleur;
  const StatutInfo(this.label, this.couleur);
}

const statuts = <String, StatutInfo>{
  'nouvelle': StatutInfo('Nouvelle', Color(0xFFDC2626)),
  'preparation': StatutInfo('En préparation', Color(0xFFEA580C)),
  'prete': StatutInfo('Prête', Color(0xFF2563EB)),
  'en_livraison': StatutInfo('En livraison', Color(0xFF7C3AED)),
  'livree': StatutInfo('Livrée', Color(0xFF16A34A)),
  'servie': StatutInfo('Servie / remise', Color(0xFF16A34A)),
  'echec': StatutInfo('Échec livraison', Color(0xFF991B1B)),
  'annulee': StatutInfo('Annulée', Color(0xFF6B7280)),
};

const statutsTermines = {'livree', 'servie', 'echec', 'annulee'};
const statutsEncaisses = {'livree', 'servie'};

const typesLabel = {
  'livraison': '🛵 Livraison',
  'emporter': '🥡 À emporter',
  'sur_place': '🍽️ Sur place',
};

class Profil {
  final String id;
  final String nom;
  final String? telephone;
  final String role;
  Profil.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        nom = m['nom'] as String,
        telephone = m['telephone'] as String?,
        role = m['role'] as String;
  bool get estAdmin => role == 'admin';
  bool get estLivreur => role == 'livreur';
}

class Reglages {
  String nomRestaurant;
  String? telephone;
  int fraisLivraison;
  bool ouvert;
  Reglages.fromMap(Map<String, dynamic> m)
      : nomRestaurant = m['nom_restaurant'] as String,
        telephone = m['telephone'] as String?,
        fraisLivraison = (m['frais_livraison'] as num).toInt(),
        ouvert = m['ouvert'] as bool;
}

class Plat {
  final String id;
  final String nom;
  final String? description;
  final int prix;
  final String? photoUrl;
  final bool disponible;
  final int ordre;
  Plat.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        nom = m['nom'] as String,
        description = m['description'] as String?,
        prix = (m['prix'] as num).toInt(),
        photoUrl = m['photo_url'] as String?,
        disponible = (m['disponible'] as bool?) ?? true,
        ordre = ((m['ordre'] as num?) ?? 0).toInt();
}

class Article {
  final String? platId;
  final String nom;
  final int prix;
  int qte;
  Article({this.platId, required this.nom, required this.prix, this.qte = 1});
  factory Article.fromMap(Map<String, dynamic> m) => Article(
        platId: m['plat_id'] as String?,
        nom: m['nom'] as String,
        prix: (m['prix'] as num).toInt(),
        qte: (m['qte'] as num).toInt(),
      );
  Map<String, dynamic> toMap() =>
      {'plat_id': platId, 'nom': nom, 'prix': prix, 'qte': qte};
  int get sousTotal => prix * qte;
}

class Commande {
  final String id;
  final int numero;
  final String codeSuivi;
  final String source;
  final String type;
  final String statut;
  final String? clientNom;
  final String? clientTel;
  final String? adresse;
  final double? lat;
  final double? lng;
  final String? note;
  final List<Article> articles;
  final int fraisLivraison;
  final int total;
  final String? livreurId;
  final String? motifEchec;
  final DateTime createdAt;
  final DateTime? termineeAt;

  Commande.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        numero = (m['numero'] as num).toInt(),
        codeSuivi = m['code_suivi'] as String,
        source = m['source'] as String,
        type = m['type'] as String,
        statut = m['statut'] as String,
        clientNom = m['client_nom'] as String?,
        clientTel = m['client_tel'] as String?,
        adresse = m['adresse'] as String?,
        lat = (m['lat'] as num?)?.toDouble(),
        lng = (m['lng'] as num?)?.toDouble(),
        note = m['note'] as String?,
        articles = ((m['articles'] as List?) ?? [])
            .map((a) => Article.fromMap(Map<String, dynamic>.from(a as Map)))
            .toList(),
        fraisLivraison = ((m['frais_livraison'] as num?) ?? 0).toInt(),
        total = ((m['total'] as num?) ?? 0).toInt(),
        livreurId = m['livreur_id'] as String?,
        motifEchec = m['motif_echec'] as String?,
        createdAt = DateTime.parse(m['created_at'] as String).toLocal(),
        termineeAt = m['terminee_at'] == null
            ? null
            : DateTime.parse(m['terminee_at'] as String).toLocal();

  bool get terminee => statutsTermines.contains(statut);
  StatutInfo get info => statuts[statut] ?? const StatutInfo('?', Colors.grey);
  int get minutesDepuis => DateTime.now().difference(createdAt).inMinutes;
}
