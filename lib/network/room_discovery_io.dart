import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'discovered_room.dart';
import 'game_message.dart';

/// Ascultă beacon-ul UDP al serverului central de eveniment de pe rețeaua
/// locală și menține live lista serverelor găsite (în practică, unul
/// singur, la un eveniment). Doar pentru clienți nativi (Android/desktop) —
/// un browser nu poate asculta UDP deloc, de-aia există [RoomDiscovery]
/// separat de restul lui [ClientService]. Odată ales un server, lista de
/// camere ale lui se cere separat, prin WebSocket, după conectare.
class RoomDiscovery {
  static const int discoveryPort = 45033;

  RawDatagramSocket? _socket;
  Timer? _pruneTimer;
  final Map<String, DiscoveredRoom> _servers = {};
  final _serversController = StreamController<List<DiscoveredRoom>>.broadcast();
  Stream<List<DiscoveredRoom>> get rooms => _serversController.stream;

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort, reuseAddress: true);
    _socket!.broadcastEnabled = true;
    _socket!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket!.receive();
      if (datagram == null) return;
      try {
        final msg = GameMessage.decode(utf8.decode(datagram.data));
        if (msg['type'] != 'server_announce') return;
        final server = DiscoveredRoom(
          name: msg['name'] as String,
          address: datagram.address.address,
          port: msg['port'] as int,
          rooms: msg['rooms'] as int? ?? 0,
          lastSeen: DateTime.now(),
        );
        _servers[server.key] = server;
        _serversController.add(_servers.values.toList());
      } catch (_) {}
    });

    _pruneTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final cutoff = DateTime.now().subtract(const Duration(seconds: 3));
      final before = _servers.length;
      _servers.removeWhere((_, r) => r.lastSeen.isBefore(cutoff));
      if (_servers.length != before) {
        _serversController.add(_servers.values.toList());
      }
    });
  }

  void stop() {
    _socket?.close();
    _socket = null;
    _pruneTimer?.cancel();
    _servers.clear();
  }
}
