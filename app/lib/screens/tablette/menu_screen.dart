import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../api.dart';
import '../../models.dart';
import '../../widgets/commun.dart';

/// Gestion du menu et des réglages (réservé à l'administrateur).
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final Stream<List<Plat>> _platsStream = Api.platsEnDirect();
  Reglages? _reglages;

  @override
  void initState() {
    super.initState();
    _chargerReglages();
  }

  Future<void> _chargerReglages() async {
    try {
      final r = await Api.reglages();
      if (mounted) setState(() => _reglages = r);
    } catch (_) {}
  }

  Future<void> _sauverReglages() async {
    try {
      await Api.enregistrerReglages(_reglages!);
      if (mounted) message(context, 'Réglages enregistrés');
    } catch (e) {
      if (mounted) message(context, texteErreur(e), erreur: true);
      _chargerReglages();
    }
  }

  Future<void> _modifierReglages() async {
    final r = _reglages!;
    final nom = TextEditingController(text: r.nomRestaurant);
    final tel = TextEditingController(text: r.telephone ?? '');
    final frais = TextEditingController(text: '${r.fraisLivraison}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Réglages du restaurant'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom affiché aux clients')),
          TextField(
              controller: tel,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone du restaurant')),
          TextField(
              controller: frais,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Frais de livraison (F)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      r.nomRestaurant = nom.text.trim().isEmpty ? r.nomRestaurant : nom.text.trim();
      r.telephone = tel.text.trim().isEmpty ? null : tel.text.trim();
      r.fraisLivraison = int.tryParse(frais.text.replaceAll(' ', '')) ?? r.fraisLivraison;
    });
    await _sauverReglages();
  }

  Future<void> _editerPlat([Plat? p]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _DialoguePlat(plat: p),
    );
    if (ok == true && mounted) message(context, 'Menu mis à jour');
  }

  Future<void> _basculer(Plat p, bool v) async {
    try {
      await Api.enregistrerPlat(p.id, {'disponible': v});
    } catch (e) {
      if (mounted) message(context, texteErreur(e), erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _reglages;
    return Scaffold(
      appBar: AppBar(title: const Text('Menu & réglages')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editerPlat(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un plat'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          if (r != null)
            Card(
              child: Column(children: [
                SwitchListTile(
                  title: Text(r.ouvert ? 'Ouvert — commandes en ligne acceptées' : 'Fermé — commandes en ligne bloquées'),
                  secondary: Icon(r.ouvert ? Icons.storefront : Icons.no_meals,
                      color: r.ouvert ? Colors.green : Colors.red),
                  value: r.ouvert,
                  onChanged: (v) {
                    setState(() => r.ouvert = v);
                    _sauverReglages();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: Text(r.nomRestaurant),
                  subtitle: Text('Frais de livraison : ${fcfa(r.fraisLivraison)}'
                      '${r.telephone != null ? '  ·  ${r.telephone}' : ''}'),
                  trailing: const Icon(Icons.edit),
                  onTap: _modifierReglages,
                ),
              ]),
            ),
          const SizedBox(height: 8),
          StreamBuilder<List<Plat>>(
            stream: _platsStream,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                    padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
              }
              final plats = snap.data!;
              if (plats.isEmpty) {
                return const Padding(
                    padding: EdgeInsets.all(32), child: Center(child: Text('Aucun plat. Ajoutez-en un.')));
              }
              return Card(
                child: Column(children: [
                  for (final p in plats)
                    ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 52,
                          height: 52,
                          child: p.photoUrl != null
                              ? Image.network(p.photoUrl!, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(child: Text('🌯')))
                              : const Center(child: Text('🌯', style: TextStyle(fontSize: 26))),
                        ),
                      ),
                      title: Text(p.nom,
                          style: TextStyle(
                              decoration: p.disponible ? null : TextDecoration.lineThrough)),
                      subtitle: Text(p.disponible ? fcfa(p.prix) : '${fcfa(p.prix)} · en rupture'),
                      trailing: Switch(value: p.disponible, onChanged: (v) => _basculer(p, v)),
                      onTap: () => _editerPlat(p),
                    ),
                ]),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DialoguePlat extends StatefulWidget {
  final Plat? plat;
  const _DialoguePlat({this.plat});

  @override
  State<_DialoguePlat> createState() => _DialoguePlatState();
}

class _DialoguePlatState extends State<_DialoguePlat> {
  late final _nom = TextEditingController(text: widget.plat?.nom ?? '');
  late final _desc = TextEditingController(text: widget.plat?.description ?? '');
  late final _prix = TextEditingController(text: widget.plat == null ? '' : '${widget.plat!.prix}');
  late final _ordre = TextEditingController(text: '${widget.plat?.ordre ?? 0}');
  Uint8List? _photo;
  String _ext = 'jpg';
  bool _envoi = false;
  String? _erreur;

  Future<void> _choisirPhoto() async {
    final f = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 900, imageQuality: 80);
    if (f == null) return;
    final b = await f.readAsBytes();
    setState(() {
      _photo = b;
      _ext = f.name.contains('.') ? f.name.split('.').last : 'jpg';
    });
  }

  Future<void> _enregistrer() async {
    final prix = int.tryParse(_prix.text.replaceAll(' ', ''));
    if (_nom.text.trim().isEmpty || prix == null) {
      setState(() => _erreur = 'Nom et prix obligatoires.');
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      final data = <String, dynamic>{
        'nom': _nom.text.trim(),
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'prix': prix,
        'ordre': int.tryParse(_ordre.text) ?? 0,
      };
      if (_photo != null) data['photo_url'] = await Api.envoyerPhoto(_photo!, _ext);
      await Api.enregistrerPlat(widget.plat?.id, data);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _envoi = false;
        _erreur = texteErreur(e);
      });
    }
  }

  Future<void> _supprimer() async {
    if (!await confirmer(context, 'Supprimer ce plat ?',
        'Astuce : désactivez-le plutôt s’il est seulement en rupture.', ok: 'Supprimer')) {
      return;
    }
    try {
      await Api.supprimerPlat(widget.plat!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _erreur = texteErreur(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.plat;
    Widget apercu;
    if (_photo != null) {
      apercu = Image.memory(_photo!, fit: BoxFit.cover);
    } else if (p?.photoUrl != null) {
      apercu = Image.network(p!.photoUrl!, fit: BoxFit.cover);
    } else {
      apercu = const Center(child: Icon(Icons.add_a_photo, size: 36));
    }
    return AlertDialog(
      title: Text(p == null ? 'Nouveau plat' : 'Modifier le plat'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              onTap: _choisirPhoto,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 150,
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: apercu,
                ),
              ),
            ),
            TextField(controller: _nom, decoration: const InputDecoration(labelText: 'Nom *')),
            TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Description')),
            TextField(
                controller: _prix,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Prix (F) *')),
            TextField(
                controller: _ordre,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Ordre d’affichage (1, 2, 3…)')),
            if (_erreur != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ]),
        ),
      ),
      actions: [
        if (p != null)
          TextButton(
            onPressed: _envoi ? null : _supprimer,
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: _envoi ? null : _enregistrer,
          child: Text(_envoi ? 'Envoi…' : 'Enregistrer'),
        ),
      ],
    );
  }
}
