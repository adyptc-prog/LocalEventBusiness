import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/chat_message.dart';
import '../core/game_definition.dart';
import '../core/game_engine.dart';
import '../core/match_record.dart';
import 'game_message.dart';
import 'lobby_room.dart';
import '../l10n/tr.dart';

/// Un jucător cunoscut de o cameră — pentru ecranul de moderare al
/// organizatorului (`ParticipantsScreen`), nu pentru protocolul de joc.
class RoomParticipant {
  final String profileId;
  final String name;
  final bool connected;

  const RoomParticipant({required this.profileId, required this.name, required this.connected});
}

/// O singură cameră de joc, așa cum trăiește pe serverul central: motorul
/// de reguli al jocului ei + jucătorii conectați prin WebSocket + chat-ul și
/// scorul ei. [EventServerService] ține câte o instanță din asta per cod de
/// cameră, complet izolate una de alta.
///
/// Spre deosebire de fostul `HostService` (un telefon = o cameră), aici NU
/// mai există un „jucător local" privilegiat — chiar și cel care creează
/// camera e doar un client WebSocket ca oricare altul, conectat la propriul
/// server. Asta simplifică livrarea chat-ului (nu mai există un caz special
/// pentru gazdă) și înseamnă că o cameră nu se închide dacă cel care a
/// creat-o pleacă — rămâne deschisă cât timp mai are un jucător conectat.
class RoomSession {
  final String code;
  final GameDefinition definition;
  final String roomName;
  final int tableStake;
  final GameEngine engine;

  /// Apelat de fiecare dată când numărul de jucători conectați sau starea
  /// `started` se schimbă — serverul îl folosește ca să retrimită lista de
  /// camere tuturor conexiunilor aflate încă în faza de lobby.
  final void Function() onRoomChanged;

  /// Apelat când camera rămâne fără niciun client conectat, ca serverul s-o
  /// poată elimina din listă.
  final void Function() onEmpty;

  static const String organizerChatId = ChatMessage.organizerId;

  final Map<String, WebSocketChannel> _clientChannels = {};
  final Map<String, String> _playerNames = {};
  final Set<String> _knownPlayerIds = {};
  final Set<String> _kickedPlayerIds = {};
  final Set<WebSocketChannel> _spectatorChannels = {};
  bool _matchRecorded = false;
  String? _hostId;

  /// De când e deconectat fiecare jucător (doar cei deconectați acum).
  final Map<String, DateTime> _disconnectedSince = {};

  /// După cât timp de absență serverul începe să joace în locul unui
  /// jucător deconectat ([GameEngine.autoActionCandidates]) — destul cât să
  /// prindă o reconectare normală, prea puțin cât să blocheze masa.
  final Duration autoActAfter;

  /// Cât de des se verifică — și deci cel mult o acțiune automată per
  /// jucător absent la fiecare interval, ca ceilalți să vadă ce se întâmplă.
  final Duration autoActTick;
  Timer? _autoActTimer;

  RoomSession({
    required this.code,
    required this.definition,
    required this.roomName,
    required this.tableStake,
    required this.onRoomChanged,
    required this.onEmpty,
    this.autoActAfter = const Duration(seconds: 45),
    this.autoActTick = const Duration(seconds: 5),
  }) : engine = definition.createEngine() {
    engine.addListener(_onGameChanged);
    if (!engine.acceptsPlayersWhileStarted) {
      _autoActTimer = Timer.periodic(autoActTick, (_) => _autoActForAbsentPlayers());
    }
  }

  /// Oprește timerele camerei — apelat de server când camera e eliminată.
  void dispose() {
    _autoActTimer?.cancel();
    _autoActTimer = null;
  }

  void _autoActForAbsentPlayers() {
    if (!engine.started || _disconnectedSince.isEmpty) return;
    final now = DateTime.now();
    for (final entry in _disconnectedSince.entries.toList()) {
      if (now.difference(entry.value) < autoActAfter) continue;
      for (final action in engine.autoActionCandidates(entry.key)) {
        try {
          engine.applyAction(entry.key, action);
          break;
        } catch (_) {
          // candidată ilegală acum (nu e rândul lui etc.) — următoarea
        }
      }
    }
  }

  int get playerCount => _clientChannels.length;
  bool get started => engine.started;

