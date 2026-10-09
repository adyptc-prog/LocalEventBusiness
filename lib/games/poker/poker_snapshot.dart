import '../../models/card.dart';
import '../../l10n/tr.dart';

class PokerPlayerSummary {
  final String id;
  final String name;
  final bool isHost;
  final bool connected;
  final int chips;
  final bool folded;
  final bool allIn;
  final bool busted;
  final int betThisRound;

  const PokerPlayerSummary({
    required this.id,
    required this.name,
    required this.isHost,
    required this.connected,
    required this.chips,
    required this.folded,
    required this.allIn,
    required this.busted,
    required this.betThisRound,
  });

  factory PokerPlayerSummary.fromJson(Map<String, dynamic> json) => PokerPlayerSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        isHost: json['isHost'] as bool,
        connected: json['connected'] as bool? ?? true,
        chips: json['chips'] as int? ?? 0,
        folded: json['folded'] as bool? ?? false,
        allIn: json['allIn'] as bool? ?? false,
        busted: json['busted'] as bool? ?? false,
        betThisRound: json['betThisRound'] as int? ?? 0,
      );
}

class ShowdownEntry {
  final String playerId;
  final List<PlayingCard> cards;
  final LocalizedText handLabel;
  final int won;

  const ShowdownEntry({required this.playerId, required this.cards, required this.handLabel, required this.won});

  factory ShowdownEntry.fromJson(Map<String, dynamic> json) => ShowdownEntry(
        playerId: json['playerId'] as String,
        cards: (json['cards'] as List<dynamic>)
            .map((c) => PlayingCard.fromJson(c as Map<String, dynamic>))
            .toList(),
        handLabel: LocalizedText.fromJson(json['handLabel']) ?? const LocalizedText('poker.hand.highCard'),
        won: json['won'] as int,
      );
}

/// Vedere (read-only) asupra unei mese de Poker, personalizată per jucător:
/// propriile cărți în mână, restul doar informații publice (fise, pariul
/// curent, cine a renunțat/e all-in) — exact ca la o masă reală.
class PokerSnapshot {
  final List<PokerPlayerSummary> players;
  final bool started;
  final String? winnerId;
  final String street; // preflop | flop | turn | river | showdown
  final List<PlayingCard> community;
  final int pot;
  final int currentBet;
  final int minRaiseIncrement;

  /// `false` dacă privitorul a pierdut dreptul de a ridica în runda curentă
  /// (după un all-in incomplet al altcuiva) — poate doar egala sau renunța.
  final bool raiseAllowed;
  final String? currentPlayerId;
  final String? dealerId;
  final List<PlayingCard> myHoleCards;
  final List<ShowdownEntry>? lastShowdown;
  final LocalizedText? lastHandSummary;

  const PokerSnapshot({
    required this.players,
    required this.started,
    required this.winnerId,
    required this.street,
    required this.community,
    required this.pot,
    required this.currentBet,
    required this.minRaiseIncrement,
    this.raiseAllowed = true,
    required this.currentPlayerId,
    required this.dealerId,
    required this.myHoleCards,
    required this.lastShowdown,
    required this.lastHandSummary,
  });

  PokerPlayerSummary? forId(String? id) {
    if (id == null) return null;
    final matches = players.where((p) => p.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  bool isMyTurn(String viewerId) => started && currentPlayerId == viewerId;
  int amountToCall(String viewerId) => (currentBet - (forId(viewerId)?.betThisRound ?? 0)).clamp(0, 1 << 30);
  int get minRaiseTotal => currentBet + minRaiseIncrement;

  String? winnerName(String viewerId) {
    if (winnerId == null) return null;
    return forId(winnerId)?.name;
  }

  factory PokerSnapshot.fromJson(Map<String, dynamic> json) => PokerSnapshot(
        players: (json['players'] as List<dynamic>)
            .map((p) => PokerPlayerSummary.fromJson(p as Map<String, dynamic>))
            .toList(),
        started: json['started'] as bool,
        winnerId: json['winnerId'] as String?,
        street: json['street'] as String? ?? 'preflop',
        community: (json['community'] as List<dynamic>? ?? const [])
            .map((c) => PlayingCard.fromJson(c as Map<String, dynamic>))
            .toList(),
        pot: json['pot'] as int? ?? 0,
        currentBet: json['currentBet'] as int? ?? 0,
        minRaiseIncrement: json['minRaiseIncrement'] as int? ?? 0,
        raiseAllowed: json['raiseAllowed'] as bool? ?? true,
        currentPlayerId: json['currentPlayerId'] as String?,
        dealerId: json['dealerId'] as String?,
        myHoleCards: (json['myHoleCards'] as List<dynamic>? ?? const [])
            .map((c) => PlayingCard.fromJson(c as Map<String, dynamic>))
            .toList(),
        lastShowdown: (json['lastShowdown'] as List<dynamic>?)
            ?.map((r) => ShowdownEntry.fromJson(r as Map<String, dynamic>))
            .toList(),
        lastHandSummary: LocalizedText.fromJson(json['lastHandSummary']),
      );
}
