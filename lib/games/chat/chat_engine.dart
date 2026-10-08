import '../../core/game_engine.dart';

class _ChatPlayerInfo {
  final String id;
  final String name;
  final bool isHost;
  bool connected = true;

  _ChatPlayerInfo({required this.id, required this.name, required this.isHost});
}

/// Nu e un joc — e camera de chat generală, deschisă tuturor de pe rețea
/// (nu doar celor de la o masă de joc). Nu are reguli, scor sau finalul unei
/// partide: se „pornește” singură de îndată ce gazda o creează, ca oricine
/// se alătură să poată scrie direct, fără nicio așteptare.
class ChatEngine extends GameEngine {
  static const int minPlayersStatic = 1;
  static const int maxPlayersStatic = 24;

  @override
  int get minPlayers => minPlayersStatic;
  @override
  int get maxPlayers => maxPlayersStatic;

  @override
  bool started = false;

  @override
  Map<String, int>? lastMatchScores;

  final List<_ChatPlayerInfo> _players = [];

  @override
  void addPlayer({required String id, required String name, required bool isHost}) {
    if (_players.length >= maxPlayers) {
      throw StateError('Camera de chat e plină (maxim $maxPlayers persoane).');
    }
    _players.add(_ChatPlayerInfo(id: id, name: name, isHost: isHost));
    started = true; // camera de chat e mereu deschisă, nu există un "start" separat
    notifyListeners();
  }

  @override
  void markDisconnected(String id) {
    final matches = _players.where((p) => p.id == id);
    if (matches.isEmpty) return;
    matches.first.connected = false;
    notifyListeners();
  }

  @override
  void markConnected(String id) {
    final matches = _players.where((p) => p.id == id);
    if (matches.isEmpty) return;
    matches.first.connected = true;
    notifyListeners();
  }

  @override
  bool get acceptsPlayersWhileStarted => true;

  @override
  void startGame() {}

  @override
  void applyAction(String playerId, Map<String, dynamic> action) {
    throw StateError('Camera de chat nu are acțiuni de joc.');
  }

  @override
  Map<String, dynamic> snapshotFor(String viewerId) => {
        'players': _players
            .map((p) => {'id': p.id, 'name': p.name, 'isHost': p.isHost, 'connected': p.connected})
            .toList(),
        'started': started,
      };
}
