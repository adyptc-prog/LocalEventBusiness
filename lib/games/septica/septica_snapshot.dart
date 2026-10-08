import '../../models/card.dart';

class SepticaPlayerSummary {
  final String id;
  final String name;
  final bool isHost;
  final bool connected;
  final int handCount;
  final int score;

  const SepticaPlayerSummary({
    required this.id,
    required this.name,
    required this.isHost,
    required this.connected,
    required this.handCount,
    required this.score,
  });

  factory SepticaPlayerSummary.fromJson(Map<String, dynamic> json) => SepticaPlayerSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        isHost: json['isHost'] as bool,
        connected: json['connected'] as bool? ?? true,
        handCount: json['handCount'] as int? ?? 0,
        score: json['score'] as int? ?? 0,
      );
}

/// Vedere (read-only) asupra unei partide de Șeptica (2-4 jucători),
/// personalizată per jucător: propria mână completă, restul doar informații
/// publice (câte cărți au și scorul lor curent).
class SepticaSnapshot {
  final String viewerId;
  final List<SepticaPlayerSummary> players;
  final bool started;
  final String? winnerId;
  final bool isDraw;
  final List<PlayingCard> myHand;
  final int drawPileCount;
  final List<PlayingCard> tableCards;
  final String? currentPlayerId;
  final String? leaderId;
  final Rank? contestedRank;
  final Set<Rank> wildRanks;
  final bool awaitingLeaderDecision;
  final String? challengerId;
  final PlayingCard? lastPlayedCard;
  final String? lastPlayedById;
  final bool lastPlayQualified;

  const SepticaSnapshot({
    required this.viewerId,
    required this.players,
    required this.started,
    required this.winnerId,
    required this.isDraw,
    required this.myHand,
    required this.drawPileCount,
    required this.tableCards,
    required this.currentPlayerId,
    required this.leaderId,
    required this.contestedRank,
    required this.wildRanks,
    required this.awaitingLeaderDecision,
    required this.challengerId,
    required this.lastPlayedCard,
    required this.lastPlayedById,
    required this.lastPlayQualified,
  });

  SepticaPlayerSummary get me => players.firstWhere((p) => p.id == viewerId);
  List<SepticaPlayerSummary> get opponents => players.where((p) => p.id != viewerId).toList();
  bool get isMyTurn => started && currentPlayerId == viewerId;
  bool get isMyFightDecision => isMyTurn && awaitingLeaderDecision && leaderId == viewerId;
  PlayingCard? get tableTop => tableCards.isEmpty ? null : tableCards.last;

  String? get winnerName {
    if (winnerId == null) return null;
    final matches = players.where((p) => p.id == winnerId);
    return matches.isEmpty ? null : matches.first.name;
  }

  /// Oglindă locală a regulii din [SepticaEngine._playCard]: la deschidere
  /// sau într-un tur normal, orice carte e validă; doar când conducătorul
  /// decide dacă mai continuă lupta, cartea trebuie să se lege (număr sau
  /// tăietură).
  bool isCardPlayable(PlayingCard card) {
    if (!isMyTurn) return false;
    if (isMyFightDecision) {
      return card.rank == contestedRank || wildRanks.contains(card.rank);
    }
    return true;
  }

  factory SepticaSnapshot.fromJson(Map<String, dynamic> json) => SepticaSnapshot(
        viewerId: json['viewerId'] as String? ?? '',
        players: (json['players'] as List<dynamic>)
            .map((p) => SepticaPlayerSummary.fromJson(p as Map<String, dynamic>))
            .toList(),
        started: json['started'] as bool,
        winnerId: json['winnerId'] as String?,
        isDraw: json['isDraw'] as bool? ?? false,
        myHand: (json['myHand'] as List<dynamic>? ?? const [])
            .map((c) => PlayingCard.fromJson(c as Map<String, dynamic>))
            .toList(),
        drawPileCount: json['drawPileCount'] as int? ?? 0,
        tableCards: (json['tableCards'] as List<dynamic>? ?? const [])
            .map((c) => PlayingCard.fromJson(c as Map<String, dynamic>))
            .toList(),
        currentPlayerId: json['currentPlayerId'] as String?,
        leaderId: json['leaderId'] as String?,
        contestedRank:
            json['contestedRank'] == null ? null : Rank.values.byName(json['contestedRank'] as String),
        wildRanks: (json['wildRanks'] as List<dynamic>? ?? const [])
            .map((r) => Rank.values.byName(r as String))
            .toSet(),
        awaitingLeaderDecision: json['awaitingLeaderDecision'] as bool? ?? false,
        challengerId: json['challengerId'] as String?,
        lastPlayedCard: json['lastPlayedCard'] == null
            ? null
            : PlayingCard.fromJson(json['lastPlayedCard'] as Map<String, dynamic>),
        lastPlayedById: json['lastPlayedById'] as String?,
        lastPlayQualified: json['lastPlayQualified'] as bool? ?? false,
      );
}
