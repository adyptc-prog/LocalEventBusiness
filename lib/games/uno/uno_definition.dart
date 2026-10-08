import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import 'uno_engine.dart';
import 'uno_game_screen.dart';

final GameDefinition unoDefinition = GameDefinition(
  id: 'uno',
  icon: Icons.filter_none,
  accentColor: const Color(0xFF1B1B2E),
  minPlayers: UnoEngine.minPlayersStatic,
  maxPlayers: UnoEngine.maxPlayersStatic,
  createEngine: () => UnoEngine(),
  buildGameScreen: (context, args) => UnoGameScreen(args: args),
);
