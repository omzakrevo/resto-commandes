import 'dart:async';

import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../widgets/commun.dart';

/// Écran principal de la tablette : les commandes du jour en colonnes.
class CommandesScreen extends StatefulWidget {
  const CommandesScreen({super.key});

  @override
  State<CommandesScreen> createState() => _CommandesScreenState();
}

class _CommandesScreenState extends State<CommandesScreen> {
  StreamSubscription<List<Commande>>? _abonnement;
  List<Commande> _commandes = [];
  final Set<String> _vues = {};
  bool _premierChargement = true;
  bool _horsLigne = false;
  Map<String, Profil> _livreurs = {};
  final _sonnerie = Sonnerie();
  Timer? _horloge;
  DateTime _debutService = debutService();

  static const _colonnes = <(String, Set<String>)>[
    ('Nouvelles', {'nouvelle'}),
    ('En préparation', {'preparation'}),
    ('Prêtes', {'prete'}),
    ('En livraison', {'en_livraison'}),
    ('Terminées', statutsTermines),
  ];

  @override
  void initState() {
    super.initState();
    _ecouter();
    _chargerLivreurs();
    // Rafraîchit les "il y a X min" et change de journée à l'heure de début de service.
    _horloge = Timer.periodic(const Duration(seconds: 30), (_) {
      final d = debutService();
      if (d != _debutService) {
        _debutService = d;
        _ecouter();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _abonnement?.cancel();
    _horloge?.cancel();
    _sonnerie.dispose();
    super.dispose();
  }

  void _ecouter() {
    _abonnement?.cancel();
    _abonnement = Api.commandesDuService().listen((liste) {
      final nouvelles = liste
          .where((c) => !_vues.contains(c.id) && c.statut == 'nouvelle' && c.source == 'en_ligne')
          .toList();
      if (!_premierChargement && nouvelles.isNotEmpty) {
        _sonnerie.jouer();
        if (mounted) {
          message(context,
              '🔔 Nouvelle commande #${nouvelles.last.numero} — ${nouvelles.last.clientNom ?? ''}');
        }
      }
      _vues.addAll(liste.map((c) => c.id));
      _premierChargement = false;
      if (mounted) {
        setState(() {
          _commandes = liste;
          _horsLigne = false;
        });
      }
    }, onError: (_) {
      if (mounted) setState(() => _horsLigne = true);
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) _ecouter();
      });
    });
  }

  Future<void> _chargerLivreurs() async {
    try {
      final l = await Api.livreurs();
      if (mounted) setState(() => _livreurs = {for (final p in l) p.id: p});
    } catch (_) {}
  }

