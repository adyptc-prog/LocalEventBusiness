import 'package:shared_preferences/shared_preferences.dart';

import 'player_identity.dart';

const String _prefsKey = 'organizer_key_v1';

/// Cheia secretă a organizatorului, generată o singură dată pe telefonul-
/// server și păstrată în `shared_preferences`. Isolate-ul UI (ecranul de
/// monitorizare, `RoomMonitorScreen`) o trimite la `spectate`; isolate-ul
/// serverului o citește din aceeași memorie persistentă și acceptă un
/// spectator — care scrie în chat ca „Organizator" — doar cu cheia corectă.
/// Un client obișnuit nu o are, deci nu se poate da drept organizator.
///
/// Trebuie inițializat în isolate-ul UI (`main.dart`) *înainte* de pornirea
/// serverului, ca isolate-ul serverului să găsească cheia deja scrisă.
class OrganizerKeyStore {
  OrganizerKeyStore._();
  static final OrganizerKeyStore instance = OrganizerKeyStore._();

  String? _key;

  String get key {
    final k = _key;
    if (k == null) throw StateError('OrganizerKeyStore nu a fost inițializat.');
    return k;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    var stored = prefs.getString(_prefsKey);
    if (stored == null || stored.length < 16) {
      stored = generateSecretId();
      await prefs.setString(_prefsKey, stored);
    }
    _key = stored;
  }

  bool matches(Object? candidate) => _key != null && candidate is String && candidate == _key;
}
