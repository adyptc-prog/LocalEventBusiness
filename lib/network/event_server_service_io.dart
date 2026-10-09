import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/activity_catalog.dart';
import '../core/bill_request.dart';
import '../core/blocked_users_store.dart';
import '../core/chat_message.dart';
import '../core/event_config_store.dart';
import '../core/menu_store.dart';
import '../core/moderation_log_store.dart';
import '../core/muted_users_store.dart';
import '../core/order.dart';
import '../core/orders_store.dart';
import '../core/organizer_key_store.dart';
import '../core/player_identity.dart';
import '../games/menu/menu_definition.dart';
import '../games/menu/menu_engine.dart';
import 'game_message.dart';
import 'lobby_room.dart';
import 'participant_info.dart';
import 'room_session.dart';
import 'web_asset_bundle.dart';
import '../l10n/tr.dart';

/// Codul fix al camerei singleton de comenzi — creată automat la pornirea
/// serverului (nu la cererea unui client, ca la restul activităților), ca
/// niciun client obișnuit să nu poată deveni „gazda" ei. Vezi
/// `MenuConnectScreen`, care se alătură direct cu acest cod.
const String menuRoomCode = 'MENU';

/// Rulează pe telefonul-server dedicat al evenimentului: UN singur
/// `HttpServer` care găzduiește simultan ORICÂTE camere de joc, fiecare
/// izolată într-un [RoomSession] propriu. Orice alt telefon — Android cu
/// aplicația, sau un simplu browser (iPhone) — se conectează o singură dată
/// la acest server și de acolo poate crea sau se poate alătura oricărei
/// camere, fără să găzduiască el însuși nimic.
///
/// Beacon-ul UDP anunță doar prezența serverului (nu camerele individuale —
/// sunt prea multe și se schimbă prea des ca să încapă într-un pachet UDP);
/// lista de camere circulă live prin WebSocket, identic pentru Android și
/// web, imediat după conectare și la fiecare schimbare.
class EventServerService {
  static const int webPort = 45034;
  static const int discoveryPort = 45033;

  // Limite anti-abuz — generoase pentru o seară normală într-un local,
  // dar opresc un client scris de mână să epuizeze memoria serverului.
  static const int maxConnections = 600;
  static const int maxRooms = 100;
  static const int maxMessageLength = 16 * 1024;
  static const int maxMessagesPerSecond = 30;
  static const int maxNameLength = 30;
  static const int maxRoomNameLength = 40;
  static const int maxChatLength = 500;
  static const int maxTableStake = 1000;

  final String serverName;

  HttpServer? _server;
  RawDatagramSocket? _udp;
  Timer? _beaconTimer;
  Timer? _heartbeatTimer;
  Timer? _expiryTimer;

  final Map<String, RoomSession> _rooms = {};
  final Map<WebSocketChannel, _ConnectionState> _connections = {};

  final _roomsListController = StreamController<List<LobbyRoom>>.broadcast();
  final _participantsController = StreamController<List<ParticipantInfo>>.broadcast();
  final _moderationLogController = StreamController<List<ModerationLogEntry>>.broadcast();
  final _ordersController = StreamController<List<Order>>.broadcast();
  final _billsController = StreamController<List<BillRequest>>.broadcast();

  /// Vezi `RoomSession.autoActAfter`/`autoActTick` — configurabile doar ca
  /// testele să nu aștepte zeci de secunde.
  final Duration autoActAfter;
  final Duration autoActTick;

  EventServerService({
    required this.serverName,
    this.autoActAfter = const Duration(seconds: 45),
    this.autoActTick = const Duration(seconds: 5),
  }) {
    _createMenuRoom();
  }

  List<LobbyRoom> get rooms => _rooms.values.map((r) => r.toLobbyRoom()).toList();

  /// Pentru ecranul de monitorizare al organizatorului (`EventServerScreen`).
  Stream<List<LobbyRoom>> get roomsUpdates => _roomsListController.stream;

