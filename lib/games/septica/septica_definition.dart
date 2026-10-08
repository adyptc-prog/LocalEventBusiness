import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import 'septica_engine.dart';
import 'septica_game_screen.dart';

final GameDefinition septicaDefinition = GameDefinition(
  id: 'septica',
  icon: Icons.filter_7,
  accentColor: const Color(0xFF5A1A22),
  minPlayers: SepticaEngine.minPlayersStatic,
  maxPlayers: SepticaEngine.maxPlayersStatic,
  createEngine: () => SepticaEngine(),
  buildGameScreen: (context, args) => SepticaGameScreen(args: args),
);
