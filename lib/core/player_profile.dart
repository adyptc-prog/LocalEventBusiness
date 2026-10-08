import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'match_record.dart';
import 'player_identity.dart';

const int _startingBalance = 500;
const String _prefsKey = 'player_profile_v1';

/// Identitatea locală a acestui telefon: un id stabil (păstrat între
/// sesiuni, spre deosebire de id-urile efemere generate per-cameră înainte),
/// un nume afișat și un sold de puncte virtuale (miza e monedă internă,
/// fără nicio legătură cu bani reali).
class PlayerProfile {
  final String id;
  final String name;
  final int balance;

  const PlayerProfile({required this.id, required this.name, required this.balance});

  PlayerProfile copyWith({String? name, int? balance}) => PlayerProfile(
        id: id,
        name: name ?? this.name,
        balance: balance ?? this.balance,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'balance': balance};

  factory PlayerProfile.fromJson(Map<String, dynamic> json) => PlayerProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        balance: json['balance'] as int,
      );
}

/// Singleton care încarcă/salvează profilul local cu `shared_preferences`.
/// Trebuie inițializat (`await init()`) înainte de `runApp`.
class PlayerProfileStore {
  PlayerProfileStore._();
  static final PlayerProfileStore instance = PlayerProfileStore._();

  late PlayerProfile profile;
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_prefsKey);
    if (raw != null) {
      try {
        profile = PlayerProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        return;
      } catch (_) {
        // profil corupt/format vechi — se recreează unul nou mai jos
      }
    }
    final id = generateSecretId();
    final name = 'Jucător ${1000 + Random().nextInt(9000)}';
    profile = PlayerProfile(id: id, name: name, balance: _startingBalance);
    await _save();
  }

  Future<void> updateName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == profile.name) return;
    profile = profile.copyWith(name: trimmed);
    await _save();
  }

  /// Actualizează soldul local dacă profilul propriu apare printre
  /// rezultatele acestei partide (aplicat de gazdă și de fiecare client, la
  /// primirea/generarea unui [MatchRecord]).
  Future<void> applyMatchRecord(MatchRecord record) async {
    final mine = record.players.where((p) => isMine(p.playerId));
    if (mine.isEmpty || mine.first.stakeDelta == 0) return;
    profile = profile.copyWith(balance: profile.balance + mine.first.stakeDelta);
    await _save();
  }

  /// Id-ul public al acestui profil — cel pe care îl văd ceilalți și care
  /// apare în rezultatele partidelor (vezi `player_identity.dart`).
  String get publicId => publicPlayerId(profile.id);

  /// `true` dacă [playerId] e acest profil — fie id-ul public actual, fie
  /// id-ul brut folosit în rezultatele înregistrate înainte de introducerea
  /// id-urilor publice.
  bool isMine(String playerId) => playerId == publicId || playerId == profile.id;

  Future<void> _save() async {
    await _prefs?.setString(_prefsKey, jsonEncode(profile.toJson()));
  }
}
