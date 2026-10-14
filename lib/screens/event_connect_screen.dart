import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../network/client_service.dart';
import '../network/event_server_service.dart';
import '../widgets/language_button.dart';
import '../widgets/version_badge.dart';
import 'event_menu_screen.dart';
import '../l10n/tr.dart';

/// Primul pas al unui invitat: conectare la serverul central al
/// evenimentului curent (auto-discovery pe Android, adresă precompletată pe
/// web, cu fallback IP manual) — doar ca să afle ce activități a activat
/// organizatorul. Se deconectează imediat după ce primește lista
/// (`EventMenuScreen` e randare locală, fără conexiune ținută deschisă);
/// fiecare activitate aleasă din meniu își face propria conexiune separată,
/// exact ca azi (`RoomBrowserScreen`, neschimbat).
class EventConnectScreen extends StatefulWidget {
  const EventConnectScreen({super.key});

  @override
  State<EventConnectScreen> createState() => _EventConnectScreenState();
}

class _EventConnectScreenState extends State<EventConnectScreen> {
  final _manualHostController = TextEditingController();
  late final _webAddressController = TextEditingController(
    text: kIsWeb ? '${Uri.base.host}:${Uri.base.hasPort ? Uri.base.port : EventServerService.webPort}' : '',
  );

  late final ClientService _clientService;
  StreamSubscription? _serversSub;
  List<DiscoveredRoom> _servers = [];
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _clientService = ClientService();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _connectWebAddress());
    } else {
      _clientService.startDiscovery();
      _serversSub = _clientService.discoveredServers.listen((servers) {
        if (!mounted) return;
        setState(() => _servers = servers);
      });
    }
  }

  @override
  void dispose() {
    _serversSub?.cancel();
    _clientService.stopDiscovery();
    _clientService.disconnect();
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
      final enabled = await _clientService.waitForActivities().timeout(const Duration(seconds: 5));
      await _clientService.disconnect();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => EventMenuScreen(enabledActivityIds: enabled)),
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
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(backgroundColor: Colors.black26, title: Text(tr('mainMenu.join.title')), actions: const [VersionBadge(), LanguageButton()]),
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
                child: SingleChildScrollView(
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

  List<Widget> _buildNativeSection() {
    return [
      Text(
        tr('connect.nativeHint'),
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      const SizedBox(height: 8),
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
}
