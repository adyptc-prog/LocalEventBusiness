import 'uno_card.dart';
import '../../l10n/tr.dart';

class UnoPlayerSummary {
  final String id;
  final String name;
  final bool isHost;
  final bool connected;
  final int handCount;

  const UnoPlayerSummary({
    required this.id,
    required this.name,
    required this.isHost,
    required this.connected,
    required this.handCount,
  });

  factory UnoPlayerSummary.fromJson(Map<String, dynamic> json) => UnoPlayerSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        isHost: json['isHost'] as bool,
        connected: json['connected'] as bool? ?? true,
        handCount: json['handCount'] as int? ?? 0,
      );
}

/// Vedere (read-only) asupra unei partide de UNO, personalizată per jucător:
/// propria mână completă, restul doar câte cărți au.
class UnoSnapshot {
  final String viewerId;
  final List<UnoPlayerSummary> players;
  final bool started;
  final String? winnerId;
  final List<UnoCard> myHand;
  final int drawPileCount;
  final UnoCard? discardTop;
  final UnoColor? activeColor;
  final int direction;
  final String? currentPlayerId;
  final bool hasDrawnThisTurn;
  final LocalizedText? lastEventMessage;
  final UnoCard? drawnCard;
  final String? unannouncedLastCardId;

  const UnoSnapshot({
    required this.viewerId,
    required this.players,
    required this.started,
    required this.winnerId,
    required this.myHand,
    required this.drawPileCount,
    required this.discardTop,
    required this.activeColor,
    required this.direction,
    required this.currentPlayerId,
    required this.hasDrawnThisTurn,
    required this.lastEventMessage,
    this.drawnCard,
    this.unannouncedLastCardId,
  });

  UnoPlayerSummary get me => players.firstWhere((p) => p.id == viewerId);
  List<UnoPlayerSummary> get opponents => players.where((p) => p.id != viewerId).toList();
  bool get isMyTurn => started && currentPlayerId == viewerId;

  String? get winnerName {
    if (winnerId == null) return null;
    final matches = players.where((p) => p.id == winnerId);
    return matches.isEmpty ? null : matches.first.name;
  }

  /// Oglindă locală a regulii din [UnoEngine.isValidPlay] — folosită doar
  /// pentru evidențierea cărților jucabile în UI; gazda rămâne sursa unică
  /// de adevăr.
  bool isCardPlayable(UnoCard card) {
    if (!isMyTurn) return false;
    if (hasDrawnThisTurn && card != drawnCard) return false;
    if (card.type == UnoCardType.wild) return true;
    if (card.type == UnoCardType.wildDrawFour) {
      final hasMatchingColor = myHand.any((c) => !c.isWild && c.color == activeColor);
      return !hasMatchingColor;
    }
    if (card.color == activeColor) return true;
    final top = discardTop;
    if (top == null) return true;
    if (card.type == UnoCardType.number && top.type == UnoCardType.number) {
      return card.number == top.number;
    }
    return card.type == top.type;
  }

  factory UnoSnapshot.fromJson(Map<String, dynamic> json) => UnoSnapshot(
        viewerId: json['viewerId'] as String? ?? '',
        players: (json['players'] as List<dynamic>)
            .map((p) => UnoPlayerSummary.fromJson(p as Map<String, dynamic>))
            .toList(),
        started: json['started'] as bool,
        winnerId: json['winnerId'] as String?,
        myHand: (json['myHand'] as List<dynamic>? ?? const [])
            .map((c) => UnoCard.fromJson(c as Map<String, dynamic>))
            .toList(),
        drawPileCount: json['drawPileCount'] as int? ?? 0,
        discardTop:
            json['discardTop'] == null ? null : UnoCard.fromJson(json['discardTop'] as Map<String, dynamic>),
        activeColor: json['activeColor'] == null ? null : UnoColor.values.byName(json['activeColor'] as String),
        direction: json['direction'] as int? ?? 1,
        currentPlayerId: json['currentPlayerId'] as String?,
        hasDrawnThisTurn: json['hasDrawnThisTurn'] as bool? ?? false,
        lastEventMessage: LocalizedText.fromJson(json['lastEventMessage']),
        drawnCard: json['drawnCard'] == null ? null : UnoCard.fromJson(json['drawnCard'] as Map<String, dynamic>),
        unannouncedLastCardId: json['unannouncedLastCardId'] as String?,
      );
}
