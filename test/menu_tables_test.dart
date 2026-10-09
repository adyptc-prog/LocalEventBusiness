// Statusul „livrată", închiderea mesei și istoricul comenzilor.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_event_business/core/menu_item.dart';
import 'package:local_event_business/core/menu_store.dart';
import 'package:local_event_business/core/order.dart';
import 'package:local_event_business/games/menu/menu_order_screen.dart';
import 'package:local_event_business/network/event_server_service_io.dart';

import 'support/fake_channel.dart';
import 'support/server_harness.dart';

void main() {
  late EventServerService server;

  setUp(() async {
    server = await createTestServer();
    MenuStore.instance.applyRemote(
      const [MenuCategory(id: 'c1', name: 'Cafele')],
      const [MenuItem(id: 'espresso', categoryId: 'c1', name: 'Espresso', priceCents: 1000)],
    );
  });
  tearDown(() async => server.stop());

  Future<FakeChannel> guest(String secret) => joinRoom(server, code: menuRoomCode, secret: secret);

  Future<void> order(FakeChannel c, String table, int qty) async {
    c.send({
      'type': 'action',
      'action': {
        'type': 'submit_order',
        'tableLabel': table,
        'lines': [
          {'menuItemId': 'espresso', 'quantity': qty},
        ],
      },
    });
    await settle();
  }

  Map<String, dynamic> stateOf(FakeChannel c) => c.lastOfType('state')!['state'] as Map<String, dynamic>;

  test('o comandă trece prin nouă → în pregătire → gata → livrată', () async {
    final a = await guest('secret-masa-livrat-01');
    await order(a, '3', 1);
    final id = server.orders.single.id;
    final seen = <OrderStatus>[server.orders.single.status];
    for (var i = 0; i < 4; i++) {
      server.advanceOrder(id);
      await settle();
      seen.add(server.orders.single.status);
    }
    expect(seen, [
      OrderStatus.placed,
      OrderStatus.preparing,
      OrderStatus.ready,
      OrderStatus.delivered,
      OrderStatus.delivered,
    ]);
    expect(server.orders.single.needsWork, isFalse, reason: 'livrată — nu mai e de lucru');
    expect((stateOf(a)['myOrders'] as List).single['status'], 'delivered');
  });

  test('închiderea mesei achită comenzile tuturor clienților ei, inclusiv al celui plecat', () async {
    final plecat = await guest('secret-masa-plecat-01');
    final nou = await guest('secret-masa-nou-0001');
    final altaMasa = await guest('secret-masa-cinci-01');
    await order(plecat, '3', 2);
    await order(nou, ' 3 ', 1); // scris cu spații — aceeași masă
    await order(altaMasa, '5', 1);
    nou.send({
      'type': 'action',
      'action': {'type': 'request_bill', 'tableLabel': '3'},
    });
    await settle();
    expect(server.bills.single.handled, isFalse);

    final total = server.closeTable('3');
    await settle();

    expect(total, 3000);
    final byTable = {for (final o in server.orders) o.tableLabel.trim(): o};
    expect(server.orders.where((o) => o.tableKey == '3').every((o) => o.isClosed), isTrue);
    expect(byTable['5']!.isClosed, isFalse, reason: 'altă masă — neatinsă');
    expect(server.bills.single.handled, isTrue, reason: 'nota cerută la masa 3 e rezolvată');

    // clienții mesei închise pornesc de la zero
    for (final c in [plecat, nou]) {
      expect(stateOf(c)['myOrders'], isEmpty);
      expect(stateOf(c)['billableTotalCents'], 0);
    }
    expect((stateOf(altaMasa)['myOrders'] as List), hasLength(1));

    // o comandă nouă la aceeași masă intră pe o notă nouă, singură
    await order(nou, '3', 1);
    expect(stateOf(nou)['billableTotalCents'], 1000);
  });

  test('închiderea unei mese fără comenzi deschise nu schimbă nimic', () async {
    expect(server.closeTable('9'), 0);
    expect(server.closeTable('   '), 0);
  });

  test('„Închide toate” închide fiecare masă deschisă și întoarce totalul', () async {
    final a = await guest('secret-toate-mesele-01');
    final b = await guest('secret-toate-mesele-02');
    await order(a, '3', 2);
    await order(b, '7', 1);
    expect(server.closeAllTables(), 3000);
    await settle();
    expect(server.orders.every((o) => o.isClosed && !o.autoClosed), isTrue);
    expect(stateOf(a)['myOrders'], isEmpty);
    expect(stateOf(b)['myOrders'], isEmpty);
    expect(server.closeAllTables(), 0, reason: 'nimic de închis a doua oară');
  });

  test('comenzile rămase deschise peste 18 ore expiră singure, cât timp serverul rulează', () async {
    final a = await guest('secret-expirare-0001');
    await order(a, '3', 1);
    a.send({
      'type': 'action',
      'action': {'type': 'request_bill', 'tableLabel': '3'},
    });
    await settle();
    expect(stateOf(a)['billableTotalCents'], 0, reason: 'comanda e deja pe nota cerută');

    // peste 17 ore: încă deschisă
    expect(server.expireStaleOrders(now: DateTime.now().add(const Duration(hours: 17))), 0);
    // peste 19 ore: expirată
    expect(server.expireStaleOrders(now: DateTime.now().add(const Duration(hours: 19))), 1);
    await settle();
    final o = server.orders.single;
    expect(o.isClosed, isTrue);
    expect(o.autoClosed, isTrue, reason: 'în istoric apare ca neachitată');
    expect(server.bills.single.handled, isTrue);
    expect(stateOf(a)['myOrders'], isEmpty, reason: 'clientul care revine nu mai vede comanda de ieri');
  });

  test('coșul netrimis e valabil 6 ore', () {
    final now = DateTime(2026, 10, 9, 22);
    int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;
    expect(menuCartIsFresh(ago(const Duration(hours: 5, minutes: 59)), now: now), isTrue);
    expect(menuCartIsFresh(ago(const Duration(hours: 6, minutes: 1)), now: now), isFalse);
    expect(menuCartIsFresh(null, now: now), isFalse, reason: 'coș salvat de o versiune veche, fără dată');
  });

  test('data închiderii se păstrează la salvare/încărcare', () {
    final o = Order(
      id: '1',
      customerId: 'p',
      tableLabel: '3',
      lines: const [OrderLine(menuItemId: 'e', name: 'Espresso', quantity: 1, unitPriceCents: 1000)],
      status: OrderStatus.delivered,
      createdAt: DateTime(2026, 10, 9, 20),
      closedAt: DateTime(2026, 10, 9, 22, 15),
      autoClosed: true,
    );
    final back = Order.fromJson(jsonDecode(jsonEncode(o.toJson())) as Map<String, dynamic>);
    expect(back.closedAt, DateTime(2026, 10, 9, 22, 15));
    expect(back.status, OrderStatus.delivered);
    expect(back.isClosed, isTrue);
    expect(back.autoClosed, isTrue);
  });
}
