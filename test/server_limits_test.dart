// Audit, punctele 7–9: limite anti-abuz, validarea cererilor de creare /
// alăturare și persistența comenzilor la bar.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_event_business/core/event_config_store.dart';
import 'package:local_event_business/core/menu_item.dart';
import 'package:local_event_business/core/menu_store.dart';
import 'package:local_event_business/core/order.dart';
import 'package:local_event_business/core/orders_store.dart';
import 'package:local_event_business/core/player_identity.dart';
import 'package:local_event_business/network/event_server_service_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_channel.dart';
import 'support/server_harness.dart';

const secretA = 'secret-profil-alice-0001';
const secretB = 'secret-profil-bob-00002';

void main() {
  late EventServerService server;

  setUp(() async {
    server = await createTestServer();
    MenuStore.instance.applyRemote(
      const [MenuCategory(id: 'c1', name: 'Cafele')],
      const [
        MenuItem(id: 'espresso', categoryId: 'c1', name: 'Espresso'),
        MenuItem(id: 'latte', categoryId: 'c1', name: 'Latte', available: false),
      ],
    );
  });

  tearDown(() async {
    await server.stop();
  });

  group('limite de conexiune', () {
    test('mesajele uriașe sunt ignorate', () async {
      final c = await connect(server);
      c.send({
        'type': 'create_room',
        'gameId': 'macao',
        'roomName': 'x' * (EventServerService.maxMessageLength + 10),
        'name': 'A',
        'profileId': secretA,
      });
      await settle();
      expect(c.ofType('joined'), isEmpty);
      expect(c.ofType('error'), isEmpty, reason: 'nici măcar nu e procesat');
    });

    test('o rafală de mesaje e tăiată, iar inundarea persistentă închide conexiunea', () async {
      final (host, _) = await createRoom(server, secret: secretA, gameId: 'chat');
      // fiecare rafală e în aceeași secundă; 5 rafale peste limită
      for (var burst = 0; burst < 5 && !host.closedByServer; burst++) {
        for (var i = 0; i < EventServerService.maxMessagesPerSecond + 5; i++) {
          host.send({'type': 'chat', 'text': 'spam $i'});
        }
        await settle();
        await Future<void>.delayed(const Duration(milliseconds: 1050));
      }
      expect(host.closedByServer, isTrue);
    });

    test('numărul de camere e limitat', () async {
      final created = <FakeChannel>[];
      for (var i = 0; i < EventServerService.maxRooms + 3; i++) {
        final c = await connect(server);
        c.send({
          'type': 'create_room',
          'gameId': 'chat',
          'roomName': 'Camera $i',
          'name': 'N$i',
          'profileId': 'secret-profil-numar-$i-xx',
        });
        created.add(c);
      }
      await settle();
      expect(server.rooms.length, EventServerService.maxRooms);
      expect(created.last.lastOfType('error')?['message'], contains('prea multe camere'));
    });

    test('mesajele de chat prea lungi sunt refuzate', () async {
      final (host, code) = await createRoom(server, secret: secretA, gameId: 'chat');
      final bob = await joinRoom(server, code: code, secret: secretB);
      host.send({'type': 'chat', 'text': 'a' * (EventServerService.maxChatLength + 1)});
      await settle();
      expect(bob.ofType('chat'), isEmpty);
      expect(host.lastOfType('error')?['message'], contains('prea lung'));
    });
  });

  group('validarea creării / alăturării', () {
    test('o activitate dezactivată de organizator nu poate fi creată', () async {
      EventConfigStore.instance.applyRemote(['macao', 'chat']);
      final c = await connect(server);
      c.send({'type': 'create_room', 'gameId': 'poker', 'roomName': 'M', 'name': 'A', 'profileId': secretA});
      await settle();
      expect(c.ofType('joined'), isEmpty);
      expect(c.lastOfType('error')?['message'], contains('nu e disponibilă'));
      await EventConfigStore.instance.init();
    });

    test('nu se poate crea o a doua cameră de Meniu', () async {
      final c = await connect(server);
      c.send({'type': 'create_room', 'gameId': 'menu', 'roomName': 'M', 'name': 'A', 'profileId': secretA});
      await settle();
      expect(c.ofType('joined'), isEmpty);
      expect(server.rooms.where((r) => r.gameId == 'menu').length, 1);
    });

    test('miza mesei e limitată la [0, max]', () async {
      final (big, _) = await createRoom(server, secret: secretA, tableStake: 999999);
      expect(big.lastOfType('state')!['state']['tableStake'], EventServerService.maxTableStake);
      final (neg, _) = await createRoom(server, secret: secretB, tableStake: -500);
      expect(neg.lastOfType('state')!['state']['tableStake'], 0);
    });

    test('alăturarea la o cameră cu alt joc decât cel așteptat nu ocupă loc', () async {
      final (_, code) = await createRoom(server, secret: secretA, gameId: 'macao');
      final c = await connect(server);
      c.send({'type': 'join_room', 'code': code, 'name': 'B', 'profileId': secretB, 'gameId': 'poker'});
      await settle();
      expect(c.ofType('joined'), isEmpty);
      expect(server.rooms.firstWhere((r) => r.code == code).players, 1);
    });
  });

  group('meniu și comenzi', () {
    Future<FakeChannel> joinMenu(String secret) =>
        joinRoom(server, code: menuRoomCode, secret: secret);

    Map<String, dynamic> order({int quantity = 1, String item = 'espresso', String table = '5'}) => {
          'type': 'action',
          'action': {
            'type': 'submit_order',
            'tableLabel': table,
            'lines': [
              {'menuItemId': item, 'quantity': quantity},
            ],
          },
        };

    test('fiecare client se vede doar pe el, nu lista tuturor clienților', () async {
      final a = await joinMenu(secretA);
      await joinMenu(secretB);
      final players = a.lastOfType('state')!['state']['players'] as List;
      expect(players.map((p) => p['id']), [publicPlayerId(secretA)]);
    });

    test('o comandă nouă retrimite starea doar celui care a comandat', () async {
      final a = await joinMenu(secretA);
      final b = await joinMenu(secretB);
      b.received.clear();
      a.send(order());
      await settle();
      final myOrders = a.lastOfType('state')!['state']['myOrders'] as List;
      expect(myOrders, hasLength(1));
      expect(b.ofType('state'), isEmpty);
    });

    test('cantitățile mari și produsele indisponibile sunt refuzate', () async {
      final a = await joinMenu(secretA);
      a.send(order(quantity: 500));
      await settle();
      expect(a.lastOfType('error')?['message'], contains('Maxim'));
      a.send(order(item: 'latte'));
      await settle();
      expect(a.lastOfType('error')?['message'], contains('goală'));
      expect(server.participants, isNotEmpty);
    });

    test('un client nu poate avea mai mult de N comenzi deschise', () async {
      final a = await joinMenu(secretA);
      for (var i = 0; i < 7; i++) {
        a.send(order());
        await settle();
      }
      final myOrders = a.lastOfType('state')!['state']['myOrders'] as List;
      expect(myOrders, hasLength(5));
      expect(a.lastOfType('error')?['message'], contains('așteptare'));
    });

    test('câmpurile cu tip greșit nu aruncă excepții', () async {
      final a = await joinMenu(secretA);
      a.send({
        'type': 'action',
        'action': {'type': 'submit_order', 'tableLabel': 7, 'lines': 'nu', 'note': []},
      });
      a.send({
        'type': 'action',
        'action': {
          'type': 'submit_order',
          'tableLabel': '1',
          'lines': [1, null, {'menuItemId': 3, 'quantity': '2'}],
        },
      });
      await settle();
      expect(a.ofType('error'), hasLength(2));
    });

    test('meniul editat ajunge imediat la clienții deja conectați', () async {
      final a = await joinMenu(secretA);
      MenuStore.instance.applyRemote(
        const [MenuCategory(id: 'c1', name: 'Cafele')],
        const [MenuItem(id: 'ceai', categoryId: 'c1', name: 'Ceai')],
      );
      server.menuChanged();
      await settle();
      final items = a.lastOfType('state')!['state']['menu']['items'] as List;
      expect(items.map((i) => i['id']), ['ceai']);
    });
  });

  group('persistența comenzilor', () {
    test('comenzile salvate sunt repuse la repornire, cele vechi sunt aruncate', () async {
      final recent = Order(
        id: '1',
        customerId: 'p1',
        tableLabel: '3',
        lines: const [OrderLine(menuItemId: 'espresso', name: 'Espresso', quantity: 2)],
        status: OrderStatus.preparing,
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
      );
      final old = Order(
        id: '0',
        customerId: 'p1',
        tableLabel: '3',
        lines: const [OrderLine(menuItemId: 'espresso', name: 'Espresso', quantity: 1)],
        status: OrderStatus.ready,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      );
      SharedPreferences.setMockInitialValues({
        'menu_orders_v1': jsonEncode([recent.toJson(), old.toJson()]),
      });
      await OrdersStore.instance.init();
      final restarted = EventServerService(serverName: 'repornit');
      final orders = <Order>[];
      final sub = restarted.ordersUpdates.listen(orders.addAll);
      restarted.advanceOrder('1');
      await settle();
      expect(orders.map((o) => o.id), ['1']);
      expect(orders.single.status, OrderStatus.ready);

      // și schimbarea a fost scrisă pe disc
      await OrdersStore.instance.flush();
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('menu_orders_v1')!) as List;
      expect(saved.single['status'], 'ready');

      await sub.cancel();
      await restarted.stop();
    });
  });
}
