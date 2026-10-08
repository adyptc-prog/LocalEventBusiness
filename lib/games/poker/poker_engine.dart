import 'dart:async';
import 'dart:math';

import '../../core/game_engine.dart';
import '../../models/card.dart';
import 'poker_hand_evaluator.dart';

class _PokerPlayerInfo {
  final String id;
  final String name;
  final bool isHost;
  bool connected = true;
  int chips = PokerEngine.startingStack;
  List<PlayingCard> holeCards = [];
  bool folded = false;
  bool allIn = false;
  bool busted = false;
  int betThisRound = 0;
  int betThisHand = 0;

  _PokerPlayerInfo({required this.id, required this.name, required this.isHost});
}

class _Pot {
  final int amount;
  final Set<String> eligiblePlayerIds;
  const _Pot({required this.amount, required this.eligiblePlayerIds});
}

class _ShowdownResult {
  final String playerId;
  final List<PlayingCard> cards;
  final String handLabel;
  final int won;

  const _ShowdownResult({required this.playerId, required this.cards, required this.handLabel, required this.won});

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'cards': cards.map((c) => c.toJson()).toList(),
        'handLabel': handLabel,
        'won': won,
      };
}

/// Motorul jocului Poker (Texas Hold'em) — 2-6 jucători, blinduri fixe,
/// implementare completă: preflop/flop/turn/river, fold/check/call/raise/
/// all-in, pot-uri secundare (side pots) când cineva intră all-in cu mai
/// puține fise, showdown cu evaluare completă a mâinilor. Se joacă mâini
/// succesive (dealerul se rotește) până rămâne un singur jucător cu fise —
/// acela câștigă sesiunea.
class PokerEngine extends GameEngine {
  static const int minPlayersStatic = 2;
  static const int maxPlayersStatic = 6;
  static const int startingStack = 1000;
  static const int smallBlind = 10;
  static const int bigBlind = 20;

  @override
  int get minPlayers => minPlayersStatic;
  @override
  int get maxPlayers => maxPlayersStatic;

  @override
  bool started = false;

  @override
  Map<String, int>? lastMatchScores;

  String? winnerId;

  final List<_PokerPlayerInfo> _players = [];
  int _dealerSeat = -1;
  List<PlayingCard> _deck = [];
  final List<PlayingCard> _community = [];

  String _street = 'preflop'; // preflop | flop | turn | river | showdown
  int _currentBet = 0;
  int _minRaiseIncrement = bigBlind;
  List<String> _actingOrder = [];
  int _actIndex = 0;
  final Set<String> _stillToAct = {};

  List<_ShowdownResult>? _lastShowdown;

  /// Pauza dintre mâini (cât se vede rezultatul) — anulată la o pornire
  /// nouă, ca o mână programată din sesiunea veche să nu se suprapună.
  Timer? _nextHandTimer;
  String? _lastHandSummary;

  _PokerPlayerInfo _playerFor(String id) => _players.firstWhere((p) => p.id == id);

  String? get currentPlayerId =>
      (!started || _street == 'showdown' || _actingOrder.isEmpty) ? null : _actingOrder[_actIndex];

  @override
  void addPlayer({required String id, required String name, required bool isHost}) {
    if (_players.length >= maxPlayers) {
      throw StateError('Camera este plină (maxim $maxPlayers jucători).');
    }
    _players.add(_PokerPlayerInfo(id: id, name: name, isHost: isHost));
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
    if (_players.length < minPlayers || _players.length > maxPlayers) {
      throw StateError('Sunt necesari $minPlayers-$maxPlayers jucători.');
    }
    for (final p in _players) {
      p.chips = startingStack;
      p.busted = false;
    }
    _nextHandTimer?.cancel();
    _nextHandTimer = null;
    _dealerSeat = -1;
    winnerId = null;
    lastMatchScores = null;
    started = true;
    _startHand();
    notifyListeners();
  }

  List<String> _activeSeatsFromDealer() {
    final n = _players.length;
    return [
      for (var i = 0; i < n; i++)
        if (!_players[(_dealerSeat + i) % n].busted) _players[(_dealerSeat + i) % n].id,
    ];
  }

