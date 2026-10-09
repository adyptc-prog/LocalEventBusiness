// Regulile oficiale reparate după verificarea jocurilor: Uno, Șeptica,
// Poker, Whist și Rentz (Macao are testele lui în macao_engine_test.dart).

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_event_business/games/poker/poker_engine.dart';
import 'package:local_event_business/games/rent/rent_categories.dart';
import 'package:local_event_business/games/rent/rent_engine.dart';
import 'package:local_event_business/games/septica/septica_engine.dart';
import 'package:local_event_business/games/uno/uno_card.dart';
import 'package:local_event_business/games/uno/uno_engine.dart';
import 'package:local_event_business/games/whist/whist_engine.dart';
import 'package:local_event_business/models/card.dart';

PlayingCard c(Suit s, Rank r) => PlayingCard(s, r);
UnoCard n(UnoColor color, int number) => UnoCard(color: color, type: UnoCardType.number, number: number);

void main() {
  group('Uno', () {
    UnoEngine engineWith(List<UnoCard> handA, List<UnoCard> handB, List<UnoCard> discard) {
      final engine = UnoEngine()
        ..addPlayer(id: 'A', name: 'A', isHost: true)
        ..addPlayer(id: 'B', name: 'B', isHost: false);
      engine.players[0].hand = List.of(handA);
      engine.players[1].hand = List.of(handB);
      engine.discardPile.addAll(discard);
      engine.activeColor = discard.last.color;
      engine.started = true;
      return engine;
    }

    test('după ce tragi, poți juca doar cartea trasă', () {
      // pe foc: albastru 9 sub verde 7 → singura carte de tras e albastru 9
      final engine = engineWith([n(UnoColor.green, 3), n(UnoColor.red, 1)], [n(UnoColor.red, 2)],
          [n(UnoColor.blue, 9), n(UnoColor.green, 7)]);
      expect(engine.isValidPlay('A', n(UnoColor.green, 3)), isTrue);
      engine.applyAction('A', {'type': 'draw_card'});
      expect(engine.isValidPlay('A', n(UnoColor.green, 3)), isFalse, reason: 'nu e cartea trasă');
      expect(engine.isValidPlay('A', n(UnoColor.blue, 9)), isFalse, reason: 'cartea trasă nu se potrivește');
      engine.applyAction('A', {'type': 'pass_turn'});
      expect(engine.currentPlayer?.id, 'B');
    });

    test('cartea trasă se poate juca dacă se potrivește', () {
      final engine = engineWith([n(UnoColor.red, 1)], [n(UnoColor.red, 2)],
          [n(UnoColor.green, 2), n(UnoColor.green, 7)]);
      engine.applyAction('A', {'type': 'draw_card'});
      engine.applyAction('A', {'type': 'play_card', 'card': n(UnoColor.green, 2).toJson(), 'announce': true});
      expect(engine.currentPlayer?.id, 'B');
    });

    test('ultima carte +2: următorul tot trage, iar cărțile intră la punctaj', () {
      const plusTwo = UnoCard(color: UnoColor.green, type: UnoCardType.drawTwo);
      final engine = engineWith([plusTwo], [n(UnoColor.red, 2)],
          [n(UnoColor.blue, 1), n(UnoColor.yellow, 4), n(UnoColor.green, 7)]);
      engine.applyAction('A', {'type': 'play_card', 'card': plusTwo.toJson()});
      expect(engine.winnerId, 'A');
      expect(engine.players[1].hand.length, 3);
      final penalty = engine.players[1].hand.fold<int>(0, (s, card) => s + card.points);
      expect(engine.lastMatchScores!['A'], penalty);
    });

    test('prima carte întoarsă își aplică efectul', () {
      final seen = <UnoCardType>{};
      for (var i = 0; i < 2000 && seen.length < 3; i++) {
        final engine = UnoEngine()
          ..addPlayer(id: 'A', name: 'A', isHost: true)
          ..addPlayer(id: 'B', name: 'B', isHost: false)
          ..addPlayer(id: 'C', name: 'C', isHost: false);
        engine.startGame();
        final first = engine.topCard!;
        switch (first.type) {
          case UnoCardType.skip:
            expect(engine.currentPlayer?.id, 'B', reason: 'Skip: primul jucător e sărit');
            seen.add(first.type);
          case UnoCardType.reverse:
            expect(engine.direction, -1);
            expect(engine.currentPlayer?.id, 'C', reason: 'Reverse: începe dealerul');
            seen.add(first.type);
          case UnoCardType.drawTwo:
            expect(engine.players[0].hand.length, UnoEngine.startingHandSize + 2);
            expect(engine.currentPlayer?.id, 'B');
            seen.add(first.type);
          default:
            expect(engine.currentPlayer?.id, 'A');
        }
      }
      expect(seen, hasLength(3), reason: 'toate cele 3 efecte au fost întâlnite');
    });

    test('„UNO!" neanunțat: prins → trage 2; anunțat → nu poate fi prins', () {
      final discard = [n(UnoColor.blue, 1), n(UnoColor.red, 2), n(UnoColor.yellow, 3), n(UnoColor.green, 7)];
      final caught = engineWith([n(UnoColor.green, 3), n(UnoColor.green, 4)], [n(UnoColor.red, 5)], discard);
      caught.applyAction('A', {'type': 'play_card', 'card': n(UnoColor.green, 3).toJson()});
      expect(caught.unannouncedLastCardId, 'A');
      caught.applyAction('B', {'type': 'catch_last_card'});
      expect(caught.players[0].hand.length, 1 + UnoEngine.lastCardPenalty);

      final safe = engineWith([n(UnoColor.green, 3), n(UnoColor.green, 4)], [n(UnoColor.red, 5)], discard);
      safe.applyAction('A', {'type': 'play_card', 'card': n(UnoColor.green, 3).toJson(), 'announce': true});
      expect(() => safe.applyAction('B', {'type': 'catch_last_card'}), throwsStateError);
    });
  });

  group('Șeptica', () {
    SepticaEngine twoPlayers() => SepticaEngine()
      ..addPlayer(id: 'A', name: 'A', isHost: true)
      ..addPlayer(id: 'B', name: 'B', isHost: false)
      ..startGame();

    int scoreOf(SepticaEngine e, String id) =>
        ((e.snapshotFor(id)['players'] as List).firstWhere((p) => p['id'] == id) as Map)['score'] as int;

    test('conducătorul care taie din nou ia masa dacă nimeni nu-l mai taie', () {
      final engine = twoPlayers();
      engine.debugDeal(leaderId: 'A', hands: {
        'A': [c(Suit.hearts, Rank.nine), c(Suit.diamonds, Rank.seven), c(Suit.clubs, Rank.eight)],
        'B': [c(Suit.spades, Rank.nine), c(Suit.clubs, Rank.ten), c(Suit.diamonds, Rank.eight)],
      });
      engine.applyAction('A', {'type': 'play_card', 'card': c(Suit.hearts, Rank.nine).toJson()});
      engine.applyAction('B', {'type': 'play_card', 'card': c(Suit.spades, Rank.nine).toJson()});
      expect(engine.currentPlayerId, 'A', reason: 'B a tăiat — A decide');
      engine.applyAction('A', {'type': 'play_card', 'card': c(Suit.diamonds, Rank.seven).toJson()});
      engine.applyAction('B', {'type': 'play_card', 'card': c(Suit.clubs, Rank.ten).toJson()});
      // B n-a mai tăiat — ultima tăietură e a lui A, care ia tot (inclusiv zecele)
      expect(scoreOf(engine, 'A'), 1);
      expect(scoreOf(engine, 'B'), 0);
      expect(engine.currentPlayerId, 'A');
    });

    test('dacă după tăietura conducătorului nimeni nu mai poate răspunde, conducătorul ia tot', () {
      final engine = twoPlayers();
      engine.debugDeal(leaderId: 'A', hands: {
        'A': [c(Suit.hearts, Rank.ten), c(Suit.diamonds, Rank.seven), c(Suit.clubs, Rank.jack)],
        'B': [c(Suit.spades, Rank.ten)],
      });
      engine.applyAction('A', {'type': 'play_card', 'card': c(Suit.hearts, Rank.ten).toJson()});
      engine.applyAction('B', {'type': 'play_card', 'card': c(Suit.spades, Rank.ten).toJson()});
      engine.applyAction('A', {'type': 'play_card', 'card': c(Suit.diamonds, Rank.seven).toJson()});
      expect(scoreOf(engine, 'A'), 2);
      expect(scoreOf(engine, 'B'), 0);
    });
  });

  group('Poker', () {
    test('un all-in incomplet nu redeschide ridicarea pentru cine acționase deja', () {
      final engine = PokerEngine()
        ..addPlayer(id: 'p0', name: 'p0', isHost: true)
        ..addPlayer(id: 'p1', name: 'p1', isHost: false)
        ..addPlayer(id: 'p2', name: 'p2', isHost: false)
        ..debugStartStacks = {'p1': 150};
      engine.startGame(); // p0 dealer, p1 small blind, p2 big blind; p0 acționează primul
      expect(engine.currentPlayerId, 'p0');
      engine.applyAction('p0', {'type': 'poker_action', 'action': 'raise', 'amount': 100}); // ridicare completă (+80)
      engine.applyAction('p1', {'type': 'poker_action', 'action': 'all_in'}); // 150: doar +50 < 80
      expect(engine.currentPlayerId, 'p2');
      expect(engine.snapshotFor('p2')['raiseAllowed'], isTrue, reason: 'p2 n-a acționat încă');
      engine.applyAction('p2', {'type': 'poker_action', 'action': 'call'});
      expect(engine.currentPlayerId, 'p0');
      expect(engine.snapshotFor('p0')['raiseAllowed'], isFalse);
      expect(() => engine.applyAction('p0', {'type': 'poker_action', 'action': 'raise', 'amount': 400}), throwsStateError);
      expect(() => engine.applyAction('p0', {'type': 'poker_action', 'action': 'all_in'}), throwsStateError);
      engine.applyAction('p0', {'type': 'poker_action', 'action': 'call'}); // egalarea e permisă
    });

    test('un all-in complet redeschide ridicarea pentru toți', () {
      final engine = PokerEngine()
        ..addPlayer(id: 'p0', name: 'p0', isHost: true)
        ..addPlayer(id: 'p1', name: 'p1', isHost: false)
        ..addPlayer(id: 'p2', name: 'p2', isHost: false)
        ..debugStartStacks = {'p1': 300};
      engine.startGame();
      engine.applyAction('p0', {'type': 'poker_action', 'action': 'raise', 'amount': 100});
      engine.applyAction('p1', {'type': 'poker_action', 'action': 'all_in'}); // 300: +200 ≥ 80
      engine.applyAction('p2', {'type': 'poker_action', 'action': 'call'});
      expect(engine.snapshotFor('p0')['raiseAllowed'], isTrue);
    });

    test('blind mare scurt: de egalat rămâne blindul mare întreg', () {
      final engine = PokerEngine()
        ..addPlayer(id: 'p0', name: 'p0', isHost: true)
        ..addPlayer(id: 'p1', name: 'p1', isHost: false)
        ..debugStartStacks = {'p1': 5};
      engine.startGame(); // la 2 jucători: p0 = dealer + small blind, p1 = big blind (all-in cu 5)
      expect(engine.snapshotFor('p0')['currentBet'], PokerEngine.bigBlind);
      expect(() => engine.applyAction('p0', {'type': 'poker_action', 'action': 'check'}), throwsStateError);
      engine.applyAction('p0', {'type': 'poker_action', 'action': 'call'});
    });
  });

  group('Whist românesc', () {
    test('structura rundelor: N×1, 2…7, N×8, 7…2, N×1', () {
      expect(WhistEngine.roundSizesFor(4), [1, 1, 1, 1, 2, 3, 4, 5, 6, 7, 8, 8, 8, 8, 7, 6, 5, 4, 3, 2, 1, 1, 1, 1]);
      expect(WhistEngine.roundSizesFor(3).length, 3 * 3 + 12);
      expect(WhistEngine.roundSizesFor(6).length, 3 * 6 + 12);
    });

    test('scor: exact = 5 + licitația, ratat = minus diferența', () {
      expect(WhistEngine.roundScore(0, 0), 5);
      expect(WhistEngine.roundScore(3, 3), 8);
      expect(WhistEngine.roundScore(2, 0), -2);
      expect(WhistEngine.roundScore(1, 4), -3);
    });

    test('fără culoarea cerută, dar cu atu — obligatoriu atu', () {
      final engine = WhistEngine()
        ..addPlayer(id: 'p0', name: 'p0', isHost: true)
        ..addPlayer(id: 'p1', name: 'p1', isHost: false)
        ..addPlayer(id: 'p2', name: 'p2', isHost: false)
        ..startGame();
      // licitație: ordinea începe la stânga dealerului (p1, p2, apoi p0)
      for (final id in ['p1', 'p2', 'p0']) {
        engine.applyAction(id, {'type': 'declare_bid', 'amount': 0});
      }
      engine.debugSetHands({
        'p1': [c(Suit.hearts, Rank.king)],
        'p2': [c(Suit.clubs, Rank.queen), c(Suit.spades, Rank.nine)],
        'p0': [c(Suit.diamonds, Rank.ace)],
      }, trumpCard: c(Suit.spades, Rank.ten));
      engine.applyAction('p1', {'type': 'play_card', 'card': c(Suit.hearts, Rank.king).toJson()});
      expect(() => engine.applyAction('p2', {'type': 'play_card', 'card': c(Suit.clubs, Rank.queen).toJson()}),
          throwsStateError);
      engine.applyAction('p2', {'type': 'play_card', 'card': c(Suit.spades, Rank.nine).toJson()});
    });
  });

  test('Rentz: fiecare jucător alege fiecare categorie exact o dată; „Levate" = −10 pe levată', () {
    fakeAsync((async) {
      final engine = RentEngine();
      final ids = ['p0', 'p1', 'p2', 'p3'];
      for (final id in ids) {
        engine.addPlayer(id: id, name: id, isHost: id == 'p0');
      }
      engine.startGame();
      var steps = 0;
      while (engine.started && steps++ < 100000) {
        for (final id in ids) {
          for (final action in engine.autoActionCandidates(id)) {
            try {
              engine.applyAction(id, action);
              break;
            } catch (_) {}
          }
        }
      }
      expect(engine.started, isFalse);
      final history = (engine.snapshotFor('p0')['history'] as List).cast<Map>();
      expect(history, hasLength(ids.length * kRentCategories.length));
      for (final category in kRentCategories) {
        expect(history.where((r) => r['category'] == category), hasLength(ids.length), reason: category);
      }
      for (final round in history.where((r) => r['category'] == 'levate')) {
        final total = (round['roundScores'] as Map).values.fold<int>(0, (s, v) => s + (v as int));
        expect(total, -10 * RentEngine.handSize, reason: '8 levate × −10');
      }
    });
  });
}
