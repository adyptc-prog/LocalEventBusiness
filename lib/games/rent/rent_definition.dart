import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import 'rent_engine.dart';
import 'rent_game_screen.dart';

final GameDefinition rentDefinition = GameDefinition(
  id: 'rent',
  icon: Icons.style,
  accentColor: const Color(0xFF3A1F1F),
  minPlayers: RentEngine.minPlayersStatic,
  maxPlayers: RentEngine.maxPlayersStatic,
  createEngine: () => RentEngine(),
  buildGameScreen: (context, args) => RentGameScreen(args: args),
);