  void _startHand() {
    final n = _players.length;
    do {
      _dealerSeat = (_dealerSeat + 1) % n;
    } while (_players[_dealerSeat].busted);

    for (final p in _players) {
      p.holeCards = [];
      p.folded = p.busted;
      p.allIn = false;
      p.betThisRound = 0;
      p.betThisHand = 0;
    }
    _community.clear();
    _lastShowdown = null;
    _lastHandSummary = null;
    _deck = PlayingCard.fullDeck()..shuffle(Random());

    final active = _activeSeatsFromDealer();
    _actingOrder = active;

    final sbId = active.length == 2 ? active[0] : active[1];
    final bbId = active.length == 2 ? active[1] : active[2];
    _postBlind(sbId, smallBlind);
    _postBlind(bbId, bigBlind);
    _currentBet = _playerFor(bbId).betThisRound;
    _minRaiseIncrement = bigBlind;

    for (final id in active) {
      _playerFor(id).holeCards = [_deck.removeLast(), _deck.removeLast()];
    }

    _street = 'preflop';
    final startIndex = active.length == 2 ? 0 : (active.indexOf(bbId) + 1) % active.length;
    _stillToAct
      ..clear()
      ..addAll(active.where((id) => !_playerFor(id).allIn));
    _setActIndexToFirstActiveFrom(startIndex);
  }

  void _postBlind(String playerId, int amount) {
    final p = _playerFor(playerId);
    final pay = min(amount, p.chips);
    p.chips -= pay;
    p.betThisRound += pay;
    p.betThisHand += pay;
    if (p.chips == 0) p.allIn = true;
  }

  void _setActIndexToFirstActiveFrom(int startIndex) {
    final n = _actingOrder.length;
    var idx = startIndex % n;
    for (var attempts = 0; attempts < n; attempts++) {
      final p = _playerFor(_actingOrder[idx]);
      if (!p.folded && !p.allIn) {
        _actIndex = idx;
        return;
      }
      idx = (idx + 1) % n;
    }
    _actIndex = startIndex % n;
  }

  @override
  void applyAction(String playerId, Map<String, dynamic> action) {
    if (action['type'] != 'poker_action') throw StateError('Acțiune necunoscută.');
    switch (action['action']) {
      case 'fold':
        _fold(playerId);
        break;
      case 'check':
        _check(playerId);
        break;
      case 'call':
        _call(playerId);
        break;
      case 'raise':
        _raise(playerId, action['amount'] as int);
        break;
      case 'all_in':
        _allIn(playerId);
        break;
      default:
        throw StateError('Acțiune necunoscută.');
    }
  }

  void _requireTurn(String playerId) {
    if (!started) throw StateError('Jocul nu este activ.');
    if (currentPlayerId != playerId) throw StateError('Nu este rândul tău.');
  }

  void _fold(String playerId) {
    _requireTurn(playerId);
    _playerFor(playerId).folded = true;
    _stillToAct.remove(playerId);
    _afterAction();
  }

  void _check(String playerId) {
    _requireTurn(playerId);
    final p = _playerFor(playerId);
    if (p.betThisRound != _currentBet) {
      throw StateError('Nu poți da check — trebuie să egalezi $_currentBet.');
    }
    _stillToAct.remove(playerId);
    _afterAction();
  }

  void _call(String playerId) {
    _requireTurn(playerId);
    final p = _playerFor(playerId);
    final toCall = _currentBet - p.betThisRound;
    if (toCall <= 0) throw StateError('Nu mai ai nimic de egalat — dă check.');
    final pay = min(toCall, p.chips);
    p.chips -= pay;
    p.betThisRound += pay;
    p.betThisHand += pay;
    if (p.chips == 0) p.allIn = true;
    _stillToAct.remove(playerId);
    _afterAction();
  }

  void _raise(String playerId, int amount) {
    _requireTurn(playerId);
    final p = _playerFor(playerId);
    if (amount < _currentBet + _minRaiseIncrement) {
      throw StateError('Raise minim: ${_currentBet + _minRaiseIncrement}.');
    }
    final need = amount - p.betThisRound;
    if (need >= p.chips) {
      _allIn(playerId);
      return;
    }
    p.chips -= need;
    _minRaiseIncrement = amount - _currentBet;
    p.betThisRound = amount;
    p.betThisHand += need;
    _currentBet = amount;
    _reopenActionExcept(playerId);
    _afterAction();
  }

