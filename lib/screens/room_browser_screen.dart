import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/game_definition.dart';
import '../core/player_profile.dart';
import '../network/client_service.dart';
import '../network/event_server_runner.dart';
import '../network/event_server_service.dart';
import '../widgets/language_button.dart';
import 'lobby_screen.dart';
import '../l10n/tr.dart';

/// Punctul unic de intrare într-un joc: conectare la serverul central al
/// evenimentului, apoi crearea sau alăturarea unei camere — identic pe
/// Android și pe web (browser), fiindcă niciun telefon-client nu mai
/// găzduiește nimic el însuși, doar serverul dedicat o face. Pe Android
/// serverul se caută automat pe rețea (beacon UDP); pe web adresa vine
/// precompletată cu gazda de la care s-a încărcat chiar pagina curentă,
/// fiindcă serverul e cel care servește și clientul web.
class RoomBrowserScreen extends StatefulWidget {
  final GameDefinition definition;

  const RoomBrowserScreen({super.key, required this.definition});

  @override
  State<RoomBrowserScreen> createState() => _RoomBrowserScreenState();
}

class _RoomBrowserScreenState extends State<RoomBrowserScreen> {
  final _nameController = TextEditingController(text: PlayerProfileStore.instance.profile.name);
  final _manualHostController = TextEditingController();
  final _manualCodeController = TextEditingController();
  late final _webAddressController = TextEditingController(
    text: kIsWeb ? '${Uri.base.host}:${Uri.base.hasPort ? Uri.base.port : EventServerService.webPort}' : '',
  );