  /// Pentru ecranul de moderare al organizatorului — toți jucătorii
  /// cunoscuți acestei camere (inclusiv cei momentan deconectați).
  List<RoomParticipant> get participants => _knownPlayerIds
      .map((id) => RoomParticipant(
            profileId: id,
            name: _playerNames[id] ?? '?',
            connected: _clientChannels.containsKey(id),
          ))
      .toList();

  /// Canalul unui jucător cunoscut, dacă e conectat acum — folosit ca să-l
  /// poți elimina forțat (organizatorul închide canalul, restul curge prin
  /// fluxul normal de deconectare).
  WebSocketChannel? channelFor(String profileId) => _clientChannels[profileId];

  /// Atașează un spectator (organizatorul, monitorizând fără să joace) —
  /// nu consumă loc de jucător, nu apare în `players`, nu afectează un
  /// cartonaș. Primește imediat starea curentă (galeria de poze etc., dacă
  /// activitatea are una) și, de-acum, fiecare actualizare live.
  void attachSpectator(WebSocketChannel channel) {
    _spectatorChannels.add(channel);
    channel.sink.add(GameMessage.encode({'type': 'state', 'state': buildSnapshot(spectatorViewerId)}));
  }

  void detachSpectator(WebSocketChannel channel) => _spectatorChannels.remove(channel);

  LobbyRoom toLobbyRoom() => LobbyRoom(
        code: code,
        gameId: definition.id,
        gameTitle: definition.title,
        roomName: roomName,
        players: playerCount,
        maxPlayers: definition.maxPlayers,
        started: started,
      );

  /// Atașează o conexiune nouă ca jucător [playerId]/[name]. Aruncă
  /// [StateError] dacă regulile jocului nu permit (cameră plină, joc deja
  /// pornit etc.) sau dacă profilul a fost dat afară de organizator din
  /// această cameră — apelantul (serverul) trebuie să trimită eroarea către
  /// client și să nu înregistreze conexiunea.
  ///
  /// [playerId] e id-ul public, derivat de server din id-ul secret al
  /// profilului (vezi `player_identity.dart`) — deci cine ajunge aici cu un
  /// id deja cunoscut camerei chiar deține acel profil. Asta e o
  /// **reconectare**: se reia locul existent (mână, scor, tură) cu noul
  /// canal, fără să se mai treacă prin `engine.addPlayer`. Dacă serverul
  /// crede încă că vechiul canal e viu (o conexiune moartă în tăcere,
  /// nedetectată încă), noul canal îl înlocuiește — vechiul primește
  /// `replaced` și e închis, ca să nu reîncerce singur să reintre.
  void attach({
    required String playerId,
    required String name,
    required bool isHost,
    required WebSocketChannel channel,
  }) {
    if (_kickedPlayerIds.contains(playerId)) {
      throw GameError('err.kicked');
    }
    if (_knownPlayerIds.contains(playerId)) {
      final previous = _clientChannels[playerId];
      if (previous != null && previous != channel) {
        try {
          previous.sink.add(GameMessage.encode({'type': 'replaced'}));
          previous.sink.close();
        } catch (_) {
          // canalul vechi e oricum mort — exact cazul pe care îl tratăm aici
        }
      }
      _playerNames[playerId] = name;
      _clientChannels[playerId] = channel;
      _disconnectedSince.remove(playerId);
      engine.markConnected(playerId);
      return;
    }
    if (engine.started && !engine.acceptsPlayersWhileStarted) {
      throw GameError('err.gameInProgressJoin');
    }
    engine.addPlayer(id: playerId, name: name, isHost: isHost);
    _playerNames[playerId] = name;
    _knownPlayerIds.add(playerId);
    _clientChannels[playerId] = channel;
    if (isHost) _hostId = playerId;
  }

  /// Marchează profilul ca dat afară de organizator — o reîncercare
  /// ulterioară de `attach()` cu același `playerId` va fi respinsă, spre
  /// deosebire de o reconectare normală după o pierdere de rețea.
  void markKicked(String playerId) => _kickedPlayerIds.add(playerId);

  Map<String, dynamic> buildSnapshot(String viewerId) =>
      {...engine.snapshotFor(viewerId), 'tableStake': tableStake};

  /// Doar cel care a creat camera (afișat cu steluță în lobby) poate porni
  /// jocul — verificat aici, nu doar ascuns în UI, ca un client greșit
  /// configurat să nu poată porni jocul altcuiva.
  void startGame(String requesterId) {
    if (requesterId != _hostId) {
      throw GameError('err.onlyHostStarts');
    }
    if (engine.started) {
      throw GameError('err.alreadyStarted');
    }
    _matchRecorded = false;
    engine.startGame();
  }