  void _allIn(String playerId) {
    _requireTurn(playerId);
    final p = _playerFor(playerId);
    final pay = p.chips;
    p.chips = 0;
    p.betThisRound += pay;
    p.betThisHand += pay;
    p.allIn = true;
    if (p.betThisRound > _currentBet) {
      _minRaiseIncrement = max(_minRaiseIncrement, p.betThisRound - _currentBet);
      _currentBet = p.betThisRound;
      _reopenActionExcept(playerId);
    } else {
      _stillToAct.remove(playerId);
    }
    _afterAction();
  }

  void _reopenActionExcept(String playerId) {
    _stillToAct
      ..clear()
      ..addAll(_actingOrder.where((id) {
        final other = _playerFor(id);
        return id != playerId && !other.folded && !other.allIn;
      }));
  }

  void _afterAction() {
    final nonFolded = _actingOrder.where((id) => !_playerFor(id).folded).toList();
    if (nonFolded.length == 1) {
      _awardPotToSingleWinner(nonFolded.first);
      return;
    }

    final canAct = nonFolded.where((id) => !_playerFor(id).allIn).toList();
    if (canAct.isEmpty) {
      _stillToAct.clear();
      _runOutRemainingStreets();
      return;
    }

    if (_stillToAct.isEmpty) {
      _advanceStreet();
      return;
    }

    _setActIndexToFirstActiveFrom(_actIndex + 1);
    notifyListeners();
  }

  void _dealNextStreetCards() {
    if (_street == 'preflop') {
      _deck.removeLast();
      _community.addAll([_deck.removeLast(), _deck.removeLast(), _deck.removeLast()]);
      _street = 'flop';
    } else if (_street == 'flop') {
      _deck.removeLast();
      _community.add(_deck.removeLast());
      _street = 'turn';
    } else if (_street == 'turn') {
      _deck.removeLast();
      _community.add(_deck.removeLast());
      _street = 'river';
    }
  }

  void _runOutRemainingStreets() {
    while (_street != 'river') {
      _dealNextStreetCards();
    }
    _resolveShowdown();
  }

  void _advanceStreet() {
    for (final p in _players) {
      p.betThisRound = 0;
    }
    if (_street == 'river') {
      _resolveShowdown();
      return;
    }
    _dealNextStreetCards();
    _currentBet = 0;
    _minRaiseIncrement = bigBlind;

    final nonFolded = _actingOrder.where((id) => !_playerFor(id).folded).toList();
    final canAct = nonFolded.where((id) => !_playerFor(id).allIn).toList();
    // Dacă rămâne cel mult un jucător care mai poate paria (restul sunt
    // all-in), nu mai există nicio pariere posibilă — nimeni n-ar putea
    // răspunde la un pariu — deci se dau direct cărțile rămase.
    if (canAct.length <= 1) {
      _runOutRemainingStreets();
      return;
    }
    _stillToAct
      ..clear()
      ..addAll(canAct);
    _setActIndexToFirstActiveFrom(1);
    notifyListeners();
  }

  List<_Pot> _calculatePots(List<String> contenders) {
    final contributions = {for (final id in _actingOrder) id: _playerFor(id).betThisHand};
    final levels = contributions.values.where((v) => v > 0).toSet().toList()..sort();
    final pots = <_Pot>[];
    var previousLevel = 0;
    for (final level in levels) {
      final contributingCount = contributions.values.where((v) => v >= level).length;
      final amount = (level - previousLevel) * contributingCount;
      final eligible = contenders.where((id) => contributions[id]! >= level).toSet();
      if (amount > 0 && eligible.isNotEmpty) {
        pots.add(_Pot(amount: amount, eligiblePlayerIds: eligible));
      }
      previousLevel = level;
    }
    return pots;
  }

