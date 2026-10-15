import '../core/qr_cards.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/player_profile.dart';
import '../games/menu/menu_definition.dart';
import '../network/client_service.dart';
import '../network/event_server_runner.dart';
import '../network/event_server_service.dart';
import '../widgets/language_button.dart';
import '../widgets/version_badge.dart';
import 'lobby_screen.dart';
import 'main_menu_screen.dart';
import '../l10n/tr.dart';

/// Punctul de intrare al clientului în activitatea „Meniu" — spre deosebire
/// de `RoomBrowserScreen`, nu arată niciun ecran de creare/alăturare cameră:
/// se conectează la server și se alătură direct camerei singleton „MENU"
/// (creată automat de server la pornire, vezi `EventServerService.start`).
/// Pe web, dacă link-ul vine din QR-ul de meniu (`?menu`, sau `?table=` de
/// pe cartonașele mai vechi), se conectează automat, fără niciun tap —
/// exact experiența „scanează QR-ul de pe masă și comandă".
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
      if (openedFromMenuQr(Uri.base)) {
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
        name: profile.name.isEmpty ? tr('menuConnect.defaultName') : profile.name,
        profileId: profile.id,
        expectedGameId: 'menu',
      );
      _entered = true;
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => LobbyScreen(
            definition: menuDefinition,
            roomName: tr('game.menu.title'),
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
        _error = tr('connect.failed', {'error': e});
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
      appBar: AppBar(
        backgroundColor: Colors.black26,
        // Deschis direct din QR-ul mesei nu există ecran anterior — oferim
        // drumul spre meniul principal al aplicației.
        leading: Navigator.of(context).canPop()
            ? null
            : IconButton(
                icon: const Icon(Icons.home),
                tooltip: tr('menuOrder.leave'),
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const MainMenuScreen()),
                ),
              ),
        title: Text(tr('game.menu.title')),
        actions: const [VersionBadge(), LanguageButton()],
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
      Text(
        tr('connect.webHint'),
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _webAddressController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: tr('connect.webAddressHint'),
          hintStyle: const TextStyle(color: Colors.white38),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(onPressed: _connectWebAddress, child: Text(tr('common.connect'))),
    ];
  }

  List<Widget> _buildNativeSection() {
    return [
      Text(
        tr('menuConnect.nativeHint'),
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      const SizedBox(height: 8),
      if (_isServerHost)
        Card(
          color: Colors.green.withValues(alpha: 0.15),
          child: ListTile(
            leading: const Icon(Icons.smartphone, color: Colors.lightGreenAccent),
            title: Text(tr('rooms.thisPhone')),
            subtitle: Text(tr('rooms.thisPhoneHint')),
            onTap: () => _connect('127.0.0.1', EventServerService.webPort),
          ),
        ),
      _servers.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text(tr('connect.searching'), style: const TextStyle(color: Colors.white38))),
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
        title: Text(tr('connect.manualIp'), style: const TextStyle(color: Colors.white70)),
        collapsedIconColor: Colors.white70,
        iconColor: Colors.white70,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualHostController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(hintText: tr('connect.ipHint')),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _connectManualHost, child: Text(tr('common.connect'))),
            ],
          ),
        ],
      ),
    ];
  }
}
