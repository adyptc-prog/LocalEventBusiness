import 'dart:math';

import '../../core/game_engine.dart';
import 'uno_card.dart';
import 'uno_player.dart';

/// Motorul de reguli UNO — rulează exclusiv pe gazdă, sursă unică de adevăr.
/// Clienții primesc doar snapshot-uri JSON.
///
/// Fără "stacking": un +2/+4 se aplică imediat asupra jucătorului următor
/// (trage și pierde tura pe loc), nu se poate răspunde cu alt +2/+4 ca să
/// paseze mai departe penalizarea — regula oficială UNO.
class UnoEngine extends GameEngine {
  static const int startingHandSize = 7;
  static const int minPlayersStatic = 2;
  static const int maxPlayersStatic = 6;

  @override
  int get minPlayers => minPlayersStatic;
  @override
  int get maxPlayers => maxPlayersStatic;

  final List<UnoPlayer> players = [];
  List<UnoCard> _drawPile = [];
  final List<UnoCard> discardPile = [];
  int currentPlayerIndex = 0;
  int direction = 1;
  UnoColor? activeColor;
  String? winnerId;
  bool hasDrawnThisTurn = false;
  String? lastEventMessage;

  @override
  bool started = false;

  @override
  Map<String, int>? lastMatchScores;

  UnoPlayer? get currentPlayer =>
      (!started || players.isEmpty) ? null : players[currentPlayerIndex];

  UnoCard? get topCard => discardPile.isEmpty ? null : discardPile.last;

  bool get canStart =>
      !started && players.length >= minPlayers && players.length <= maxPlayers;

  @override
  void addPlayer({required String id, required String name, required bool isHost}) {
    if (players.length >= maxPlayers) {
      throw StateError('Camera este plină (maxim $maxPlayers jucători).');
    }
    players.add(UnoPlayer(id: id, name: name, isHost: isHost));
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
      throw StateError(
          'Nu se poate porni jocul (minim $minPlayers, maxim $maxPlayers jucători).');
    }
    final deck = UnoCard.fullDeck()..shuffle(Random());
    _drawPile = deck;
    discardPile.clear();

    for (final p in players) {
      p.hand = _drawPile.take(startingHandSize).toList();
      _drawPile = _drawPile.skip(startingHandSize).toList();
    }

    // Prima carte de pe foc nu poate fi wild, altfel jocul ar începe cerând
    // deja alegerea unei culori fără niciun jucător activ.
    UnoCard first = _drawPile.removeLast();
    while (first.isWild) {
      _drawPile.insert(0, first);
      _drawPile.shuffle(Random());
      first = _drawPile.removeLast();
    }
    discardPile.add(first);

