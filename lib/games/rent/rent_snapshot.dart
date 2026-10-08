import '../../models/card.dart';
import 'rent_categories.dart';

class RentPlayerSummary {
  final String id;
  final String name;
  final bool isHost;
  final bool connected;
  final int handCount;

  const RentPlayerSummary({
    required this.id,
    required this.name,
    required this.isHost,
    required this.connected,
    required this.handCount,
  });

  factory RentPlayerSummary.fromJson(Map<String, dynamic> json) => RentPlayerSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        isHost: json['isHost'] as bool,
        connected: json['connected'] as bool? ?? true,
        handCount: json['handCount'] as int? ?? 0,
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

/// O categorie încheiată, așa cum apare într-un rând din tabel.
class RentRoundHistoryEntry {
  final String category;
  final Map<String, int> roundScores;
  final Map<String, int> totals;

  const RentRoundHistoryEntry({required this.category, required this.roundScores, required this.totals});

  factory RentRoundHistoryEntry.fromJson(Map<String, dynamic> json) => RentRoundHistoryEntry(
        category: json['category'] as String,
        roundScores: Map<String, int>.from(json['roundScores'] as Map),
        totals: Map<String, int>.from(json['totals'] as Map),
      );
}

/// Vedere (read-only) asupra unei partide de Rent, personalizată per
/// jucător: propria mână completă, restul doar informații publice.
class RentSnapshot {
  final List<RentPlayerSummary> players;
  final bool started;
  final String? winnerId;
  final bool isDraw;
  final List<String> usedCategories;
  final bool choosingCategory;
  final String? chooserId;
  final String? activeCategory;
  final List<PlayingCard> myHand;
  final String? currentPlayerId;
  final List<TrickCardEntry> currentTrick;
  final List<TrickCardEntry>? lastTrick;
  final String? lastTrickWinnerId;
  final Map<Suit, List<PlayingCard>> rentSequences;
  final List<String> rentFinishOrder;
  final Map<String, int> cumulativeScores;
  final List<RentRoundHistoryEntry> history;

  const RentSnapshot({
    required this.players,
    required this.started,
    required this.winnerId,
    required this.isDraw,
    required this.usedCategories,
    required this.choosingCategory,
    required this.chooserId,
    required this.activeCategory,
    required this.myHand,
    required this.currentPlayerId,
    required this.currentTrick,
    required this.lastTrick,
    required this.lastTrickWinnerId,
    required this.rentSequences,
    required this.rentFinishOrder,
    required this.cumulativeScores,
    required this.history,
  });

  List<String> get availableCategories =>
      kRentCategories.where((c) => !usedCategories.contains(c)).toList();

  bool get isRentCategory => activeCategory == 'rent';
  bool isMyTurn(String viewerId) => started && !choosingCategory && currentPlayerId == viewerId;
  bool isMyTurnToChoose(String viewerId) => started && choosingCategory && chooserId == viewerId;

  String? winnerName(String viewerId) {
    if (winnerId == null) return null;
    final matches = players.where((p) => p.id == winnerId);
    return matches.isEmpty ? null : matches.first.name;
  }

  /// Oglindă locală a regulilor din [RentEngine] — la levată trebuie urmată
  /// culoarea cerută dacă ai; la Rent, cartea trebuie să continue o
  /// secvență deschisă (sau să fie un 10 care deschide una nouă).
  bool isCardPlayable(PlayingCard card) {
    if (isRentCategory) return isValidRentMove(card);
    if (currentTrick.isEmpty) return true;
    final ledSuit = currentTrick.first.card.suit;
    final hasLedSuit = myHand.any((c) => c.suit == ledSuit);
    if (hasLedSuit) return card.suit == ledSuit;
    return true;
  }

  bool isValidRentMove(PlayingCard card) {
    final seq = rentSequences[card.suit];
    if (seq == null || seq.isEmpty) return card.rank == Rank.ten;
    final minVal = seq.first.rank.value;
    final maxVal = seq.last.rank.value;
    return card.rank.value == minVal - 1 || card.rank.value == maxVal + 1;
  }

  factory RentSnapshot.fromJson(Map<String, dynamic> json) => RentSnapshot(
        players: (json['players'] as List<dynamic>)
            .map((p) => RentPlayerSummary.fromJson(p as Map<String, dynamic>))
            .toList(),
        started: json['started'] as bool,
        winnerId: json['winnerId'] as String?,
        isDraw: json['isDraw'] as bool? ?? false,
        usedCategories: List<String>.from(json['usedCategories'] as List? ?? const []),
        choosingCategory: json['choosingCategory'] as bool? ?? false,
        chooserId: json['chooserId'] as String?,
        activeCategory: json['activeCategory'] as String?,
        myHand: (json['myHand'] as List<dynamic>? ?? const [])
            .map((c) => PlayingCard.fromJson(c as Map<String, dynamic>))
            .toList(),
        currentPlayerId: json['currentPlayerId'] as String?,
        currentTrick: (json['currentTrick'] as List<dynamic>? ?? const [])
            .map((c) => TrickCardEntry.fromJson(c as Map<String, dynamic>))
            .toList(),
        lastTrick: (json['lastTrick'] as List<dynamic>?)
            ?.map((c) => TrickCardEntry.fromJson(c as Map<String, dynamic>))
            .toList(),
        lastTrickWinnerId: json['lastTrickWinnerId'] as String?,
        rentSequences: (json['rentSequences'] as Map<String, dynamic>? ?? const {}).map(
          (suitName, cards) => MapEntry(
            Suit.values.byName(suitName),
            (cards as List<dynamic>).map((c) => PlayingCard.fromJson(c as Map<String, dynamic>)).toList(),
          ),
        ),
        rentFinishOrder: List<String>.from(json['rentFinishOrder'] as List? ?? const []),
        cumulativeScores: Map<String, int>.from(json['cumulativeScores'] as Map? ?? const {}),
        history: (json['history'] as List<dynamic>? ?? const [])
            .map((r) => RentRoundHistoryEntry.fromJson(r as Map<String, dynamic>))
            .toList(),
      );
}
