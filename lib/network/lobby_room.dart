/// O cameră activă pe serverul central, așa cum apare în lista live
/// trimisă tuturor conexiunilor aflate încă în faza de lobby (înainte să se
/// alăture uneia). Diferă de `DiscoveredRoom`, care descrie doar *serverul*
/// găsit prin beacon UDP, nu camerele lui.
class LobbyRoom {
  final String code;
  final String gameId;
  final String gameTitle;
  final String roomName;
  final int players;
  final int maxPlayers;
  final bool started;

  const LobbyRoom({
    required this.code,
    required this.gameId,
    required this.gameTitle,
    required this.roomName,
    required this.players,
    required this.maxPlayers,
    required this.started,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'gameId': gameId,
        'gameTitle': gameTitle,
        'roomName': roomName,
        'players': players,
        'maxPlayers': maxPlayers,
        'started': started,
      };

  factory LobbyRoom.fromJson(Map<String, dynamic> json) => LobbyRoom(
        code: json['code'] as String,
        gameId: json['gameId'] as String,
        gameTitle: json['gameTitle'] as String,
        roomName: json['roomName'] as String,
        players: json['players'] as int,
        maxPlayers: json['maxPlayers'] as int,
        started: json['started'] as bool,
      );
}
