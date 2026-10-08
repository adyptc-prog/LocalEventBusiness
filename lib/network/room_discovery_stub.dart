import 'discovered_room.dart';

/// Un browser nu poate asculta UDP broadcast — descoperirea automată a
/// serverului nu e posibilă pe web. Ecranele client ascund deja lista de
/// servere găsite pe web (`kIsWeb`), deci acest stub există doar ca targetul
/// web să compileze.
class RoomDiscovery {
  Stream<List<DiscoveredRoom>> get rooms => const Stream.empty();

  Future<void> start() async {}

  void stop() {}
}
