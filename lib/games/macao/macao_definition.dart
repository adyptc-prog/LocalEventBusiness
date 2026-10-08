import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import 'macao_engine.dart';
import 'macao_game_screen.dart';

final GameDefinition macaoDefinition = GameDefinition(
  id: 'macao',
  icon: Icons.style,
  accentColor: const Color(0xFF0B5E3B),
  minPlayers: MacaoEngine.minPlayersStatic,
  maxPlayers: MacaoEngine.maxPlayersStatic,
  createEngine: () => MacaoEngine(),
  buildGameScreen: (context, args) => MacaoGameScreen(args: args),
);
