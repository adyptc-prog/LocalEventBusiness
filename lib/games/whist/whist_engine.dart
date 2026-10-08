import 'dart:math';

import '../../core/game_engine.dart';
import '../../models/card.dart';
import '../../l10n/tr.dart';

class _WhistPlayerInfo {
  final String id;
  final String name;
  final bool isHost;
  bool connected = true;

  _WhistPlayerInfo({required this.id, required this.name, required this.isHost});
}

class _TrickCard {
  final String playerId;
  final PlayingCard card;
  const _TrickCard(this.playerId, this.card);

  Map<String, dynamic> toJson() => {'playerId': playerId, 'card': card.toJson()};
}

class _RoundResult {
  final int roundIndex;
  final int handSize;
  final Suit? trumpSuit;
  final Map<String, int> bids;
  final Map<String, int> taken;
  final Map<String, int> roundScores;
  final Map<String, int> totals;

  const _RoundResult({
    required this.roundIndex,
    required this.handSize,
    required this.trumpSuit,
    required this.bids,
    required this.taken,
    required this.roundScores,
    required this.totals,
  });

  Map<String, dynamic> toJson() => {
        'roundIndex': roundIndex,
        'handSize': handSize,
        'trumpSuit': trumpSuit?.name,
        'bids': bids,
        'taken': taken,
        'roundScores': roundScores,
        'totals': totals,
      };
}

/// Motorul jocului Whist (tip "Oh Hell") — 3-6 jucători, 15 runde (mâna
/// crește de la 1 la 8 cărți, apoi scade înapoi la 1). Pachetul e redus per
/// masă: se scot rangurile cele mai mici până rămân exact `jucători × 8`
/// cărți, ca la runda de vârf (8/jucător) să se împartă tot pachetul, fără
/// rest. La fiecare rundă: se amestecă din nou, se dă mâna, iar cartea de
/// deasupra restului (talonul) arată atuul — la runda de vârf nu mai rămâne
/// nimic de întors, deci acea rundă se joacă fără atu. Fiecare jucător
/// licitează câte levate crede că ia (ultimul, dealerul, nu poate licita un
/// număr care ar face suma exact egală cu mâna — "screw the dealer"), apoi
/// se joacă levatele (obligatoriu culoarea cerută, dacă o ai). Scor pe
/// rundă: licitație nimerită exact → +licitația; ratată → -diferența.
class WhistEngine extends GameEngine {
  static const int minPlayersStatic = 3;
  static const int maxPlayersStatic = 6;
  static const int maxHandSize = 8;

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

  final List<_WhistPlayerInfo> _players = [];
  List<int> _roundSizes = [];
  int _roundIndex = 0;
  int _dealerIndex = -1;

  final Map<String, List<PlayingCard>> _hands = {};
  PlayingCard? _trumpCard;

  bool _bidding = true;
  List<String> _turnOrder = [];
  int _biddingTurnIndex = 0;
  int _turnIndex = 0;
  final Map<String, int> _bids = {};

  final List<_TrickCard> _currentTrick = [];
  List<_TrickCard>? _lastTrick;
  String? _lastTrickWinnerId;
  final Map<String, int> _tricksWonThisRound = {};

  final Map<String, int> _cumulativeScore = {};
  final List<_RoundResult> _history = [];

  @override
  void addPlayer({required String id, required String name, required bool isHost}) {
    if (_players.length >= maxPlayers) {
      throw GameError('err.roomFull', {'max': maxPlayers});
    }
    _players.add(_WhistPlayerInfo(id: id, name: name, isHost: isHost));
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
    if (_players.length < minPlayers || _players.length > maxPlayers) {
      throw GameError('err.playersRange', {'min': minPlayers, 'max': maxPlayers});
    }
    _roundSizes = [
      for (var i = 1; i <= maxHandSize; i++) i,
      for (var i = maxHandSize - 1; i >= 1; i--) i,
    ];
    _roundIndex = 0;
    _dealerIndex = -1;
    _cumulativeScore
      ..clear()
      ..addEntries(_players.map((p) => MapEntry(p.id, 0)));
    _history.clear();
    winnerId = null;
    isDraw = false;
    lastMatchScores = null;
    started = true;
    _startRound();
    notifyListeners();
  }

