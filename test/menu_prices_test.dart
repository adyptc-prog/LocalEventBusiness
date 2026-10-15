// Prețurile din meniu, totalurile comenzilor și cartonașele QR de tipărit.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_event_business/core/menu_item.dart';
import 'package:local_event_business/core/menu_store.dart';
import 'package:local_event_business/core/order.dart';
import 'package:local_event_business/core/qr_cards.dart';
import 'package:local_event_business/l10n/money.dart';
import 'package:local_event_business/l10n/tr.dart';
import 'package:local_event_business/network/event_server_service_io.dart';

import 'support/server_harness.dart';

void main() {
  tearDown(() => LanguageController.instance.debugSetLanguage(AppLanguage.ro));

  group('prețuri', () {
    test('formatare după limbă, cu moneda aleasă de local (sau fără)', () {
      expect(formatPrice(1250, 'lei'), '12,50 lei');
      expect(formatPrice(700, 'lei'), '7,00 lei');
      expect(formatPrice(1250, ''), '12,50');
      LanguageController.instance.debugSetLanguage(AppLanguage.en);
      expect(formatPrice(1250, '€'), '12.50 €');
      expect(formatPrice(1250, ' '), '12.50');
    });

    test('citirea prețului scris de organizator', () {
      expect(parsePrice('12'), 1200);
      expect(parsePrice('12,5'), 1250);
      expect(parsePrice(' 12.50 '), 1250);
      expect(parsePrice('0'), 0);
      for (final bad in ['', 'abc', '-3', '12,505', '1.2.3', '9999999']) {
        expect(parsePrice(bad), isNull, reason: bad);
      }
      expect(priceForEditing(1250), '12,50');
      expect(priceForEditing(1200), '12');
    });

    test('prețul produsului și al liniilor de comandă trec prin JSON', () {
      const item = MenuItem(id: 'e', categoryId: 'c', name: 'Espresso', priceCents: 900);
      expect(MenuItem.fromJson(item.toJson()).priceCents, 900);
      expect(item.copyWith(priceCents: 1000).priceCents, 1000);
      expect(item.copyWith(name: 'Ristretto').priceCents, 900);

      final order = Order(
        id: '1',
        customerId: 'p',
        tableLabel: '3',
        lines: const [
          OrderLine(menuItemId: 'e', name: 'Espresso', quantity: 2, unitPriceCents: 900),
          OrderLine(menuItemId: 'l', name: 'Latte', quantity: 1, unitPriceCents: 1450),
        ],
        status: OrderStatus.placed,
        createdAt: DateTime(2026),
      );
      expect(order.totalCents, 3250);
      final back = Order.fromJson(jsonDecode(jsonEncode(order.toJson())) as Map<String, dynamic>);
      expect(back.totalCents, 3250);
    });
  });

  group('server', () {
    late EventServerService server;
    setUp(() async {
      server = await createTestServer();
      MenuStore.instance.applyRemote(
        const [MenuCategory(id: 'c1', name: 'Cafele')],
        const [MenuItem(id: 'espresso', categoryId: 'c1', name: 'Espresso', priceCents: 1250)],
      );
    });
    tearDown(() async => server.stop());

    test('prețul comenzii vine din meniu, nu de la client', () async {
      final guest = await joinRoom(server, code: menuRoomCode, secret: 'secret-profil-pret-0001');
      expect(((guest.lastOfType('state')!['state']['menu']['items'] as List).single as Map)['priceCents'], 1250);
      guest.send({
        'type': 'action',
        'action': {
          'type': 'submit_order',
          'tableLabel': '4',
          'lines': [
            {'menuItemId': 'espresso', 'quantity': 2, 'unitPriceCents': 1},
          ],
        },
      });
      await settle();
      final order = (guest.lastOfType('state')!['state']['myOrders'] as List).single as Map;
      final line = (order['lines'] as List).single as Map;
      expect(line['unitPriceCents'], 1250);
      expect(server.orders.single.totalCents, 2500);
    });

    test('moneda aleasă de local ajunge la clienți', () async {
      MenuStore.instance.applyRemote(MenuStore.instance.categories, MenuStore.instance.items, currency: '€');
      final guest = await joinRoom(server, code: menuRoomCode, secret: 'secret-profil-pret-0002');
      expect(guest.lastOfType('state')!['state']['menu']['currency'], '€');
      MenuStore.instance.applyRemote(MenuStore.instance.categories, MenuStore.instance.items, currency: '');
    });

    test('cererea de notă: totalul comenzilor nefacturate, una deschisă odată, apoi notă nouă', () async {
      final guest = await joinRoom(server, code: menuRoomCode, secret: 'secret-profil-nota-0001');
      Map<String, dynamic> state() => guest.lastOfType('state')!['state'] as Map<String, dynamic>;
      void order(int qty) => guest.send({
            'type': 'action',
            'action': {
              'type': 'submit_order',
              'tableLabel': '7',
              'lines': [
                {'menuItemId': 'espresso', 'quantity': qty},
              ],
            },
          });
      void requestBill([String table = '7']) => guest.send({
            'type': 'action',
            'action': {'type': 'request_bill', 'tableLabel': table},
          });

      order(2);
      await settle();
      expect(state()['billableTotalCents'], 2500);

      requestBill('');
      await settle();
      expect(guest.lastOfType('error')?['messageKey'], 'err.menu.tableRequired');

      requestBill();
      await settle();
      expect(state()['myBill']['handled'], isFalse);
      expect(state()['myBill']['totalCents'], 2500);
      expect(server.bills.single.tableLabel, '7');

      requestBill();
      await settle();
      expect(guest.lastOfType('error')?['messageKey'], 'err.menu.billAlreadyRequested');

      server.handleBill(server.bills.single.id);
      await settle();
      expect(state()['myBill']['handled'], isTrue);
      expect(state()['billableTotalCents'], 0, reason: 'comanda a intrat deja pe notă');

      // o comandă nouă după notă intră pe nota următoare, singură
      order(1);
      await settle();
      requestBill();
      await settle();
      expect(state()['myBill']['totalCents'], 1250);
      expect(server.bills.where((b) => !b.handled), hasLength(1));
    });
  });

  group('cartonașul QR de tipărit', () {
    testWidgets('imaginea cartonașului e un PNG pătrat, cu sau fără Wi-Fi', (tester) async {
      for (final ssid in ['Cafenea', '']) {
        final png = await tester.runAsync(
          () => QrCards.renderCardPng(menuUrl: menuUrlFor('192.168.1.10'), wifiSsid: ssid, wifiPassword: 'parola123'),
        );
        expect(png!.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
        // lățimea și înălțimea din antetul IHDR
        final width = (png[16] << 24) | (png[17] << 16) | (png[18] << 8) | png[19];
        final height = (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23];
        expect(width, QrCards.cardPixels);
        expect(height, QrCards.cardPixels);
      }
    });

    testWidgets('PDF-ul are câte 6 cartonașe pe pagină', (tester) async {
      final pdf = await tester.runAsync(() async {
        final card = await QrCards.renderCardPng(menuUrl: menuUrlFor('192.168.1.10'));
        return QrCards.buildCardsPdf(card: card, copies: 7);
      });
      expect(ascii.decode(pdf!.sublist(0, 5)), '%PDF-');
      final text = latin1.decode(pdf);
      expect(RegExp(r'/Type\s*/Page[^s]').allMatches(text).length, 2, reason: '7 cartonașe → 2 pagini');
    });

    test('link-ul de meniu nu are număr de masă și e recunoscut la deschidere', () {
      final url = menuUrlFor('192.168.1.10');
      expect(url, 'http://192.168.1.10:45034/?menu');
      expect(openedFromMenuQr(Uri.parse(url)), isTrue);
      // cartonașele vechi, numerotate, merg în continuare
      expect(openedFromMenuQr(Uri.parse('http://192.168.1.10:45034/?table=5')), isTrue);
      expect(openedFromMenuQr(Uri.parse('http://192.168.1.10:45034/')), isFalse);
    });

    test('QR-ul de Wi-Fi are formatul recunoscut de telefoane', () {
      expect(wifiQrPayload(ssid: 'Cafenea', password: 'parola123'), 'WIFI:T:WPA;S:Cafenea;P:parola123;;');
      expect(wifiQrPayload(ssid: 'Cafenea', password: ''), 'WIFI:T:nopass;S:Cafenea;;');
      expect(wifiQrPayload(ssid: 'Bar;Nou', password: r'a:b"c\d'), r'WIFI:T:WPA;S:Bar\;Nou;P:a\:b\"c\\d;;');
    });
  });
}
