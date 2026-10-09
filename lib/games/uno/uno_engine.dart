import 'dart:math';

import '../../core/game_engine.dart';
import 'uno_card.dart';
import 'uno_player.dart';
import '../../l10n/tr.dart';

/// Motorul de reguli UNO — rulează exclusiv pe gazdă, sursă unică de adevăr.
/// Clienții primesc doar snapshot-uri JSON.
///
/// Fără "stacking": un +2/+4 se aplică imediat asupra jucătorului următor
/// (trage și pierde tura pe loc), nu se poate răspunde cu alt +2/+4 ca să
/// paseze mai departe penalizarea — regula oficială UNO.
///
/// Tot după regulile oficiale: după ce tragi o carte, poți juca doar acea
/// carte (dacă se potrivește) sau treci; prima carte întoarsă își aplică
/// efectul (Skip / Reverse / +2) asupra primului jucător; dacă ultima carte
/// a câștigătorului e +2/+4, jucătorul următor tot trage cărțile (contează
/// la punctaj); cine rămâne cu o carte trebuie să anunțe „UNO!" — dacă e
/// prins că n-a anunțat, trage [lastCardPenalty] cărți.
class UnoEngine extends GameEngine {
  static const int lastCardPenalty = 2;
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
  LocalizedText? lastEventMessage;

  /// Cartea trasă în tura curentă — singura care mai poate fi jucată.
  UnoCard? _drawnCard;

