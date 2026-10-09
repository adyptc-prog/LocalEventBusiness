import 'dart:async';

import '../core/moderation_log_store.dart';
import '../core/bill_request.dart';
import '../core/order.dart';
import 'lobby_room.dart';
import 'participant_info.dart';

/// Rularea serverului central al evenimentului e disponibilă doar pe
/// Android (nativ) — un browser nu poate accepta conexiuni primite, deci nu
/// poate găzdui camere. Acest stub există doar ca targetul web să compileze
/// (aceeași formă publică ca [EventServerService] din
/// `event_server_service_io.dart`); UI-ul deja ascunde ecranul de server pe
/// web (`kIsWeb`), deci metodele de mai jos n-ar trebui apelate niciodată
/// efectiv dintr-un build web.
class EventServerService {
  static const int webPort = 45034;
  static const int discoveryPort = 45033;

  final String serverName;

  EventServerService({required this.serverName});

  List<LobbyRoom> get rooms => const [];
  Stream<List<LobbyRoom>> get roomsUpdates => const Stream.empty();

  List<ParticipantInfo> get participants => const [];
  Stream<List<ParticipantInfo>> get participantsUpdates => const Stream.empty();
  Stream<List<ModerationLogEntry>> get moderationLogUpdates => const Stream.empty();
  Stream<List<Order>> get ordersUpdates => const Stream.empty();

  void kickParticipant(String profileId) {}

  Future<void> blockParticipant(String profileId, String name) async {}

  Future<void> unblockParticipant(String profileId) async {}

  Future<void> muteParticipant(String profileId, String name) async {}

  Future<void> unmuteParticipant(String profileId) async {}

  void advanceOrder(String orderId) {}

  void cancelOrder(String orderId) {}
  void menuChanged() {}
  List<Order> get orders => const [];
  Stream<List<BillRequest>> get billsUpdates => const Stream.empty();
  List<BillRequest> get bills => const [];
  void handleBill(String billId) {}

  Future<void> broadcastAnnouncement(String text) async {}

  Future<void> start() async {
    throw UnsupportedError('Serverul evenimentului nu poate rula din browser.');
  }

  Future<void> stop() async {}
}