  late final ClientService _clientService;
  StreamSubscription? _serversSub;
  StreamSubscription? _roomsSub;
  List<DiscoveredRoom> _servers = [];
  List<LobbyRoom> _rooms = [];
  bool _connecting = false;
  bool _connected = false;
  bool _roomEntered = false;
  bool _isServerHost = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _clientService = ClientService();
    if (kIsWeb) {
      // Adresa serverului e deja completată (pagina vine chiar de la el) —
      // ne conectăm singuri dacă avem și numele, fără încă un tap.
      if (_myName.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _connectWebAddress());
      }
    } else {
      _clientService.startDiscovery();
      _serversSub = _clientService.discoveredServers.listen((servers) {
        if (!mounted) return;
        setState(() => _servers = servers);
      });
      // Telefonul care rulează serverul se descoperă și pe el însuși prin
      // beacon-ul UDP, dar conectarea prin adresa de rețea, ricoșată de pe
      // router înapoi spre același telefon (hairpin NAT), e nesigură pe
      // routerele ieftine de eveniment — multe o rup silențios după
      // handshake-ul inițial. Când serverul rulează chiar pe acest telefon,
      // oferim conectarea directă prin loopback, care ocolește routerul
      // complet.
      EventServerRunner.isRunning.then((running) {
        if (!mounted || !running) return;
        setState(() => _isServerHost = true);
      });
    }
  }

  @override
  void dispose() {
    _serversSub?.cancel();
    _roomsSub?.cancel();
    _clientService.stopDiscovery();
    if (!_roomEntered) _clientService.disconnect();
    _nameController.dispose();
    _manualHostController.dispose();
    _manualCodeController.dispose();
    _webAddressController.dispose();
    super.dispose();
  }

  String get _myName => _nameController.text.trim();

  Future<void> _connect(String host, int port) async {
    if (_myName.isEmpty) {
      setState(() => _error = tr('rooms.enterNameFirst'));
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      await PlayerProfileStore.instance.updateName(_myName);
      await _clientService.connect(host: host, port: port);
      _clientService.stopDiscovery();
      _rooms = (_clientService.latestRooms ?? const <LobbyRoom>[])
          .where((r) => r.gameId == widget.definition.id)
          .toList();
      _roomsSub = _clientService.rooms.listen((rooms) {
        if (!mounted) return;
        setState(() => _rooms = rooms.where((r) => r.gameId == widget.definition.id).toList());
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

  void _connectWebAddress() {
    final raw = _webAddressController.text.trim();
    if (raw.isEmpty) return;
    final parts = raw.split(':');
    final host = parts.first.trim();
    final port = parts.length > 1 ? int.tryParse(parts[1]) ?? EventServerService.webPort : EventServerService.webPort;
    if (host.isEmpty) return;
    _connect(host, port);
  }

  Future<void> _enterRoom(Future<String> Function() request, {required bool isHost}) async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final myId = await request();
      _roomEntered = true;
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => LobbyScreen(
            definition: widget.definition,
            roomName: tr('rooms.defaultName', {'game': widget.definition.title}),
            isHost: isHost,
            myId: myId,
            roomCode: _clientService.roomCode,
            serverOrigin: _clientService.host != null ? 'http://${_clientService.host}:${_clientService.port}' : null,
            stateStream: _clientService.states,
            initialSnapshot: _clientService.latestSnapshot,
            onStartGame: isHost ? _clientService.startGame : null,
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
        _error = tr('rooms.enterFailed', {'error': e});
      });
    }
  }

  Future<void> _showCreateRoomSheet() async {
    final roomNameController = TextEditingController(text: tr('rooms.defaultName', {'game': widget.definition.title}));
    final stakeController = TextEditingController(text: '0');
    final formKey = GlobalKey<FormState>();
    final hasStake = widget.definition.id != 'chat';

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black87,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('rooms.newRoom'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextFormField(
                controller: roomNameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: tr('rooms.roomName'), labelStyle: const TextStyle(color: Colors.white70)),
                validator: (v) => (v == null || v.trim().isEmpty) ? tr('rooms.enterAName') : null,
              ),
              if (hasStake) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: stakeController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: tr('rooms.stake'),
                    helperText: tr('rooms.stakeHelp'),
                    helperStyle: const TextStyle(color: Colors.white38),
                    labelStyle: const TextStyle(color: Colors.white70),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.of(context).pop(true);
                  }
                },
                child: Text(tr('rooms.create')),
              ),
            ],
          ),
        ),
      ),
    );

    if (result != true || !mounted) return;
    final tableStake = hasStake ? (int.tryParse(stakeController.text.trim()) ?? 0) : 0;
    final roomName = roomNameController.text.trim();
    await _enterRoom(
      () => _clientService.createRoom(
        gameId: widget.definition.id,
        roomName: roomName,
        tableStake: tableStake,
        name: _myName,
        profileId: PlayerProfileStore.instance.profile.id,
      ),
      isHost: true,
    );
  }

  void _joinRoom(LobbyRoom room) {
    _enterRoom(
      () => _clientService.joinRoom(
        code: room.code,
        name: _myName,
        profileId: PlayerProfileStore.instance.profile.id,
        expectedGameId: widget.definition.id,
      ),
      isHost: false,
    );
  }

  void _joinManualCode() {
    final code = _manualCodeController.text.trim();
    if (code.isEmpty) return;
    _enterRoom(
      () => _clientService.joinRoom(
        code: code,
        name: _myName,
        profileId: PlayerProfileStore.instance.profile.id,
        expectedGameId: widget.definition.id,
      ),
      isHost: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.definition.accentColor,
      appBar: AppBar(backgroundColor: Colors.black26, title: Text(widget.definition.title), actions: const [LanguageButton()]),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StepLabel(number: 1, text: tr('rooms.yourName')),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                enabled: !_connecting && !_connected,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: tr('rooms.nameHint'),
                  hintStyle: const TextStyle(color: Colors.white38),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
                ),
              ),
              const SizedBox(height: 20),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
                ),
              Expanded(child: _connected ? _buildLobby() : _buildConnect()),
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
        children: kIsWeb ? _buildWebConnectSection() : _buildNativeConnectSection(),
      ),
    );
  }

  List<Widget> _buildWebConnectSection() {
    return [
      _StepLabel(number: 2, text: tr('rooms.serverAddress')),
      const SizedBox(height: 4),
      Text(
        tr('connect.webHint'),
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _webAddressController,
        enabled: !_connecting,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: tr('connect.webAddressHint'),
          hintStyle: const TextStyle(color: Colors.white38),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _connecting ? null : _connectWebAddress,
        child: _connecting
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(tr('common.connect')),
      ),
    ];
  }

  List<Widget> _buildNativeConnectSection() {
    return [
      _StepLabel(number: 2, text: tr('rooms.serversFound')),
      const SizedBox(height: 4),
      Text(
        tr('rooms.serversHint'),
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
            trailing: _connecting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.arrow_forward),
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
                          trailing: _connecting
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.arrow_forward),
                          onTap: _connecting ? null : () => _connect(server.address, server.port),
                        ),
                      ))
                  .toList(),
            ),
      const Divider(color: Colors.white24),
      _StepLabel(number: 3, text: tr('rooms.cantFind')),
      ExpansionTile(
        title: Text(tr('rooms.enterIp'), style: const TextStyle(color: Colors.white70)),
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
                  decoration: InputDecoration(
                    hintText: tr('connect.ipHint'),
                    hintStyle: const TextStyle(color: Colors.white38),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _connecting ? null : _connectManualHost,
                child: Text(tr('common.connect')),
              ),
            ],
          ),
        ],
      ),
    ];
  }

  Widget _buildLobby() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.add_circle_outline),
            label: Text(tr('rooms.createRoom')),
            onPressed: _connecting ? null : _showCreateRoomSheet,
          ),
        ),
        const SizedBox(height: 16),
        _StepLabel(number: 3, text: tr('rooms.activeRooms', {'game': widget.definition.title})),
        const SizedBox(height: 8),
        Expanded(
          child: _rooms.isEmpty
              ? Center(child: Text(tr('rooms.none'), style: const TextStyle(color: Colors.white38)))
              : ListView.builder(
                  itemCount: _rooms.length,
                  itemBuilder: (context, index) {
                    final room = _rooms[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.videogame_asset),
                        title: Text(room.roomName),
                        subtitle: Text(tr('rooms.roomSubtitle', {'players': room.players, 'max': room.maxPlayers, 'code': room.code}) +
                            (room.started ? tr('rooms.inProgressSuffix') : '')),
                        trailing: _connecting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.arrow_forward),
                        onTap: _connecting || room.started ? null : () => _joinRoom(room),
                      ),
                    );
                  },
                ),
        ),
        const Divider(color: Colors.white24),
        ExpansionTile(
          title: Text(tr('rooms.haveCode'), style: const TextStyle(color: Colors.white70)),
          collapsedIconColor: Colors.white70,
          iconColor: Colors.white70,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualCodeController,
                    enabled: !_connecting,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: tr('rooms.codeHint'),
                      hintStyle: const TextStyle(color: Colors.white38),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _connecting ? null : _joinManualCode,
                  child: Text(tr('rooms.join')),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _StepLabel extends StatelessWidget {
  final int number;
  final String text;

  const _StepLabel({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(radius: 11, backgroundColor: Colors.white24, child: Text('$number', style: const TextStyle(color: Colors.white, fontSize: 12))),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
