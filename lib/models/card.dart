enum Suit { hearts, diamonds, clubs, spades }

/// Ordinea contează: valoarea numerică a fiecărei cărți (folosită de orice
/// joc — comparații, scor) este `index + 2`, deci J=11, Q=12, K=13, iar
/// Asul e 14 — cea mai mare carte din pachet, în toate jocurile.
enum Rank { two, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace }

extension SuitDisplay on Suit {
  String get symbol {
    switch (this) {
      case Suit.hearts:
        return '♥';
      case Suit.diamonds:
        return '♦';
      case Suit.clubs:
        return '♣';
      case Suit.spades:
        return '♠';
    }
  }

  String get label {
    switch (this) {
      case Suit.hearts:
        return 'Inimă roșie';
      case Suit.diamonds:
        return 'Romb';
      case Suit.clubs:
        return 'Trifoi';
      case Suit.spades:
        return 'Pică';
    }
  }

  bool get isRed => this == Suit.hearts || this == Suit.diamonds;
}

extension RankDisplay on Rank {
  String get label {
    switch (this) {
      case Rank.two:
        return '2';
      case Rank.three:
        return '3';
      case Rank.four:
        return '4';
      case Rank.five:
        return '5';
      case Rank.six:
        return '6';
      case Rank.seven:
        return '7';
      case Rank.eight:
        return '8';
      case Rank.nine:
        return '9';
      case Rank.ten:
        return '10';
      case Rank.jack:
        return 'J';
      case Rank.queen:
        return 'Q';
      case Rank.king:
        return 'K';
      case Rank.ace:
        return 'A';
    }
  }

  /// Valoarea canonică, aceeași în orice joc din bibliotecă: 2-10 valoarea
  /// de pe carte, J=11, Q=12, K=13, Asul 14 (cea mai mare).
  int get value => index + 2;
}

class PlayingCard {
  final Suit suit;
  final Rank rank;

  const PlayingCard(this.suit, this.rank);

  int get value => rank.value;

  bool get isTwo => rank == Rank.two;
  bool get isThree => rank == Rank.three;
  bool get isFour => rank == Rank.four;
  bool get isAce => rank == Rank.ace;

  /// Singura carte "wild" — poate fi jucată oricând, indiferent de culoarea/
  /// rangul cărții de deasupra focului, pentru că efectul ei include mereu
  /// alegerea unei noi culori.
  bool get isWild => isAce;

  Map<String, dynamic> toJson() => {
        'suit': suit.name,
        'rank': rank.name,
      };

  factory PlayingCard.fromJson(Map<String, dynamic> json) => PlayingCard(
        Suit.values.byName(json['suit'] as String),
        Rank.values.byName(json['rank'] as String),
      );

  @override
  bool operator ==(Object other) =>
      other is PlayingCard && other.suit == suit && other.rank == rank;

  @override
  int get hashCode => Object.hash(suit, rank);

  @override
  String toString() => '${rank.label}${suit.symbol}';

  static List<PlayingCard> fullDeck() => [
        for (final suit in Suit.values)
          for (final rank in Rank.values) PlayingCard(suit, rank),
      ];
}
