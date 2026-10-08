import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import 'uno_engine.dart';
import 'uno_game_screen.dart';

final GameDefinition unoDefinition = GameDefinition(
  id: 'uno',
  title: 'UNO',
  subtitle: '2-6 jucători. Scapă primul de cărți — Sări, Inversează, +2, Wild și Wild+4.',
  icon: Icons.filter_none,
  accentColor: const Color(0xFF1B1B2E),
  minPlayers: UnoEngine.minPlayersStatic,
  maxPlayers: UnoEngine.maxPlayersStatic,
  createEngine: () => UnoEngine(),
  buildGameScreen: (context, args) => UnoGameScreen(args: args),
);
