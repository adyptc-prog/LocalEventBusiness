import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import 'septica_engine.dart';
import 'septica_game_screen.dart';

final GameDefinition septicaDefinition = GameDefinition(
  id: 'septica',
  title: 'Șeptica',
  subtitle: 'Pachet de la 7 în sus. Capturezi masa cu un 7 (și 8, la 3 jucători) sau cu aceeași valoare — Așii și Zecarii aduc puncte.',
  icon: Icons.filter_7,
  accentColor: const Color(0xFF5A1A22),
  minPlayers: SepticaEngine.minPlayersStatic,
  maxPlayers: SepticaEngine.maxPlayersStatic,
  createEngine: () => SepticaEngine(),
  buildGameScreen: (context, args) => SepticaGameScreen(args: args),
);
