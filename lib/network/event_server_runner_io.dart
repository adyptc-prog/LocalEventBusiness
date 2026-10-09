import 'dart:async';
import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../core/bill_request.dart';
import '../core/blocked_users_store.dart';
import '../core/event_config_store.dart';
import '../core/menu_item.dart';
import '../core/menu_store.dart';
import '../core/moderation_log_store.dart';
import '../core/muted_users_store.dart';
import '../core/order.dart';
import '../l10n/tr.dart';
import '../core/orders_store.dart';
import '../core/organizer_key_store.dart';
import 'event_server_service.dart';
import 'lobby_room.dart';
import 'participant_info.dart';

/// Rulează [EventServerService] într-un foreground service Android
/// (`flutter_foreground_task`), ca Android să nu omoare serverul când
/// ecranul telefonului-server se stinge sau aplicația trece în fundal —
/// esențial cât timp serverul găzduiește un local de ore întregi.
///
/// Serverul rulează efectiv într-un isolate separat de UI, deținut de
/// service-ul Android (nu de ecranul care l-a pornit); comunicarea trece
/// prin canalul de date al pluginului, ca JSON, în ambele sensuri: server →
/// UI pentru stări (camere, participanți, comenzi), UI → server pentru
/// comenzi de moderare/gestiune (elimină/blochează/deblochează, avansează o
/// comandă, sincronizează meniul) — singurul loc din aplicație unde ecranul
/// comandă serverul, nu doar îi ascultă starea.
class EventServerRunner {
  static const _serviceId = 4503;

  // Ultima stare primită de la server — un ecran deschis după ce serverul
  // a trimis-o (ex: „Comenzi la bar" deschis după ce au venit comenzi) o
  // afișează imediat, fără să aștepte următoarea schimbare.
  static List<LobbyRoom> _lastRooms = const [];
  static List<ParticipantInfo> _lastParticipants = const [];
  static List<ModerationLogEntry> _lastModerationLog = const [];
  static List<Order> _lastOrders = const [];
  static List<BillRequest> _lastBills = const [];
  static List<BillRequest> get lastBills => _lastBills;
  static final _billsController = StreamController<List<BillRequest>>.broadcast();
  static Stream<List<BillRequest>> get billsUpdates => _billsController.stream;
  static List<LobbyRoom> get lastRooms => _lastRooms;
  static List<ParticipantInfo> get lastParticipants => _lastParticipants;
  static List<ModerationLogEntry> get lastModerationLog => _lastModerationLog;
  static List<Order> get lastOrders => _lastOrders;

  static final _roomsController = StreamController<List<LobbyRoom>>.broadcast();
  static Stream<List<LobbyRoom>> get roomsUpdates => _roomsController.stream;

  static final _participantsController = StreamController<List<ParticipantInfo>>.broadcast();
  static Stream<List<ParticipantInfo>> get participantsUpdates => _participantsController.stream;

  static final _moderationLogController = StreamController<List<ModerationLogEntry>>.broadcast();
  static Stream<List<ModerationLogEntry>> get moderationLogUpdates => _moderationLogController.stream;

  static final _ordersController = StreamController<List<Order>>.broadcast();
  static Stream<List<Order>> get ordersUpdates => _ordersController.stream;

  /// Emite un mesaj când isolate-ul serverului nu a reușit efectiv să
  /// pornească (ex: portul 45034 e deja ocupat) — spre deosebire de
  /// [start], care confirmă doar că foreground service-ul Android a fost
  /// lansat, nu că `HttpServer.bind` a reușit înăuntrul lui.
  static final _startErrorController = StreamController<String>.broadcast();
  static Stream<String> get startErrorEvents => _startErrorController.stream;

  static bool _listening = false;

  /// Apelat o singură dată, înainte de `runApp` (vezi `main.dart`).
  static void initCommunicationPort() {
    FlutterForegroundTask.initCommunicationPort();
    if (!_listening) {
      _listening = true;
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    }
  }