  void _startRound() {
    final handSize = _roundSizes[_roundIndex];
    _dealerIndex = (_dealerIndex + 1) % _players.length;

    final deck = _buildTrimmedDeck(_players.length)..shuffle(Random());
    var offset = 0;
    for (final p in _players) {
      _hands[p.id] = deck.sublist(offset, offset + handSize);
      offset += handSize;
    }
    final kitty = deck.sublist(offset);
    _trumpCard = kitty.isEmpty ? null : kitty.first;

    _turnOrder = [for (var i = 0; i < _players.length; i++) _players[(_dealerIndex + 1 + i) % _players.length].id];
    _bids.clear();
    _biddingTurnIndex = 0;
    _bidding = true;
    _currentTrick.clear();
    _lastTrick = null;
    _lastTrickWinnerId = null;
    _turnIndex = 0;
    _tricksWonThisRound
      ..clear()
      ..addEntries(_players.map((p) => MapEntry(p.id, 0)));
  }

  /// Păstrează doar cele mai mari `jucători × 2` ranguri, ca pachetul să se
  /// împartă exact la runda de vârf (8 cărți/jucător), fără rest.
  List<PlayingCard> _buildTrimmedDeck(int players) {
    final ranksNeeded = players * 2;
    final minRankIndex = Rank.values.length - ranksNeeded;
    return [
      for (final suit in Suit.values)
        for (final rank in Rank.values)
          if (rank.index >= minRankIndex) PlayingCard(suit, rank),
    ];
  }

  @override
  void applyAction(String playerId, Map<String, dynamic> action) {
    switch (action['type']) {
      case 'declare_bid':
        _declareBid(playerId, action['amount'] as int);
        break;
      case 'play_card':
        _playCard(playerId, PlayingCard.fromJson(action['card'] as Map<String, dynamic>));
        break;
      default:
        throw GameError('err.unknownAction');
    }
  }

  void _declareBid(String playerId, int amount) {
    if (!started || !_bidding) throw GameError('err.whist.notBidding');
    if (_biddingTurnIndex >= _turnOrder.length || _turnOrder[_biddingTurnIndex] != playerId) {
      throw GameError('err.whist.notYourBid');
    }
    final handSize = _roundSizes[_roundIndex];
    if (amount < 0 || amount > handSize) {
      throw GameError('err.whist.bidRange', {'max': handSize});
    }
    final isLastBidder = _biddingTurnIndex == _turnOrder.length - 1;
    if (isLastBidder) {
      final sumSoFar = _bids.values.fold(0, (a, b) => a + b);
      if (sumSoFar + amount == handSize) {
        throw GameError('err.whist.forbiddenBid', {'amount': amount, 'total': handSize});
      }
    }
    _bids[playerId] = amount;
    _biddingTurnIndex++;
    if (_biddingTurnIndex >= _turnOrder.length) {
      _bidding = false;
    }
    notifyListeners();
  }

  void _playCard(String playerId, PlayingCard card) {
    if (!started || _bidding) throw GameError('err.notPlayingPhase');
    if (_turnOrder.isEmpty || _turnOrder[_turnIndex] != playerId) {
      throw GameError('err.notYourTurn');
    }
    final hand = _hands[playerId]!;
    if (!hand.contains(card)) throw GameError('err.notYourCard');
    if (_currentTrick.isNotEmpty) {
      final ledSuit = _currentTrick.first.card.suit;
      final hasLedSuit = hand.any((c) => c.suit == ledSuit);
      if (hasLedSuit && card.suit != ledSuit) {
        throw GameError('err.mustFollowSuit');
      }
    }

    hand.remove(card);
    _currentTrick.add(_TrickCard(playerId, card));

    if (_currentTrick.length < _turnOrder.length) {
      _turnIndex = (_turnIndex + 1) % _turnOrder.length;
      notifyListeners();
      return;
    }

    final winner = _determineTrickWinner();
    _tricksWonThisRound[winner.playerId] = (_tricksWonThisRound[winner.playerId] ?? 0) + 1;
    _lastTrick = List.of(_currentTrick);
    _lastTrickWinnerId = winner.playerId;
    _currentTrick.clear();

    final roundOver = _hands.values.every((h) => h.isEmpty);
    if (roundOver) {
      _finishRound();
    } else {
      final winnerIndex = _turnOrder.indexOf(winner.playerId);
      _turnOrder = [for (var i = 0; i < _turnOrder.length; i++) _turnOrder[(winnerIndex + i) % _turnOrder.length]];
      _turnIndex = 0;
    }
    notifyListeners();
  }

