import '../core/menu_item.dart';
import '../core/moderation_log_store.dart';
import '../core/bill_request.dart';
import '../core/order.dart';
import 'lobby_room.dart';
import 'participant_info.dart';

/// Foreground service-ul e disponibil doar pe Android — pe web serverul
/// evenimentului nu poate rula deloc (vezi `event_server_service_stub.dart`),
/// deci acest runner nici nu ar trebui invocat vreodată dintr-un build web.
/// Există doar ca targetul web să compileze.
class EventServerRunner {
  static void initCommunicationPort() {}

  static Stream<List<LobbyRoom>> get roomsUpdates => const Stream.empty();
  static Stream<List<ParticipantInfo>> get participantsUpdates => const Stream.empty();
  static Stream<List<ModerationLogEntry>> get moderationLogUpdates => const Stream.empty();
  static Stream<List<Order>> get ordersUpdates => const Stream.empty();
  static Stream<String> get startErrorEvents => const Stream.empty();

  static List<LobbyRoom> get lastRooms => const [];
  static List<ParticipantInfo> get lastParticipants => const [];
  static List<ModerationLogEntry> get lastModerationLog => const [];
  static List<Order> get lastOrders => const [];
  static List<BillRequest> get lastBills => const [];
  static Stream<List<BillRequest>> get billsUpdates => const Stream.empty();
  static void handleBill(String billId) {}

  static void requestState() {}

  static Future<bool> get isRunning async => false;

  static Future<bool> start({required String serverName}) async => false;

  static Future<void> stop() async {}

  static void kick(String profileId) {}

  static void block(String profileId, String name) {}

  static void unblock(String profileId) {}

  static void mute(String profileId, String name) {}

  static void unmute(String profileId) {}

  static void announce(String text) {}

  static void advanceOrder(String orderId) {}

  static void cancelOrder(String orderId) {}

  static void syncActivities(Set<String> enabledIds) {}

  static void syncMenu(List<MenuCategory> categories, List<MenuItem> items, {required String currency}) {}
}
