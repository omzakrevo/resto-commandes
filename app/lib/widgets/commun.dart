import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../models.dart';

/// Petite sonnerie pour les nouvelles commandes.
class Sonnerie {
  final _player = AudioPlayer();
  Future<void> jouer() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('bip.wav'), volume: 1);
    } catch (_) {}
  }

  void dispose() => _player.dispose();
}

void message(BuildContext context, String texte, {bool erreur = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(texte),
      backgroundColor: erreur ? Theme.of(context).colorScheme.error : null,
    ));
}

String texteErreur(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is StorageException) return 'Photo : ${e.message}';
  return 'Erreur : vérifiez la connexion Internet.';
}

Future<void> appeler(String tel) async {
  await launchUrl(Uri(scheme: 'tel', path: tel.replaceAll(' ', '')));
}

Future<void> ouvrirCarte(Commande c) async {
  final q = (c.lat != null && c.lng != null) ? '${c.lat},${c.lng}' : (c.adresse ?? '');
  final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Demande un motif d'échec de livraison.
Future<String?> demanderMotif(BuildContext context) {
  const motifs = [
    'Client injoignable',
    'Client absent',
    'Adresse introuvable',
    'Client a refusé la commande',
  ];
  final autre = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Pourquoi la livraison a échoué ?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in motifs)
              ListTile(
                title: Text(m),
                leading: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(ctx, m),
              ),
            TextField(
              controller: autre,
              decoration: const InputDecoration(labelText: 'Autre motif'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final t = autre.text.trim();
            if (t.isNotEmpty) Navigator.pop(ctx, t);
          },
          child: const Text('Valider'),
        ),
      ],
    ),
  );
}

Future<bool> confirmer(BuildContext context, String titre, String texte,
    {String ok = 'Confirmer'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titre),
      content: Text(texte),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

class PuceStatut extends StatelessWidget {
  final String statut;
  const PuceStatut(this.statut, {super.key});
  @override
  Widget build(BuildContext context) {
    final i = statuts[statut]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: i.couleur.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(i.label,
          style: TextStyle(color: i.couleur, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class BoutonDeconnexion extends StatelessWidget {
  const BoutonDeconnexion({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Se déconnecter',
        icon: const Icon(Icons.logout),
        onPressed: () async {
          if (await confirmer(context, 'Déconnexion', 'Se déconnecter de cet appareil ?',
              ok: 'Se déconnecter')) {
            await sb.auth.signOut();
          }
        },
      );
}
