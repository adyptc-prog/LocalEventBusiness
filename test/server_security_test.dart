// Audit, punctele 1–3: impersonarea organizatorului, preluarea locului
// altui jucător și reconectarea cât serverul încă ține canalul vechi.

import 'package:flutter_test/flutter_test.dart';
import 'package:local_event_business/core/organizer_key_store.dart';
import 'package:local_event_business/core/player_identity.dart';
import 'package:local_event_business/network/event_server_service_io.dart';

import 'support/server_harness.dart';

const secretA = 'secret-profil-alice-0001';
const secretB = 'secret-profil-bob-00002';

void main() {
  late EventServerService server;

  setUp(() async {
    server = await createTestServer();
  });

  tearDown(() async {
    await server.stop();
  });

  group('spectator / organizator', () {
    test('spectate fără cheia organizatorului e respins', () async {
      final (_, code) = await createRoom(server, secret: secretA);
      final intruder = await connect(server);
      intruder.send({'type': 'spectate', 'code': code});
      await settle();
      expect(intruder.ofType('spectating'), isEmpty);
      expect(intruder.lastOfType('error')?['message'], contains('organizatorul'));
    });

    test('spectate cu o cheie greșită e respins, iar chat-ul nu ajunge ca „Organizator"', () async {
      final (host, code) = await createRoom(server, secret: secretA);
      final intruder = await connect(server);
      intruder.send({'type': 'spectate', 'code': code, 'organizerKey': 'ghicit'});
      await settle();
      intruder.send({'type': 'chat', 'text': 'Localul se închide, plătiți aici'});
      await settle();
      expect(intruder.ofType('spectating'), isEmpty);
      expect(host.ofType('chat'), isEmpty);
    });

    test('organizatorul, cu cheia corectă, monitorizează și scrie în chat', () async {
      final (host, code) = await createRoom(server, secret: secretA);
      final organizer = await connect(server);
      organizer.send({'type': 'spectate', 'code': code, 'organizerKey': OrganizerKeyStore.instance.key});
      await settle();
      expect(organizer.ofType('spectating'), isNotEmpty);
      organizer.send({'type': 'chat', 'text': 'Bine ați venit!'});
      await settle();
      final chat = host.lastOfType('chat')!['message'] as Map;
      expect(chat['fromName'], 'Organizator');
      expect(chat['text'], 'Bine ați venit!');
    });
  });

  group('identitate', () {
    test('id-ul secret nu apare niciodată în ce primesc ceilalți clienți', () async {
      final (host, code) = await createRoom(server, secret: secretA);
      final other = await joinRoom(server, code: code, secret: secretB);
      host.send({'type': 'chat', 'text': 'salut'});
      await settle();

      final everything = [...host.received, ...other.received].toString();
      expect(everything, isNot(contains(secretA)));
      expect(everything, isNot(contains(secretB)));
      expect(host.lastOfType('joined')!['id'], publicPlayerId(secretA));
    });

    test('cine știe doar id-ul public al altcuiva nu-i poate lua locul', () async {
      final (host, code) = await createRoom(server, secret: secretA);
      final victimPublicId = host.lastOfType('joined')!['id'] as String;
      // Bob ține camera deschisă cât victima e plecată.
      await joinRoom(server, code: code, secret: secretB);
      host.disconnect(); // victima pierde rețeaua
      await settle();

      final attacker = await joinRoom(server, code: code, secret: victimPublicId);
      final joined = attacker.lastOfType('joined');
      expect(joined, isNotNull, reason: 'intră ca jucător nou, cu identitatea lui');
      expect(joined!['id'], isNot(victimPublicId));
      // și nu primește nimic din starea privată a victimei
      expect(attacker.ofType('replaced'), isEmpty);
    });

    test('preluarea nu merge nici cât victima e în cameră', () async {
      final (host, code) = await createRoom(server, secret: secretA);
      final victimPublicId = host.lastOfType('joined')!['id'] as String;
      final attacker = await joinRoom(server, code: code, secret: victimPublicId);
      expect(attacker.lastOfType('joined')?['id'], isNot(victimPublicId));
      expect(host.closedByServer, isFalse);
      expect(host.ofType('replaced'), isEmpty);
    });

    test('blocarea se aplică pe id-ul public derivat din secret', () async {
      final (_, code) = await createRoom(server, secret: secretA);
      await server.blockParticipant(publicPlayerId(secretB), 'Bob');
      final bob = await joinRoom(server, code: code, secret: secretB);
      expect(bob.ofType('joined'), isEmpty);
      expect(bob.lastOfType('error')?['message'], contains('blocat'));
    });

    test('id-uri secrete invalide sunt respinse', () async {
      final (_, code) = await createRoom(server, secret: secretA);
      for (final bad in <Object?>[null, 42, 'scurt', 'x' * 500]) {
        final c = await connect(server);
        c.send({'type': 'join_room', 'code': code, 'name': 'X', 'profileId': bad});
        await settle();
        expect(c.ofType('joined'), isEmpty, reason: 'profileId=$bad');
      }
    });
  });

  group('reconectare', () {
    test('o reconectare cu același profil înlocuiește canalul vechi încă „viu"', () async {
      final (host, code) = await createRoom(server, secret: secretA);
      final other = await joinRoom(server, code: code, secret: secretB);
      expect(other.ofType('joined'), isNotEmpty);

      // Serverul crede că `other` e încă conectat (conexiune moartă în
      // tăcere); clientul reintră pe un canal nou.
      final again = await joinRoom(server, code: code, secret: secretB);
      expect(again.lastOfType('joined')?['id'], publicPlayerId(secretB));
      expect(other.ofType('replaced'), isNotEmpty);
      expect(other.closedByServer, isTrue);

      await settle();
      final room = server.rooms.firstWhere((r) => r.code == code);
      expect(room.players, 2, reason: 'același loc, nu unul nou');
      expect(host.closedByServer, isFalse);
    });

    test('închiderea canalului vechi nu-l deconectează pe cel nou', () async {
      final (_, code) = await createRoom(server, secret: secretA);
      final first = await joinRoom(server, code: code, secret: secretB);
      final second = await joinRoom(server, code: code, secret: secretB);
      first.disconnect();
      await settle();
      final room = server.rooms.firstWhere((r) => r.code == code);
      expect(room.players, 2);
      expect(second.closedByServer, isFalse);
    });
  });

  group('robustețe la mesaje malformate', () {
    test('tipuri greșite și JSON invalid nu aruncă excepții', () async {
      final (host, code) = await createRoom(server, secret: secretA);
      host.sendRaw('{nu e json');
      host.sendRaw('[1,2,3]');
      host.send({'type': 5});
      host.send({'type': 'chat', 'text': 123, 'to': 7});
      host.send({'type': 'action', 'action': 'nu-e-map'});
      final c = await connect(server);
      c.send({'type': 'join_room', 'code': 123, 'name': [], 'profileId': secretB});
      c.send({'type': 'create_room', 'gameId': 1, 'roomName': 2, 'name': 3, 'profileId': secretB, 'tableStake': 'mult'});
      c.send({'type': 'spectate', 'code': code, 'organizerKey': 99});
      await settle();
      expect(server.rooms.where((r) => r.code == code), isNotEmpty);
    });
  });
}
