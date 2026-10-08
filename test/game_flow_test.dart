// Audit, punctele 4–6: intrarea într-un joc pornit, repornirea în timpul
// partidei și jucătorii deconectați care blochează tura.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_event_business/core/games_registry.dart';
import 'package:local_event_business/core/player_identity.dart';
import 'package:local_event_business/games/poker/poker_engine.dart';
import 'package:local_event_business/network/event_server_service_io.dart';

import 'support/server_harness.dart';

const secretA = 'secret-profil-alice-0001';
const secretB = 'secret-profil-bob-00002';
const secretC = 'secret-profil-carol-003';

void main() {
  group('server', () {
    late EventServerService server;

    setUp(() async {
      server = await createTestServer();
    });

    tearDown(() async {
      await server.stop();
    });

    test('un jucător nou nu poate intra într-un joc deja pornit', () async {
      final (host, code) = await createRoom(server, secret: secretA);
      await joinRoom(server, code: code, secret: secretB);
      host.send({'type': 'start_game'});
      await settle();
      expect(host.lastOfType('state')!['state']['started'], isTrue);

      final late = await joinRoom(server, code: code, secret: secretC);
      expect(late.ofType('joined'), isEmpty);
      expect(late.lastOfType('error')?['message'], contains('început'));
    });

    test('un jucător deja în partidă se poate reconecta după start', () async {
      final (host, code) = await createRoom(server, secret: secretA);
      final bob = await joinRoom(server, code: code, secret: secretB);
      host.send({'type': 'start_game'});
      await settle();
      bob.disconnect();
      await settle();
      final again = await joinRoom(server, code: code, secret: secretB);
      expect(again.lastOfType('joined')?['id'], publicPlayerId(secretB));
    });

    test('chat-ul acceptă participanți noi oricând', () async {
      final (_, code) = await createRoom(server, secret: secretA, gameId: 'chat');
      final late = await joinRoom(server, code: code, secret: secretB);
      expect(late.ofType('joined'), isNotEmpty);
    });

    test('gazda nu poate reporni jocul în timpul partidei', () async {
      final (host, code) = await createRoom(server, secret: secretA, gameId: 'poker');
      await joinRoom(server, code: code, secret: secretB);
      host.send({'type': 'start_game'});
      await settle();
      final before = host.lastOfType('state')!['state'];
      host.received.clear();

      host.send({'type': 'start_game'});
      await settle();
      expect(host.lastOfType('error')?['message'], contains('desfășurare'));
      expect(host.ofType('state'), isEmpty, reason: 'starea nu s-a schimbat deloc');
      expect(before['started'], isTrue);
    });
  });

  test('serverul joacă în locul unui jucător deconectat prea mult timp', () async {
    final server = await createTestServer();
    final fast = EventServerService(
      serverName: 'test',
      autoActAfter: const Duration(milliseconds: 60),
      autoActTick: const Duration(milliseconds: 20),
    );
    await server.stop();
    try {
      final (host, code) = await createRoom(fast, secret: secretA, gameId: 'poker');
      final bob = await joinRoom(fast, code: code, secret: secretB);
      host.send({'type': 'start_game'});
      await settle();
      final state = host.lastOfType('state')!['state'];
      final current = state['currentPlayerId'] as String;

      // Cel care trebuie să acționeze pleacă și nu se mai întoarce.
      (current == publicPlayerId(secretA) ? host : bob).disconnect();
      final watcher = current == publicPlayerId(secretA) ? bob : host;
      await settle();
      expect(watcher.lastOfType('state')!['state']['currentPlayerId'], current);

      await Future<void>.delayed(const Duration(milliseconds: 300));
      await settle();
      final after = watcher.lastOfType('state')!['state'];
      final absent = (after['players'] as List).firstWhere((p) => p['id'] == current);
      expect(after['currentPlayerId'] != current || absent['folded'] == true, isTrue,
          reason: 'partida a mers mai departe fără jucătorul absent');
    } finally {
      await fast.stop();
    }
  });

  test('Poker: startGame de două ori aruncă eroare, fisele rămân neatinse', () {
    final engine = PokerEngine()
      ..addPlayer(id: 'a', name: 'A', isHost: true)
      ..addPlayer(id: 'b', name: 'B', isHost: false);
    engine.startGame();
    final chips = engine.snapshotFor('a')['players'];
    expect(() => engine.startGame(), throwsStateError);
    expect(engine.snapshotFor('a')['players'], chips);
  });

  // Pentru fiecare joc: dacă *toți* jucătorii ar fi plecați, acțiunile
  // automate trebuie să ducă partida la capăt — nicio stare în care niciuna
  // dintre candidate nu e legală (blocaj).
  for (final definition in availableGames) {
    test('${definition.title}: acțiunile automate nu blochează niciodată partida', () {
      fakeAsync((async) {
        final engine = definition.createEngine();
        final ids = [for (var i = 0; i < engine.minPlayers; i++) 'p$i'];
        for (final id in ids) {
          engine.addPlayer(id: id, name: id, isHost: id == ids.first);
        }
        engine.startGame();

        var steps = 0;
        var stuck = 0;
        while (engine.started && steps < 50000) {
          var progressed = false;
          for (final id in ids) {
            for (final action in engine.autoActionCandidates(id)) {
              try {
                engine.applyAction(id, action);
                progressed = true;
                break;
              } catch (_) {}
            }
          }
          steps++;
          if (progressed) {
            stuck = 0;
            continue;
          }
          // Unele jocuri fac o pauză temporizată între mâini (Poker).
          async.elapse(const Duration(seconds: 5));
          stuck++;
          if (stuck > 3) {
            fail('Blocaj după $steps pași: ${engine.snapshotFor(ids.first)}');
          }
        }
        // Unde acțiunile automate sunt doar pasive (trage/pas/fold) sau jocul
        // e pur noroc (Război), o partidă cu *toți* jucătorii absenți poate
        // continua la nesfârșit — important e doar să nu se blocheze. Unde
        // jucătorul e obligat să joace o carte, partida trebuie să se încheie.
        if (!const {'war', 'poker', 'macao', 'uno'}.contains(definition.id)) {
          expect(engine.started, isFalse, reason: 'partida trebuie să se încheie');
        }
      });
    });
  }
}