  void applyAction(String playerId, Map<String, dynamic> action) =>
      engine.applyAction(playerId, action);

  String? nameOf(String playerId) => _playerNames[playerId];

  /// Livrează un mesaj de chat: public (fără destinatar) → tuturor
  /// celorlalți din cameră, plus spectatorilor (organizatorul monitorizează
  /// ce vede toată lumea, niciodată mesajele private); privat → doar
  /// destinatarului. Expeditorul își afișează mesajul local, optimist, la
  /// trimitere — nu i se retrimite.
  void deliverChat(ChatMessage msg) {
    if (msg.toId == null) {
      for (final entry in _clientChannels.entries) {
        if (entry.key == msg.fromId) continue;
        entry.value.sink.add(GameMessage.encode({'type': 'chat', 'message': msg.toJson()}));
      }
      if (_spectatorChannels.isNotEmpty) {
        final payload = GameMessage.encode({'type': 'chat', 'message': msg.toJson()});
        for (final channel in _spectatorChannels) {
          channel.sink.add(payload);
        }
      }
    } else {
      _clientChannels[msg.toId]?.sink.add(GameMessage.encode({'type': 'chat', 'message': msg.toJson()}));
    }
  }

  void handleDisconnect(String playerId, WebSocketChannel channel) {
    if (_clientChannels[playerId] != channel) return;
    _clientChannels.remove(playerId);
    _disconnectedSince[playerId] = DateTime.now();
    engine.markDisconnected(playerId);
    onRoomChanged();
    if (_clientChannels.isEmpty) onEmpty();
  }

  void _onGameChanged() {
    _broadcastState();
    _maybeRecordMatchResult();
    onRoomChanged();
  }

  void _broadcastState() {
    final affected = engine.takeAffectedViewers();
    for (final entry in _clientChannels.entries) {
      if (affected != null && !affected.contains(entry.key)) continue;
      entry.value.sink.add(GameMessage.encode({'type': 'state', 'state': buildSnapshot(entry.key)}));
    }
    if (_spectatorChannels.isNotEmpty) {
      final payload = GameMessage.encode({'type': 'state', 'state': buildSnapshot(spectatorViewerId)});
      for (final channel in _spectatorChannels) {
        channel.sink.add(payload);
      }
    }
  }

  /// Notează rezultatul partidei o singură dată, exact când motorul
  /// stabilește un scor final, și îl trimite tuturor clienților conectați —
  /// fiecare telefon își înregistrează local rezultatul (vezi
  /// `leaderboard_store.dart`); serverul central nu ține el însuși scoruri.
  void _maybeRecordMatchResult() {
    if (_matchRecorded || _clientChannels.isEmpty) return;
    final scores = engine.lastMatchScores;
    if (scores == null) return;
    _matchRecorded = true;

    final snap = buildSnapshot(_clientChannels.keys.first);
    final record = _buildMatchRecord(snap, scores);
    final payload = GameMessage.encode({'type': 'match_result', 'record': record.toJson()});
    for (final channel in _clientChannels.values) {
      channel.sink.add(payload);
    }
  }

  MatchRecord _buildMatchRecord(Map<String, dynamic> snap, Map<String, int> scores) {
    final playersJson = (snap['players'] as List).cast<Map<String, dynamic>>();
    final winnerId = snap['winnerId'] as String?;

    final results = <MatchPlayerResult>[];
    for (final pj in playersJson) {
      final id = pj['id'] as String;
      // Câștigătorul primește miza mesei; ceilalți nu pierd nimic. La
      // egalitate (winnerId null) nimeni nu o primește.
      final stakeDelta = (id == winnerId) ? tableStake : 0;
      results.add(MatchPlayerResult(
        playerId: id,
        playerName: pj['name'] as String,
        scoreDelta: scores[id] ?? 0,
        stake: tableStake,
        stakeDelta: stakeDelta,
        isWinner: id == winnerId,
      ));
    }

    return MatchRecord(
      id: '$code-${DateTime.now().microsecondsSinceEpoch}',
      gameId: definition.id,
      gameTitle: definition.title,
      roomName: roomName,
      playedAt: DateTime.now(),
      players: results,
    );
  }
}
