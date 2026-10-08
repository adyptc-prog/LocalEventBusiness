import 'dart:math';

import '../../core/game_engine.dart';
import '../../models/card.dart';
import '../../l10n/tr.dart';

class _WarPlayerInfo {
  final String id;
  final String name;
  final bool isHost;
  bool connected = true;

  _WarPlayerInfo({required this.id, required this.name, required this.isHost});
}

/// Motorul jocului Război — fiecare jucător întoarce cartea din vârful
/// pachetului său (acțiunea `flip`); cea mai mare ia ambele cărți, la
/// egalitate se intră în "război" (fiecare pune o carte cu fața în jos,
/// apoi trebuie să întoarcă din nou). Nu există decizii de joc, doar
/// sincronizare — motorul rezolvă runda automat de îndată ce ambii au întors.
class WarEngine extends GameEngine {
  static const int minPlayersStatic = 2;
  static const int maxPlayersStatic = 2;

  @override
  int get minPlayers => minPlayersStatic;
  @override
  int get maxPlayers => maxPlayersStatic;

  @override
  bool started = false;

  @override
  Map<String, int>? lastMatchScores;

  String? winnerId;

  final List<_WarPlayerInfo> _players = [];
  final Map<String, List<PlayingCard>> _decks = {};
  final Map<String, PlayingCard> _revealed = {};
  final List<PlayingCard> _pot = [];
  bool _warPending = false;

  Map<String, PlayingCard>? _lastRoundCards;
  String? _lastRoundWinnerId; // null înseamnă că ultima rundă a fost egalitate (război)

  @override
  void addPlayer({required String id, required String name, required bool isHost}) {
    if (_players.length >= maxPlayers) {
      throw GameError('err.roomFull', {'max': maxPlayers});
    }
    _players.add(_WarPlayerInfo(id: id, name: name, isHost: isHost));
    notifyListeners();
  }

  @override
  void markDisconnected(String id) {
    final matches = _players.where((p) => p.id == id);
    if (matches.isEmpty) return;
    matches.first.connected = false;
    notifyListeners();
  }

  @override
  void markConnected(String id) {
    final matches = _players.where((p) => p.id == id);
    if (matches.isEmpty) return;
    matches.first.connected = true;
    notifyListeners();
  }

  @override
  void startGame() {
    if (started) throw GameError('err.alreadyStarted');
    if (_players.length != minPlayers) {
      throw GameError('err.playersExact', {'n': minPlayers});
    }
    final deck = PlayingCard.fullDeck()..shuffle(Random());
    final half = deck.length ~/ 2;
    _decks[_players[0].id] = deck.sublist(0, half);
    _decks[_players[1].id] = deck.sublist(half);
    _revealed.clear();
    _pot.clear();
    _warPending = false;
    winnerId = null;
    lastMatchScores = null;
    _lastRoundCards = null;
    _lastRoundWinnerId = null;
    started = true;
    notifyListeners();
  }

  String _otherPlayer(String id) => _decks.keys.firstWhere((k) => k != id);

  @override
  void applyAction(String playerId, Map<String, dynamic> action) {
    if (action['type'] != 'flip') {
      throw GameError('err.unknownAction');
    }
    _flip(playerId);
  }

  void _flip(String playerId) {
    if (!started || winnerId != null) throw GameError('err.gameNotActive');
    if (!_decks.containsKey(playerId)) throw GameError('err.unknownPlayer');
    if (_revealed.containsKey(playerId)) {
      throw GameError('err.war.alreadyFlipped');
    }

    final deck = _decks[playerId]!;
    if (deck.isEmpty) {
      _finishGame(_otherPlayer(playerId));
      notifyListeners();
      return;
    }

    _revealed[playerId] = deck.removeAt(0);
    if (_revealed.length == _decks.length) {
      _resolveRound();
    }
    notifyListeners();
  }

  void _resolveRound() {
    final ids = _revealed.keys.toList();
    final aId = ids[0];
    final bId = ids[1];
    final aCard = _revealed[aId]!;
    final bCard = _revealed[bId]!;
    _pot.addAll([aCard, bCard]);
    _lastRoundCards = {aId: aCard, bId: bCard};
    _revealed.clear();

    final cmp = aCard.rank.index.compareTo(bCard.rank.index);
    if (cmp == 0) {
      _lastRoundWinnerId = null;
      _warPending = true;
      for (final id in [aId, bId]) {
        final deck = _decks[id]!;
        if (deck.isEmpty) {
          _finishGame(id == aId ? bId : aId);
          return;
        }
        _pot.add(deck.removeAt(0));
      }
      return;
    }

    final winner = cmp > 0 ? aId : bId;
    _lastRoundWinnerId = winner;
    _warPending = false;
    _decks[winner]!.addAll(_pot);
    _pot.clear();
    _checkGameOver();
  }

  void _checkGameOver() {
    for (final entry in _decks.entries) {
      if (entry.value.isEmpty) {
        _finishGame(_otherPlayer(entry.key));
        return;
      }
    }
  }

  void _finishGame(String winner) {
    winnerId = winner;
    started = false;
    lastMatchScores = {for (final id in _decks.keys) id: id == winner ? 1 : -1};
  }

  @override
  List<Map<String, dynamic>> autoActionCandidates(String playerId) => const [
        {'type': 'flip'},
      ];

  @override
  Map<String, dynamic> snapshotFor(String viewerId) {
    final opponents = _players.where((p) => p.id != viewerId).toList();
    final opponentId = opponents.isEmpty ? null : opponents.first.id;
    final lastMine = _lastRoundCards?[viewerId];
    final lastOpp = opponentId == null ? null : _lastRoundCards?[opponentId];

    return {
      'players': _players
          .map((p) => {'id': p.id, 'name': p.name, 'isHost': p.isHost, 'connected': p.connected})
          .toList(),
      'started': started,
      'winnerId': winnerId,
      'myDeckCount': _decks[viewerId]?.length ?? 0,
      'opponentId': opponentId,
      'opponentName': opponents.isEmpty ? null : opponents.first.name,
      'opponentDeckCount': opponentId == null ? 0 : (_decks[opponentId]?.length ?? 0),
      'potCount': _pot.length,
      'warPending': _warPending,
      'iHaveFlipped': _revealed.containsKey(viewerId),
      'opponentHasFlipped': opponentId != null && _revealed.containsKey(opponentId),
      'myRevealedCard': _revealed[viewerId]?.toJson(),
      'lastRoundMyCard': lastMine?.toJson(),
      'lastRoundOpponentCard': lastOpp?.toJson(),
      'lastRoundOutcome': _lastRoundCards == null
          ? null
          : (_lastRoundWinnerId == null ? 'war' : (_lastRoundWinnerId == viewerId ? 'win' : 'lose')),
    };
  }
}
