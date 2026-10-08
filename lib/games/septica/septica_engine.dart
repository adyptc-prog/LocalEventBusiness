import 'dart:math';

import '../../core/game_engine.dart';
import '../../models/card.dart';
import '../../l10n/tr.dart';

class _SepticaPlayerInfo {
  final String id;
  final String name;
  final bool isHost;
  bool connected = true;

  _SepticaPlayerInfo({required this.id, required this.name, required this.isHost});
}

/// Motorul jocului Șeptica — 2-4 jucători, pachet de la 7 în sus (32 de
/// cărți; la 3 jucători se scot 2 optari ca să se împartă exact la 10 de
/// fiecare, iar cei 2 optari rămași devin tăietură, pe lângă cele 4 șepci).
///
/// O rundă: conducătorul deschide o carte (numărul disputat); pe rând,
/// FIECARE ceilalt jucător e obligat să pună câte o carte, oricare, fără
/// restricție — asta e un "tur". Dacă în tur nimeni n-a nimerit numărul
/// disputat sau o tăietură, conducătorul ia direct tot ce e pe masă. Dacă
/// cineva a nimerit (ultimul care a nimerit în tur devine "provocatorul"),
/// se deschide o luptă: doar conducătorul alege — continuă (pune el o carte
/// cu numărul disputat sau o tăietură, se joacă un tur nou) sau renunță
/// (provocatorul curent ia tot). Cine ia cărțile devine noul conducător și
/// trage primul la completarea mâinilor la 4 (ceilalți, pe rând, după el;
/// la ultima completare, dacă pachetul nu mai ajunge pentru toți, ce rămâne
/// se împarte cât mai egal). Punctează doar Așii și Zecarii capturați.
class SepticaEngine extends GameEngine {
  static const int minPlayersStatic = 2;
  static const int maxPlayersStatic = 4;
  static const int handSize = 4;

  @override
  int get minPlayers => minPlayersStatic;
  @override
  int get maxPlayers => maxPlayersStatic;

  @override
  bool started = false;

  @override
  Map<String, int>? lastMatchScores;

  String? winnerId;
  bool isDraw = false;

  final List<_SepticaPlayerInfo> _players = [];
  final Map<String, List<PlayingCard>> _hands = {};
  final Map<String, List<PlayingCard>> _captured = {};
  List<PlayingCard> _drawPile = [];
  final List<PlayingCard> _table = [];

  Set<Rank> _wildRanks = {Rank.seven};

  String _leaderId = '';
  Rank? _contestedRank;
  List<String> _circuitQueue = [];
  String? _challengerId;
  bool _awaitingLeaderDecision = false;

  String? _lastPlayedBy;
  PlayingCard? _lastPlayedCard;
  bool _lastPlayQualified = false;

  bool get canStart =>
      !started && _players.length >= minPlayers && _players.length <= maxPlayers;

  String? get currentPlayerId {
    if (!started) return null;
    if (_table.isEmpty || _awaitingLeaderDecision) return _leaderId;
    if (_circuitQueue.isNotEmpty) return _circuitQueue.first;
    return _leaderId;
  }

  @override
  void addPlayer({required String id, required String name, required bool isHost}) {
    if (_players.length >= maxPlayers) {
      throw GameError('err.roomFull', {'max': maxPlayers});
    }
    _players.add(_SepticaPlayerInfo(id: id, name: name, isHost: isHost));
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
    if (!canStart) {
      throw GameError('err.cannotStart', {'min': minPlayers, 'max': maxPlayers});
    }
    _wildRanks = {Rank.seven};
    _drawPile = [
      for (final suit in Suit.values)
        for (final rank in Rank.values)
          if (rank.index >= Rank.seven.index) PlayingCard(suit, rank),
    ];
    if (_players.length == 3) {
      // 32 de cărți nu se împart exact la 3 — scoatem 2 optari (rămân 30,
      // 10 de fiecare); cei 2 optari rămași devin și ei tăietură.
      for (final c in _drawPile.where((c) => c.rank == Rank.eight).take(2).toList()) {
        _drawPile.remove(c);
      }
      _wildRanks = {Rank.seven, Rank.eight};
    }
    _drawPile.shuffle(Random());

    _table.clear();
    for (final p in _players) {
      _hands[p.id] = [];
      _captured[p.id] = [];
    }
    _leaderId = _players.first.id;
    _refillHands(_leaderId);

    _contestedRank = null;
    _circuitQueue = [];
    _challengerId = null;
    _awaitingLeaderDecision = false;
    _lastPlayedBy = null;
    _lastPlayedCard = null;
    _lastPlayQualified = false;
    winnerId = null;
    isDraw = false;
    lastMatchScores = null;
    started = true;
    notifyListeners();
  }