  _TrickCard _determineTrickWinner() {
    final ledSuit = _currentTrick.first.card.suit;
    var winner = _currentTrick.first;
    for (final tc in _currentTrick.skip(1)) {
      if (_beats(tc.card, winner.card, ledSuit)) winner = tc;
    }
    return winner;
  }

  bool _beats(PlayingCard challenger, PlayingCard current, Suit ledSuit) {
    final trump = _trumpCard?.suit;
    final challengerTrump = trump != null && challenger.suit == trump;
    final currentTrump = trump != null && current.suit == trump;
    if (challengerTrump && !currentTrump) return true;
    if (!challengerTrump && currentTrump) return false;
    if (challengerTrump && currentTrump) return challenger.rank.value > current.rank.value;
    if (challenger.suit == ledSuit && current.suit == ledSuit) {
      return challenger.rank.value > current.rank.value;
    }
    return false; // n-a urmat culoarea cerută și nu e atu — nu poate câștiga
  }

  void _finishRound() {
    final handSize = _roundSizes[_roundIndex];
    final bids = Map<String, int>.from(_bids);
    final taken = Map<String, int>.from(_tricksWonThisRound);
    final roundScores = <String, int>{};
    for (final p in _players) {
      final bid = bids[p.id] ?? 0;
      final got = taken[p.id] ?? 0;
      final score = bid == got ? bid : -(bid - got).abs();
      roundScores[p.id] = score;
      _cumulativeScore[p.id] = (_cumulativeScore[p.id] ?? 0) + score;
    }
    _history.add(_RoundResult(
      roundIndex: _roundIndex,
      handSize: handSize,
      trumpSuit: _trumpCard?.suit,
      bids: bids,
      taken: taken,
      roundScores: roundScores,
      totals: Map<String, int>.from(_cumulativeScore),
    ));

    _roundIndex++;
    if (_roundIndex >= _roundSizes.length) {
      started = false;
      lastMatchScores = Map.of(_cumulativeScore);
      final maxScore = _cumulativeScore.values.reduce((a, b) => a > b ? a : b);
      final leaders = _cumulativeScore.entries.where((e) => e.value == maxScore).map((e) => e.key).toList();
      if (leaders.length == 1) {
        winnerId = leaders.first;
        isDraw = false;
      } else {
        winnerId = null;
        isDraw = true;
      }
    } else {
      _startRound();
    }
  }

  @override
  List<Map<String, dynamic>> autoActionCandidates(String playerId) => [
        if (started && _roundIndex < _roundSizes.length)
          for (var amount = 0; amount <= _roundSizes[_roundIndex]; amount++) {'type': 'declare_bid', 'amount': amount},
        for (final card in _hands[playerId] ?? const <PlayingCard>[]) {'type': 'play_card', 'card': card.toJson()},
      ];

  @override
  Map<String, dynamic> snapshotFor(String viewerId) {
    final handSize = _roundIndex < _roundSizes.length ? _roundSizes[_roundIndex] : 0;
    final currentPlayerId = !started
        ? null
        : (_bidding
            ? (_biddingTurnIndex < _turnOrder.length ? _turnOrder[_biddingTurnIndex] : null)
            : (_turnOrder.isNotEmpty ? _turnOrder[_turnIndex] : null));

    return {
      'players': _players
          .map((p) => {'id': p.id, 'name': p.name, 'isHost': p.isHost, 'connected': p.connected})
          .toList(),
      'started': started,
      'winnerId': winnerId,
      'isDraw': isDraw,
      'roundNumber': _roundIndex + 1,
      'totalRounds': _roundSizes.length,
      'handSize': handSize,
      'phase': _bidding ? 'bidding' : 'playing',
      'trumpCard': _trumpCard?.toJson(),
      'currentPlayerId': currentPlayerId,
      'bids': Map<String, int>.from(_bids),
      'myHand': _hands[viewerId]?.map((c) => c.toJson()).toList(),
      'currentTrick': _currentTrick.map((tc) => tc.toJson()).toList(),
      'lastTrick': _lastTrick?.map((tc) => tc.toJson()).toList(),
      'lastTrickWinnerId': _lastTrickWinnerId,
      'tricksWonThisRound': Map<String, int>.from(_tricksWonThisRound),
      'cumulativeScores': Map<String, int>.from(_cumulativeScore),
      'history': _history.map((r) => r.toJson()).toList(),
    };
  }
}
