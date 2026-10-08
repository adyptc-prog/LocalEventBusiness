/// Rezultatul unui singur jucător la finalul unei partide: câte puncte a
/// câștigat/pierdut după regulile specifice jocului ([scoreDelta]) și câte
/// puncte de miză a câștigat/pierdut din pot ([stakeDelta]).
class MatchPlayerResult {
  final String playerId;
  final String playerName;
  final int scoreDelta;
  final int stake;
  final int stakeDelta;
  final bool isWinner;

  const MatchPlayerResult({
    required this.playerId,
    required this.playerName,
    required this.scoreDelta,
    required this.stake,
    required this.stakeDelta,
    required this.isWinner,
  });

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'playerName': playerName,
        'scoreDelta': scoreDelta,
        'stake': stake,
        'stakeDelta': stakeDelta,
        'isWinner': isWinner,
      };

  factory MatchPlayerResult.fromJson(Map<String, dynamic> json) => MatchPlayerResult(
        playerId: json['playerId'] as String,
        playerName: json['playerName'] as String,
        scoreDelta: json['scoreDelta'] as int,
        stake: json['stake'] as int,
        stakeDelta: json['stakeDelta'] as int,
        isWinner: json['isWinner'] as bool,
      );
}

/// O partidă încheiată, cu rezultatul fiecărui jucător care a participat.
/// Fiecare telefon salvează local rezultatele partidelor la care a luat
/// parte (ca gazdă sau ca client) — nu există un clasament central.
class MatchRecord {
  final String id;
  final String gameId;
  final String gameTitle;
  final String roomName;
  final DateTime playedAt;
  final List<MatchPlayerResult> players;

  const MatchRecord({
    required this.id,
    required this.gameId,
    required this.gameTitle,
    required this.roomName,
    required this.playedAt,
    required this.players,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'gameId': gameId,
        'gameTitle': gameTitle,
        'roomName': roomName,
        'playedAt': playedAt.millisecondsSinceEpoch,
        'players': players.map((p) => p.toJson()).toList(),
      };

  factory MatchRecord.fromJson(Map<String, dynamic> json) => MatchRecord(
        id: json['id'] as String,
        gameId: json['gameId'] as String,
        gameTitle: json['gameTitle'] as String,
        roomName: json['roomName'] as String,
        playedAt: DateTime.fromMillisecondsSinceEpoch(json['playedAt'] as int),
        players: (json['players'] as List<dynamic>)
            .map((p) => MatchPlayerResult.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}
