import '../../models/card.dart';

/// Reprezentarea unui jucător așa cum e vizibilă de un anumit "viewer":
/// propria mână completă, dar pentru adversari doar numărul de cărți.
class PlayerSummary {
  final String id;
  final String name;
  final bool isHost;
  final bool connected;
  final int handCount;
  final List<PlayingCard>? hand;

  const PlayerSummary({
    required this.id,
    required this.name,
    required this.isHost,
    required this.connected,
    required this.handCount,
    this.hand,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isHost': isHost,
        'connected': connected,
        'handCount': handCount,
        if (hand != null) 'hand': hand!.map((c) => c.toJson()).toList(),
      };

  factory PlayerSummary.fromJson(Map<String, dynamic> json) => PlayerSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        isHost: json['isHost'] as bool,
        connected: json['connected'] as bool? ?? true,
        handCount: json['handCount'] as int,
        hand: (json['hand'] as List<dynamic>?)
            ?.map((c) => PlayingCard.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

/// Vedere (read-only) asupra stării jocului, trimisă de gazdă către fiecare
/// jucător (personalizată: fiecare își vede doar propria mână) și folosită
/// identic de UI atât pe gazdă, cât și pe clienți.
class MacaoSnapshot {
  final String viewerId;
  final List<PlayerSummary> players;
  final int drawPileCount;
  final PlayingCard? discardTop;
  final String? currentPlayerId;
  final Suit? requestedSuit;
  final int pendingDraw;
  final int pendingSkip;
  final String? winnerId;
  final bool started;
  final String? unannouncedLastCardId;

  const MacaoSnapshot({
    required this.viewerId,
    required this.players,
    required this.drawPileCount,
    required this.discardTop,
    required this.currentPlayerId,
    required this.requestedSuit,
    required this.pendingDraw,
    required this.pendingSkip,
    required this.winnerId,
    required this.started,
    this.unannouncedLastCardId,
  });

  PlayerSummary get me => players.firstWhere((p) => p.id == viewerId);
  List<PlayerSummary> get opponents =>
      players.where((p) => p.id != viewerId).toList();
  bool get isMyTurn => started && currentPlayerId == viewerId;
  String? get winnerName {
    if (winnerId == null) return null;
    final matches = players.where((p) => p.id == winnerId);
    return matches.isEmpty ? null : matches.first.name;
  }

  /// Verificare locală (pentru evidențierea în UI a cărților jucabile).
  /// Gazda rămâne mereu sursa de adevăr — aceasta e doar o oglindă a regulii
  /// din [MacaoEngine.isValidPlay], folosită de client fără acces la motorul complet.
  bool isCardPlayable(PlayingCard card) {
    if (!isMyTurn) return false;
    if (pendingSkip > 0) return card.isFour;
    if (pendingDraw > 0) {
      if (!(card.isTwo || card.isThree)) return false;
      if (discardTop == null) return true;
      return card.suit == discardTop!.suit || card.rank == discardTop!.rank;
    }
    if (card.isWild) return true;
    if (requestedSuit != null && card.suit == requestedSuit) return true;
    if (discardTop != null && card.rank == discardTop!.rank) return true;
    return false;
  }

  Map<String, dynamic> toJson() => {
        'viewerId': viewerId,
        'players': players.map((p) => p.toJson()).toList(),
        'drawPileCount': drawPileCount,
        'discardTop': discardTop?.toJson(),
        'currentPlayerId': currentPlayerId,
        'requestedSuit': requestedSuit?.name,
        'pendingDraw': pendingDraw,
        'pendingSkip': pendingSkip,
        'winnerId': winnerId,
        'started': started,
        'unannouncedLastCardId': unannouncedLastCardId,
      };

  factory MacaoSnapshot.fromJson(Map<String, dynamic> json) => MacaoSnapshot(
        viewerId: json['viewerId'] as String,
        players: (json['players'] as List<dynamic>)
            .map((p) => PlayerSummary.fromJson(p as Map<String, dynamic>))
            .toList(),
        drawPileCount: json['drawPileCount'] as int,
        discardTop: json['discardTop'] == null
            ? null
            : PlayingCard.fromJson(json['discardTop'] as Map<String, dynamic>),
        currentPlayerId: json['currentPlayerId'] as String?,
        requestedSuit: json['requestedSuit'] == null
            ? null
            : Suit.values.byName(json['requestedSuit'] as String),
        pendingDraw: json['pendingDraw'] as int,
        pendingSkip: json['pendingSkip'] as int? ?? 0,
        winnerId: json['winnerId'] as String?,
        started: json['started'] as bool,
        unannouncedLastCardId: json['unannouncedLastCardId'] as String?,
      );
}
