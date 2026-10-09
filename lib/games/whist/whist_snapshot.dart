import '../../models/card.dart';

class WhistPlayerSummary {
  final String id;
  final String name;
  final bool isHost;
  final bool connected;

  const WhistPlayerSummary({
    required this.id,
    required this.name,
    required this.isHost,
    required this.connected,
  });

  factory WhistPlayerSummary.fromJson(Map<String, dynamic> json) => WhistPlayerSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        isHost: json['isHost'] as bool,
        connected: json['connected'] as bool? ?? true,
      );
}

class TrickCardEntry {
  final String playerId;
  final PlayingCard card;

  const TrickCardEntry({required this.playerId, required this.card});

  factory TrickCardEntry.fromJson(Map<String, dynamic> json) => TrickCardEntry(
        playerId: json['playerId'] as String,
        card: PlayingCard.fromJson(json['card'] as Map<String, dynamic>),
      );
}

/// O rundă încheiată, așa cum apare într-un rând din tabelul de scor.
class WhistRoundHistoryEntry {
  final int roundIndex;
  final int handSize;
  final Suit? trumpSuit;
  final Map<String, int> bids;
  final Map<String, int> taken;
  final Map<String, int> roundScores;
  final Map<String, int> totals;

  const WhistRoundHistoryEntry({
    required this.roundIndex,
    required this.handSize,
    required this.trumpSuit,
    required this.bids,
    required this.taken,
    required this.roundScores,
    required this.totals,
  });

  factory WhistRoundHistoryEntry.fromJson(Map<String, dynamic> json) => WhistRoundHistoryEntry(
        roundIndex: json['roundIndex'] as int,
        handSize: json['handSize'] as int,
        trumpSuit: json['trumpSuit'] == null ? null : Suit.values.byName(json['trumpSuit'] as String),
        bids: Map<String, int>.from(json['bids'] as Map),
        taken: Map<String, int>.from(json['taken'] as Map),
        roundScores: Map<String, int>.from(json['roundScores'] as Map),
        totals: Map<String, int>.from(json['totals'] as Map),
      );
}

/// Vedere (read-only) asupra unei partide de Whist, personalizată per
/// jucător: propria mână completă, restul doar informații publice (licitații,
/// levate luate, scoruri) — la Whist nu există informație privată despre
/// ceilalți în afară de mâna lor.
class WhistSnapshot {
  final List<WhistPlayerSummary> players;
  final bool started;
  final String? winnerId;
  final bool isDraw;
  final int roundNumber;
  final int totalRounds;
  final int handSize;
  final String phase; // 'bidding' | 'playing'
  final PlayingCard? trumpCard;
  final String? currentPlayerId;
  final Map<String, int> bids;
  final List<PlayingCard> myHand;
  final List<TrickCardEntry> currentTrick;
  final List<TrickCardEntry>? lastTrick;
  final String? lastTrickWinnerId;
  final Map<String, int> tricksWonThisRound;
  final Map<String, int> cumulativeScores;
  final List<WhistRoundHistoryEntry> history;

  const WhistSnapshot({
    required this.players,
    required this.started,
    required this.winnerId,
    required this.isDraw,
    required this.roundNumber,
    required this.totalRounds,
    required this.handSize,
    required this.phase,
    required this.trumpCard,
    required this.currentPlayerId,
    required this.bids,
    required this.myHand,
    required this.currentTrick,
    required this.lastTrick,
    required this.lastTrickWinnerId,
    required this.tricksWonThisRound,
    required this.cumulativeScores,
    required this.history,
  });

  bool isMyTurn(String viewerId) => started && currentPlayerId == viewerId;
  bool get isBidding => phase == 'bidding';

  String? winnerName(String viewerId) {
    if (winnerId == null) return null;
    final matches = players.where((p) => p.id == winnerId);
    return matches.isEmpty ? null : matches.first.name;
  }

  /// Oglindă locală a regulii din [WhistEngine._playCard] — trebuie urmată
  /// culoarea cerută dacă ai o carte din ea; altfel, dacă ai atu, atu;
  /// altfel orice carte e validă. Apelabilă doar în faza de joc (nu de
  /// licitație) — verifică [isBidding] înainte, la fel ca ecranul de joc.
  bool isCardPlayable(PlayingCard card) {
    if (currentTrick.isEmpty) return true; // duci tu — orice carte e validă
    final ledSuit = currentTrick.first.card.suit;
    final hasLedSuit = myHand.any((c) => c.suit == ledSuit);
    if (hasLedSuit) return card.suit == ledSuit;
    final trump = trumpCard?.suit;
    if (trump != null && myHand.any((c) => c.suit == trump)) return card.suit == trump;
    return true;
  }

  factory WhistSnapshot.fromJson(Map<String, dynamic> json) => WhistSnapshot(
        players: (json['players'] as List<dynamic>)
            .map((p) => WhistPlayerSummary.fromJson(p as Map<String, dynamic>))
            .toList(),
        started: json['started'] as bool,
        winnerId: json['winnerId'] as String?,
        isDraw: json['isDraw'] as bool? ?? false,
        roundNumber: json['roundNumber'] as int? ?? 1,
        totalRounds: json['totalRounds'] as int? ?? 0,
        handSize: json['handSize'] as int? ?? 0,
        phase: json['phase'] as String? ?? 'bidding',
        trumpCard: json['trumpCard'] == null
            ? null
            : PlayingCard.fromJson(json['trumpCard'] as Map<String, dynamic>),
        currentPlayerId: json['currentPlayerId'] as String?,
        bids: Map<String, int>.from(json['bids'] as Map? ?? const {}),
        myHand: (json['myHand'] as List<dynamic>? ?? const [])
            .map((c) => PlayingCard.fromJson(c as Map<String, dynamic>))
            .toList(),
        currentTrick: (json['currentTrick'] as List<dynamic>? ?? const [])
            .map((c) => TrickCardEntry.fromJson(c as Map<String, dynamic>))
            .toList(),
        lastTrick: (json['lastTrick'] as List<dynamic>?)
            ?.map((c) => TrickCardEntry.fromJson(c as Map<String, dynamic>))
            .toList(),
        lastTrickWinnerId: json['lastTrickWinnerId'] as String?,
        tricksWonThisRound: Map<String, int>.from(json['tricksWonThisRound'] as Map? ?? const {}),
        cumulativeScores: Map<String, int>.from(json['cumulativeScores'] as Map? ?? const {}),
        history: (json['history'] as List<dynamic>? ?? const [])
            .map((r) => WhistRoundHistoryEntry.fromJson(r as Map<String, dynamic>))
            .toList(),
      );
}
