import 'package:flutter_test/flutter_test.dart';
import 'package:local_event_business/games/macao/macao_engine.dart';
import 'package:local_event_business/models/card.dart';

/// Pornește un motor Macao cu jucătorii dați, fără să treacă prin
/// [MacaoEngine.startGame] (care amestecă pachetul aleator) — starea de
/// pornire e construită manual, ca testele să fie deterministe.
MacaoEngine _engineWithPlayers(List<String> ids) {
  final engine = MacaoEngine();
  for (final id in ids) {
    engine.addPlayer(id: id, name: id, isHost: id == ids.first);
  }
  engine.started = true;
  engine.discardPile.add(const PlayingCard(Suit.hearts, Rank.five));
  engine.requestedSuit = Suit.hearts;
  engine.currentPlayerIndex = 0;
  return engine;
}

void main() {
  group('regula lui 4 (sărit tururi)', () {
    test('un singur 4 obligă următorul jucător să stea un tur dacă nu se apără', () {
      final engine = _engineWithPlayers(['A', 'B', 'C']);
      engine.players[0].hand = [
        const PlayingCard(Suit.hearts, Rank.four),
        const PlayingCard(Suit.clubs, Rank.eight),
      ];
      engine.players[1].hand = [const PlayingCard(Suit.clubs, Rank.six)];
      engine.players[2].hand = [const PlayingCard(Suit.clubs, Rank.seven)];

      engine.applyAction('A', {
        'type': 'play_card',
        'cards': [const PlayingCard(Suit.hearts, Rank.four).toJson()],
      });

      expect(engine.currentPlayer?.id, 'B');
      expect(engine.pendingSkip, 1);
      // B nu are 4 — poate juca doar cărți de 4 cât timp pendingSkip > 0.
      expect(engine.isValidPlay('B', const PlayingCard(Suit.clubs, Rank.six)), isFalse);

      engine.applyAction('B', {'type': 'draw_card'});

      expect(engine.pendingSkip, 0);
      expect(engine.currentPlayer?.id, 'C');
    });

    test('două cărți de 4 jucate odată obligă următorul să stea două tururi', () {
      final engine = _engineWithPlayers(['A', 'B', 'C']);
      engine.players[0].hand = [
        const PlayingCard(Suit.hearts, Rank.four),
        const PlayingCard(Suit.spades, Rank.four),
        const PlayingCard(Suit.clubs, Rank.eight),
      ];
      engine.players[1].hand = [const PlayingCard(Suit.clubs, Rank.six)];
      engine.players[2].hand = [const PlayingCard(Suit.clubs, Rank.seven)];

      engine.applyAction('A', {
        'type': 'play_card',
        'cards': [
          const PlayingCard(Suit.hearts, Rank.four).toJson(),
          const PlayingCard(Suit.spades, Rank.four).toJson(),
        ],
      });

      expect(engine.currentPlayer?.id, 'B');
      expect(engine.pendingSkip, 2);

      engine.applyAction('B', {'type': 'draw_card'});

      // B a acceptat pedeapsa integral (2 tururi) într-o singură mutare —
      // cu 3 jucători, asta duce mai departe rândul înapoi la A.
      expect(engine.pendingSkip, 0);
      expect(engine.currentPlayer?.id, 'A');
    });

    test('jucătorul vizat se poate apăra cu propriul 4, adunând povara mai departe', () {
      final engine = _engineWithPlayers(['A', 'B', 'C']);
      engine.players[0].hand = [
        const PlayingCard(Suit.hearts, Rank.four),
        const PlayingCard(Suit.spades, Rank.four),
        const PlayingCard(Suit.clubs, Rank.eight),
      ];
      engine.players[1].hand = [
        const PlayingCard(Suit.diamonds, Rank.four),
        const PlayingCard(Suit.clubs, Rank.nine),
      ];
      engine.players[2].hand = [const PlayingCard(Suit.clubs, Rank.seven)];

      engine.applyAction('A', {
        'type': 'play_card',
        'cards': [
          const PlayingCard(Suit.hearts, Rank.four).toJson(),
          const PlayingCard(Suit.spades, Rank.four).toJson(),
        ],
      });
      expect(engine.pendingSkip, 2);

      // B se apără cu propriul 4 (orice culoare) — povara trece la C, adunată.
      engine.applyAction('B', {
        'type': 'play_card',
        'cards': [const PlayingCard(Suit.diamonds, Rank.four).toJson()],
      });

      expect(engine.currentPlayer?.id, 'C');
      expect(engine.pendingSkip, 3);
      expect(engine.isValidPlay('C', const PlayingCard(Suit.clubs, Rank.seven)), isFalse);
    });
  });
}
