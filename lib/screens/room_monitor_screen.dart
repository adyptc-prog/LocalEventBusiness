import 'dart:async';

import 'package:flutter/material.dart';

import '../core/activity_catalog.dart';
import '../core/chat_message.dart';
import '../core/organizer_key_store.dart';
import '../network/client_service.dart';
import '../network/event_server_runner.dart';
import '../network/event_server_service.dart';
import '../widgets/language_button.dart';
import '../l10n/tr.dart';

/// Ecran de organizator: conectare la propriul server (exact fluxul din
/// `EventConnectScreen`), apoi alegerea unei camere active de monitorizat
/// ca spectator — chat public live. Nu consumă loc de jucător în camera
/// aleasă.
class RoomMonitorScreen extends StatefulWidget {
  const RoomMonitorScreen({super.key});

  @override
  State<RoomMonitorScreen> createState() => _RoomMonitorScreenState();
}

class _RoomMonitorScreenState extends State<RoomMonitorScreen> {
  final _manualHostController = TextEditingController();
  late final ClientService _clientService;
  StreamSubscription? _serversSub;
  StreamSubscription? _roomsSub;
  List<DiscoveredRoom> _servers = [];
  List<LobbyRoom> _rooms = [];
  bool _connecting = false;
  bool _connected = false;
  bool _spectating = false;
  bool _isServerHost = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _clientService = ClientService();
    _clientService.startDiscovery();
    _serversSub = _clientService.discoveredServers.listen((servers) {
      if (!mounted) return;
      setState(() => _servers = servers);
    });
    // La fel ca în RoomBrowserScreen — conectarea prin adresa de rețea,
    // ricoșată de pe router înapoi spre același telefon, e nesigură pe
    // routere ieftine. Dacă serverul rulează chiar pe acest telefon,
    // preferăm loopback-ul, care ocolește routerul complet.
    EventServerRunner.isRunning.then((running) {
      if (!mounted || !running) return;
      setState(() => _isServerHost = true);
    });
  }

  @override
  void dispose() {
    _serversSub?.cancel();
    _roomsSub?.cancel();
    _clientService.stopDiscovery();
    _clientService.disconnect();
    _manualHostController.dispose();
    super.dispose();
  }

  Future<void> _connect(String host, int port) async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      await _clientService.connect(host: host, port: port);
      _clientService.stopDiscovery();
      await _roomsSub?.cancel();
      _roomsSub = _clientService.rooms.listen((rooms) {
        if (!mounted) return;
        setState(() => _rooms = rooms);
      });
      if (!mounted) return;
      setState(() {
        _connected = true;
        _connecting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = tr('connect.failed', {'error': e});
      });
    }
  }

  void _connectManualHost() {
    final raw = _manualHostController.text.trim();
    if (raw.isEmpty) return;
    _connect(raw, EventServerService.webPort);
  }

  Future<void> _spectate(LobbyRoom room) async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      await _clientService.spectate(room.code, organizerKey: OrganizerKeyStore.instance.key);
      if (!mounted) return;
      setState(() {
        _spectating = true;
        _connecting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = tr('monitor.failed', {'error': e});
      });
    }
  }

  /// Revine la lista de camere fără să părăsești ecranul — reconectare
  /// rapidă la același server, ca să poți monitoriza alta.
  Future<void> _backToList() async {
    final host = _clientService.host;
    final port = _clientService.port;
    await _clientService.disconnect();
    if (!mounted) return;
    setState(() {
      _spectating = false;
      _connected = false;
      _rooms = [];
    });
    if (host != null && port != null) {
      await _connect(host, port);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(
        backgroundColor: Colors.black26,
        title: Text(tr('mainMenu.monitor')),
        actions: const [LanguageButton()],
        leading: _spectating
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: tr('monitor.backToList'),
                onPressed: _backToList,
              )
            : null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
                ),
              Expanded(
                child: _spectating
                    ? _SpectatorView(clientService: _clientService)
                    : (_connected ? _buildRoomList() : _buildConnect()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnect() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('connect.nativeHint'),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (_isServerHost)
            Card(
              color: Colors.green.withValues(alpha: 0.15),
              child: ListTile(
                leading: const Icon(Icons.smartphone, color: Colors.lightGreenAccent),
                title: Text(tr('rooms.thisPhone')),
                subtitle: Text(tr('rooms.thisPhoneHint')),
                onTap: _connecting ? null : () => _connect('127.0.0.1', EventServerService.webPort),
              ),
            ),
          _servers.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: _connecting
                        ? const CircularProgressIndicator()
                        : Text(tr('connect.searching'), style: const TextStyle(color: Colors.white38)),
                  ),
                )
              : Column(
                  children: _servers
                      .map((server) => Card(
                            child: ListTile(
                              leading: const Icon(Icons.dns),
                              title: Text(server.name),
                              subtitle: Text(tr('connect.serverSubtitle', {'n': server.rooms, 'address': server.address})),
                              onTap: _connecting ? null : () => _connect(server.address, server.port),
                            ),
                          ))
                      .toList(),
                ),
          const Divider(color: Colors.white24),
          ExpansionTile(
            title: Text(tr('connect.manualIp'), style: const TextStyle(color: Colors.white70)),
            collapsedIconColor: Colors.white70,
            iconColor: Colors.white70,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualHostController,
                      enabled: !_connecting,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(hintText: tr('monitor.ipHint')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _connecting ? null : _connectManualHost, child: Text(tr('common.connect'))),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoomList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('monitor.activeRooms'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Expanded(
          child: _rooms.isEmpty
              ? Center(child: Text(tr('monitor.noRooms'), style: const TextStyle(color: Colors.white38)))
              : ListView.builder(
                  itemCount: _rooms.length,
                  itemBuilder: (context, index) {
                    final room = _rooms[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.visibility),
                        title: Text(room.gameId == 'menu' ? activityTitleFor('menu') : room.roomName),
                        subtitle: Text('${activityTitleFor(room.gameId, fallback: room.gameTitle)} · ${tr('rooms.roomSubtitle', {'players': room.players, 'max': room.maxPlayers, 'code': room.code})}'),
                        trailing: _connecting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.arrow_forward),
                        onTap: _connecting ? null : () => _spectate(room),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SpectatorView extends StatefulWidget {
  final ClientService clientService;

  const _SpectatorView({required this.clientService});

  @override
  State<_SpectatorView> createState() => _SpectatorViewState();
}

class _SpectatorViewState extends State<_SpectatorView> {
  final _messageController = TextEditingController();
  StreamSubscription? _chatSub;
  final List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _chatSub = widget.clientService.chatMessages.listen((msg) {
      if (!mounted) return;
      setState(() => _messages.add(msg));
    });
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    widget.clientService.sendSpectatorChat(text);
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('monitor.publicChat'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Expanded(
          child: _messages.isEmpty
              ? Center(child: Text(tr('chat.noMessages'), style: const TextStyle(color: Colors.white38)))
              : ListView.builder(
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: '${msg.displayName}: ', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                          TextSpan(text: msg.text, style: const TextStyle(color: Colors.white)),
                        ]),
                      ),
                    );
                  },
                ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(hintText: tr('monitor.writeAsOrganizer')),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(icon: const Icon(Icons.send), onPressed: _send),
          ],
        ),
      ],
    );
  }
}
