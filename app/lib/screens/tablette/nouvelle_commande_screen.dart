import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../widgets/commun.dart';

/// Saisie d'une commande au comptoir (sur place, à emporter ou livraison par téléphone).
class NouvelleCommandeScreen extends StatefulWidget {
  final VoidCallback? onCreee;
  const NouvelleCommandeScreen({super.key, this.onCreee});

  @override
  State<NouvelleCommandeScreen> createState() => _NouvelleCommandeScreenState();
}

class _NouvelleCommandeScreenState extends State<NouvelleCommandeScreen> {
  final Stream<List<Plat>> _platsStream = Api.platsEnDirect();
  final Map<String, Article> _panier = {};
  String _type = 'sur_place';
  int _fraisLivraison = 0;
  bool _envoi = false;
  final _nom = TextEditingController();
  final _tel = TextEditingController();
  final _adresse = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _chargerFrais();
  }

  Future<void> _chargerFrais() async {
    try {
      final r = await Api.reglages();
      if (mounted) setState(() => _fraisLivraison = r.fraisLivraison);
    } catch (_) {}
  }

  int get _sousTotal => _panier.values.fold(0, (s, a) => s + a.sousTotal);
  int get _frais => _type == 'livraison' ? _fraisLivraison : 0;

  void _ajouter(Plat p) => setState(() {
        _panier.update(p.id, (a) => a..qte += 1,
            ifAbsent: () => Article(platId: p.id, nom: p.nom, prix: p.prix));
      });

  void _changer(String id, int d) => setState(() {
        final a = _panier[id];
        if (a == null) return;
        a.qte += d;
        if (a.qte <= 0) _panier.remove(id);
      });

  void _vider() {
    setState(_panier.clear);
    _nom.clear();
    _tel.clear();
    _adresse.clear();
    _note.clear();
  }

  Future<void> _valider(String statut) async {
    if (_panier.isEmpty) return;
    if (_type == 'livraison' &&
        (_tel.text.trim().length < 8 || _adresse.text.trim().isEmpty)) {
      message(context, 'Pour une livraison : téléphone et adresse obligatoires.', erreur: true);
      return;
    }
    setState(() => _envoi = true);
    try {
      String? vide(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
      final numero = await Api.creerCommande(
        type: _type,
        statut: statut,
        articles: _panier.values.toList(),
        frais: _frais,
        nom: vide(_nom),
        tel: vide(_tel),
        adresse: _type == 'livraison' ? vide(_adresse) : null,
        note: vide(_note),
      );
      if (!mounted) return;
      message(
          context,
          statut == 'servie'
              ? '✅ Commande #$numero encaissée et validée'
              : '👨‍🍳 Commande #$numero envoyée en cuisine');
      _vider();
      if (statut != 'servie') widget.onCreee?.call();
    } catch (e) {
      if (mounted) message(context, texteErreur(e), erreur: true);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Widget _grillePlats() => StreamBuilder<List<Plat>>(
        stream: _platsStream,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final plats = snap.data!.where((p) => p.disponible).toList();
          if (plats.isEmpty) return const Center(child: Text('Aucun plat disponible.'));
          return GridView.extent(
            maxCrossAxisExtent: 200,
            padding: const EdgeInsets.all(12),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: .85,
            children: [
              for (final p in plats)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _ajouter(p),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Stack(fit: StackFit.expand, children: [
                            p.photoUrl != null
                                ? Image.network(p.photoUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Center(child: Text('🌯', style: TextStyle(fontSize: 40))))
                                : Container(
                                    color: Theme.of(context).colorScheme.primaryContainer,
                                    child: const Center(child: Text('🌯', style: TextStyle(fontSize: 40)))),
                            if (_panier[p.id] != null)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: CircleAvatar(
                                  radius: 14,
                                  child: Text('${_panier[p.id]!.qte}'),
                                ),
                              ),
                          ]),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.nom,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(fcfa(p.prix)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      );

  Widget _panierWidget() {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Text('Commande', style: t.titleLarge),
          const Spacer(),
          if (_panier.isNotEmpty) TextButton(onPressed: _vider, child: const Text('Vider')),
        ]),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'sur_place', label: Text('Sur place'), icon: Icon(Icons.restaurant)),
            ButtonSegment(value: 'emporter', label: Text('Emporter'), icon: Icon(Icons.takeout_dining)),
            ButtonSegment(value: 'livraison', label: Text('Livraison'), icon: Icon(Icons.delivery_dining)),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() => _type = s.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 12),
        if (_panier.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Touchez un plat pour l’ajouter.', textAlign: TextAlign.center),
          ),
        for (final e in _panier.entries)
          Row(children: [
            Expanded(child: Text(e.value.nom)),
            IconButton(onPressed: () => _changer(e.key, -1), icon: const Icon(Icons.remove_circle_outline)),
            Text('${e.value.qte}', style: const TextStyle(fontWeight: FontWeight.bold)),
            IconButton(onPressed: () => _changer(e.key, 1), icon: const Icon(Icons.add_circle_outline)),
            SizedBox(width: 80, child: Text(fcfa(e.value.sousTotal), textAlign: TextAlign.right)),
          ]),
        const SizedBox(height: 8),
        TextField(controller: _nom, decoration: const InputDecoration(labelText: 'Nom du client (facultatif)')),
        if (_type == 'livraison') ...[
          TextField(
            controller: _tel,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Téléphone *'),
          ),
          TextField(controller: _adresse, decoration: const InputDecoration(labelText: 'Adresse / repère *')),
        ],
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (sans piment…)')),
        const Divider(height: 32),
        if (_frais > 0)
          Row(children: [const Text('Frais de livraison'), const Spacer(), Text(fcfa(_frais))]),
        Row(children: [
          Text('Total', style: t.titleLarge),
          const Spacer(),
          Text(fcfa(_sousTotal + _frais), style: t.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 16),
        if (_type != 'livraison') ...[
          FilledButton.icon(
            onPressed: _panier.isEmpty || _envoi ? null : () => _valider('servie'),
            icon: const Icon(Icons.payments),
            label: const Text('Encaisser et valider'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: _panier.isEmpty || _envoi ? null : () => _valider('nouvelle'),
          icon: const Icon(Icons.soup_kitchen),
          label: const Text('Envoyer en cuisine'),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
        ),
        if (_type != 'livraison')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '« Encaisser et valider » : le client est servi tout de suite.\n'
              '« Envoyer en cuisine » : la commande suit les étapes préparation → prête.',
              style: t.bodySmall,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle commande au comptoir')),
      body: large
          ? Row(children: [
              Expanded(child: _grillePlats()),
              const VerticalDivider(width: 1),
              SizedBox(width: 380, child: _panierWidget()),
            ])
          : Column(children: [
              Expanded(flex: 2, child: _grillePlats()),
              const Divider(height: 1),
              Expanded(flex: 3, child: _panierWidget()),
            ]),
    );
  }
}
