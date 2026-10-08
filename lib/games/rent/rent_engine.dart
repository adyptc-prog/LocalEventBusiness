import 'dart:math';

import '../../core/game_engine.dart';
import '../../models/card.dart';
import 'rent_categories.dart';

class _RentPlayerInfo {
  final String id;
  final String name;
  final bool isHost;
  bool connected = true;

  _RentPlayerInfo({required this.id, required this.name, required this.isHost});
}

class _TrickCard {
  final String playerId;
  final PlayingCard card;
  const _TrickCard(this.playerId, this.card);

  Map<String, dynamic> toJson() => {'playerId': playerId, 'card': card.toJson()};
}

class _RoundResult {
  final String category;
  final Map<String, int> roundScores;
  final Map<String, int> totals;

  const _RoundResult({required this.category, required this.roundScores, required this.totals});

  Map<String, dynamic> toJson() => {'category': category, 'roundScores': roundScores, 'totals': totals};
}

/// Motorul jocului Rent — exact 4 jucători, pachet de 32 de cărți (7-A),
/// 8 în mâna fiecăruia. 6 categorii, jucate câte una pe rundă, alese pe
/// rând de fiecare jucător (rotație, fără repetare): 4 sunt jocuri de
/// levată fără atu (Popa roșu, Dame, Romburi, Totale — penalizare; Imperiale
/// — aceleași cărți, dar bonus), iar "Rent" e o cursă separată de scăpat
/// cărțile, construind câte o secvență per culoare pornind de la 10.
class RentEngine extends GameEngine {
  static const int minPlayersStatic = 4;
  static const int maxPlayersStatic = 4;
  static const int handSize = 8;

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

  final List<_RentPlayerInfo> _players = [];
  final Set<String> _usedCategories = {};
  int _chooserIndex = 0;
  String? _activeCategory;
  bool _choosingCategory = true;

  final Map<String, List<PlayingCard>> _hands = {};
  List<String> _turnOrder = [];
  int _turnIndex = 0;

  // levată (Popa roșu / Dame / Romburi / Totale / Imperiale)
  final List<_TrickCard> _currentTrick = [];
  List<_TrickCard>? _lastTrick;
  String? _lastTrickWinnerId;
  Map<String, List<PlayingCard>> _capturedThisRound = {};

  // Rent
  final Map<Suit, List<PlayingCard>> _rentSequences = {};
  final List<String> _rentFinishOrder = [];

  final Map<String, int> _cumulativeScore = {};
  final List<_RoundResult> _history = [];

  @override
  void addPlayer({required String id, required String name, required bool isHost}) {
    if (_players.length >= maxPlayers) {
      throw StateError('Camera este plină (maxim $maxPlayers jucători).');
    }
    _players.add(_RentPlayerInfo(id: id, name: name, isHost: isHost));
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
    if (started) throw StateError('Jocul e deja în desfășurare.');
    if (_players.length != minPlayers) {
      throw StateError('Sunt necesari exact $minPlayers jucători.');
    }
    _usedCategories.clear();
    _chooserIndex = 0;
    _cumulativeScore
      ..clear()
      ..addEntries(_players.map((p) => MapEntry(p.id, 0)));
    _history.clear();
    winnerId = null;
    isDraw = false;
    lastMatchScores = null;
    started = true;
    _choosingCategory = true;
    _activeCategory = null;
    notifyListeners();
  }

  List<PlayingCard> _buildDeck() => [
        for (final suit in Suit.values)
          for (final rank in Rank.values)
            if (rank.index >= Rank.seven.index) PlayingCard(suit, rank),
      ];

  void _startRound(String category) {
    final deck = _buildDeck()..shuffle(Random());
    var offset = 0;
    for (final p in _players) {
      _hands[p.id] = deck.sublist(offset, offset + handSize);
      offset += handSize;
    }

    _currentTrick.clear();
    _lastTrick = null;
    _lastTrickWinnerId = null;
    _capturedThisRound = {for (final p in _players) p.id: <PlayingCard>[]};
    _rentSequences.clear();
    _rentFinishOrder.clear();

    _turnOrder = [for (var i = 0; i < _players.length; i++) _players[(_chooserIndex + i) % _players.length].id];
    _turnIndex = 0;

    if (category == 'rent') {
      _prepareRentTurn();
    }
  }

