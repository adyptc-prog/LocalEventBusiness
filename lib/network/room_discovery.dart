// Descoperirea automată prin UDP broadcast are nevoie de `dart:io` —
// disponibilă doar pe Android/desktop. Pe web se folosește stub-ul din
// `room_discovery_stub.dart` (nu emite niciodată camere), ca aplicația să
// rămână compilabilă pentru `flutter build web`.
export 'room_discovery_stub.dart' if (dart.library.io) 'room_discovery_io.dart';
