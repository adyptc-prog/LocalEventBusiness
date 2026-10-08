import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import 'whist_engine.dart';
import 'whist_game_screen.dart';

final GameDefinition whistDefinition = GameDefinition(
  id: 'whist',
  icon: Icons.table_chart,
  accentColor: const Color(0xFF213A2B),
  minPlayers: WhistEngine.minPlayersStatic,
  maxPlayers: WhistEngine.maxPlayersStatic,
  createEngine: () => WhistEngine(),
  buildGameScreen: (context, args) => WhistGameScreen(args: args),
);
