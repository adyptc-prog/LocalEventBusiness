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

      // B stă 2 tururi *ale lui*: tura de acum e prima, iar data viitoare
      // când i-ar veni rândul e sărit încă o dată. C nu pierde nimic.
      expect(engine.pendingSkip, 0);
      expect(engine.currentPlayer?.id, 'C');
      engine.applyAction('C', {'type': 'draw_card'});
      expect(engine.currentPlayer?.id, 'A');
      engine.applyAction('A', {'type': 'draw_card'});
      expect(engine.currentPlayer?.id, 'C', reason: 'B își stă al doilea tur');
      engine.applyAction('C', {'type': 'draw_card'});
      engine.applyAction('A', {'type': 'draw_card'});
      expect(engine.currentPlayer?.id, 'B', reason: 'pedeapsa s-a consumat');
    });

    test('la 2 jucători, două cărți de 4 îl țin pe adversar pe loc două tururi', () {
      final engine = _engineWithPlayers(['A', 'B']);
      engine.players[0].hand = [
        const PlayingCard(Suit.hearts, Rank.four),
        const PlayingCard(Suit.spades, Rank.four),
        const PlayingCard(Suit.clubs, Rank.eight),
        const PlayingCard(Suit.clubs, Rank.nine),
      ];
      engine.players[1].hand = [const PlayingCard(Suit.diamonds, Rank.six)];
      engine.discardPile.insertAll(0, [
        const PlayingCard(Suit.diamonds, Rank.king),
        const PlayingCard(Suit.diamonds, Rank.queen),
        const PlayingCard(Suit.diamonds, Rank.jack),
      ]);

      engine.applyAction('A', {
        'type': 'play_card',
        'cards': [
          const PlayingCard(Suit.hearts, Rank.four).toJson(),
          const PlayingCard(Suit.spades, Rank.four).toJson(),
        ],
      });
      engine.applyAction('B', {'type': 'draw_card'}); // acceptă: primul tur stat
      expect(engine.currentPlayer?.id, 'A');
      engine.applyAction('A', {'type': 'draw_card'});
      expect(engine.currentPlayer?.id, 'A', reason: 'B stă și al doilea tur');
      engine.applyAction('A', {'type': 'draw_card'});
      expect(engine.currentPlayer?.id, 'B');
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

  group('anunțul „Macao!"', () {
    MacaoEngine twoCards() {
      final engine = _engineWithPlayers(['A', 'B']);
      engine.players[0].hand = [
        const PlayingCard(Suit.hearts, Rank.nine),
        const PlayingCard(Suit.clubs, Rank.eight),
      ];
      engine.players[1].hand = [const PlayingCard(Suit.clubs, Rank.six)];
      // cărți pe foc, ca penalizarea să aibă de unde trage
      engine.discardPile.insertAll(0, [
        for (final r in [Rank.two, Rank.three, Rank.jack, Rank.queen, Rank.king, Rank.seven])
          PlayingCard(Suit.spades, r),
      ]);
      return engine;
    }

    test('cine rămâne cu o carte fără anunț poate fi prins și trage 5', () {
      final engine = twoCards();
      engine.applyAction('A', {
        'type': 'play_card',
        'cards': [const PlayingCard(Suit.hearts, Rank.nine).toJson()],
      });
      expect(engine.unannouncedLastCardId, 'A');
      engine.applyAction('B', {'type': 'catch_last_card'});
      expect(engine.players[0].hand.length, 1 + MacaoEngine.lastCardPenalty);
      expect(engine.unannouncedLastCardId, isNull);
    });

    test('cu anunț, nu mai poate fi prins', () {
      final engine = twoCards();
      engine.applyAction('A', {
        'type': 'play_card',
        'cards': [const PlayingCard(Suit.hearts, Rank.nine).toJson()],
        'announce': true,
      });
      expect(engine.unannouncedLastCardId, isNull);
      expect(() => engine.applyAction('B', {'type': 'catch_last_card'}), throwsStateError);
    });

    test('anunțul întârziat salvează, iar fereastra se închide când următorul joacă', () {
      final engine = twoCards();
      engine.applyAction('A', {
        'type': 'play_card',
        'cards': [const PlayingCard(Suit.hearts, Rank.nine).toJson()],
      });
      engine.applyAction('A', {'type': 'announce_last_card'});
      expect(engine.unannouncedLastCardId, isNull);

      final late = twoCards();
      late.applyAction('A', {
        'type': 'play_card',
        'cards': [const PlayingCard(Suit.hearts, Rank.nine).toJson()],
      });
      late.applyAction('B', {'type': 'draw_card'}); // B își începe tura
      expect(() => late.applyAction('B', {'type': 'catch_last_card'}), throwsStateError);
    });
  });
}
