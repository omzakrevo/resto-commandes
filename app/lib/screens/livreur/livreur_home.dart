import 'dart:async';

import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../widgets/commun.dart';

/// Écran du livreur : ses commandes à livrer, puis "Livrée" ou "Échec".
class LivreurHome extends StatefulWidget {
  final Profil profil;
  const LivreurHome({super.key, required this.profil});

  @override
  State<LivreurHome> createState() => _LivreurHomeState();
}

class _LivreurHomeState extends State<LivreurHome> {
  StreamSubscription<List<Commande>>? _abonnement;
  List<Commande> _commandes = [];
  final Set<String> _vues = {};
  bool _premier = true;
  bool _horsLigne = false;
  bool _charge = false;
  final Set<String> _envoiEnCours = {};
  final _sonnerie = Sonnerie();

  @override
  void initState() {
    super.initState();
    _ecouter();
  }

  @override
  void dispose() {
    _abonnement?.cancel();
    _sonnerie.dispose();
    super.dispose();
  }

  void _ecouter() {
    _abonnement?.cancel();
    _abonnement = Api.mesCommandes(widget.profil.id).listen((liste) {
      final nouvelles =
          liste.where((c) => c.statut == 'en_livraison' && !_vues.contains(c.id)).toList();
      if (!_premier && nouvelles.isNotEmpty) {
        _sonnerie.jouer();
        if (mounted) message(context, '🛵 Nouvelle livraison : #${nouvelles.last.numero}');
      }
      _vues.addAll(liste.where((c) => c.statut == 'en_livraison').map((c) => c.id));
      _premier = false;
      if (mounted) {
        setState(() {
          _commandes = liste;
          _horsLigne = false;
          _charge = true;
        });
      }
    }, onError: (_) {
      if (mounted) setState(() => _horsLigne = true);
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) _ecouter();
      });
    });
  }

  Future<void> _maj(Commande c, String statut, {String? motif}) async {
    setState(() => _envoiEnCours.add(c.id));
    try {
      await Api.majLivraison(c.id, statut, motif: motif);
      if (mounted) {
        message(context, statut == 'livree' ? '✅ #${c.numero} livrée' : '#${c.numero} signalée en échec');
      }
    } catch (e) {
      if (mounted) message(context, texteErreur(e), erreur: true);
    } finally {
      if (mounted) setState(() => _envoiEnCours.remove(c.id));
    }
  }

  Future<void> _livree(Commande c) async {
    if (await confirmer(context, 'Commande #${c.numero} livrée ?',
        'Avez-vous bien remis la commande et encaissé ${fcfa(c.total)} ?', ok: 'Oui, livrée')) {
      await _maj(c, 'livree');
    }
  }

  Future<void> _echec(Commande c) async {
    final motif = await demanderMotif(context);
    if (motif != null) await _maj(c, 'echec', motif: motif);
  }

  Widget _carte(Commande c) {
    final t = Theme.of(context).textTheme;
    final envoi = _envoiEnCours.contains(c.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('#${c.numero}', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            Text(heure(c.createdAt)),
          ]),
          const SizedBox(height: 6),
          Text(c.clientNom ?? 'Client', style: t.titleMedium),
          if (c.adresse != null) Text(c.adresse!),
          if (c.lat != null) const Text('📍 Le client a partagé sa position GPS'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            if (c.clientTel != null)
              OutlinedButton.icon(
                onPressed: () => appeler(c.clientTel!),
                icon: const Icon(Icons.call),
                label: Text(c.clientTel!),
              ),
            if (c.adresse != null || c.lat != null)
              OutlinedButton.icon(
                onPressed: () => ouvrirCarte(c),
                icon: const Icon(Icons.map),
                label: const Text('Itinéraire'),
              ),
          ]),
          const Divider(height: 20),
          for (final a in c.articles) Text('${a.qte} × ${a.nom}'),
          if (c.note != null) Text('📝 ${c.note}', style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          Text('À encaisser : ${fcfa(c.total)}',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.green.shade800)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: envoi ? null : () => _livree(c),
                icon: const Icon(Icons.check_circle),
                label: const Text('Livrée'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: envoi ? null : () => _echec(c),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
              child: const Text('Échec'),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final debut = debutService();
    final aLivrer = _commandes.where((c) => c.statut == 'en_livraison').toList();
    final faites = _commandes
        .where((c) => (c.statut == 'livree' || c.statut == 'echec') && !c.createdAt.isBefore(debut))
        .toList()
      ..sort((a, b) => (b.termineeAt ?? b.createdAt).compareTo(a.termineeAt ?? a.createdAt));
    final encaisse =
        faites.where((c) => c.statut == 'livree').fold<int>(0, (s, c) => s + c.total);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('🛵 ${widget.profil.nom}'),
          actions: [
            if (_horsLigne) const Icon(Icons.wifi_off, color: Colors.red),
            const BoutonDeconnexion(),
          ],
          bottom: TabBar(tabs: [
            Tab(text: 'À livrer (${aLivrer.length})'),
            Tab(text: 'Aujourd’hui (${faites.length})'),
          ]),
        ),
        body: !_charge
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [
                aLivrer.isEmpty
                    ? const Center(child: Text('Aucune livraison en attente.\nVous serez alerté dès qu’une commande vous est confiée.', textAlign: TextAlign.center))
                    : ListView(padding: const EdgeInsets.all(12), children: [for (final c in aLivrer) _carte(c)]),
                ListView(padding: const EdgeInsets.all(12), children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.payments, color: Colors.green),
                      title: Text('Encaissé aujourd’hui : ${fcfa(encaisse)}'),
                      subtitle: Text('${faites.where((c) => c.statut == 'livree').length} livrée(s) · '
                          '${faites.where((c) => c.statut == 'echec').length} échec(s)'),
                    ),
                  ),
                  for (final c in faites)
                    ListTile(
                      leading: Text('#${c.numero}', style: Theme.of(context).textTheme.titleMedium),
                      title: Text('${c.clientNom ?? 'Client'} · ${fcfa(c.total)}'),
                      subtitle: Text([
                        heure(c.termineeAt ?? c.createdAt),
                        if (c.motifEchec != null) c.motifEchec!,
                      ].join(' · ')),
                      trailing: PuceStatut(c.statut),
                    ),
                ]),
              ]),
      ),
    );
  }
}