  Future<void> _action(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) message(context, texteErreur(e), erreur: true);
    }
  }

  Future<void> _confierAuLivreur(Commande c) async {
    await _chargerLivreurs();
    if (!mounted) return;
    if (_livreurs.isEmpty) {
      message(context, "Aucun livreur actif. Créez d'abord un compte livreur.", erreur: true);
      return;
    }
    final choix = await showDialog<Profil>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Commande #${c.numero} — quel livreur ?'),
        children: [
          for (final l in _livreurs.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, l),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(children: [
                const Icon(Icons.delivery_dining),
                const SizedBox(width: 12),
                Expanded(child: Text(l.nom, style: const TextStyle(fontSize: 16))),
                Text('${_enCoursPour(l.id)} en cours',
                    style: TextStyle(color: Theme.of(ctx).colorScheme.outline)),
              ]),
            ),
        ],
      ),
    );
    if (choix != null) await _action(() => Api.confierAuLivreur(c.id, choix.id));
  }

  int _enCoursPour(String livreurId) =>
      _commandes.where((c) => c.livreurId == livreurId && c.statut == 'en_livraison').length;

  Future<void> _echec(Commande c) async {
    final motif = await demanderMotif(context);
    if (motif != null) await _action(() => Api.changerStatut(c.id, 'echec', motif: motif));
  }

  Future<void> _annuler(Commande c) async {
    if (await confirmer(context, 'Annuler la commande #${c.numero} ?',
        'Le client verra que sa commande est annulée.', ok: 'Annuler la commande')) {
      await _action(() => Api.changerStatut(c.id, 'annulee'));
    }
  }

  List<Widget> _boutons(Commande c) {
    Widget b(String texte, String statut, {IconData? icone}) => FilledButton.icon(
          onPressed: () => _action(() => Api.changerStatut(c.id, statut)),
          icon: Icon(icone ?? Icons.arrow_forward, size: 18),
          label: Text(texte),
        );
    switch (c.statut) {
      case 'nouvelle':
        return [
          b('Préparer', 'preparation', icone: Icons.local_fire_department),
          TextButton(onPressed: () => _annuler(c), child: const Text('Annuler')),
        ];
      case 'preparation':
        return [b('Prête', 'prete', icone: Icons.check)];
      case 'prete':
        if (c.type == 'livraison') {
          return [
            FilledButton.icon(
              onPressed: () => _confierAuLivreur(c),
              icon: const Icon(Icons.delivery_dining, size: 18),
              label: const Text('Confier au livreur'),
            ),
          ];
        }
        return [
          b(c.type == 'emporter' ? 'Remise au client' : 'Servie', 'servie',
              icone: Icons.done_all),
        ];
      case 'en_livraison':
        return [
          TextButton(
            onPressed: () async {
              if (await confirmer(context, 'Marquer #${c.numero} livrée ?',
                  'À utiliser seulement si le livreur ne peut pas valider depuis son téléphone.')) {
                await _action(() => Api.changerStatut(c.id, 'livree'));
              }
            },
            child: const Text('Marquer livrée'),
          ),
          TextButton(onPressed: () => _echec(c), child: const Text('Échec')),
        ];
      default:
        return [];
    }
  }

  Widget _carte(Commande c) {
    final t = Theme.of(context).textTheme;
    final retard = !c.terminee && c.minutesDepuis >= 30;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: c.info.couleur, width: 5)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('#${c.numero}', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Expanded(child: Text(typesLabel[c.type] ?? c.type, style: t.labelLarge)),
              Text(
                c.terminee ? heure(c.termineeAt ?? c.createdAt) : '${heure(c.createdAt)} · ${c.minutesDepuis} min',
                style: TextStyle(
                  color: retard ? Colors.red : null,
                  fontWeight: retard ? FontWeight.bold : null,
                ),
              ),
            ]),
            if (c.terminee) Padding(padding: const EdgeInsets.only(top: 4), child: PuceStatut(c.statut)),
            if (c.clientNom != null || c.clientTel != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${c.clientNom ?? ''}  ${c.clientTel ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            if (c.adresse != null || c.lat != null)
              Text(
                [if (c.adresse != null) c.adresse!, if (c.lat != null) '📍 position GPS'].join(' · '),
                style: t.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const Divider(height: 16),
            for (final a in c.articles)
              Text('${a.qte} × ${a.nom}', style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
            if (c.note != null)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(6),
                color: Colors.amber.withValues(alpha: .2),
                child: Text('📝 ${c.note}'),
              ),
            const SizedBox(height: 6),
            Row(children: [
              Text(fcfa(c.total), style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (c.livreurId != null)
                Text('🛵 ${_livreurs[c.livreurId]?.nom ?? 'Livreur'}', style: t.bodySmall),
            ]),
            if (c.motifEchec != null)
              Text('Motif : ${c.motifEchec}', style: const TextStyle(color: Colors.red)),
            if (!c.terminee)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 8, runSpacing: 4, children: _boutons(c)),
              ),
          ],
        ),
      ),
    );
  }

  List<Commande> _pour(Set<String> s) {
    final l = _commandes.where((c) => s.contains(c.statut)).toList();
    if (s == statutsTermines) {
      l.sort((a, b) => (b.termineeAt ?? b.createdAt).compareTo(a.termineeAt ?? a.createdAt));
    }
    return l;
  }

  Widget _liste(List<Commande> l, String vide) => l.isEmpty
      ? Center(child: Text(vide, style: TextStyle(color: Theme.of(context).colorScheme.outline)))
      : ListView(padding: const EdgeInsets.all(8), children: [for (final c in l) _carte(c)]);

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= 1000;
    final enCours = _commandes.where((c) => !c.terminee).length;
    final titre = Row(children: [
      const Text('Commandes du jour'),
      const SizedBox(width: 12),
      if (enCours > 0) Chip(label: Text('$enCours en cours')),
      if (_horsLigne)
        const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Chip(
            avatar: Icon(Icons.wifi_off, size: 16),
            label: Text('Hors ligne — reconnexion…'),
          ),
        ),
    ]);

    if (large) {
      return Scaffold(
        appBar: AppBar(title: titre, actions: const [BoutonDeconnexion()]),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final col in _colonnes)
              Expanded(
                child: Column(children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    color: (statuts[col.$2.first]?.couleur ?? Colors.grey).withValues(alpha: .1),
                    child: Text('${col.$1} (${_pour(col.$2).length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  Expanded(child: _liste(_pour(col.$2), '—')),
                ]),
              ),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: _colonnes.length,
      child: Scaffold(
        appBar: AppBar(
          title: titre,
          actions: const [BoutonDeconnexion()],
          bottom: TabBar(
            isScrollable: true,
            tabs: [for (final col in _colonnes) Tab(text: '${col.$1} (${_pour(col.$2).length})')],
          ),
        ),
        body: TabBarView(
          children: [for (final col in _colonnes) _liste(_pour(col.$2), 'Aucune commande')],
        ),
      ),
    );
  }
}