    activeColor = first.color;
    direction = 1;
    currentPlayerIndex = 0;
    winnerId = null;
    hasDrawnThisTurn = false;
    lastEventMessage = null;
    lastMatchScores = null;
    started = true;
    notifyListeners();
  }

  UnoPlayer _requirePlayer(String playerId) {
    final matches = players.where((p) => p.id == playerId);
    if (matches.isEmpty) throw StateError('Jucător necunoscut.');
    return matches.first;
  }

  bool isValidPlay(String playerId, UnoCard card) {
    if (!started || winnerId != null) return false;
    if (currentPlayer?.id != playerId) return false;
    final player = _requirePlayer(playerId);
    if (!player.hand.contains(card)) return false;
    if (card.type == UnoCardType.wild) return true;
    if (card.type == UnoCardType.wildDrawFour) {
      // Oficial: Wild +4 e permis doar dacă n-ai nicio carte colorată care
      // s-ar potrivi normal cu culoarea activă.
      final hasMatchingColor = player.hand.any((c) => !c.isWild && c.color == activeColor);
      return !hasMatchingColor;
    }
    if (card.color == activeColor) return true;
    final top = topCard;
    if (top == null) return true;
    if (card.type == UnoCardType.number && top.type == UnoCardType.number) {
      return card.number == top.number;
    }
    return card.type == top.type;
  }

  @override
  void applyAction(String playerId, Map<String, dynamic> action) {
    switch (action['type']) {
      case 'play_card':
        final card = UnoCard.fromJson(action['card'] as Map<String, dynamic>);
        final chosenColorName = action['chosenColor'] as String?;
        final chosenColor = chosenColorName == null ? null : UnoColor.values.byName(chosenColorName);
        _playCard(playerId, card, chosenColor: chosenColor);
        break;
      case 'draw_card':
        _drawCard(playerId);
        break;
      case 'pass_turn':
        _passTurn(playerId);
        break;
      default:
        throw StateError('Acțiune necunoscută.');
    }
  }

  /// Jucătorul aflat la [steps] poziții distanță de cel curent, în sensul de
  /// joc curent (calculat înainte de a avansa efectiv tura).
  UnoPlayer _playerAt(int steps) {
    final n = players.length;
    final idx = ((currentPlayerIndex + direction * steps) % n + n) % n;
    return players[idx];
  }

  void _advanceTurn(int steps) {
    final n = players.length;
    if (n == 0) return;
    currentPlayerIndex = ((currentPlayerIndex + direction * steps) % n + n) % n;
  }

  void _playCard(String playerId, UnoCard card, {UnoColor? chosenColor}) {
    if (!isValidPlay(playerId, card)) throw StateError('Mutare invalidă.');
    if (card.isWild && chosenColor == null) {
      throw StateError('Trebuie aleasă o culoare pentru această carte.');
    }

    final player = _requirePlayer(playerId);
    player.hand.remove(card);
    discardPile.add(card);
    hasDrawnThisTurn = false;

    if (player.hand.isEmpty) {
      activeColor = card.isWild ? chosenColor : card.color;
      winnerId = playerId;
      started = false;
      lastMatchScores = _computeMatchScores(playerId);
      lastEventMessage = '${player.name} a terminat cărțile!';
      notifyListeners();
      return;
    }

    switch (card.type) {
      case UnoCardType.number:
        activeColor = card.color;
        lastEventMessage = null;
        _advanceTurn(1);
        break;
      case UnoCardType.skip:
        activeColor = card.color;
        lastEventMessage = '${_playerAt(1).name} a fost sărit.';
        _advanceTurn(2);
        break;
      case UnoCardType.reverse:
        activeColor = card.color;
        if (players.length == 2) {
          // La 2 jucători, Reverse se comportă ca un Skip: adversarul e
          // sărit și rândul rămâne tot la cel care a jucat cartea.
          lastEventMessage = '${_playerAt(1).name} a fost sărit.';
        } else {
          direction *= -1;
          lastEventMessage = 'Sensul de joc s-a inversat.';
          _advanceTurn(1);
        }
        break;
      case UnoCardType.drawTwo:
        {
          activeColor = card.color;
          final target = _playerAt(1);
          for (var i = 0; i < 2; i++) {
            target.hand.add(_drawFromPile());
          }
          lastEventMessage = '${target.name} a tras 2 cărți și a fost sărit.';
          _advanceTurn(2);
          break;
        }
      case UnoCardType.wild:
        activeColor = chosenColor;
        lastEventMessage = null;
        _advanceTurn(1);
        break;
      case UnoCardType.wildDrawFour:
        {
          activeColor = chosenColor;
          final target = _playerAt(1);
          for (var i = 0; i < 4; i++) {
            target.hand.add(_drawFromPile());
          }
          lastEventMessage = '${target.name} a tras 4 cărți și a fost sărit.';
          _advanceTurn(2);
          break;
        }
    }
    notifyListeners();
  }

  void _drawCard(String playerId) {
    if (!started || winnerId != null) throw StateError('Jocul nu este activ.');
    if (currentPlayer?.id != playerId) throw StateError('Nu este rândul tău.');
    if (hasDrawnThisTurn) throw StateError('Ai tras deja o carte tura asta.');
    final player = _requirePlayer(playerId);
    player.hand.add(_drawFromPile());
    hasDrawnThisTurn = true;
    lastEventMessage = null;
    notifyListeners();
  }

  void _passTurn(String playerId) {
    if (!started || winnerId != null) throw StateError('Jocul nu este activ.');
    if (currentPlayer?.id != playerId) throw StateError('Nu este rândul tău.');
    // Cu pachetul complet epuizat nu ai ce trage — poți trece direct,
    // altfel un jucător fără carte jucabilă ar bloca partida.
    if (!hasDrawnThisTurn && _canDraw) throw StateError('Trebuie să tragi o carte înainte să treci tura.');
    hasDrawnThisTurn = false;
    _advanceTurn(1);
    notifyListeners();
  }

  /// `false` doar când toate cărțile sunt în mâinile jucătorilor (pachetul
  /// gol și pe foc doar cartea de sus) — atunci nu se mai poate trage nimic.
  bool get _canDraw => _drawPile.isNotEmpty || discardPile.length > 1;

  UnoCard _drawFromPile() {
    if (_drawPile.isEmpty) {
      if (discardPile.length <= 1) {
        throw StateError('Nu mai sunt cărți disponibile în pachet.');
      }
      final top = discardPile.removeLast();
      _drawPile = List.of(discardPile)..shuffle(Random());
      discardPile.clear();
      discardPile.add(top);
    }
    return _drawPile.removeLast();
  }

  /// Câștigătorul primește suma valorilor cărților rămase în mâinile
  /// celorlalți; fiecare dintre ei pierde exact atâtea puncte cât valorează
  /// propria mână rămasă.
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

  int _handValue(List<UnoCard> hand) => hand.fold(0, (sum, c) => sum + c.points);

  @override
  List<Map<String, dynamic>> autoActionCandidates(String playerId) => const [
        {'type': 'draw_card'},
        {'type': 'pass_turn'},
      ];

  @override
  Map<String, dynamic> snapshotFor(String viewerId) {
    return {
      'viewerId': viewerId,
      'players': players
          .map((p) => {
                'id': p.id,
                'name': p.name,
                'isHost': p.isHost,
                'connected': p.connected,
                'handCount': p.hand.length,
              })
          .toList(),
      'started': started,
      'winnerId': winnerId,
      'myHand': players.any((p) => p.id == viewerId)
          ? _requirePlayer(viewerId).hand.map((c) => c.toJson()).toList()
          : const [],
      'drawPileCount': _drawPile.length,
      'discardTop': topCard?.toJson(),
      'activeColor': activeColor?.name,
      'direction': direction,
      'currentPlayerId': currentPlayer?.id,
      'hasDrawnThisTurn': hasDrawnThisTurn,
      'lastEventMessage': lastEventMessage,
    };
  }
}
