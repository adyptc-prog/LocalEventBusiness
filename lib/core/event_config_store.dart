import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'activity_catalog.dart';

const String _prefsKey = 'event_config_v1';

/// Ce activități din [activityCatalog] a activat organizatorul pentru
/// evenimentul curent — controlează ce vede un invitat în meniul lui
/// (`EventMenuScreen`). Persistat cu `shared_preferences` pe telefonul-
/// server; implicit toate activitățile sunt activate, ca organizatorul doar
/// să dezactiveze ce nu vrea, nu să configureze de la zero de fiecare dată.
///
/// Trebuie inițializat (`await init()`) atât în isolate-ul UI (pentru
/// ecranul de configurare, `ActivityConfigScreen`), cât și în isolate-ul
/// serverului (`_EventServerTaskHandler.onStart()`) — dar cele două rulează
/// separat, fiecare cu propria copie în memorie: o schimbare din
/// `ActivityConfigScreen` **nu** ajunge singură la serverul deja pornit,
/// oricât ar citi amândouă același fișier de pe disc. De-aia orice
/// schimbare trebuie trimisă explicit serverului prin canalul de comenzi
/// (`EventServerRunner.syncActivities`, la fel ca elimină/blochează), care
/// apelează [applyRemote] pe copia din isolate-ul serverului.
class EventConfigStore {
  EventConfigStore._();
  static final EventConfigStore instance = EventConfigStore._();

  Set<String> _enabledActivityIds = {};
  SharedPreferences? _prefs;

  Set<String> get enabledActivityIds => Set.unmodifiable(_enabledActivityIds);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_prefsKey);
    if (raw == null) {
      _enabledActivityIds = activityCatalog.map((a) => a.id).toSet();
      return;
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      _enabledActivityIds = decoded.cast<String>().toSet();
    } catch (_) {
      _enabledActivityIds = activityCatalog.map((a) => a.id).toSet();
    }
  }

  bool isEnabled(String activityId) => _enabledActivityIds.contains(activityId);

  Future<void> setEnabled(String activityId, bool enabled) async {
    if (enabled) {
      _enabledActivityIds.add(activityId);
    } else {
      _enabledActivityIds.remove(activityId);
    }
    await _save();
  }

  Future<void> _save() async {
    await _prefs?.setString(_prefsKey, jsonEncode(_enabledActivityIds.toList()));
  }

  /// Aplică o listă primită de la isolate-ul UI, prin canalul de comenzi —
  /// nu mai scrie pe disc (UI-ul deja a persistat-o), doar reflectă starea
  /// în copia din acest isolate, ca invitații care se conectează de acum
  /// înainte să vadă selecția actuală.
  void applyRemote(List<String> enabledIds) {
    _enabledActivityIds = enabledIds.toSet();
  }
}