  static void _onTaskData(Object data) {
    if (data is! String) return;
    try {
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      switch (decoded['type']) {
        case 'rooms':
          final rooms = (decoded['rooms'] as List)
              .map((r) => LobbyRoom.fromJson(Map<String, dynamic>.from(r as Map)))
              .toList();
          _lastRooms = rooms;
          _roomsController.add(rooms);
          break;
        case 'participants':
          final participants = (decoded['participants'] as List)
              .map((p) => ParticipantInfo.fromJson(Map<String, dynamic>.from(p as Map)))
              .toList();
          _lastParticipants = participants;
          _participantsController.add(participants);
          break;
        case 'moderation_log':
          final log = (decoded['log'] as List)
              .map((e) => ModerationLogEntry.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
          _lastModerationLog = log;
          _moderationLogController.add(log);
          break;
        case 'orders':
          final orders = (decoded['orders'] as List)
              .map((o) => Order.fromJson(Map<String, dynamic>.from(o as Map)))
              .toList();
          _lastOrders = orders;
          _ordersController.add(orders);
          break;
        case 'bills':
          final bills = (decoded['bills'] as List)
              .map((b) => BillRequest.fromJson(Map<String, dynamic>.from(b as Map)))
              .toList();
          _lastBills = bills;
          _billsController.add(bills);
          break;
        case 'start_error':
          _startErrorController.add(decoded['message'] as String? ?? tr('err.serverStart'));
          break;
      }
    } catch (_) {}
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  /// Pornește serverul localului ca foreground service. Cere permisiunea
  /// de notificări (obligatorie pe Android 13+ pentru notificarea
  /// persistentă a service-ului) dacă nu e deja acordată.
  static Future<bool> start({required String serverName}) async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'localevent_server',
        channelName: tr('server.notif.channel'),
        channelDescription: tr('server.notif.channelDesc'),
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      notificationTitle: tr('server.notif.title'),
      notificationText: serverName,
      callback: _startCallback,
    );
    return result is ServiceRequestSuccess;
  }

  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
    _lastRooms = const [];
    _lastParticipants = const [];
    _lastModerationLog = const [];
    _lastOrders = const [];
    _lastBills = const [];
  }

  /// Barul a dus nota la masă.
  static void handleBill(String billId) {
    FlutterForegroundTask.sendDataToTask(jsonEncode({'type': 'handle_bill', 'billId': billId}));
  }

  /// Cere serverului să retrimită toată starea curentă (camere, participanți,
  /// istoric de moderare, comenzi) — apelat de ecranele organizatorului la
  /// deschidere, inclusiv după ce aplicația a fost redeschisă cu serverul
  /// încă pornit în fundal.
  static void requestState() {
    FlutterForegroundTask.sendDataToTask(jsonEncode({'type': 'request_state'}));
  }

  static void kick(String profileId) {
    FlutterForegroundTask.sendDataToTask(jsonEncode({'type': 'kick', 'profileId': profileId}));
  }

  static void block(String profileId, String name) {
    FlutterForegroundTask.sendDataToTask(jsonEncode({'type': 'block', 'profileId': profileId, 'name': name}));
  }

  static void unblock(String profileId) {
    FlutterForegroundTask.sendDataToTask(jsonEncode({'type': 'unblock', 'profileId': profileId}));
  }

  static void mute(String profileId, String name) {
    FlutterForegroundTask.sendDataToTask(jsonEncode({'type': 'mute', 'profileId': profileId, 'name': name}));
  }

  static void unmute(String profileId) {
    FlutterForegroundTask.sendDataToTask(jsonEncode({'type': 'unmute', 'profileId': profileId}));
  }

  static void announce(String text) {
    FlutterForegroundTask.sendDataToTask(jsonEncode({'type': 'announce', 'text': text}));
  }

  static void advanceOrder(String orderId) {
    FlutterForegroundTask.sendDataToTask(jsonEncode({'type': 'advance_order', 'orderId': orderId}));
  }

  static void cancelOrder(String orderId) {
    FlutterForegroundTask.sendDataToTask(jsonEncode({'type': 'cancel_order', 'orderId': orderId}));
  }

  /// Trimite serverului deja pornit selecția curentă de activități — fără
  /// asta, o schimbare din `ActivityConfigScreen` nu ajunge niciodată la
  /// isolate-ul serverului (fiecare are propria copie în memorie a
  /// [EventConfigStore], vezi documentația lui).
  static void syncActivities(Set<String> enabledIds) {
    FlutterForegroundTask.sendDataToTask(jsonEncode({'type': 'sync_activities', 'activities': enabledIds.toList()}));
  }

  /// La fel ca [syncActivities], dar pentru banca de produse de meniu —
  /// aceeași problemă de izolate separate, aceeași soluție.
  static void syncMenu(List<MenuCategory> categories, List<MenuItem> items, {required String currency}) {
    FlutterForegroundTask.sendDataToTask(jsonEncode({
      'type': 'sync_menu',
      'categories': categories.map((c) => c.toJson()).toList(),
      'items': items.map((i) => i.toJson()).toList(),
      'currency': currency,
    }));
  }
}

// Trebuie top-level, cu adnotarea de mai jos — pluginul îl rulează într-un
// isolate nou, dedicat service-ului, la pornirea foreground service-ului.
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_EventServerTaskHandler());
}

