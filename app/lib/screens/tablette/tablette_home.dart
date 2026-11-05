import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models.dart';
import 'bilan_screen.dart';
import 'commandes_screen.dart';
import 'menu_screen.dart';
import 'nouvelle_commande_screen.dart';

class TabletteHome extends StatefulWidget {
  final Profil profil;
  const TabletteHome({super.key, required this.profil});

  @override
  State<TabletteHome> createState() => _TabletteHomeState();
}

class _TabletteHomeState extends State<TabletteHome> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // la tablette ne se met pas en veille
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <(IconData, String, Widget)>[
      (Icons.receipt_long, 'Commandes', const CommandesScreen()),
      (
        Icons.add_shopping_cart,
        'Sur place',
        NouvelleCommandeScreen(onCreee: () => setState(() => _index = 0)),
      ),
      if (widget.profil.estAdmin) (Icons.restaurant_menu, 'Menu', const MenuScreen()),
      (Icons.bar_chart, 'Bilan', const BilanScreen()),
    ];
    if (_index >= pages.length) _index = 0;
    final large = MediaQuery.sizeOf(context).width >= 700;
    final contenu = IndexedStack(index: _index, children: [for (final p in pages) p.$3]);

    if (large) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Icon(Icons.restaurant, size: 32),
            ),
            destinations: [
              for (final p in pages)
                NavigationRailDestination(icon: Icon(p.$1), label: Text(p.$2)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: contenu),
        ]),
      );
    }
    return Scaffold(
      body: contenu,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final p in pages) NavigationDestination(icon: Icon(p.$1), label: p.$2),
        ],
      ),
    );
  }
}
