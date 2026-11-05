import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api.dart';
import '../../models.dart';
import '../../widgets/commun.dart';

/// Bilan d'une journée de service : qui a été livré, qui ne l'a pas été, combien encaissé.
class BilanScreen extends StatefulWidget {
  const BilanScreen({super.key});

  @override
  State<BilanScreen> createState() => _BilanScreenState();
}

class _BilanScreenState extends State<BilanScreen> {
  DateTime _jour = debutService();
  late Future<(List<Commande>, Map<String, String>)> _future = _charger();

  Future<(List<Commande>, Map<String, String>)> _charger() async {
    final res = await Future.wait([
      Api.commandesEntre(_jour, _jour.add(const Duration(days: 1))),
      Api.livreurs(),
    ]);
    final commandes = res[0] as List<Commande>;
    final livreurs = {for (final l in res[1] as List<Profil>) l.id: l.nom};
    return (commandes, livreurs);
  }

  void _recharger() => setState(() => _future = _charger());

  Future<void> _choisirJour() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _jour,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (d != null) {
      _jour = DateTime(d.year, d.month, d.day, debutService().hour);
      _recharger();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bilan du ${DateFormat('EEEE d MMMM', 'fr_FR').format(_jour)}'),
        actions: [
          IconButton(onPressed: _choisirJour, icon: const Icon(Icons.calendar_month), tooltip: 'Autre jour'),
          IconButton(onPressed: _recharger, icon: const Icon(Icons.refresh), tooltip: 'Actualiser'),
        ],
      ),
      body: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text(texteErreur(snap.error!)));
          }
          final (commandes, livreurs) = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _recharger(),
            child: _contenu(commandes, livreurs),
          );
        },
      ),
    );
  }

  Widget _contenu(List<Commande> cs, Map<String, String> livreurs) {
    final t = Theme.of(context).textTheme;
    int nb(String s) => cs.where((c) => c.statut == s).length;
    final encaisses = cs.where((c) => statutsEncaisses.contains(c.statut));
    final ca = encaisses.fold<int>(0, (s, c) => s + c.total);
    final aSuivre = cs.where((c) => !c.terminee || c.statut == 'echec').toList();

    // Par livreur
    final parLivreur = <String, (int, int, int)>{}; // livrées, échecs, montant
    for (final c in cs.where((c) => c.livreurId != null)) {
      final v = parLivreur[c.livreurId!] ?? (0, 0, 0);
      parLivreur[c.livreurId!] = (
        v.$1 + (c.statut == 'livree' ? 1 : 0),
        v.$2 + (c.statut == 'echec' ? 1 : 0),
        v.$3 + (c.statut == 'livree' ? c.total : 0),
      );
    }

    // Plats vendus
    final plats = <String, int>{};
    for (final c in encaisses) {
      for (final a in c.articles) {
        plats[a.nom] = (plats[a.nom] ?? 0) + a.qte;
      }
    }
    final platsTries = plats.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    Widget tuile(String titre, String valeur, Color couleur, IconData icone) => SizedBox(
          width: 170,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icone, color: couleur),
                const SizedBox(height: 6),
                Text(valeur, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: couleur)),
                Text(titre),
              ]),
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          tuile('Encaissé', fcfa(ca), Colors.green.shade700, Icons.payments),
          tuile('Livrées', '${nb('livree')}', Colors.green, Icons.check_circle),
          tuile('Servies / emportées', '${nb('servie')}', Colors.teal, Icons.restaurant),
          tuile('Échecs livraison', '${nb('echec')}', Colors.red.shade800, Icons.cancel),
          tuile('Annulées', '${nb('annulee')}', Colors.grey, Icons.block),
          tuile('Pas terminées', '${cs.where((c) => !c.terminee).length}', Colors.orange.shade800,
              Icons.hourglass_bottom),
        ]),
        const SizedBox(height: 16),
        Text('À vérifier', style: t.titleMedium),
        Text('Commandes non terminées ou non livrées — à rappeler ou à régulariser.', style: t.bodySmall),
        const SizedBox(height: 6),
        if (aSuivre.isEmpty)
          const Card(child: ListTile(leading: Icon(Icons.verified, color: Colors.green), title: Text('Tout est en ordre 👍'))),
        for (final c in aSuivre)
          Card(
            child: ListTile(
              leading: Text('#${c.numero}', style: t.titleMedium),
              title: Text('${c.clientNom ?? 'Client'} · ${fcfa(c.total)}'),
              subtitle: Text([
                heure(c.createdAt),
                if (c.livreurId != null) '🛵 ${livreurs[c.livreurId] ?? 'livreur'}',
                if (c.motifEchec != null) 'Motif : ${c.motifEchec}',
              ].join(' · ')),
              trailing: PuceStatut(c.statut),
              onTap: c.clientTel == null ? null : () => appeler(c.clientTel!),
            ),
          ),
        if (parLivreur.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Par livreur (argent à récupérer)', style: t.titleMedium),
          Card(
            child: Column(children: [
              for (final e in parLivreur.entries)
                ListTile(
                  leading: const Icon(Icons.delivery_dining),
                  title: Text(livreurs[e.key] ?? 'Livreur'),
                  subtitle: Text('${e.value.$1} livrée(s) · ${e.value.$2} échec(s)'),
                  trailing: Text(fcfa(e.value.$3),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
            ]),
          ),
        ],
        if (platsTries.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Plats vendus', style: t.titleMedium),
          Card(
            child: Column(children: [
              for (final e in platsTries)
                ListTile(dense: true, title: Text(e.key), trailing: Text('× ${e.value}')),
            ]),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}
