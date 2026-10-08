import 'dart:math';

import '../../core/game_engine.dart';
import '../../models/card.dart';
import 'macao_player.dart';
import 'macao_snapshot.dart';
import '../../l10n/tr.dart';

/// Motorul de reguli Macao — rulează exclusiv pe gazdă și este sursa unică
/// de adevăr pentru starea jocului. Clienții primesc doar snapshot-uri JSON.
///
/// Cărți speciale: Asul schimbă culoarea cerută (singura carte "wild",
/// jucabilă oricând); 2 și 3 obligă jucătorul următor să tragă 2, respectiv
/// 3 cărți — se pot înlănțui (de către alt jucător, la rândul lui) cu alt
/// 2/3 care se potrivește la număr (alt 2 peste un 2, alt 3 peste un 3) sau
/// la culoare cu cea de pe foc, valorile adunându-se. 4 obligă jucătorul
/// următor să stea pe loc atâtea tururi câte cărți de 4 s-au jucat — acesta
/// se poate apăra jucând la rândul lui una sau mai multe cărți de 4 (orice
/// culoare), caz în care povara trece mai departe la jucătorul de după el,
/// cu numărul de tururi adunat din toate cărțile de 4 jucate până atunci.
/// Un jucător care are mai multe cărți de aceeași valoare le poate juca pe
/// toate deodată, într-o singură mutare — e nevoie doar ca prima să fie
/// jucabilă normal; efectele cărților speciale din pachet (trageri, tururi
/// de stat pe loc) se adună pentru toate.
class MacaoEngine extends GameEngine {
  static const int startingHandSize = 5;
  static const int minPlayersStatic = 2;
  static const int maxPlayersStatic = 4;

  @override
  int get minPlayers => minPlayersStatic;
  @override
  int get maxPlayers => maxPlayersStatic;

  final List<MacaoPlayer> players = [];
  List<PlayingCard> _drawPile = [];
  final List<PlayingCard> discardPile = [];
  int currentPlayerIndex = 0;
  Suit? requestedSuit;
  int pendingDraw = 0;
  int pendingSkip = 0;
  String? winnerId;

  @override
  bool started = false;

  @override
  Map<String, int>? lastMatchScores;

  MacaoPlayer? get currentPlayer =>
      (!started || players.isEmpty) ? null : players[currentPlayerIndex];

  PlayingCard? get topCard => discardPile.isEmpty ? null : discardPile.last;

  bool get canStart =>
      !started && players.length >= minPlayers && players.length <= maxPlayers;

  @override
  void addPlayer({required String id, required String name, required bool isHost}) {
    if (players.length >= maxPlayers) {
      throw GameError('err.roomFull', {'max': maxPlayers});
    }
    players.add(MacaoPlayer(id: id, name: name, isHost: isHost));
    notifyListeners();
  }

