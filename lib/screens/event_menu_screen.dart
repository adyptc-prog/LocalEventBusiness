import 'package:flutter/material.dart';

import '../core/activity_catalog.dart';
import '../core/games_registry.dart';
import '../widgets/menu_card.dart';
import 'game_library_screen.dart';
import 'menu_connect_screen.dart';
import 'room_browser_screen.dart';

/// Meniul propriu-zis al invitatului, randat local din lista de id-uri de
/// activități primită de la server (`EventConnectScreen`) — doar ce a
/// activat organizatorul pentru localul curent. Jocurile de cărți se
/// grupează sub un singur card „Jocuri" (apare doar dacă cel puțin unul e
/// activat); Chat și Meniu capătă propriul card. Meniul e singura
/// activitate care nu duce la `RoomBrowserScreen` — clientul se alătură
/// direct camerei singleton de comenzi (vezi `MenuConnectScreen`).
class EventMenuScreen extends StatelessWidget {
  final List<String> enabledActivityIds;

  const EventMenuScreen({super.key, required this.enabledActivityIds});

  @override
  Widget build(BuildContext context) {
    final enabledGameIds = availableGames.map((g) => g.id).where(enabledActivityIds.contains).toList();
    final standaloneActivities =
        activityCatalog.where((a) => !availableGames.contains(a) && enabledActivityIds.contains(a.id)).toList();

    final cards = <Widget>[
      if (enabledGameIds.isNotEmpty)
        MenuCard(
          icon: Icons.sports_esports,
          title: 'Jocuri',
          subtitle: 'Alege un joc de cărți și creează sau alătură-te unei mese.',
          color: const Color(0xFF0B5E3B),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => GameLibraryScreen(enabledGameIds: enabledGameIds)),
          ),
        ),
      for (final activity in standaloneActivities)
        MenuCard(
          icon: activity.icon,
          title: activity.title,
          subtitle: activity.subtitle,
          color: activity.accentColor,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) =>
                  activity.id == 'menu' ? const MenuConnectScreen() : RoomBrowserScreen(definition: activity),
            ),
          ),
        ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(backgroundColor: Colors.black26, title: const Text('Ce vrei să faci?')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: cards.isEmpty
              ? const Center(
                  child: Text(
                    'Organizatorul nu a activat nicio activitate pentru acest eveniment încă.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.separated(
                  itemCount: cards.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 20),
                  itemBuilder: (context, index) => cards[index],
                ),
        ),
      ),
    );
  }
}
