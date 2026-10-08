/// Un server de eveniment găsit pe rețea prin beacon-ul lui UDP (doar
/// clienți nativi — un browser nu poate asculta UDP, vezi
/// `room_discovery.dart`). Numele e păstrat din compatibilitate cu ecranele
/// existente, dar descrie *serverul*, nu o cameră individuală — camerele lui
/// se cer separat, prin WebSocket, după conectare (vezi `LobbyRoom`).
class DiscoveredRoom {
  final String name;
  final String address;
  final int port;
  final int rooms;
  final DateTime lastSeen;

  DiscoveredRoom({
    required this.name,
    required this.address,
    required this.port,
    required this.rooms,
    required this.lastSeen,
  });

  String get key => '$address:$port';
}
