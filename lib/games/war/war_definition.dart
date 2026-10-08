import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import 'war_engine.dart';
import 'war_game_screen.dart';

final GameDefinition warDefinition = GameDefinition(
  id: 'war',
  title: 'Război',
  subtitle: 'Fiecare întoarce câte o carte — cea mai mare le ia pe amândouă.',
  icon: Icons.flash_on,
  accentColor: const Color(0xFF1B2A4A),
  minPlayers: WarEngine.minPlayersStatic,
  maxPlayers: WarEngine.maxPlayersStatic,
  createEngine: () => WarEngine(),
  buildGameScreen: (context, args) => WarGameScreen(args: args),
);
