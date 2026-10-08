import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/chat_message.dart';
import '../core/leaderboard_store.dart';
import '../core/match_record.dart';
import 'discovered_room.dart';
import 'game_message.dart';
import 'lobby_room.dart';
import 'room_discovery.dart';

export 'discovered_room.dart' show DiscoveredRoom;
export 'lobby_room.dart' show LobbyRoom;

/// Rulează pe telefoanele-client — Android nativ *sau* browser (iPhone), cu
/// exact același cod pe ambele: [WebSocketChannel] merge identic peste
/// `dart:io` sau peste API-ul de rețea al browserului. Se conectează o
/// singură dată la serverul central al evenimentului ([connect]); de acolo
/// primește live lista camerelor active ([rooms]) și poate crea una nouă
/// ([createRoom]) sau se poate alătura uneia existente ([joinRoom]) — nu
/// găzduiește niciodată el însuși nimic. Complet generic — nu decodează
/// starea jocului, doar o transportă ca JSON brut.
class ClientService {
  final RoomDiscovery _discovery = RoomDiscovery();

  /// Servere de eveniment găsite pe rețea prin beacon UDP (doar Android —
  /// un browser nu poate asculta UDP, vezi `room_discovery.dart`).
  Stream<List<DiscoveredRoom>> get discoveredServers => _discovery.rooms;

  Future<void> startDiscovery() => _discovery.start();
  void stopDiscovery() => _discovery.stop();

  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;
  /// Id-ul public primit de la server la `joined` — cel care apare în
  /// snapshot-uri și chat. Nu e același cu id-ul secret al profilului.
  String? myId;
  String? myName;

  /// Id-ul secret al profilului, trimis doar serverului — reținut ca o
  /// reconectare automată să poată revendica același loc.
  String? _profileSecret;

  /// Cheia organizatorului, cerută de server la [spectate].
  String? _organizerKey;

