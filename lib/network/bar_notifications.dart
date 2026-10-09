import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/bill_request.dart';
import '../core/order.dart';
import '../l10n/money.dart';
import '../l10n/tr.dart';

/// Notificările cu sunet de pe telefonul-server: o comandă nouă și o cerere
/// de notă apar ca notificare „heads-up" (peste orice aplicație deschisă),
/// cu sunet și vibrație — barul nu trebuie să stea cu ochii pe ecran.
///
/// Rulează în isolate-ul serverului (foreground service-ul), deci merge și
/// cu ecranul stins sau aplicația în fundal. Ține minte ce a anunțat deja,
/// ca la repornirea serverului comenzile restaurate să nu sune din nou.
class BarNotifications {
  static const String _channelId = 'bar_events_v1';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final Set<String> _announcedOrders = {};
  final Set<String> _announcedBills = {};
  bool _ready = false;
  int _nextId = 1000;

  /// [existingOrders] / [existingBills]: ce exista deja la pornire (restaurat
  /// de pe disc) — nu se anunță.
  Future<void> init({required List<Order> existingOrders, required List<BillRequest> existingBills}) async {
    _announcedOrders.addAll(existingOrders.map((o) => o.id));
    _announcedBills.addAll(existingBills.map((b) => b.id));
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(AndroidNotificationChannel(
          _channelId,
          tr('notif.channel'),
          description: tr('notif.channelDesc'),
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ));
    _ready = true;
  }

  /// Anunță comenzile noi din lista curentă (cele încă neanunțate).
  Future<void> onOrders(List<Order> orders, String currency) async {
    for (final order in orders.reversed) {
      if (!_announcedOrders.add(order.id)) continue;
      if (order.status != OrderStatus.placed) continue;
      final lines = order.lines.map((l) => '${l.quantity}x ${l.name}').join(', ');
      final total = order.totalCents > 0 ? ' · ${formatPrice(order.totalCents, currency)}' : '';
      await _show(
        tr('notif.newOrder', {'table': order.tableLabel}),
        '$lines$total${order.note == null ? '' : '\n${tr('orders.note', {'note': order.note})}'}',
      );
    }
  }

  /// Anunță cererile de notă noi.
  Future<void> onBills(List<BillRequest> bills, String currency) async {
    for (final bill in bills.reversed) {
      if (!_announcedBills.add(bill.id)) continue;
      if (bill.handled) continue;
      await _show(
        tr('bills.tableAsks', {'table': bill.tableLabel}),
        bill.totalCents > 0 ? tr('orders.total', {'amount': formatPrice(bill.totalCents, currency)}) : tr('bills.noAppOrders'),
      );
    }
  }

  Future<void> _show(String title, String body) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            tr('notif.channel'),
            channelDescription: tr('notif.channelDesc'),
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            ticker: title,
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
      );
    } catch (_) {
      // o notificare eșuată (ex: permisiune refuzată) nu are voie să oprească serverul
    }
  }
}
