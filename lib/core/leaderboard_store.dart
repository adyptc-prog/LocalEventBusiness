import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'match_record.dart';
import 'player_profile.dart';

const int _maxHistory = 300;
const String _prefsKey = 'leaderboard_history_v1';

/// Clasamentul agregat al unui jucător — fie pe un singur joc, fie general
/// (peste toate jocurile, dacă [gameId] filtrat e `null`).
class PlayerRanking {
  final String playerId;
  final String playerName;
  final int totalScore;
  final int matchesPlayed;
  final int wins;
  final int stakeBalance;

  const PlayerRanking({
    required this.playerId,
    required this.playerName,
    required this.totalScore,
    required this.matchesPlayed,
    required this.wins,
    required this.stakeBalance,
  });
}

/// Istoricul local de partide terminate — salvat cu `shared_preferences` pe
/// acest telefon. Nu există un clasament central: fiecare telefon ține doar
/// rezultatele partidelor la care a participat el însuși (ca gazdă sau ca
/// client). Trebuie inițializat (`await init()`) înainte de `runApp`.
class LeaderboardStore extends ChangeNotifier {
  LeaderboardStore._();
  static final LeaderboardStore instance = LeaderboardStore._();

  final List<MatchRecord> _history = [];
  List<MatchRecord> get history => List.unmodifiable(_history);

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getStringList(_prefsKey);
    if (raw == null) return;
    _history.clear();
    for (final entry in raw) {
      try {
        _history.add(MatchRecord.fromJson(jsonDecode(entry) as Map<String, dynamic>));
      } catch (_) {
        // rezultat corupt — îl ignorăm, restul istoricului rămâne valid
      }
    }
  }

  Future<void> addRecord(MatchRecord record) async {
    _history.insert(0, record);
    if (_history.length > _maxHistory) {
      _history.removeRange(_maxHistory, _history.length);
    }
    notifyListeners();
    await _prefs?.setStringList(_prefsKey, _history.map((r) => jsonEncode(r.toJson())).toList());
  }

  /// Clasament agregat: dacă [gameId] e `null`, sumează peste toate
  /// jocurile (vedere „generală”); altfel doar peste partidele acelui joc.
  List<PlayerRanking> rankingsFor({String? gameId}) {
    final byPlayer = <String, _Accumulator>{};
    for (final match in _history) {
      if (gameId != null && match.gameId != gameId) continue;
      for (final result in match.players) {
        final acc = byPlayer.putIfAbsent(result.playerId, () => _Accumulator());
        acc.name = result.playerName;
        acc.totalScore += result.scoreDelta;
        acc.matchesPlayed += 1;
        acc.stakeBalance += result.stakeDelta;
        if (result.isWinner) acc.wins += 1;
      }
    }
    final rankings = byPlayer.entries
        .map((e) => PlayerRanking(
              playerId: e.key,
              playerName: e.value.name,
              totalScore: e.value.totalScore,
              matchesPlayed: e.value.matchesPlayed,
              wins: e.value.wins,
              stakeBalance: e.value.stakeBalance,
            ))
        .toList();
    rankings.sort((a, b) => b.totalScore.compareTo(a.totalScore));
    return rankings;
  }
}

class _Accumulator {
  String name = '';
  int totalScore = 0;
  int matchesPlayed = 0;
  int wins = 0;
  int stakeBalance = 0;
}

/// Aplică rezultatul unei partide terminate atât în istoricul de clasament,
/// cât și în soldul local (dacă profilul acestui telefon a participat) —
/// folosit identic de gazdă (când detectează finalul jocului) și de client
/// (când primește `match_result` prin rețea).
Future<void> recordMatchLocally(MatchRecord record) async {
  await LeaderboardStore.instance.addRecord(record);
  await PlayerProfileStore.instance.applyMatchRecord(record);
}
