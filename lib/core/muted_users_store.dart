import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String _prefsKey = 'muted_users_v1';

/// Profilurile cu chat-ul oprit de organizator — mai blând decât blocarea
/// completă: jocul/pozele lor merg mai departe normal, doar mesajele nu se
/// mai livrează. Șablon identic `BlockedUsersStore`. Folosit doar din
/// isolate-ul serverului.
class MutedUsersStore {
  MutedUsersStore._();
  static final MutedUsersStore instance = MutedUsersStore._();

  Map<String, String> _muted = {}; // profileId -> nume
  SharedPreferences? _prefs;

  Map<String, String> get muted => Map.unmodifiable(_muted);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_prefsKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _muted = decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      _muted = {};
    }
  }

  bool isMuted(String profileId) => _muted.containsKey(profileId);

  Future<void> mute(String profileId, String name) async {
    _muted[profileId] = name;
    await _save();
  }

  Future<void> unmute(String profileId) async {
    _muted.remove(profileId);
    await _save();
  }

  Future<void> _save() async {
    await _prefs?.setString(_prefsKey, jsonEncode(_muted));
  }
}
