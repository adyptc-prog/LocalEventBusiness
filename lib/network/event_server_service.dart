// Serverul evenimentului are nevoie de `dart:io` (server HTTP + WebSocket +
// beacon UDP) — disponibil doar pe Android/desktop, nu într-un browser.
// Pe web se folosește automat stub-ul din `event_server_service_stub.dart`,
// ca întreaga aplicație să rămână compilabilă pentru `flutter build web`.
export 'event_server_service_stub.dart' if (dart.library.io) 'event_server_service_io.dart';
