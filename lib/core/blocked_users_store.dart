import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String _prefsKey = 'blocked_users_v1';

/// Profilurile blocate de organizator pentru evenimentul curent — persistat
/// cu `shared_preferences` pe telefonul-server, ca o blocare să nu se piardă
/// dacă serverul repornește accidental în timpul evenimentului. Ține și
/// ultimul nume cunoscut al fiecărui profil blocat, ca lista să rămână
/// lizibilă chiar și după ce camera din care a fost dat afară s-a închis.
///
/// Folosit doar din isolate-ul serverului (`EventServerService`) — ecranul
/// de organizator nu-l citește direct, primește starea prin push (vezi
/// `EventServerRunner`), ca să existe o singură sursă de adevăr live.
class BlockedUsersStore {
  BlockedUsersStore._();
  static final BlockedUsersStore instance = BlockedUsersStore._();

  Map<String, String> _blocked = {}; // profileId -> nume
  SharedPreferences? _prefs;

  Map<String, String> get blocked => Map.unmodifiable(_blocked);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_prefsKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _blocked = decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      _blocked = {};
    }
  }

  bool isBlocked(String profileId) => _blocked.containsKey(profileId);

  Future<void> block(String profileId, String name) async {
    _blocked[profileId] = name;
    await _save();
  }

  Future<void> unblock(String profileId) async {
    _blocked.remove(profileId);
    await _save();
  }

  Future<void> _save() async {
    await _prefs?.setString(_prefsKey, jsonEncode(_blocked));
  }
}