  /// Toți participanții cunoscuți evenimentului curent, agregați peste
  /// toate camerele — plus cei blocați, chiar dacă nu (mai) sunt în nicio
  /// cameră activă. Pentru ecranul de moderare (`ParticipantsScreen`).
  List<ParticipantInfo> get participants {
    final blocked = BlockedUsersStore.instance.blocked;
    final muted = MutedUsersStore.instance.muted;
    final list = <ParticipantInfo>[];
    for (final room in _rooms.values) {
      for (final p in room.participants) {
        list.add(ParticipantInfo(
          profileId: p.profileId,
          name: p.name,
          roomCode: room.code,
          activityTitle: room.definition.title,
          connected: p.connected,
          blocked: blocked.containsKey(p.profileId),
          muted: muted.containsKey(p.profileId),
        ));
      }
    }
    for (final entry in blocked.entries) {
      if (list.any((p) => p.profileId == entry.key)) continue;
      list.add(ParticipantInfo(
        profileId: entry.key,
        name: entry.value,
        roomCode: null,
        activityTitle: null,
        connected: false,
        blocked: true,
        muted: muted.containsKey(entry.key),
      ));
    }
    return list;
  }

  Stream<List<ParticipantInfo>> get participantsUpdates => _participantsController.stream;

  void _broadcastParticipants() => _participantsController.add(participants);

  Stream<List<ModerationLogEntry>> get moderationLogUpdates => _moderationLogController.stream;

  Future<void> _log(String action, {String? targetName, String? detail}) async {
    await ModerationLogStore.instance.add(action, targetName: targetName, detail: detail);
    _moderationLogController.add(ModerationLogStore.instance.entries);
  }

  String? _nameOf(String profileId) {
    final matches = participants.where((p) => p.profileId == profileId);
    return matches.isEmpty ? null : matches.first.name;
  }

  /// Închide conexiunea curentă a unui participant, dacă e conectat acum —
  /// fluxul normal de deconectare (`onDone` → `_handleDisconnect`) preia de
  /// aici, exact ca la o pierdere de rețea. Camera e marcată explicit
  /// (`markKicked`) ca profilul să nu se poată reconecta singur imediat după
  /// — spre deosebire de o pierdere de rețea reală, un kick trebuie să
  /// rămână efectiv.
  void kickParticipant(String profileId) {
    final name = _nameOf(profileId);
    for (final room in _rooms.values) {
      // Doar camerele unde chiar e cunoscut ca participant — altfel un kick
      // ar bloca profilul și din camere de care nu a ținut niciodată.
      if (room.participants.any((p) => p.profileId == profileId)) {
        room.markKicked(profileId);
      }
      room.channelFor(profileId)?.sink.close();
    }
    _log('kick', targetName: name ?? profileId);
  }

  Future<void> blockParticipant(String profileId, String name) async {
    await BlockedUsersStore.instance.block(profileId, name);
    kickParticipant(profileId);
    _broadcastParticipants();
    await _log('block', targetName: name);
  }

  Future<void> unblockParticipant(String profileId) async {
    final name = BlockedUsersStore.instance.blocked[profileId];
    await BlockedUsersStore.instance.unblock(profileId);
    _broadcastParticipants();
    await _log('unblock', targetName: name ?? profileId);
  }

  Future<void> muteParticipant(String profileId, String name) async {
    await MutedUsersStore.instance.mute(profileId, name);
    _broadcastParticipants();
    await _log('mute', targetName: name);
  }

  Future<void> unmuteParticipant(String profileId) async {
    final name = MutedUsersStore.instance.muted[profileId];
    await MutedUsersStore.instance.unmute(profileId);
    _broadcastParticipants();
    await _log('unmute', targetName: name ?? profileId);
  }

  MenuEngine get _menuEngine => _rooms[menuRoomCode]!.engine as MenuEngine;

  Stream<List<Order>> get ordersUpdates => _ordersController.stream;

  /// Cererile de notă — pentru ecranul barului (`OrdersDashboardScreen`).
  Stream<List<BillRequest>> get billsUpdates => _billsController.stream;
  List<BillRequest> get bills => _menuEngine.allBills;

  /// Barul a dus nota la masă.
  void handleBill(String billId) => _menuEngine.markBillHandled(billId);