  @override
  void applyAction(String playerId, Map<String, dynamic> action) {
    switch (action['type']) {
      case 'choose_category':
        _chooseCategory(playerId, action['category'] as String);
        break;
      case 'play_card':
        final card = PlayingCard.fromJson(action['card'] as Map<String, dynamic>);
        if (_activeCategory == 'rent') {
          _playRentCard(playerId, card);
        } else {
          _playTrickCard(playerId, card);
        }
        break;
      default:
        throw StateError('Acțiune necunoscută.');
    }
  }

  void _chooseCategory(String playerId, String category) {
    if (!started || !_choosingCategory) throw StateError('Nu este faza de alegere a categoriei.');
    if (_players[_chooserIndex].id != playerId) throw StateError('Nu este rândul tău să alegi.');
    if (!kRentCategories.contains(category)) throw StateError('Categorie necunoscută.');
    if (_usedCategories.contains(category)) throw StateError('Categoria a fost deja jucată.');
    _activeCategory = category;
    _choosingCategory = false;
    _startRound(category);
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Popa roșu / Dame / Romburi / Totale / Imperiale — levată fără atu
  // ---------------------------------------------------------------------

  void _playTrickCard(String playerId, PlayingCard card) {
    if (!started || _choosingCategory) throw StateError('Nu este faza de joc.');
    if (_turnOrder.isEmpty || _turnOrder[_turnIndex] != playerId) throw StateError('Nu este rândul tău.');
    final hand = _hands[playerId]!;
    if (!hand.contains(card)) throw StateError('Nu ai această carte.');
    if (_currentTrick.isNotEmpty) {
      final ledSuit = _currentTrick.first.card.suit;
      final hasLedSuit = hand.any((c) => c.suit == ledSuit);
      if (hasLedSuit && card.suit != ledSuit) {
        throw StateError('Trebuie să joci culoarea cerută dacă o ai.');
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
    _capturedThisRound[winner.playerId]!.addAll(_currentTrick.map((tc) => tc.card));
    _lastTrick = List.of(_currentTrick);
    _lastTrickWinnerId = winner.playerId;
    _currentTrick.clear();

    final roundOver = _hands.values.every((h) => h.isEmpty);
    if (roundOver) {
      _finishTrickRound();
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
      if (tc.card.suit == ledSuit && tc.card.rank.value > winner.card.rank.value) {
        winner = tc;
      }
    }
    return winner;
  }

  void _finishTrickRound() {
    final roundScores = <String, int>{};
    for (final p in _players) {
      final captured = _capturedThisRound[p.id] ?? const <PlayingCard>[];
      var score = 0;
      for (final c in captured) {
        score += _cardScoreFor(_activeCategory!, c);
      }
      roundScores[p.id] = score;
    }
    _completeRound(roundScores);
  }

  int _cardScoreFor(String category, PlayingCard c) {
    final isPopaRosu = c.suit == Suit.hearts && c.rank == Rank.king;
    final isDama = c.rank == Rank.queen;
    final isRomb = c.suit == Suit.diamonds;
    switch (category) {
      case 'popa_rosu':
        return isPopaRosu ? -100 : 0;
      case 'dame':
        return isDama ? -30 : 0;
      case 'romburi':
        return isRomb ? -20 : 0;
      case 'totale':
        return (isPopaRosu ? -100 : 0) + (isDama ? -30 : 0) + (isRomb ? -20 : 0);
      case 'imperiale':
        return (isPopaRosu ? 100 : 0) + (isDama ? 30 : 0) + (isRomb ? 20 : 0);
      default:
        return 0;
    }
  }

  // ---------------------------------------------------------------------
  // Rent — cursă de scăpat cărțile, secvențe per culoare pornind de la 10
  // ---------------------------------------------------------------------

  bool _isValidRentMove(PlayingCard card) {
    final seq = _rentSequences[card.suit];
    if (seq == null || seq.isEmpty) return card.rank == Rank.ten;
    final minVal = seq.first.rank.value;
    final maxVal = seq.last.rank.value;
    return card.rank.value == minVal - 1 || card.rank.value == maxVal + 1;
  }

  bool _hasAnyValidRentMove(String playerId) {
    final hand = _hands[playerId];
    if (hand == null || hand.isEmpty) return false;
    return hand.any(_isValidRentMove);
  }

  /// Avansează la următorul jucător care chiar are o mutare posibilă,
  /// sărind peste cei fără — dacă niciunul nu mai are nicio mutare (blocaj
  /// total, foarte improbabil dat fiind cum se construiesc secvențele),
  /// încheiem runda defensiv ca să nu rămână jocul blocat.
  void _prepareRentTurn() {
    var attempts = 0;
    final n = _turnOrder.length;
    while (attempts < n) {
      final pid = _turnOrder[_turnIndex];
      if (_hasAnyValidRentMove(pid)) return;
      _turnIndex = (_turnIndex + 1) % n;
      attempts++;
    }
    _finishRentRound();
  }

  void _playRentCard(String playerId, PlayingCard card) {
    if (!started || _choosingCategory) throw StateError('Nu este faza de joc.');
    if (_turnOrder.isEmpty || _turnOrder[_turnIndex] != playerId) throw StateError('Nu este rândul tău.');
    final hand = _hands[playerId]!;
    if (!hand.contains(card)) throw StateError('Nu ai această carte.');
    if (!_isValidRentMove(card)) throw StateError('Mutare invalidă — nu se leagă de nicio secvență deschisă.');

    hand.remove(card);
    final seq = _rentSequences.putIfAbsent(card.suit, () => []);
    seq.add(card);
    seq.sort((a, b) => a.rank.value.compareTo(b.rank.value));

    if (hand.isEmpty && !_rentFinishOrder.contains(playerId)) {
      _rentFinishOrder.add(playerId);
    }

    final allEmpty = _hands.values.every((h) => h.isEmpty);
    if (allEmpty) {
      _finishRentRound();
      notifyListeners();
      return;
    }

    _turnIndex = (_turnIndex + 1) % _turnOrder.length;
    _prepareRentTurn();
    notifyListeners();
  }

  void _finishRentRound() {
    final order = List<String>.from(_rentFinishOrder);
    for (final p in _players) {
      if (!order.contains(p.id)) order.add(p.id);
    }
    const placementScores = [300, 200, 100, 0];
    final roundScores = <String, int>{};
    for (var i = 0; i < order.length; i++) {
      roundScores[order[i]] = i < placementScores.length ? placementScores[i] : 0;
    }
    _completeRound(roundScores);
  }

  // ---------------------------------------------------------------------

  void _completeRound(Map<String, int> roundScores) {
    for (final p in _players) {
      final s = roundScores[p.id] ?? 0;
      _cumulativeScore[p.id] = (_cumulativeScore[p.id] ?? 0) + s;
    }
    _usedCategories.add(_activeCategory!);
    _history.add(_RoundResult(
      category: _activeCategory!,
      roundScores: Map.of(roundScores),
      totals: Map.of(_cumulativeScore),
    ));
    _activeCategory = null;
    _hands.clear();

    if (_usedCategories.length >= kRentCategories.length) {
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
      _chooserIndex = (_chooserIndex + 1) % _players.length;
      _choosingCategory = true;
    }
  }

  @override
  List<Map<String, dynamic>> autoActionCandidates(String playerId) => [
        for (final category in kRentCategories) {'type': 'choose_category', 'category': category},
        for (final card in _hands[playerId] ?? const <PlayingCard>[]) {'type': 'play_card', 'card': card.toJson()},
      ];

  @override
  Map<String, dynamic> snapshotFor(String viewerId) {
    return {
      'players': _players
          .map((p) => {
                'id': p.id,
                'name': p.name,
                'isHost': p.isHost,
                'connected': p.connected,
                'handCount': _hands[p.id]?.length ?? 0,
              })
          .toList(),
      'started': started,
      'winnerId': winnerId,
      'isDraw': isDraw,
      'usedCategories': _usedCategories.toList(),
      'choosingCategory': _choosingCategory,
      'chooserId': _players.isEmpty ? null : _players[_chooserIndex].id,
      'activeCategory': _activeCategory,
      'myHand': _hands[viewerId]?.map((c) => c.toJson()).toList(),
      'currentPlayerId': (started && !_choosingCategory && _turnOrder.isNotEmpty) ? _turnOrder[_turnIndex] : null,
      'currentTrick': _currentTrick.map((tc) => tc.toJson()).toList(),
      'lastTrick': _lastTrick?.map((tc) => tc.toJson()).toList(),
      'lastTrickWinnerId': _lastTrickWinnerId,
      'rentSequences': _rentSequences.map((suit, cards) => MapEntry(suit.name, cards.map((c) => c.toJson()).toList())),
      'rentFinishOrder': _rentFinishOrder,
      'cumulativeScores': Map<String, int>.from(_cumulativeScore),
      'history': _history.map((r) => r.toJson()).toList(),
    };
  }
}