  List<String> _seatOrderFrom(String startId) {
    final n = _players.length;
    final startIdx = _players.indexWhere((p) => p.id == startId);
    return [for (var i = 0; i < n; i++) _players[(startIdx + i) % n].id];
  }

  List<String> _buildCircuitQueue() =>
      _seatOrderFrom(_leaderId).skip(1).where((id) => _hands[id]!.isNotEmpty).toList();

  /// Dă cărți pornind cu [startId] (câștigătorul luptei anterioare), apoi
  /// ceilalți în ordine, pe rând câte una (nu unul complet, apoi altul) —
  /// dacă pachetul ajunge pentru toți la 4, rezultatul e identic cu "primul
  /// se completează complet, apoi următorul"; dacă nu ajunge, diferența
  /// dintre jucători e de cel mult o carte, cu prioritate pentru [startId].
  void _refillHands(String startId) {
    final order = _seatOrderFrom(startId);
    var dealt = true;
    while (dealt && _drawPile.isNotEmpty) {
      dealt = false;
      for (final id in order) {
        if (_drawPile.isEmpty) break;
        final hand = _hands[id]!;
        if (hand.length < handSize) {
          hand.add(_drawPile.removeLast());
          dealt = true;
        }
      }
    }
  }

  @override
  void applyAction(String playerId, Map<String, dynamic> action) {
    switch (action['type']) {
      case 'play_card':
        final card = PlayingCard.fromJson(action['card'] as Map<String, dynamic>);
        _playCard(playerId, card);
        break;
      case 'concede':
        _concede(playerId);
        break;
      default:
        throw GameError('err.unknownAction');
    }
  }

  bool _qualifies(PlayingCard card) => card.rank == _contestedRank || _wildRanks.contains(card.rank);

  void _playCard(String playerId, PlayingCard card) {
    if (!started || winnerId != null || isDraw) throw GameError('err.gameNotActive');
    if (currentPlayerId != playerId) throw GameError('err.notYourTurn');
    final hand = _hands[playerId]!;
    if (!hand.contains(card)) throw GameError('err.notYourCard');

    if (_table.isEmpty) {
      // Conducătorul deschide o rundă nouă — orice carte, fără restricție.
      hand.remove(card);
      _table.add(card);
      _contestedRank = card.rank;
      _challengerId = null;
      _lastPlayedBy = playerId;
      _lastPlayedCard = card;
      _lastPlayQualified = false;
      _circuitQueue = _buildCircuitQueue();
      if (_circuitQueue.isEmpty) {
        _resolveCapture(_leaderId);
      }
      notifyListeners();
      return;
    }

    if (_awaitingLeaderDecision) {
      // Conducătorul continuă lupta — obligatoriu o carte care se leagă.
      if (!_qualifies(card)) {
        throw GameError('err.septica.mustMatch');
      }
      hand.remove(card);
      _table.add(card);
      _lastPlayedBy = playerId;
      _lastPlayedCard = card;
      _lastPlayQualified = true;
      _awaitingLeaderDecision = false;
      _circuitQueue = _buildCircuitQueue();
      if (_circuitQueue.isEmpty) {
        // Nimeni nu mai poate răspunde — provocatorul curent rămâne câștigător.
        _resolveCapture(_challengerId!);
      }
      notifyListeners();
      return;
    }

    // Un membru al turului curent — orice carte, fără restricție.
    hand.remove(card);
    _table.add(card);
    final qualifies = _qualifies(card);
    if (qualifies) _challengerId = playerId;
    _lastPlayedBy = playerId;
    _lastPlayedCard = card;
    _lastPlayQualified = qualifies;
    _circuitQueue.removeAt(0);

    if (_circuitQueue.isEmpty) {
      if (_challengerId == null) {
        _resolveCapture(_leaderId);
      } else {
        _awaitingLeaderDecision = true;
      }
    }
    notifyListeners();
  }

