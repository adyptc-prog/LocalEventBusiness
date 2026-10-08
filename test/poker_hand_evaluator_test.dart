import 'package:flutter_test/flutter_test.dart';
import 'package:local_event_business/games/poker/poker_hand_evaluator.dart';
import 'package:local_event_business/models/card.dart';

PlayingCard c(String rank, Suit suit) {
  final map = {
    '2': Rank.two, '3': Rank.three, '4': Rank.four, '5': Rank.five, '6': Rank.six,
    '7': Rank.seven, '8': Rank.eight, '9': Rank.nine, '10': Rank.ten,
    'J': Rank.jack, 'Q': Rank.queen, 'K': Rank.king, 'A': Rank.ace,
  };
  return PlayingCard(suit, map[rank]!);
}

void main() {
  test('categoria crește corect: careu > full > culoare > chintă', () {
    final fourOfAKind = bestHandFrom([
      c('9', Suit.hearts), c('9', Suit.diamonds), c('9', Suit.clubs), c('9', Suit.spades),
      c('2', Suit.hearts), c('3', Suit.diamonds), c('4', Suit.clubs),
    ]);
    final fullHouse = bestHandFrom([
      c('8', Suit.hearts), c('8', Suit.diamonds), c('8', Suit.clubs),
      c('K', Suit.hearts), c('K', Suit.diamonds), c('2', Suit.clubs), c('3', Suit.spades),
    ]);
    final flush = bestHandFrom([
      c('2', Suit.hearts), c('5', Suit.hearts), c('9', Suit.hearts), c('J', Suit.hearts), c('K', Suit.hearts),
      c('3', Suit.clubs), c('4', Suit.diamonds),
    ]);
    final straight = bestHandFrom([
      c('4', Suit.hearts), c('5', Suit.diamonds), c('6', Suit.clubs), c('7', Suit.spades), c('8', Suit.hearts),
      c('2', Suit.clubs), c('3', Suit.diamonds),
    ]);

    expect(fourOfAKind.compareTo(fullHouse) > 0, isTrue);
    expect(fullHouse.compareTo(flush) > 0, isTrue);
    expect(flush.compareTo(straight) > 0, isTrue);
  });

  test('chinta mica A-2-3-4-5 (roata) e recunoscută ca chintă, cu vârf 5 nu As', () {
    final wheel = bestHandFrom([
      c('A', Suit.hearts), c('2', Suit.diamonds), c('3', Suit.clubs), c('4', Suit.spades), c('5', Suit.hearts),
      c('9', Suit.clubs), c('K', Suit.diamonds),
    ]);
    expect(wheel.category, 4); // chintă
    expect(wheel.tiebreakers.first, 5);

    final higherStraight = bestHandFrom([
      c('6', Suit.hearts), c('7', Suit.diamonds), c('8', Suit.clubs), c('9', Suit.spades), c('10', Suit.hearts),
      c('2', Suit.clubs), c('3', Suit.diamonds),
    ]);
    expect(higherStraight.compareTo(wheel) > 0, isTrue);
  });

  test('la pereche egală, câștigă kickerul mai mare', () {
    final pairWithHighKicker = bestHandFrom([
      c('7', Suit.hearts), c('7', Suit.diamonds), c('A', Suit.clubs), c('9', Suit.spades), c('4', Suit.hearts),
      c('2', Suit.clubs), c('3', Suit.diamonds),
    ]);
    final pairWithLowKicker = bestHandFrom([
      c('7', Suit.clubs), c('7', Suit.spades), c('6', Suit.clubs), c('9', Suit.hearts), c('4', Suit.diamonds),
      c('2', Suit.hearts), c('3', Suit.clubs),
    ]);
    expect(pairWithHighKicker.category, 1);
    expect(pairWithLowKicker.category, 1);
    expect(pairWithHighKicker.compareTo(pairWithLowKicker) > 0, isTrue);
  });

  test('Asul e cea mai mare carte (peste Popa/King)', () {
    expect(Rank.ace.value, 14);
    expect(Rank.king.value, 13);
    expect(Rank.ace.value > Rank.king.value, isTrue);
  });
}