  /// Barul închide masa: comenzile ei sunt achitate și trec în istoric.
  int closeTable(String tableLabel) => _menuEngine.closeTable(tableLabel);

  /// Barul închide toate mesele (sfârșitul serii).
  int closeAllTables() => _menuEngine.closeAllTables();

  /// Trece în istoric comenzile rămase deschise prea mult (vezi
  /// `MenuEngine.expireStale`) — rulat periodic cât timp serverul merge.
  int expireStaleOrders({DateTime? now}) => _menuEngine.expireStale(OrdersStore.maxAge, now: now);

  /// Avansează statusul unei comenzi (nouă → în pregătire → gata) — apelată
  /// direct de `OrdersDashboardScreen` prin canalul de comenzi, niciodată de
  /// un client obișnuit prin WebSocket (vezi `MenuEngine`). Nu retrimite
  /// explicit pe `_ordersController` — ascultătorul înregistrat în
  /// `_startHttpServer` prinde orice schimbare a motorului, inclusiv comenzi
  /// noi trimise de clienți.
  void advanceOrder(String orderId) => _menuEngine.advanceStatus(orderId);

  void cancelOrder(String orderId) => _menuEngine.cancelOrder(orderId);

  /// Toate comenzile curente, cele mai noi primele.
  List<Order> get orders => _menuEngine.allOrders;

  /// Apelat după ce organizatorul a sincronizat meniul editat — clienții
  /// deja conectați la Meniu primesc imediat produsele noi.
  void menuChanged() => _menuEngine.menuChanged();

  /// Mesaj de sistem, livrat public în toate camerele active deodată.
  Future<void> broadcastAnnouncement(String text) async {
    for (final room in _rooms.values) {
      room.deliverChat(ChatMessage(fromId: RoomSession.organizerChatId, fromName: 'Organizator', text: text));
    }
    await _log('announcement', detail: text);
  }

  Future<void> start() async {
    // Limita de vechime a comenzilor se aplică și cât timp serverul rulează,
    // nu doar la pornire (când `OrdersStore` filtrează ce încarcă).
    _expiryTimer = Timer.periodic(const Duration(minutes: 10), (_) => expireStaleOrders());
    await _startHttpServer();
    await _startBeacon();
    _startHeartbeat();
  }

  /// Creată o singură dată, odată cu serverul — nu la cererea unui
  /// client (spre deosebire de restul camerelor) — ca niciun client obișnuit
  /// să nu devină „gazda" ei. `onEmpty` e un no-op: rămâne deschisă chiar
  /// dacă, temporar, niciun client nu e conectat la ea.
  void _createMenuRoom() {
    final room = RoomSession(
      code: menuRoomCode,
      definition: menuDefinition,
      roomName: 'Meniu',
      tableStake: 0,
      onRoomChanged: _broadcastRoomsToLobby,
      onEmpty: () {},
    );
    _rooms[menuRoomCode] = room;
    final engine = room.engine as MenuEngine;
    engine.restoreOrders(OrdersStore.instance.loaded);
    engine.restoreBills(OrdersStore.instance.loadedBills);
    engine.addListener(() {
      _ordersController.add(engine.allOrders);
      _billsController.add(engine.allBills);
      OrdersStore.instance.save(engine.allOrders, engine.allBills);
    });
  }

