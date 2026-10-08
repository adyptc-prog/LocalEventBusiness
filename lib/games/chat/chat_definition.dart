import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import 'chat_engine.dart';
import 'chat_room_screen.dart';

/// Nu apare în lista de jocuri ([availableGames]) — e legată separat, ca
/// buton propriu pe ecranul principal, tocmai ca discuția să nu fie legată
/// de o singură masă de joc. Reutilizează în schimb același flux generic de
/// conectare/alăturare (`RoomBrowserScreen`/`LobbyScreen`).
final GameDefinition chatDefinition = GameDefinition(
  id: 'chat',
  title: 'Chat general',
  subtitle: 'Discută cu oricine e conectat pe rețea acum, indiferent la ce joc participă.',
  icon: Icons.forum,
  accentColor: const Color(0xFF0E2A47),
  minPlayers: ChatEngine.minPlayersStatic,
  maxPlayers: ChatEngine.maxPlayersStatic,
  createEngine: () => ChatEngine(),
  buildGameScreen: (context, args) => ChatRoomScreen(args: args),
);
