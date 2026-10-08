// Foreground service-ul (`flutter_foreground_task`) are nevoie de `dart:io`
// — disponibil doar pe Android/desktop, nu într-un browser. Pe web se
// folosește automat stub-ul din `event_server_runner_stub.dart`, ca întreaga
// aplicație să rămână compilabilă pentru `flutter build web`. UI-ul oricum
// ascunde ecranul de server pe orice platformă în afară de Android (vezi
// `core/platform_support.dart`), deci runner-ul nu ar trebui invocat
// vreodată dintr-un build web sau desktop.
export 'event_server_runner_stub.dart' if (dart.library.io) 'event_server_runner_io.dart';
