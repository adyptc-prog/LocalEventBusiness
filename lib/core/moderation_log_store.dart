import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String _prefsKey = 'moderation_log_v1';
const int _maxHistory = 200;

/// O acțiune de moderare — pentru istoricul organizatorului, ca să poată
/// verifica ulterior ce a eliminat/blocat/silențiat și când.
class ModerationLogEntry {
  final String action; // 'kick' | 'block' | 'unblock' | 'mute' | 'unmute' | 'delete_photo' | 'announcement'
  final String? targetName;
  final String? detail;
  final DateTime timestamp;

  const ModerationLogEntry({
    required this.action,
    this.targetName,
    this.detail,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'action': action,
        'targetName': targetName,
        'detail': detail,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  factory ModerationLogEntry.fromJson(Map<String, dynamic> json) => ModerationLogEntry(
        action: json['action'] as String,
        targetName: json['targetName'] as String?,
        detail: json['detail'] as String?,
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      );
}

/// Istoricul acțiunilor de moderare ale evenimentului curent — persistat cu
/// `shared_preferences` pe telefonul-server, șablon identic
/// `LeaderboardStore`. Folosit doar din isolate-ul serverului.
class ModerationLogStore {
  ModerationLogStore._();
  static final ModerationLogStore instance = ModerationLogStore._();

  final List<ModerationLogEntry> _entries = [];
  SharedPreferences? _prefs;

  List<ModerationLogEntry> get entries => List.unmodifiable(_entries);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getStringList(_prefsKey);
    if (raw == null) return;
    _entries.clear();
    for (final entry in raw) {
      try {
        _entries.add(ModerationLogEntry.fromJson(jsonDecode(entry) as Map<String, dynamic>));
      } catch (_) {
        // intrare coruptă — o ignorăm, restul istoricului rămâne valid
      }
    }
  }

  Future<void> add(String action, {String? targetName, String? detail}) async {
    _entries.insert(0, ModerationLogEntry(action: action, targetName: targetName, detail: detail, timestamp: DateTime.now()));
    if (_entries.length > _maxHistory) {
      _entries.removeRange(_maxHistory, _entries.length);
    }
    await _prefs?.setStringList(_prefsKey, _entries.map((e) => jsonEncode(e.toJson())).toList());
  }
}
