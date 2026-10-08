import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/player_profile.dart';
import '../games/menu/menu_definition.dart';
import '../network/client_service.dart';
import '../network/event_server_runner.dart';
import '../network/event_server_service.dart';
import 'lobby_screen.dart';

/// Punctul de intrare al clientului în activitatea „Meniu" — spre deosebire
/// de `RoomBrowserScreen`, nu arată niciun ecran de creare/alăturare cameră:
/// se conectează la server și se alătură direct camerei singleton „MENU"
/// (creată automat de server la pornire, vezi `EventServerService.start`).
/// Pe web, dacă link-ul are `?table=`, se conectează automat, fără niciun
/// tap — exact experiența „scanează QR-ul mesei și comandă".
class MenuConnectScreen extends StatefulWidget {
  const MenuConnectScreen({super.key});

  @override
  State<MenuConnectScreen> createState() => _MenuConnectScreenState();
}

class _MenuConnectScreenState extends State<MenuConnectScreen> {
  final _manualHostController = TextEditingController();
  late final _webAddressController = TextEditingController(
    text: kIsWeb ? '${Uri.base.host}:${Uri.base.hasPort ? Uri.base.port : EventServerService.webPort}' : '',
  );

  late final ClientService _clientService;
  StreamSubscription? _serversSub;
  List<DiscoveredRoom> _servers = [];
  bool _connecting = false;
  bool _entered = false;
  bool _isServerHost = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _clientService = ClientService();
    if (kIsWeb) {
      if (Uri.base.queryParameters.containsKey('table')) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _connectWebAddress());
      }
    } else {
      _clientService.startDiscovery();
      _serversSub = _clientService.discoveredServers.listen((servers) {
        if (!mounted) return;
        setState(() => _servers = servers);
      });
      EventServerRunner.isRunning.then((running) {
        if (!mounted || !running) return;
        setState(() => _isServerHost = true);
      });
    }
  }

  @override
  void dispose() {
    _serversSub?.cancel();
    _clientService.stopDiscovery();
    if (!_entered) _clientService.disconnect();
    _manualHostController.dispose();
    _webAddressController.dispose();
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
      final profile = PlayerProfileStore.instance.profile;
      final myId = await _clientService.joinRoom(
        code: 'MENU',
        name: profile.name.isEmpty ? 'Client' : profile.name,
        profileId: profile.id,
        expectedGameId: 'menu',
      );
      _entered = true;
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => LobbyScreen(
            definition: menuDefinition,
            roomName: 'Meniu',
            isHost: false,
            myId: myId,
            roomCode: _clientService.roomCode,
            serverOrigin: 'http://${_clientService.host}:${_clientService.port}',
            stateStream: _clientService.states,
            initialSnapshot: _clientService.latestSnapshot,
            onAction: _clientService.sendAction,
            errorStream: _clientService.errors,
            onLeave: _clientService.disconnect,
            chatStream: _clientService.chatMessages,
            onChat: _clientService.sendChat,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = 'Nu m-am putut conecta: $e';
      });
    }
  }

  void _connectManualHost() {
    final raw = _manualHostController.text.trim();
    if (raw.isEmpty) return;
    _connect(raw, EventServerService.webPort);
  }

  void _connectWebAddress() {
    final raw = _webAddressController.text.trim();
    if (raw.isEmpty) return;
    final parts = raw.split(':');
    final host = parts.first.trim();
    final port = parts.length > 1 ? int.tryParse(parts[1]) ?? EventServerService.webPort : EventServerService.webPort;
    if (host.isEmpty) return;
    _connect(host, port);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF6B3F1D),
      appBar: AppBar(backgroundColor: Colors.black26, title: const Text('Meniu')),
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
                child: _connecting
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: kIsWeb ? _buildWebSection() : _buildNativeSection(),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildWebSection() {
    return [
      const Text(
        'Un browser nu poate găsi serverul automat — dar fiindcă ai deschis această pagină direct de la el, adresa e deja completată mai jos.',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _webAddressController,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'ex: 192.168.43.1:45034',
          hintStyle: TextStyle(color: Colors.white38),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(onPressed: _connectWebAddress, child: const Text('Conectează')),
    ];
  }

  List<Widget> _buildNativeSection() {
    return [
      const Text(
        'Conectează-te la același Wi-Fi sau hotspot ca serverul localului — apare automat aici.',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      ),
      const SizedBox(height: 8),
      if (_isServerHost)
        Card(
          color: Colors.green.withValues(alpha: 0.15),
          child: ListTile(
            leading: const Icon(Icons.smartphone, color: Colors.lightGreenAccent),
            title: const Text('Acest telefon (server local)'),
            subtitle: const Text('Conectare directă, recomandat — nu depinde de router.'),
            onTap: () => _connect('127.0.0.1', EventServerService.webPort),
          ),
        ),
      _servers.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Se caută serverul...', style: TextStyle(color: Colors.white38))),
            )
          : Column(
              children: _servers
                  .map((server) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.dns),
                          title: Text(server.name),
                          subtitle: Text(server.address),
                          onTap: () => _connect(server.address, server.port),
                        ),
                      ))
                  .toList(),
            ),
      const Divider(color: Colors.white24),
      ExpansionTile(
        title: const Text('Nu găsești serverul? Introdu IP-ul manual', style: TextStyle(color: Colors.white70)),
        collapsedIconColor: Colors.white70,
        iconColor: Colors.white70,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualHostController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(hintText: 'ex: 192.168.43.1'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _connectManualHost, child: const Text('Conectează')),
            ],
          ),
        ],
      ),
    ];
  }
}
