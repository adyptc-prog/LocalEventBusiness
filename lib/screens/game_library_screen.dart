import 'package:flutter/material.dart';

import '../core/game_definition.dart';
import '../core/games_registry.dart';
import '../widgets/language_button.dart';
import 'room_browser_screen.dart';
import '../l10n/tr.dart';

/// Bibliotecă de jocuri locale multiplayer, filtrată la doar cele activate
/// de organizator pentru evenimentul curent ([enabledGameIds] — vezi
/// `EventMenuScreen`). Fiecare joc e independent — alegi unul, apoi decizi
/// dacă creezi o cameră sau te alături uneia existente pe rețea.
class GameLibraryScreen extends StatelessWidget {
  final List<String> enabledGameIds;

  const GameLibraryScreen({super.key, required this.enabledGameIds});

  @override
  Widget build(BuildContext context) {
    final games = availableGames.where((g) => enabledGameIds.contains(g.id)).toList();
    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: const [LanguageButton()],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.sports_esports, size: 48, color: Colors.white),
                  const SizedBox(height: 12),
                  Text(tr('gameLibrary.title'),
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                  Text(tr('mainMenu.tagline'),
                      style: const TextStyle(color: Colors.white54)),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: games.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _GameCard(definition: games[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final GameDefinition definition;

  const _GameCard({required this.definition});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: definition.accentColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => RoomBrowserScreen(definition: definition)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(definition.icon, size: 44, color: Colors.white),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(definition.title,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(definition.subtitle, style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 6),
                    Text(definition.playersLabel,
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}
