import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _mdp = TextEditingController();
  bool _chargement = false;
  bool _masquer = true;
  String? _erreur;

  Future<void> _connexion() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      await sb.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _mdp.text,
      );
    } on AuthException catch (e) {
      setState(() => _erreur = e.message.contains('Invalid')
          ? 'E-mail ou mot de passe incorrect.'
          : e.message);
    } catch (_) {
      setState(() => _erreur = 'Pas de connexion Internet ?');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.restaurant, size: 64, color: c.primary),
                  const SizedBox(height: 12),
                  Text('Resto Commandes',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const Text('Tablette du restaurant ou téléphone livreur',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                        labelText: 'E-mail', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _mdp,
                    obscureText: _masquer,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _connexion(),
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_masquer ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _masquer = !_masquer),
                      ),
                    ),
                  ),
                  if (_erreur != null) ...[
                    const SizedBox(height: 12),
                    Text(_erreur!, style: TextStyle(color: c.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _chargement ? null : _connexion,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                    child: _chargement
                        ? const SizedBox(
                            height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Se connecter'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
