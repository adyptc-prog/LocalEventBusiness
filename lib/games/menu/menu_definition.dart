import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import 'menu_engine.dart';
import 'menu_order_screen.dart';

/// Nu apare în lista de jocuri de cărți ([availableGames]) — e activitatea
/// de comenzi la bar. Spre deosebire de restul activităților de-sine-
/// stătătoare, nu se ajunge la ea prin `RoomBrowserScreen` (creare/alăturare
/// cu cod) — clientul e conectat direct la camera singleton „MENU", creată
/// automat de server (vezi `MenuConnectScreen`/`EventServerService`).
final GameDefinition menuDefinition = GameDefinition(
  id: 'menu',
  icon: Icons.restaurant_menu,
  accentColor: const Color(0xFF6B3F1D),
  minPlayers: MenuEngine.minPlayersStatic,
  maxPlayers: MenuEngine.maxPlayersStatic,
  createEngine: () => MenuEngine(),
  buildGameScreen: (context, args) => MenuOrderScreen(args: args),
);
