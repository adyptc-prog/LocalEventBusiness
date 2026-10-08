import 'package:flutter/material.dart';

import 'chat_message.dart';
import 'game_engine.dart';
import '../l10n/tr.dart';

/// Tot ce trebuie ecranului de joc ca să afișeze o partidă și să trimită
/// acțiuni — indiferent dacă rulează pe gazdă sau pe un client, și
/// indiferent prin ce rețea circulă mesajele. Ecranul de joc își decodează
/// singur `initialSnapshot`/`stateStream` (JSON brut) în tipul lui de
/// snapshot. Include și canalul de chat al camerei (public + privat), ca să
/// poată oferi acces la clasament/chat din propriul AppBar.
class GameSessionArgs {
  final String myId;
  final Stream<Map<String, dynamic>> stateStream;
  final Map<String, dynamic> initialSnapshot;
  final void Function(Map<String, dynamic> action) onAction;
  final Stream<String>? errorStream;
  final VoidCallback onLeave;
  final Stream<ChatMessage> chatStream;
  final void Function(String text, {String? toId}) onChat;

  /// `http://host:port` al serverului curent — `null` pentru orice
  /// activitate care nu are nevoie de fișiere. Singurul loc unde un ecran de
  /// joc capătă vreo informație despre transport, fiindcă pozele (ex.
  /// produsele din Meniu) circulă peste HTTP, nu prin `stateStream`/
  /// `onAction`; ecranul construiește singur URL-ul de descărcare din
  /// `serverOrigin` plus numele fișierului.
  final String? serverOrigin;

  /// Codul camerei curente — disponibil pentru orice activitate care ar avea
  /// nevoie să știe explicit de el (ex: o rută HTTP specifică unei camere).
  final String? roomCode;

  const GameSessionArgs({
    required this.myId,
    required this.stateStream,
    required this.initialSnapshot,
    required this.onAction,
    this.errorStream,
    required this.onLeave,
    required this.chatStream,
    required this.onChat,
    this.serverOrigin,
    this.roomCode,
  });
}

/// Descrie un joc disponibil în bibliotecă: metadate pentru UI, cum se
/// construiește motorul de reguli și cum se construiește ecranul de joc.
class GameDefinition {
  final String id;
  final IconData icon;
  final Color accentColor;
  final int minPlayers;
  final int maxPlayers;
  final GameEngine Function() createEngine;
  final Widget Function(BuildContext context, GameSessionArgs args) buildGameScreen;

  const GameDefinition({
    required this.id,
    required this.icon,
    required this.accentColor,
    required this.minPlayers,
    required this.maxPlayers,
    required this.createEngine,
    required this.buildGameScreen,
  });

  /// Numele și descrierea jocului, în limba curentă (cheile
  /// `game.<id>.title` / `game.<id>.subtitle` din `lib/l10n`).
  String get title => tr('game.$id.title');
  String get subtitle => tr('game.$id.subtitle');

  String get playersLabel => minPlayers == maxPlayers
      ? tr('game.players', {'n': minPlayers})
      : tr('game.playersRange', {'min': minPlayers, 'max': maxPlayers});
}
