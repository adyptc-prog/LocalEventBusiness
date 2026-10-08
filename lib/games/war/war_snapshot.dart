import '../../models/card.dart';

class WarPlayerSummary {
  final String id;
  final String name;
  final bool isHost;
  final bool connected;

  const WarPlayerSummary({
    required this.id,
    required this.name,
    required this.isHost,
    required this.connected,
  });

  factory WarPlayerSummary.fromJson(Map<String, dynamic> json) => WarPlayerSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        isHost: json['isHost'] as bool,
        connected: json['connected'] as bool? ?? true,
      );
}

/// Vedere (read-only) asupra stării jocului Război, așa cum trebuie afișată
/// unui anumit jucător — cartea adversarului nu apare decât după ce ambii au
/// întors, ca să nu se poată "trișa" citind snapshot-ul brut.
class WarSnapshot {
  final List<WarPlayerSummary> players;
  final bool started;
  final String? winnerId;
  final int myDeckCount;
  final String? opponentId;
  final String? opponentName;
  final int opponentDeckCount;
  final int potCount;
  final bool warPending;
  final bool iHaveFlipped;
  final bool opponentHasFlipped;
  final PlayingCard? myRevealedCard;
  final PlayingCard? lastRoundMyCard;
  final PlayingCard? lastRoundOpponentCard;
  final String? lastRoundOutcome; // 'win' | 'lose' | 'war'

  const WarSnapshot({
    required this.players,
    required this.started,
    required this.winnerId,
    required this.myDeckCount,
    required this.opponentId,
    required this.opponentName,
    required this.opponentDeckCount,
    required this.potCount,
    required this.warPending,
    required this.iHaveFlipped,
    required this.opponentHasFlipped,
    required this.myRevealedCard,
    required this.lastRoundMyCard,
    required this.lastRoundOpponentCard,
    required this.lastRoundOutcome,
  });

  String? winnerName(String myId) {
    if (winnerId == null) return null;
    if (winnerId == myId) return null; // ecranul decide singur mesajul pentru "eu"
    final matches = players.where((p) => p.id == winnerId);
    return matches.isEmpty ? null : matches.first.name;
  }

  factory WarSnapshot.fromJson(Map<String, dynamic> json) => WarSnapshot(
        players: (json['players'] as List<dynamic>)
            .map((p) => WarPlayerSummary.fromJson(p as Map<String, dynamic>))
            .toList(),
        started: json['started'] as bool,
        winnerId: json['winnerId'] as String?,
        myDeckCount: json['myDeckCount'] as int? ?? 0,
        opponentId: json['opponentId'] as String?,
        opponentName: json['opponentName'] as String?,
        opponentDeckCount: json['opponentDeckCount'] as int? ?? 0,
        potCount: json['potCount'] as int? ?? 0,
        warPending: json['warPending'] as bool? ?? false,
        iHaveFlipped: json['iHaveFlipped'] as bool? ?? false,
        opponentHasFlipped: json['opponentHasFlipped'] as bool? ?? false,
        myRevealedCard: json['myRevealedCard'] == null
            ? null
            : PlayingCard.fromJson(json['myRevealedCard'] as Map<String, dynamic>),
        lastRoundMyCard: json['lastRoundMyCard'] == null
            ? null
            : PlayingCard.fromJson(json['lastRoundMyCard'] as Map<String, dynamic>),
        lastRoundOpponentCard: json['lastRoundOpponentCard'] == null
            ? null
            : PlayingCard.fromJson(json['lastRoundOpponentCard'] as Map<String, dynamic>),
        lastRoundOutcome: json['lastRoundOutcome'] as String?,
      );
}
