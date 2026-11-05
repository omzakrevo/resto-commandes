// Les valeurs sont injectées au moment de la compilation par GitHub Actions
// (variables du dépôt SUPABASE_URL et SUPABASE_KEY).
// En local : flutter run --dart-define=SUPABASE_URL=https://... --dart-define=SUPABASE_KEY=...
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://VOTRE-SUPABASE.exemple.com',
);

// Clé "anon" (ANON_KEY du fichier .env de ton Supabase auto-hébergé)
// ou clé "publishable" sur Supabase Cloud.
const supabaseKey = String.fromEnvironment(
  'SUPABASE_KEY',
  defaultValue: 'VOTRE_CLE_ANON',
);

// Heure à laquelle commence une "journée de service" (6 h du matin).
// Les commandes passées après minuit restent dans la journée de la veille.
const heureDebutService = 6;
