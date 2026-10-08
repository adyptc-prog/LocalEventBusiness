import '../../models/card.dart';

/// Scorul unei combinații de 5 cărți: [category] (0=cartea mare ... 8=chintă
/// culoare/royală), apoi [tiebreakers] — valori de departajare, comparate în
/// ordine. Mai mare câștigă.
class HandScore implements Comparable<HandScore> {
  final int category;
  final List<int> tiebreakers;

  const HandScore(this.category, this.tiebreakers);

  @override
  int compareTo(HandScore other) {
    if (category != other.category) return category.compareTo(other.category);
    for (var i = 0; i < tiebreakers.length && i < other.tiebreakers.length; i++) {
      if (tiebreakers[i] != other.tiebreakers[i]) return tiebreakers[i].compareTo(other.tiebreakers[i]);
    }
    return 0;
  }

  /// Cheia de traducere a numelui combinației (vezi `lib/l10n`) — textul
  /// final îl alege fiecare client, în limba lui.
  String get labelKey {
    switch (category) {
      case 8:
        return tiebreakers.first == 14 ? 'poker.hand.royalFlush' : 'poker.hand.straightFlush';
      case 7:
        return 'poker.hand.fourOfAKind';
      case 6:
        return 'poker.hand.fullHouse';
      case 5:
        return 'poker.hand.flush';
      case 4:
        return 'poker.hand.straight';
      case 3:
        return 'poker.hand.threeOfAKind';
      case 2:
        return 'poker.hand.twoPair';
      case 1:
        return 'poker.hand.pair';
      default:
        return 'poker.hand.highCard';
    }
  }
}

HandScore _evaluate5(List<PlayingCard> five) {
  final ranks = five.map((c) => c.value).toList()..sort((a, b) => b.compareTo(a));
  final isFlush = five.map((c) => c.suit).toSet().length == 1;

  final uniqueDesc = ranks.toSet().toList()..sort((a, b) => b.compareTo(a));
  var isStraight = false;
  var straightHigh = 0;
  if (uniqueDesc.length == 5) {
    if (uniqueDesc.first - uniqueDesc.last == 4) {
      isStraight = true;
      straightHigh = uniqueDesc.first;
    } else if (uniqueDesc.toSet().containsAll(const [14, 5, 4, 3, 2])) {
      isStraight = true; // chinta mica, "roata" A-2-3-4-5 — Asul joacă jos
      straightHigh = 5;
    }
  }

  final freq = <int, int>{};
  for (final r in ranks) {
    freq[r] = (freq[r] ?? 0) + 1;
  }
  final groups = freq.entries.toList()
    ..sort((a, b) {
      if (a.value != b.value) return b.value.compareTo(a.value);
      return b.key.compareTo(a.key);
    });

  if (isStraight && isFlush) return HandScore(8, [straightHigh]);
  if (groups[0].value == 4) {
    final kicker = groups.firstWhere((g) => g.value == 1).key;
    return HandScore(7, [groups[0].key, kicker]);
  }
  if (groups[0].value == 3 && groups.length > 1 && groups[1].value >= 2) {
    return HandScore(6, [groups[0].key, groups[1].key]);
  }
  if (isFlush) return HandScore(5, ranks);
  if (isStraight) return HandScore(4, [straightHigh]);
  if (groups[0].value == 3) {
    final kickers = groups.where((g) => g.value == 1).map((g) => g.key).toList();
    return HandScore(3, [groups[0].key, ...kickers]);
  }
  if (groups[0].value == 2 && groups.length > 1 && groups[1].value == 2) {
    final pairs = [groups[0].key, groups[1].key]..sort((a, b) => b.compareTo(a));
    final kicker = groups.firstWhere((g) => g.value == 1).key;
    return HandScore(2, [...pairs, kicker]);
  }
  if (groups[0].value == 2) {
    final kickers = groups.where((g) => g.value == 1).map((g) => g.key).toList()..sort((a, b) => b.compareTo(a));
    return HandScore(1, [groups[0].key, ...kickers]);
  }
  return HandScore(0, ranks);
}

/// Toate combinațiile de 5 din [cards] (folosit cu 7 cărți: 2 în mână + 5
/// comune — 21 combinații), obținute excluzând fiecare pereche posibilă.
Iterable<List<PlayingCard>> _combinations5(List<PlayingCard> cards) sync* {
  final n = cards.length;
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      yield [for (var k = 0; k < n; k++) if (k != i && k != j) cards[k]];
    }
  }
}

/// Cea mai bună combinație de 5 cărți din [cards] (2-7 cărți disponibile).
HandScore bestHandFrom(List<PlayingCard> cards) {
  if (cards.length <= 5) return _evaluate5(cards);
  HandScore? best;
  for (final combo in _combinations5(cards)) {
    final score = _evaluate5(combo);
    if (best == null || score.compareTo(best) > 0) best = score;
  }
  return best!;
}