  void _awardPotToSingleWinner(String playerId) {
    final total = _actingOrder.fold<int>(0, (sum, id) => sum + _playerFor(id).betThisHand);
    _playerFor(playerId).chips += total;
    _lastShowdown = null;
    _lastHandSummary = '${_playerFor(playerId).name} a câștigat $total puncte (ceilalți au renunțat)';
    _finishHand();
  }

  void _resolveShowdown() {
    _street = 'showdown';
    final contenders = _actingOrder.where((id) => !_playerFor(id).folded).toList();
    final scoresByPlayer = <String, HandScore>{
      for (final id in contenders) id: bestHandFrom([..._playerFor(id).holeCards, ..._community]),
    };

    final pots = _calculatePots(contenders);
    final wonAmounts = <String, int>{for (final id in contenders) id: 0};
    for (final pot in pots) {
      HandScore? best;
      for (final id in pot.eligiblePlayerIds) {
        final s = scoresByPlayer[id]!;
        if (best == null || s.compareTo(best) > 0) best = s;
      }
      final winners = pot.eligiblePlayerIds.where((id) => scoresByPlayer[id]!.compareTo(best!) == 0).toList();
      final share = pot.amount ~/ winners.length;
      final remainder = pot.amount - share * winners.length;
      for (var i = 0; i < winners.length; i++) {
        wonAmounts[winners[i]] = wonAmounts[winners[i]]! + share + (i < remainder ? 1 : 0);
      }
    }
    for (final entry in wonAmounts.entries) {
      _playerFor(entry.key).chips += entry.value;
    }

    _lastShowdown = [
      for (final id in contenders)
        _ShowdownResult(
          playerId: id,
          cards: List.of(_playerFor(id).holeCards),
          handLabel: scoresByPlayer[id]!.label,
          won: wonAmounts[id]!,
        ),
    ];
    _lastHandSummary = null;
    _finishHand();
  }

  void _finishHand() {
    for (final p in _players) {
      if (p.chips <= 0) p.busted = true;
    }
    final remaining = _players.where((p) => !p.busted).toList();
    if (remaining.length <= 1) {
      started = false;
      winnerId = remaining.isNotEmpty ? remaining.first.id : null;
      lastMatchScores = {for (final p in _players) p.id: p.chips - startingStack};
      notifyListeners();
      return;
    }
    // Notificăm acum, cât încă se vede rezultatul mâinii (showdown/cine a
    // câștigat) — dacă am porni mâna următoare imediat, starea s-ar
    // suprascrie înainte să apuce cineva să vadă rezultatul prin rețea.
    notifyListeners();
    _nextHandTimer?.cancel();
    _nextHandTimer = Timer(const Duration(seconds: 4), () {
      _nextHandTimer = null;
      if (!started) return;
      _startHand();
      notifyListeners();
    });
  }

  @override
  List<Map<String, dynamic>> autoActionCandidates(String playerId) => const [
        {'type': 'poker_action', 'action': 'check'},
        {'type': 'poker_action', 'action': 'fold'},
      ];

  @override
  Map<String, dynamic> snapshotFor(String viewerId) {
    final dealerId = (_dealerSeat >= 0 && _dealerSeat < _players.length) ? _players[_dealerSeat].id : null;
    return {
      'players': _players
          .map((p) => {
                'id': p.id,
                'name': p.name,
                'isHost': p.isHost,
                'connected': p.connected,
                'chips': p.chips,
                'folded': p.folded,
                'allIn': p.allIn,
                'busted': p.busted,
                'betThisRound': p.betThisRound,
              })
          .toList(),
      'started': started,
      'winnerId': winnerId,
      'street': _street,
      'community': _community.map((c) => c.toJson()).toList(),
      'pot': _actingOrder.fold<int>(0, (sum, id) => sum + _playerFor(id).betThisHand),
      'currentBet': _currentBet,
      'minRaiseIncrement': _minRaiseIncrement,
      'currentPlayerId': currentPlayerId,
      'dealerId': dealerId,
      'myHoleCards': _players.any((p) => p.id == viewerId)
          ? _playerFor(viewerId).holeCards.map((c) => c.toJson()).toList()
          : const [],
      'lastShowdown': _lastShowdown?.map((r) => r.toJson()).toList(),
      'lastHandSummary': _lastHandSummary,
    };
  }
}