class _EventServerTaskHandler extends TaskHandler {
  EventServerService? _server;
  StreamSubscription? _roomsSub;
  StreamSubscription? _participantsSub;
  StreamSubscription? _moderationLogSub;
  StreamSubscription? _ordersSub;
  StreamSubscription? _billsSub;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Isolate separat de UI — își citește propriul config, din aceeași
    // memorie persistentă a dispozitivului (shared_preferences).
    await EventConfigStore.instance.init();
    await MenuStore.instance.init();
    await BlockedUsersStore.instance.init();
    await MutedUsersStore.instance.init();
    await ModerationLogStore.instance.init();
    await OrganizerKeyStore.instance.init();
    await OrdersStore.instance.init();
    await LanguageController.instance.init();
    final server = EventServerService(serverName: 'Server local');
    try {
      await server.start();
    } catch (e) {
      FlutterForegroundTask.sendDataToMain(jsonEncode({'type': 'start_error', 'message': e.toString()}));
      await FlutterForegroundTask.stopService();
      return;
    }
    _server = server;
    _roomsSub = server.roomsUpdates.listen((rooms) {
      FlutterForegroundTask.sendDataToMain(jsonEncode({
        'type': 'rooms',
        'rooms': rooms.map((r) => r.toJson()).toList(),
      }));
      FlutterForegroundTask.updateService(
        notificationText: rooms.isEmpty ? tr('server.notif.noRooms') : tr('server.notif.rooms', {'n': rooms.length}),
      );
    });
    _participantsSub = server.participantsUpdates.listen((participants) {
      FlutterForegroundTask.sendDataToMain(jsonEncode({
        'type': 'participants',
        'participants': participants.map((p) => p.toJson()).toList(),
      }));
    });
    _moderationLogSub = server.moderationLogUpdates.listen((log) {
      FlutterForegroundTask.sendDataToMain(jsonEncode({
        'type': 'moderation_log',
        'log': log.map((e) => e.toJson()).toList(),
      }));
    });
    _ordersSub = server.ordersUpdates.listen(_sendOrders);
    _billsSub = server.billsUpdates.listen(_sendBills);
  }

  void _sendBills(List<BillRequest> bills) {
    FlutterForegroundTask.sendDataToMain(jsonEncode({
      'type': 'bills',
      'bills': bills.map((b) => b.toJson()).toList(),
    }));
  }

  void _sendOrders(List<Order> orders) {
    FlutterForegroundTask.sendDataToMain(jsonEncode({
      'type': 'orders',
      'orders': orders.map((o) => o.toJson()).toList(),
    }));
  }

  void _sendFullState(EventServerService server) {
    FlutterForegroundTask.sendDataToMain(jsonEncode({
      'type': 'rooms',
      'rooms': server.rooms.map((r) => r.toJson()).toList(),
    }));
    FlutterForegroundTask.sendDataToMain(jsonEncode({
      'type': 'participants',
      'participants': server.participants.map((p) => p.toJson()).toList(),
    }));
    FlutterForegroundTask.sendDataToMain(jsonEncode({
      'type': 'moderation_log',
      'log': ModerationLogStore.instance.entries.map((e) => e.toJson()).toList(),
    }));
    _sendOrders(server.orders);
    _sendBills(server.bills);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  /// Comenzi trimise de ecranele UI (`ParticipantsScreen`, `MenuEditorScreen`,
  /// `OrdersDashboardScreen`) — singurul loc din aplicație unde UI-ul
  /// comandă serverul, nu doar ascultă starea lui.
  @override
  void onReceiveData(Object data) {
    if (data is! String) return;
    final server = _server;
    if (server == null) return;
    try {
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      switch (decoded['type']) {
        case 'request_state':
          _sendFullState(server);
          break;
        case 'kick':
          server.kickParticipant(decoded['profileId'] as String);
          break;
        case 'block':
          server.blockParticipant(decoded['profileId'] as String, decoded['name'] as String);
          break;
        case 'unblock':
          server.unblockParticipant(decoded['profileId'] as String);
          break;
        case 'mute':
          server.muteParticipant(decoded['profileId'] as String, decoded['name'] as String);
          break;
        case 'unmute':
          server.unmuteParticipant(decoded['profileId'] as String);
          break;
        case 'announce':
          server.broadcastAnnouncement(decoded['text'] as String);
          break;
        case 'advance_order':
          server.advanceOrder(decoded['orderId'] as String);
          break;
        case 'cancel_order':
          server.cancelOrder(decoded['orderId'] as String);
          break;
        case 'handle_bill':
          server.handleBill(decoded['billId'] as String);
          break;
        case 'sync_activities':
          EventConfigStore.instance.applyRemote((decoded['activities'] as List).cast<String>());
          break;
        case 'sync_menu':
          MenuStore.instance.applyRemote(
            (decoded['categories'] as List).map((c) => MenuCategory.fromJson(Map<String, dynamic>.from(c as Map))).toList(),
            (decoded['items'] as List).map((i) => MenuItem.fromJson(Map<String, dynamic>.from(i as Map))).toList(),
            currency: decoded['currency'] as String?,
          );
          server.menuChanged();
          break;
      }
    } catch (_) {}
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _roomsSub?.cancel();
    await _participantsSub?.cancel();
    await _moderationLogSub?.cancel();
    await _ordersSub?.cancel();
    await _billsSub?.cancel();
    await _server?.stop();
  }
}