  /// Puls periodic trimis tuturor conexiunilor active (indiferent dacă sunt
  /// deja atașate unei camere) — fără el, un client nu are cum să distingă
  /// „nu s-a întâmplat nimic în joc" de „conexiunea a murit în tăcere" (ex:
  /// un roaming WiFi prost, între access point-uri fără 802.11r, care nu
  /// generează o eroare explicită de socket). Clientul (`ClientService`)
  /// consideră conexiunea moartă dacă nu mai primește nimic — nici puls,
  /// nici stare de joc — o vreme, și reconectează singur.
  void _startHeartbeat() {
    final payload = GameMessage.encode({'type': 'ping'});
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      for (final channel in _connections.keys) {
        try {
          channel.sink.add(payload);
        } catch (_) {
          // canalul e oricum pe cale să se închidă — fluxul normal de
          // deconectare (`onDone`/`onError`) curăță conexiunea la timpul ei
        }
      }
    });
  }

  Future<void> _startHttpServer() async {
    final webAssets = await WebAssetBundle.load();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, webPort);
    _server!.listen(onError: (_) {}, (request) async {
      if (request.uri.path == '/ws' && WebSocketTransformer.isUpgradeRequest(request)) {
        final WebSocket socket;
        try {
          socket = await WebSocketTransformer.upgrade(request);
        } catch (_) {
          return; // handshake eșuat — clientul a plecat între timp
        }
        // Ping la nivel de protocol WebSocket (browserul și dart:io răspund
        // automat cu pong): dacă pong-ul nu vine la timp, socket-ul se
        // închide singur și `onDone` curăță conexiunea. Fără asta, o
        // conexiune moartă în tăcere (roaming WiFi) ar rămâne „vie" pe server
        // minute în șir, cât ține timeout-ul TCP.
        socket.pingInterval = const Duration(seconds: 10);
        acceptClient(IOWebSocketChannel(socket));
        return;
      }
      if (request.uri.pathSegments.length == 3 &&
          request.uri.pathSegments[0] == 'menu' &&
          request.uri.pathSegments[1] == 'photos' &&
          request.method == 'GET') {
        await _handleMenuPhotoRequest(request, request.uri.pathSegments[2]);
        return;
      }
      _serveStatic(request, webAssets);
    });
  }

  /// `GET /menu/photos/<fișier>` — poza unui produs de meniu, citită direct
  /// de pe disc (`MenuStore`, persistă între reporniri ale serverului — spre
  /// deosebire de vechea arhivă de poze de eveniment, ștearsă odată cu
  /// Bingo/Vot poze).
  Future<void> _handleMenuPhotoRequest(HttpRequest request, String fileName) async {
    final file = await MenuStore.instance.photoFileHandle(fileName);
    if (file == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    request.response.headers.contentType = ContentType.parse('image/jpeg');
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  void _serveStatic(HttpRequest request, Map<String, Uint8List> webAssets) {
    var path = request.uri.path;
    if (path.startsWith('/')) path = path.substring(1);
    if (path.isEmpty) path = 'index.html';
    final bytes = webAssets[path];
    if (bytes == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.close();
      return;
    }
    request.response.headers.contentType = ContentType.parse(WebAssetBundle.contentTypeFor(path));
    // Fără cache: după o actualizare a aplicației, browserele invitaților
    // trebuie să ia imediat noul client web, nu o versiune veche păstrată.
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    request.response.add(bytes);
    request.response.close();
  }

  Future<void> _startBeacon() async {
    _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _udp!.broadcastEnabled = true;
    _beaconTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final payload = GameMessage.encode({
        'type': 'server_announce',
        'name': serverName,
        'port': webPort,
        'rooms': _rooms.length,
      });
      try {
        _udp!.send(utf8.encode(payload), InternetAddress('255.255.255.255'), discoveryPort);
      } catch (_) {
        // rețeaua poate refuza temporar broadcast-ul; se reîncearcă la tick-ul următor
      }
    });
  }

  /// Preia o conexiune WebSocket nouă — apelat de serverul HTTP la fiecare
  /// upgrade reușit; public doar ca testele să poată conecta canale false,
  /// fără rețea reală.
  @visibleForTesting
  void acceptClient(WebSocketChannel channel) {
    if (_connections.length >= maxConnections) {
      _sendError(channel, 'err.serverFull');
      channel.sink.close();
      return;
    }
    final state = _ConnectionState();
    _connections[channel] = state;
    _sendRooms(channel);
    _sendActivities(channel);

    state.subscription = channel.stream.listen(
      (raw) {
        if (raw is! String || raw.length > maxMessageLength) return;
        if (!state.allowMessage()) {
          // Inundare persistentă — conexiunea e închisă; `onDone` curăță.
          if (state.floodStrikes > 3) channel.sink.close();
          return;
        }
        Map<String, dynamic> msg;
        try {
          msg = GameMessage.decode(raw);
        } catch (_) {
          return;
        }
        try {
          _handleMessage(channel, state, msg);
        } catch (_) {
          // Un mesaj malformat nu are voie să scape ca excepție neprinsă.
        }
      },
      onDone: () => _handleDisconnect(channel, state),
      onError: (_) => _handleDisconnect(channel, state),
    );
  }

  /// Trimite o eroare traductibilă: clientul o afișează în limba lui din
  /// `messageKey`/`messageArgs`; `message` (în română) rămâne pentru
  /// clienții vechi, care nu știu de chei.
  static void _sendError(WebSocketChannel channel, String key, [Map<String, Object?> args = const {}]) {
    channel.sink.add(GameMessage.encode({
      'type': 'error',
      'message': trIn(AppLanguage.ro, key, args),
      'messageKey': key,
      if (args.isNotEmpty) 'messageArgs': args,
    }));
  }

  static void _sendException(WebSocketChannel channel, Object e) {
    if (e is GameError) {
      _sendError(channel, e.key, e.args);
    } else {
      _sendError(channel, 'err.invalidAction');
    }
  }

  /// Citește un câmp text dintr-un mesaj de client — `null` dacă lipsește
  /// sau are alt tip, în loc de o excepție neprinsă la un cast.
  static String? _readString(Map<String, dynamic> msg, String key) {
    final value = msg[key];
    return value is String ? value : null;
  }

  void _handleMessage(WebSocketChannel channel, _ConnectionState state, Map<String, dynamic> msg) {
    final type = _readString(msg, 'type');

    if (type == 'create_room') {
      _createRoom(channel, state, msg);
      return;
    }
    if (type == 'join_room') {
      _joinRoom(channel, state, msg);
      return;
    }
    if (type == 'spectate') {
      _spectate(channel, state, msg);
      return;
    }

    final room = state.room;
    if (room == null) return; // trebuie create_room/join_room/spectate înainte de orice altă acțiune

    if (state.isSpectator) {
      // Un spectator poate doar scrie în chat-ul public — nu poate porni
      // jocul sau trimite acțiuni, fiindcă nu e un jucător real.
      if (type == 'chat') {
        final text = _readString(msg, 'text')?.trim();
        if (text == null || text.isEmpty || text.length > maxChatLength) return;
        room.deliverChat(ChatMessage(fromId: RoomSession.organizerChatId, fromName: 'Organizator', text: text));
      }
      return;
    }

    final playerId = state.playerId;
    if (playerId == null) return;

    if (type == 'start_game') {
      try {
        room.startGame(playerId);
      } catch (e) {
        _sendException(channel, e);
      }
    } else if (type == 'action') {
      try {
        final rawAction = msg['action'];
        if (rawAction is! Map) throw GameError('err.invalidAction');
        final action = Map<String, dynamic>.from(rawAction);
        room.applyAction(playerId, action);
      } catch (e) {
        _sendException(channel, e);
      }
    } else if (type == 'chat') {
      final text = _readString(msg, 'text')?.trim();
      if (text == null || text.isEmpty) return;
      if (text.length > maxChatLength) {
        _sendError(channel, 'err.chatTooLong', {'max': maxChatLength});
        return;
      }
      if (MutedUsersStore.instance.isMuted(playerId)) {
        _sendError(channel, 'err.muted');
        return;
      }
      final toId = _readString(msg, 'to');
      room.deliverChat(ChatMessage(
        fromId: playerId,
        fromName: room.nameOf(playerId) ?? '?',
        text: text,
        toId: toId,
        toName: toId == null ? null : room.nameOf(toId),
      ));
    }
  }

  void _spectate(WebSocketChannel channel, _ConnectionState state, Map<String, dynamic> msg) {
    if (state.room != null) return; // deja atașat (jucător sau spectator)
    // Spectatorul scrie în chat ca „Organizator" — deci doar cine are cheia
    // organizatorului (păstrată pe telefonul-server) poate fi spectator.
    if (!OrganizerKeyStore.instance.matches(msg['organizerKey'])) {
      _sendError(channel, 'err.organizerOnly');
      return;
    }
    final code = _readString(msg, 'code')?.trim().toUpperCase();
    final room = code == null ? null : _rooms[code];
    if (room == null) {
      _sendError(channel, 'err.roomNotFound');
      return;
    }
    room.attachSpectator(channel);
    state.room = room;
    state.isSpectator = true;
    channel.sink.add(GameMessage.encode({'type': 'spectating', 'code': room.code}));
  }

  void _createRoom(WebSocketChannel channel, _ConnectionState state, Map<String, dynamic> msg) {
    if (state.room != null) return; // deja atașat unei camere
    final gameId = _readString(msg, 'gameId');
    final matches = activityCatalog.where((g) => g.id == gameId);
    final definition = matches.isEmpty ? null : matches.first;
    final name = _readString(msg, 'name')?.trim();
    final secretId = msg['profileId'];
    final roomName = _readString(msg, 'roomName')?.trim();
    if (definition == null ||
        definition.id == menuDefinition.id ||
        name == null ||
        name.isEmpty ||
        name.length > maxNameLength ||
        !isValidSecretProfileId(secretId) ||
        roomName == null ||
        roomName.isEmpty ||
        roomName.length > maxRoomNameLength) {
      _sendError(channel, 'err.invalidCreate');
      return;
    }
    if (!EventConfigStore.instance.isEnabled(definition.id)) {
      _sendError(channel, 'err.activityUnavailable');
      return;
    }
    if (_rooms.length >= maxRooms) {
      _sendError(channel, 'err.tooManyRooms');
      return;
    }
    final profileId = publicPlayerId(secretId as String);
    if (BlockedUsersStore.instance.isBlocked(profileId)) {
      _sendError(channel, 'err.blocked');
      return;
    }
    final rawStake = msg['tableStake'];
    final tableStake = rawStake is int ? rawStake.clamp(0, maxTableStake) : 0;

    final code = _generateRoomCode();
    final room = RoomSession(
      code: code,
      definition: definition,
      roomName: roomName,
      tableStake: tableStake,
      onRoomChanged: _broadcastRoomsToLobby,
      onEmpty: () => _removeRoom(code),
      autoActAfter: autoActAfter,
      autoActTick: autoActTick,
    );
    _rooms[code] = room;

    if (!_attach(room, channel, state, playerId: profileId, name: name, isHost: true)) {
      // Fără creator, camera n-ar avea niciodată jucători — și deci nici
      // `onEmpty` care s-o elimine.
      _rooms.remove(code)?.dispose();
      _broadcastRoomsToLobby();
    }
  }

  void _joinRoom(WebSocketChannel channel, _ConnectionState state, Map<String, dynamic> msg) {
    if (state.room != null) return;
    final code = _readString(msg, 'code')?.trim().toUpperCase();
    final name = _readString(msg, 'name')?.trim();
    final secretId = msg['profileId'];
    final room = code == null ? null : _rooms[code];
    if (room == null) {
      _sendError(channel, 'err.roomNotFound');
      return;
    }
    if (name == null || name.isEmpty || name.length > maxNameLength || !isValidSecretProfileId(secretId)) {
      _sendError(channel, 'err.invalidJoin');
      return;
    }
    // Verificat aici, nu doar în client — altfel clientul ar ocupa un loc
    // într-o cameră pe care o refuză apoi singur.
    final expectedGameId = _readString(msg, 'gameId');
    if (expectedGameId != null && expectedGameId != room.definition.id) {
      _sendError(channel, 'err.wrongGame');
      return;
    }
    final profileId = publicPlayerId(secretId as String);
    if (BlockedUsersStore.instance.isBlocked(profileId)) {
      _sendError(channel, 'err.blocked');
      return;
    }
    _attach(room, channel, state, playerId: profileId, name: name, isHost: false);
  }

  /// Întoarce `false` dacă atașarea a fost refuzată (eroarea a fost deja
  /// trimisă clientului).
  bool _attach(
    RoomSession room,
    WebSocketChannel channel,
    _ConnectionState state, {
    required String playerId,
    required String name,
    required bool isHost,
  }) {
    try {
      room.attach(playerId: playerId, name: name, isHost: isHost, channel: channel);
    } catch (e) {
      _sendException(channel, e);
      return false;
    }
    state.room = room;
    state.playerId = playerId;
    channel.sink.add(GameMessage.encode({'type': 'joined', 'id': playerId, 'gameId': room.definition.id, 'code': room.code}));
    channel.sink.add(GameMessage.encode({'type': 'state', 'state': room.buildSnapshot(playerId)}));
    _broadcastRoomsToLobby();
    _broadcastParticipants();
    return true;
  }

  String _generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // fără 0/O/1/I, ambigue rostite cu voce tare
    final rand = Random();
    String code;
    do {
      code = List.generate(4, (_) => chars[rand.nextInt(chars.length)]).join();
    } while (_rooms.containsKey(code));
    return code;
  }

  void _removeRoom(String code) {
    _rooms.remove(code)?.dispose();
    _broadcastRoomsToLobby();
    _broadcastParticipants();
  }

  void _sendRooms(WebSocketChannel channel) {
    channel.sink.add(GameMessage.encode({'type': 'rooms', 'rooms': rooms.map((r) => r.toJson()).toList()}));
  }

  /// Trimisă o singură dată, la conectare — lista de activități pe care
  /// organizatorul le-a activat pentru evenimentul curent. Un ecran de
  /// meniu al invitatului o cere o singură dată și se deconectează (vezi
  /// `EventConnectScreen`), deci nu retrimitem la schimbări ulterioare.
  void _sendActivities(WebSocketChannel channel) {
    channel.sink.add(GameMessage.encode({
      'type': 'activities',
      'activities': EventConfigStore.instance.enabledActivityIds.toList(),
    }));
  }

  /// Retrimite lista de camere doar conexiunilor aflate încă în faza de
  /// lobby (nu atașate niciunei camere) — cele care joacă deja primesc
  /// starea jocului lor prin `state`, nu prin lista de camere.
  void _broadcastRoomsToLobby() {
    final payload = GameMessage.encode({'type': 'rooms', 'rooms': rooms.map((r) => r.toJson()).toList()});
    for (final entry in _connections.entries) {
      if (entry.value.room != null) continue;
      entry.key.sink.add(payload);
    }
    _roomsListController.add(rooms);
  }

  void _handleDisconnect(WebSocketChannel channel, _ConnectionState state) {
    state.subscription?.cancel();
    _connections.remove(channel);
    final room = state.room;
    if (room == null) return;
    if (state.isSpectator) {
      room.detachSpectator(channel);
      return;
    }
    final playerId = state.playerId;
    if (playerId != null) {
      room.handleDisconnect(playerId, channel);
      _broadcastParticipants();
    }
  }

  Future<void> stop() async {
    _beaconTimer?.cancel();
    _heartbeatTimer?.cancel();
    _expiryTimer?.cancel();
    _udp?.close();
    for (final state in _connections.values) {
      await state.subscription?.cancel();
    }
    for (final channel in _connections.keys) {
      await channel.sink.close();
    }
    _connections.clear();
    for (final room in _rooms.values) {
      room.dispose();
    }
    _rooms.clear();
    await _server?.close();
    await OrdersStore.instance.flush();
    await _roomsListController.close();
    await _participantsController.close();
    await _moderationLogController.close();
    await _ordersController.close();
    await _billsController.close();
  }
}

class _ConnectionState {
  StreamSubscription? subscription;
  RoomSession? room;
  String? playerId;
  bool isSpectator = false;

  int _windowStartMs = 0;
  int _messagesInWindow = 0;
  int floodStrikes = 0;

  /// Limitare simplă pe fereastră de o secundă — `false` dacă mesajul
  /// trebuie ignorat (prea multe într-o secundă).
  bool allowMessage() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _windowStartMs >= 1000) {
      _windowStartMs = now;
      _messagesInWindow = 0;
    }
    _messagesInWindow++;
    if (_messagesInWindow > EventServerService.maxMessagesPerSecond) {
      if (_messagesInWindow == EventServerService.maxMessagesPerSecond + 1) floodStrikes++;
      return false;
    }
    return true;
  }
}