  /// Jucătorul rămas cu o carte fără să fi anunțat „UNO!" — poate fi prins
  /// de ceilalți până când jucătorul următor își începe tura.
  String? unannouncedLastCardId;

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
      throw GameError('err.roomFull', {'max': maxPlayers});
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
      throw GameError('err.cannotStart', {'min': minPlayers, 'max': maxPlayers});
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
    _drawnCard = null;
    unannouncedLastCardId = null;
    lastEventMessage = null;
    lastMatchScores = null;
    started = true;
    _applyFirstCardEffect(first);
    notifyListeners();
  }

  /// Efectul primei cărți întoarse, ca și cum dealerul (ultimul jucător) ar
  /// fi jucat-o: Skip — primul jucător e sărit; Reverse — sensul se inversează
  /// și dealerul începe; +2 — primul jucător trage 2 și e sărit.
  void _applyFirstCardEffect(UnoCard first) {
    final n = players.length;
    switch (first.type) {
      case UnoCardType.skip:
        lastEventMessage = LocalizedText('uno.event.skipped', {'name': players[0].name});
        currentPlayerIndex = 1 % n;
        break;
      case UnoCardType.reverse:
        direction = -1;
        currentPlayerIndex = n - 1;
        lastEventMessage = const LocalizedText('uno.event.reversed');
        break;
      case UnoCardType.drawTwo:
        for (var i = 0; i < 2; i++) {
          players[0].hand.add(_drawFromPile());
        }
        lastEventMessage = LocalizedText('uno.event.drewTwo', {'name': players[0].name});
        currentPlayerIndex = 1 % n;
        break;
      default:
        break;
    }
  }

  UnoPlayer _requirePlayer(String playerId) {
    final matches = players.where((p) => p.id == playerId);
    if (matches.isEmpty) throw GameError('err.unknownPlayer');
    return matches.first;
  }

  bool isValidPlay(String playerId, UnoCard card) {
    if (!started || winnerId != null) return false;
    if (currentPlayer?.id != playerId) return false;
    final player = _requirePlayer(playerId);
    if (!player.hand.contains(card)) return false;
    // După ce ai tras, doar cartea trasă mai poate fi jucată.
    if (hasDrawnThisTurn && card != _drawnCard) return false;
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
        _playCard(playerId, card, chosenColor: chosenColor, announced: action['announce'] == true);
        break;
      case 'draw_card':
        _drawCard(playerId);
        break;
      case 'pass_turn':
        _passTurn(playerId);
        break;
      case 'announce_last_card':
        _announceLate(playerId);
        break;
      case 'catch_last_card':
        _catchLastCard(playerId);
        break;
      default:
        throw GameError('err.unknownAction');
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

  void _playCard(String playerId, UnoCard card, {UnoColor? chosenColor, bool announced = false}) {
    if (!isValidPlay(playerId, card)) throw GameError('err.invalidMove');
    if (card.isWild && chosenColor == null) {
      throw GameError('err.mustChooseColor');
    }

    final player = _requirePlayer(playerId);
    _closeCatchWindow(playerId);
    player.hand.remove(card);
    discardPile.add(card);
    hasDrawnThisTurn = false;
    _drawnCard = null;
    if (player.hand.length == 1 && !announced) unannouncedLastCardId = playerId;

    if (player.hand.isEmpty) {
      activeColor = card.isWild ? chosenColor : card.color;
      // Oficial: și ultima carte își aplică efectul de tragere — cărțile
      // trase contează la punctajul câștigătorului.
      final finalDraw = card.type == UnoCardType.drawTwo ? 2 : (card.type == UnoCardType.wildDrawFour ? 4 : 0);
      if (finalDraw > 0) {
        final target = _playerAt(1);
        for (var i = 0; i < finalDraw && _canDraw; i++) {
          target.hand.add(_drawFromPile());
        }
      }
      winnerId = playerId;
      started = false;
      lastMatchScores = _computeMatchScores(playerId);
      lastEventMessage = LocalizedText('uno.event.finished', {'name': player.name});
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
        lastEventMessage = LocalizedText('uno.event.skipped', {'name': _playerAt(1).name});
        _advanceTurn(2);
        break;
      case UnoCardType.reverse:
        activeColor = card.color;
        if (players.length == 2) {
          // La 2 jucători, Reverse se comportă ca un Skip: adversarul e
          // sărit și rândul rămâne tot la cel care a jucat cartea.
          lastEventMessage = LocalizedText('uno.event.skipped', {'name': _playerAt(1).name});
        } else {
          direction *= -1;
          lastEventMessage = const LocalizedText('uno.event.reversed');
          _advanceTurn(1);
        }
        break;
      case UnoCardType.drawTwo:
        {
          activeColor = card.color;
          final target = _playerAt(1);
          for (var i = 0; i < 2 && _canDraw; i++) {
            target.hand.add(_drawFromPile());
          }
          lastEventMessage = LocalizedText('uno.event.drewTwo', {'name': target.name});
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
          for (var i = 0; i < 4 && _canDraw; i++) {
            target.hand.add(_drawFromPile());
          }
          lastEventMessage = LocalizedText('uno.event.drewFour', {'name': target.name});
          _advanceTurn(2);
          break;
        }
    }
    notifyListeners();
  }

  void _drawCard(String playerId) {
    if (!started || winnerId != null) throw GameError('err.gameNotActive');
    if (currentPlayer?.id != playerId) throw GameError('err.notYourTurn');
    if (hasDrawnThisTurn) throw GameError('err.uno.alreadyDrew');
    _closeCatchWindow(playerId);
    final player = _requirePlayer(playerId);
    final drawn = _drawFromPile();
    player.hand.add(drawn);
    _drawnCard = drawn;
    hasDrawnThisTurn = true;
    lastEventMessage = null;
    notifyListeners();
  }

  void _passTurn(String playerId) {
    if (!started || winnerId != null) throw GameError('err.gameNotActive');
    if (currentPlayer?.id != playerId) throw GameError('err.notYourTurn');
    // Cu pachetul complet epuizat nu ai ce trage — poți trece direct,
    // altfel un jucător fără carte jucabilă ar bloca partida.
    if (!hasDrawnThisTurn && _canDraw) throw GameError('err.uno.mustDrawFirst');
    _closeCatchWindow(playerId);
    hasDrawnThisTurn = false;
    _drawnCard = null;
    _advanceTurn(1);
    notifyListeners();
  }

  /// Fereastra în care cineva poate fi prins că n-a anunțat „UNO!" se
  /// închide când alt jucător își începe tura.
  void _closeCatchWindow(String actingPlayerId) {
    if (unannouncedLastCardId != null && unannouncedLastCardId != actingPlayerId) {
      unannouncedLastCardId = null;
    }
  }

  void _announceLate(String playerId) {
    if (!started || winnerId != null) throw GameError('err.gameNotActive');
    if (unannouncedLastCardId != playerId) throw GameError('err.lastCard.nothingToAnnounce');
    unannouncedLastCardId = null;
    notifyListeners();
  }

  void _catchLastCard(String catcherId) {
    if (!started || winnerId != null) throw GameError('err.gameNotActive');
    final target = unannouncedLastCardId;
    if (target == null || target == catcherId) throw GameError('err.lastCard.nobodyToCatch');
    _requirePlayer(catcherId);
    final player = _requirePlayer(target);
    for (var i = 0; i < lastCardPenalty && _canDraw; i++) {
      player.hand.add(_drawFromPile());
    }
    unannouncedLastCardId = null;
    notifyListeners();
  }

  /// `false` doar când toate cărțile sunt în mâinile jucătorilor (pachetul
  /// gol și pe foc doar cartea de sus) — atunci nu se mai poate trage nimic.
  bool get _canDraw => _drawPile.isNotEmpty || discardPile.length > 1;

  UnoCard _drawFromPile() {
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
      // Doar jucătorul care a tras vede ce carte a tras.
      'drawnCard': hasDrawnThisTurn && currentPlayer?.id == viewerId ? _drawnCard?.toJson() : null,
      'unannouncedLastCardId': unannouncedLastCardId,
      'lastEventMessage': lastEventMessage?.toJson(),
    };
  }
}
