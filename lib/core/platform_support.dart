// `Platform.isAndroid` are nevoie de `dart:io`, indisponibil pe web. Pe web
// se folosește automat stub-ul din `platform_support_stub.dart`, ca
// întreaga aplicație să rămână compilabilă pentru `flutter build web`.
export 'platform_support_stub.dart' if (dart.library.io) 'platform_support_io.dart';
