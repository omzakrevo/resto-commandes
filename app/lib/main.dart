import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api.dart';
import 'config.dart';
import 'models.dart';
import 'screens/livreur/livreur_home.dart';
import 'screens/login_screen.dart';
import 'screens/tablette/tablette_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  runApp(const RestoApp());
}

class RestoApp extends StatelessWidget {
  const RestoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Resto Commandes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFC2410C),
        useMaterial3: true,
        visualDensity: VisualDensity.comfortable,
      ),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AuthGate(),
    );
  }
}

/// Affiche l'écran de connexion ou l'écran correspondant au rôle.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: sb.auth.onAuthStateChange,
      builder: (context, _) {
        final session = sb.auth.currentSession;
        if (session == null) return const LoginScreen();
        return ChargeurProfil(key: ValueKey(session.user.id));
      },
    );
  }
}

class ChargeurProfil extends StatefulWidget {
  const ChargeurProfil({super.key});

  @override
  State<ChargeurProfil> createState() => _ChargeurProfilState();
}

class _ChargeurProfilState extends State<ChargeurProfil> {
  late Future<Profil?> _future = Api.monProfil();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profil?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final profil = snap.data;
        if (snap.hasError || profil == null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_off, size: 56),
                    const SizedBox(height: 12),
                    Text(
                      snap.hasError
                          ? 'Impossible de charger le compte.\nVérifiez la connexion Internet.'
                          : "Ce compte n'est pas encore configuré (aucun profil).",
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Wrap(spacing: 12, children: [
                      FilledButton(
                        onPressed: () => setState(() => _future = Api.monProfil()),
                        child: const Text('Réessayer'),
                      ),
                      OutlinedButton(
                        onPressed: () => sb.auth.signOut(),
                        child: const Text('Se déconnecter'),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          );
        }
        return profil.estLivreur ? LivreurHome(profil: profil) : TabletteHome(profil: profil);
      },
    );
  }
}
