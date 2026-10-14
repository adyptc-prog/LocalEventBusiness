/// Versiunea aplicației, afișată în bara de sus (`VersionBadge`) ca
/// utilizatorul să poată compara cu ultima versiune publicată.
///
/// Trebuie să fie identică cu `version:` din `pubspec.yaml` (partea de
/// dinainte de `+`) — `test/app_version_test.dart` verifică asta. E o
/// constantă în cod, nu citită la rulare, ca să apară la fel și în clientul
/// web servit de telefonul-server, fără nicio cerere în plus.
const String appVersion = '1.1.0';
