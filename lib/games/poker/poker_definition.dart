import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import 'poker_engine.dart';
import 'poker_game_screen.dart';

final GameDefinition pokerDefinition = GameDefinition(
  id: 'poker',
  icon: Icons.casino,
  accentColor: const Color(0xFF10331F),
  minPlayers: PokerEngine.minPlayersStatic,
  maxPlayers: PokerEngine.maxPlayersStatic,
  createEngine: () => PokerEngine(),
  buildGameScreen: (context, args) => PokerGameScreen(args: args),
);