  void _concede(String playerId) {
    if (!started || winnerId != null || isDraw) throw GameError('err.gameNotActive');
    if (!_awaitingLeaderDecision) throw GameError('err.septica.cannotConcede');
    if (playerId != _leaderId) throw GameError('err.septica.onlyLeaderConcedes');
    _resolveCapture(_challengerId!);
    notifyListeners();
  }

  void _resolveCapture(String capturerId) {
    _captured[capturerId]!.addAll(_table);
    _table.clear();
    _leaderId = capturerId;
    _contestedRank = null;
    _challengerId = null;
    _awaitingLeaderDecision = false;
    _circuitQueue = [];

    _refillHands(capturerId);

    // Dacă noul conducător tot n-are cărți (pachetul s-a epuizat chiar
    // acum), conducerea trece la primul care mai are.
    if (_hands[_leaderId]!.isEmpty) {
      final next = _seatOrderFrom(_leaderId).where((id) => _hands[id]!.isNotEmpty);
      if (next.isNotEmpty) _leaderId = next.first;
    }

    final allEmpty = _players.every((p) => _hands[p.id]!.isEmpty);
    if (_drawPile.isEmpty && allEmpty) {
      _finishGame();
    }
  }

  void _finishGame() {
    started = false;
    final scores = {for (final p in _players) p.id: _pointsIn(_captured[p.id] ?? const [])};
    lastMatchScores = scores;

    final maxScore = scores.values.reduce((a, b) => a > b ? a : b);
    final leaders = scores.entries.where((e) => e.value == maxScore).map((e) => e.key).toList();
    if (leaders.length == 1) {
      winnerId = leaders.first;
      isDraw = false;
    } else {
      winnerId = null;
      isDraw = true;
    }
  }

  int _pointsIn(List<PlayingCard> cards) =>
      cards.where((c) => c.rank == Rank.ace || c.rank == Rank.ten).length;

  @override
  List<Map<String, dynamic>> autoActionCandidates(String playerId) => [
        {'type': 'concede'},
        for (final card in _hands[playerId] ?? const <PlayingCard>[]) {'type': 'play_card', 'card': card.toJson()},
      ];

  @override
  Map<String, dynamic> snapshotFor(String viewerId) {
    return {
      'viewerId': viewerId,
      'players': _players
          .map((p) => {
                'id': p.id,
                'name': p.name,
                'isHost': p.isHost,
                'connected': p.connected,
                'handCount': _hands[p.id]?.length ?? 0,
                'score': _pointsIn(_captured[p.id] ?? const []),
              })
          .toList(),
      'started': started,
      'winnerId': winnerId,
      'isDraw': isDraw,
      'myHand': _hands[viewerId]?.map((c) => c.toJson()).toList(),
      'drawPileCount': _drawPile.length,
      'tableCards': _table.map((c) => c.toJson()).toList(),
      'currentPlayerId': currentPlayerId,
      'leaderId': started ? _leaderId : null,
      'contestedRank': _contestedRank?.name,
      'wildRanks': _wildRanks.map((r) => r.name).toList(),
      'awaitingLeaderDecision': _awaitingLeaderDecision,
      'challengerId': _challengerId,
      'lastPlayedCard': _lastPlayedCard?.toJson(),
      'lastPlayedById': _lastPlayedBy,
      'lastPlayQualified': _lastPlayQualified,
    };
  }
}