  void removePlayer(String id) {
    players.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  @override
  void markDisconnected(String id) {
    final matches = players.where((p) => p.id == id);
    if (matches.isEmpty) return;
    matches.first.connected = false;
    notifyListeners();
  }

  @override
  void markConnected(String id) {
    final matches = players.where((p) => p.id == id);
    if (matches.isEmpty) return;
    matches.first.connected = true;
    notifyListeners();
  }

  @override
  void startGame() {
    if (!canStart) {
      throw GameError('err.cannotStart', {'min': minPlayers, 'max': maxPlayers});
    }
    final deck = PlayingCard.fullDeck()..shuffle(Random());
    _drawPile = deck;
    discardPile.clear();

    for (final p in players) {
      p.hand = _drawPile.take(startingHandSize).toList();
      _drawPile = _drawPile.skip(startingHandSize).toList();
    }

    // Prima carte de pe foc nu poate fi Asul ("wild"), altfel jocul ar
    // începe cerând deja alegerea unei culori fără niciun jucător activ.
    PlayingCard first = _drawPile.removeLast();
    while (first.isWild) {
      _drawPile.insert(0, first);
      _drawPile.shuffle(Random());
      first = _drawPile.removeLast();
    }
    discardPile.add(first);

    requestedSuit = first.suit;
    pendingDraw = 0;
    pendingSkip = 0;
    currentPlayerIndex = 0;
    winnerId = null;
    lastMatchScores = null;
    started = true;
    notifyListeners();
  }

  MacaoPlayer _requirePlayer(String playerId) {
    final matches = players.where((p) => p.id == playerId);
    if (matches.isEmpty) throw GameError('err.unknownPlayer');
    return matches.first;
  }

  bool isValidPlay(String playerId, PlayingCard card) {
    if (!started || winnerId != null) return false;
    if (currentPlayer?.id != playerId) return false;
    final player = _requirePlayer(playerId);
    if (!player.hand.contains(card)) return false;
    if (pendingSkip > 0) return card.isFour;
    if (pendingDraw > 0) {
      if (!(card.isTwo || card.isThree)) return false;
      if (topCard == null) return true;
      return card.suit == topCard!.suit || card.rank == topCard!.rank;
    }
    if (card.isWild) return true;
    if (requestedSuit != null && card.suit == requestedSuit) return true;
    if (topCard != null && card.rank == topCard!.rank) return true;
    return false;
  }

  @override
  void applyAction(String playerId, Map<String, dynamic> action) {
    switch (action['type']) {
      case 'play_card':
        final cards = (action['cards'] as List<dynamic>)
            .map((c) => PlayingCard.fromJson(c as Map<String, dynamic>))
            .toList();
        final chosenSuitName = action['chosenSuit'] as String?;
        final chosenSuit = chosenSuitName == null ? null : Suit.values.byName(chosenSuitName);
        _playCards(playerId, cards, chosenSuit: chosenSuit);
        break;
      case 'draw_card':
        _drawCard(playerId);
        break;
      default:
        throw GameError('err.unknownAction');
    }
  }

  /// Joacă una sau mai multe cărți deodată — toate trebuie să aibă aceeași
  /// valoare, iar prima trebuie să fie o mutare validă în mod normal (restul
  /// se leagă automat de ea, fiind la fel). Efectele cărților speciale
  /// (trageri, sărituri de tură) se adună pentru toate cărțile jucate.
  void _playCards(String playerId, List<PlayingCard> cards, {Suit? chosenSuit}) {
    if (cards.isEmpty) throw GameError('err.noCardsToPlay');
    if (cards.any((c) => c.rank != cards.first.rank)) {
      throw GameError('err.sameRankOnly');
    }
    if (!isValidPlay(playerId, cards.first)) {
      throw GameError('err.invalidMove');
    }
    if (cards.first.isWild && chosenSuit == null) {
      throw GameError('err.mustChooseColor');
    }

    final player = _requirePlayer(playerId);
    for (final card in cards) {
      if (!player.hand.contains(card)) throw GameError('err.notYourCard');
    }
    for (final card in cards) {
      player.hand.remove(card);
      discardPile.add(card);
    }

    for (final card in cards) {
      if (card.isTwo) {
        pendingDraw += 2;
        requestedSuit = card.suit;
      } else if (card.isThree) {
        pendingDraw += 3;
        requestedSuit = card.suit;
      } else if (card.isFour) {
        pendingSkip += 1;
        requestedSuit = card.suit;
      } else if (card.isAce) {
        requestedSuit = chosenSuit;
      } else {
        requestedSuit = card.suit;
      }
    }

    if (player.hand.isEmpty) {
      winnerId = playerId;
      started = false;
      lastMatchScores = _computeMatchScores(playerId);
      notifyListeners();
      return;
    }

    // Jucătorul următor preia povara (dacă e cazul): fie se apără cu propriile
    // cărți de 4 (adunând mai departe la pendingSkip), fie o acceptă integral
    // data viitoare când trage — vezi _drawCard.
    _advanceTurn(1);
    notifyListeners();
  }

  /// Scorul clasic la jocurile de tip Macao/Uno: câștigătorul primește suma
  /// valorilor cărților rămase în mâinile celorlalți, iar fiecare dintre ei
  /// pierde exact atâtea puncte cât valorează propria mână rămasă.
  Map<String, int> _computeMatchScores(String winnerId) {
    final scores = <String, int>{};
    var winnerGain = 0;
    for (final p in players) {
      if (p.id == winnerId) continue;
      final penalty = _handValue(p.hand);
      scores[p.id] = -penalty;
      winnerGain += penalty;
    }
    scores[winnerId] = winnerGain;
    return scores;
  }

  int _handValue(List<PlayingCard> hand) => hand.fold(0, (sum, c) => sum + c.value);

  void _drawCard(String playerId) {
    if (!started || winnerId != null) throw GameError('err.gameNotActive');
    if (currentPlayer?.id != playerId) throw GameError('err.notYourTurn');

    // Nu are (sau nu vrea să joace) o carte de 4 — acceptă să stea pe loc
    // atâtea tururi cât s-a acumulat, fără să tragă nicio carte.
    if (pendingSkip > 0) {
      final steps = pendingSkip;
      pendingSkip = 0;
      _advanceTurn(steps);
      notifyListeners();
      return;
    }

    final player = _requirePlayer(playerId);
    final count = pendingDraw > 0 ? pendingDraw : 1;
    // Cu pachetul complet epuizat, jucătorul trage cât se poate (posibil
    // nimic) și tura merge mai departe — altfel partida s-ar bloca.
    for (var i = 0; i < count && _canDraw; i++) {
      player.hand.add(_drawFromPile());
    }
    pendingDraw = 0;
    _advanceTurn(1);
    notifyListeners();
  }

  /// `false` doar când toate cărțile sunt în mâinile jucătorilor (pachetul
  /// gol și pe foc doar cartea de sus) — atunci nu se mai poate trage nimic.
  bool get _canDraw => _drawPile.isNotEmpty || discardPile.length > 1;

  PlayingCard _drawFromPile() {
    if (_drawPile.isEmpty) {
      if (discardPile.length <= 1) {
        throw GameError('err.deckEmpty');
      }
      final top = discardPile.removeLast();
      _drawPile = List.of(discardPile)..shuffle(Random());
      discardPile.clear();
      discardPile.add(top);
    }
    return _drawPile.removeLast();
  }

  void _advanceTurn(int steps) {
    final n = players.length;
    if (n == 0) return;
    currentPlayerIndex = (currentPlayerIndex + steps) % n;
  }

  @override
  List<Map<String, dynamic>> autoActionCandidates(String playerId) => const [
        {'type': 'draw_card'},
      ];

  @override
  Map<String, dynamic> snapshotFor(String viewerId) => MacaoSnapshot(
        viewerId: viewerId,
        players: players
            .map((p) => PlayerSummary(
                  id: p.id,
                  name: p.name,
                  isHost: p.isHost,
                  connected: p.connected,
                  handCount: p.hand.length,
                  hand: p.id == viewerId ? List.of(p.hand) : null,
                ))
            .toList(),
        drawPileCount: _drawPile.length,
        discardTop: topCard,
        currentPlayerId: currentPlayer?.id,
        requestedSuit: requestedSuit,
        pendingDraw: pendingDraw,
        pendingSkip: pendingSkip,
        winnerId: winnerId,
        started: started,
      ).toJson();
}