  /// `true` doar când utilizatorul a ales explicit să plece ([disconnect])
  /// — altfel, orice pierdere a canalului (WiFi instabil, ecran blocat)
  /// declanșează o reîncercare automată de reconectare, vezi
  /// [_attemptReconnect].
  bool _intentionalDisconnect = false;
  int _reconnectAttempt = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 2);

  /// Ultima dată când a sosit orice mesaj pe canal (inclusiv pulsul
  /// `ping` trimis de server la fiecare 5s, vezi `event_server_service_io.
  /// dart`) — dacă trece mult peste intervalul pulsului fără nimic, canalul
  /// e considerat mort chiar dacă sistemul de operare nu a raportat nicio
  /// eroare explicită (posibil la un roaming WiFi prost, fără 802.11r).
  DateTime _lastMessageAt = DateTime.now();
  Timer? _heartbeatWatchdog;
  static const Duration _heartbeatTimeout = Duration(seconds: 12);

  /// Adresa serverului curent — reținută ca ecranele de activități (ex.
  /// Meniu) să poată construi URL-uri de poze fără să reimplementeze
  /// conectarea.
  String? host;
  int? port;

  /// Codul camerei curente (primit odată cu `joined`) — afișat jucătorului
  /// care a creat-o, ca să-l poată împărtăși cu ceilalți invitați.
  String? roomCode;

  Completer<String>? _pendingJoin;
  String? _pendingGameId;
  Completer<void>? _pendingSpectate;

  Map<String, dynamic>? latestSnapshot;
  final _stateController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get states => _stateController.stream;

  /// Lista live a camerelor active pe server. Serverul o trimite imediat
  /// după conectare și la fiecare schimbare, cât timp conexiunea nu e încă
  /// atașată unei camere — după [createRoom]/[joinRoom], acest flux nu mai
  /// primește actualizări (starea jocului circulă prin [states]).
  Stream<List<LobbyRoom>> get rooms => _roomsController.stream;
  final _roomsController = StreamController<List<LobbyRoom>>.broadcast();

  /// Id-urile activităților activate de organizator pentru evenimentul
  /// curent — trimise o singură dată, imediat după conectare.
  Stream<List<String>> get activities => _activitiesController.stream;
  final _activitiesController = StreamController<List<String>>.broadcast();

  final _errorController = StreamController<String>.broadcast();
  Stream<String> get errors => _errorController.stream;

  final _chatController = StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get chatMessages => _chatController.stream;

  final _disconnectedController = StreamController<void>.broadcast();
  Stream<void> get onDisconnected => _disconnectedController.stream;

  /// Deschide conexiunea către serverul central al evenimentului. Nu te
  /// alătură nicio cameră — de aici înainte [rooms] arată lista live, până
  /// la un [createRoom]/[joinRoom].
  Future<void> connect({required String host, required int port}) async {
    _intentionalDisconnect = false;
    final channel = WebSocketChannel.connect(Uri.parse('ws://$host:$port/ws'));
    await channel.ready;
    this.host = host;
    this.port = port;
    _attachChannel(channel);
    _heartbeatWatchdog ??= Timer.periodic(const Duration(seconds: 3), (_) => _checkHeartbeat());
  }

  /// Verificat periodic — dacă suntem încă atașați unui canal dar n-a mai
  /// sosit nimic (nici pulsul serverului) de prea mult timp, îl închidem noi
  /// înșine și lăsăm fluxul normal de reconectare să preia de aici, exact ca
  /// la o eroare de socket raportată de sistem.
  void _checkHeartbeat() {
    if (_channel == null || _intentionalDisconnect) return;
    if (DateTime.now().difference(_lastMessageAt) <= _heartbeatTimeout) return;
    _channelSub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _pendingJoin?.completeError('Conexiune inactivă.');
    _pendingJoin = null;
    _pendingSpectate?.completeError('Conexiune inactivă.');
    _pendingSpectate = null;
    _disconnectedController.add(null);
    _maybeAutoReconnect();
  }

  /// Ascultă mesajele canalului [channel] — logică comună lui [connect] și
  /// unei reconectări automate ([_attemptReconnect]): în ambele cazuri,
  /// stream-urile publice (`states`, `chatMessages` etc.) rămân aceleași
  /// instanțe, deci ecranele care le ascultă deja nu au nevoie să știe că a
  /// avut loc o reconectare.
  void _attachChannel(WebSocketChannel channel) {
    _channel = channel;
    _lastMessageAt = DateTime.now();
    _channelSub = channel.stream.listen(
      (raw) {
        Map<String, dynamic> msg;
        try {
          msg = GameMessage.decode(raw);
        } catch (_) {
          return;
        }
        _lastMessageAt = DateTime.now();
        switch (msg['type']) {
          case 'rooms':
            final list = (msg['rooms'] as List)
                .map((r) => LobbyRoom.fromJson(Map<String, dynamic>.from(r as Map)))
                .toList();
            _roomsController.add(list);
            break;
          case 'activities':
            _activitiesController.add((msg['activities'] as List).cast<String>());
            break;
          case 'joined':
            final gameId = msg['gameId'] as String?;
            final expected = _pendingGameId;
            if (expected != null && gameId != null && gameId != expected) {
              _pendingJoin?.completeError('Camera aceasta găzduiește alt joc.');
              _pendingJoin = null;
              return;
            }
            myId = msg['id'] as String;
            roomCode = msg['code'] as String?;
            _pendingJoin?.complete(myId);
            _pendingJoin = null;
            break;
          case 'spectating':
            roomCode = msg['code'] as String?;
            _pendingSpectate?.complete();
            _pendingSpectate = null;
            break;
          case 'state':
            latestSnapshot = Map<String, dynamic>.from(msg['state'] as Map);
            _stateController.add(latestSnapshot!);
            break;
          case 'error':
            final message = msg['message'] as String? ?? 'Eroare necunoscută';
            _errorController.add(message);
            _pendingJoin?.completeError(message);
            _pendingJoin = null;
            _pendingSpectate?.completeError(message);
            _pendingSpectate = null;
            break;
          case 'replaced':
            // Același profil a intrat în cameră pe o conexiune nouă (alt tab,
            // sau o reconectare a noastră cât serverul încă ținea canalul
            // vechi) — acest canal nu mai reîncearcă, altfel cele două
            // conexiuni s-ar da afară reciproc la nesfârșit.
            _intentionalDisconnect = true;
            _errorController.add('Ai intrat în cameră de pe altă conexiune — aceasta a fost închisă.');
            break;
          case 'chat':
            _chatController.add(ChatMessage.fromJson(Map<String, dynamic>.from(msg['message'] as Map)));
            break;
          case 'match_result':
            final record = MatchRecord.fromJson(Map<String, dynamic>.from(msg['record'] as Map));
            recordMatchLocally(record);
            break;
        }
      },
      onDone: () {
        _pendingJoin?.completeError('Conexiune închisă.');
        _pendingJoin = null;
        _pendingSpectate?.completeError('Conexiune închisă.');
        _pendingSpectate = null;
        _disconnectedController.add(null);
        _maybeAutoReconnect();
      },
      onError: (e) {
        _pendingJoin?.completeError(e);
        _pendingJoin = null;
        _pendingSpectate?.completeError(e);
        _pendingSpectate = null;
        _disconnectedController.add(null);
        _maybeAutoReconnect();
      },
    );
  }

  /// Declanșează o reconectare automată doar dacă pierderea canalului nu a
  /// fost cerută de utilizator ([disconnect]) și eram deja atașați unei
  /// camere — altfel (ex: canalul din ecranul de conectare, înainte de a
  /// intra într-o cameră) nu are ce reconecta.
  void _maybeAutoReconnect() {
    if (_intentionalDisconnect) return;
    if (myId == null || roomCode == null || host == null || port == null) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_intentionalDisconnect) return;
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      _errorController.add('Conexiune pierdută — nu m-am putut reconecta.');
      return;
    }
    _reconnectAttempt++;
    Future.delayed(_reconnectDelay, _attemptReconnect);
  }

  Future<void> _attemptReconnect() async {
    if (_intentionalDisconnect) return;
    final h = host;
    final p = port;
    final id = myId;
    final code = roomCode;
    final name = myName;
    if (h == null || p == null || id == null || code == null || name == null) return;
    if (_intentionalDisconnect) return;

    WebSocketChannel channel;
    try {
      channel = WebSocketChannel.connect(Uri.parse('ws://$h:$p/ws'));
      await channel.ready;
    } catch (_) {
      _scheduleReconnect();
      return;
    }
    _attachChannel(channel);
    final secret = _profileSecret;
    if (secret == null) return;
    try {
      await joinRoom(code: code, name: name, profileId: secret);
      _reconnectAttempt = 0;
    } on TimeoutException {
      // Niciun răspuns — rețeaua e încă instabilă; reîncercăm.
      await _channelSub?.cancel();
      await channel.sink.close();
      _channel = null;
      _scheduleReconnect();
    } catch (_) {
      // Serverul a refuzat explicit reintrarea (kick, cameră dispărută
      // etc.) — mesajul de eroare a ajuns deja pe `errors` prin fluxul
      // normal de mesaje (case 'error' de mai sus); nu mai reîncercăm.
    }
  }

  /// Cere serverului să creeze o cameră nouă pentru jocul [gameId] și te
  /// atașează ei ca prim jucător. Întoarce id-ul de jucător atribuit.
  Future<String> createRoom({
    required String gameId,
    required String roomName,
    required int tableStake,
    required String name,
    required String profileId,
  }) {
    myName = name;
    _profileSecret = profileId;
    final completer = Completer<String>();
    _pendingJoin = completer;
    _pendingGameId = gameId;
    _channel?.sink.add(GameMessage.encode({
      'type': 'create_room',
      'gameId': gameId,
      'roomName': roomName,
      'tableStake': tableStake,
      'name': name,
      'profileId': profileId,
    }));
    return completer.future.timeout(const Duration(seconds: 5));
  }

  /// Se alătură camerei cu codul [code]. Dacă [expectedGameId] e dat și nu
  /// se potrivește cu jocul camerei, întoarce eroare fără să te atașeze.
  Future<String> joinRoom({
    required String code,
    required String name,
    required String profileId,
    String? expectedGameId,
  }) {
    myName = name;
    _profileSecret = profileId;
    final completer = Completer<String>();
    _pendingJoin = completer;
    _pendingGameId = expectedGameId;
    _channel?.sink.add(GameMessage.encode({
      'type': 'join_room',
      'code': code.trim().toUpperCase(),
      'name': name,
      'profileId': profileId,
      'gameId': ?expectedGameId,
    }));
    return completer.future.timeout(const Duration(seconds: 5));
  }

  /// Se alătură camerei [code] ca spectator — vede chat-ul public și starea
  /// ei (galeria de poze, dacă activitatea are una), fără să consume un loc
  /// de jucător. Pentru ecranul de monitorizare al organizatorului
  /// (`RoomMonitorScreen`).
  Future<void> spectate(String code, {required String organizerKey}) {
    _organizerKey = organizerKey;
    final completer = Completer<void>();
    _pendingSpectate = completer;
    _channel?.sink.add(GameMessage.encode({
      'type': 'spectate',
      'code': code.trim().toUpperCase(),
      'organizerKey': _organizerKey,
    }));
    return completer.future.timeout(const Duration(seconds: 5));
  }

  /// Trimite un mesaj public în camera monitorizată curent, ca organizator —
  /// spre deosebire de [sendChat], nu se afișează local optimist: serverul
  /// îl retrimite tuturor spectatorilor camerei, inclusiv celui care l-a
  /// trimis, exact ca oricărui alt abonat.
  void sendSpectatorChat(String text) {
    _channel?.sink.add(GameMessage.encode({'type': 'chat', 'text': text}));
  }

  /// Cere serverului să pornească jocul din camera curentă. Doar cel care a
  /// creat camera poate reuși — serverul verifică asta, nu doar UI-ul.
  void startGame() {
    _channel?.sink.add(GameMessage.encode({'type': 'start_game'}));
  }

  void sendAction(Map<String, dynamic> action) {
    _channel?.sink.add(GameMessage.encode({'type': 'action', 'action': action}));
  }

  /// Trimite un mesaj (public dacă [toId] e `null`) și îl afișează local
  /// imediat — serverul nu îl retransmite înapoi la expeditor.
  void sendChat(String text, {String? toId}) {
    _chatController.add(ChatMessage(fromId: myId ?? '', fromName: myName ?? '', text: text, toId: toId));
    _channel?.sink.add(GameMessage.encode({
      'type': 'chat',
      'text': text,
      'to': ?toId,
    }));
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _heartbeatWatchdog?.cancel();
    _heartbeatWatchdog = null;
    await _channelSub?.cancel();
    await _channel?.sink.close();
    _channel = null;
  }
}
