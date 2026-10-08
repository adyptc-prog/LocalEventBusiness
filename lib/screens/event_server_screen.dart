import 'dart:async';

import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../network/event_server_runner.dart';
import '../network/event_server_service.dart' show EventServerService;
import '../network/lobby_room.dart';

/// Ecranul telefonului-server dedicat al evenimentului: pornește serverul
/// central (care poate găzdui simultan orice număr de camere, pentru orice
/// joc din bibliotecă) și arată o listă live a camerelor active, ca
/// organizatorul să poată monitoriza dintr-o privire ce se joacă. Orice alt
/// telefon — Android cu aplicația sau browser (iPhone) — se conectează la
/// acest server prin ecranul normal al fiecărui joc.
class EventServerScreen extends StatefulWidget {
  const EventServerScreen({super.key});

  @override
  State<EventServerScreen> createState() => _EventServerScreenState();
}

class _EventServerScreenState extends State<EventServerScreen> {
  StreamSubscription? _roomsSub;
  List<LobbyRoom> _rooms = [];
  String? _localIp;
  bool _running = false;
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Serverul rulează ca foreground service independent de acest ecran —
    // dacă era deja pornit dintr-o vizită anterioară, ne reatașăm la el.
    _checkAlreadyRunning();
  }

  Future<void> _checkAlreadyRunning() async {
    final running = await EventServerRunner.isRunning;
    if (!mounted || !running) return;
    final ip = await NetworkInfo().getWifiIP();
    if (!mounted) return;
    _listenRooms();
    setState(() {
      _running = true;
      _localIp = ip;
    });
  }

  void _listenRooms() {
    _roomsSub ??= EventServerRunner.roomsUpdates.listen((rooms) {
      if (!mounted) return;
      setState(() => _rooms = rooms);
    });
  }

  @override
  void dispose() {
    _roomsSub?.cancel();
    // Nu oprim serverul la ieșirea din acest ecran — rămâne activ în
    // foreground service cât timp aplicația rulează, ca invitații să poată
    // continua să se conecteze.
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final ok = await EventServerRunner.start(serverName: 'Server eveniment');
      if (!ok) throw Exception('Serviciul de fundal nu a putut porni.');
      // `start()` confirmă doar că foreground service-ul Android a fost
      // lansat — legarea efectivă a `HttpServer`-ului (ex: port deja ocupat)
      // se întâmplă asincron, în isolate-ul serverului; așteptăm un moment
      // scurt să vedem dacă raportează un eșec înainte să anunțăm succesul.
      final startError = await EventServerRunner.startErrorEvents.first.timeout(
        const Duration(seconds: 2),
        onTimeout: () => '',
      );
      if (startError.isNotEmpty) throw Exception(startError);
      final ip = await NetworkInfo().getWifiIP();
      if (!mounted) return;
      _listenRooms();
      setState(() {
        _running = true;
        _localIp = ip;
        _starting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = 'Nu am putut porni serverul: $e';
      });
    }
  }

  Future<void> _stop() async {
    await _roomsSub?.cancel();
    _roomsSub = null;
    await EventServerRunner.stop();
    if (!mounted) return;
    setState(() {
      _running = false;
      _rooms = [];
      _localIp = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(backgroundColor: Colors.black26, title: const Text('Server eveniment')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _running ? _buildRunning() : _buildStart(),
        ),
      ),
    );
  }

  Widget _buildStart() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.dns, size: 72, color: Colors.white70),
        const SizedBox(height: 16),
        const Text(
          'Pornește acest telefon ca server central pentru eveniment. Toți invitații — Android sau iPhone — se vor putea conecta și își vor putea crea singuri camere de joc.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 8),
        const Text(
          'Ține telefonul la priză și conectat la aceeași rețea Wi-Fi pe tot parcursul evenimentului.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 32),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent), textAlign: TextAlign.center),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _starting ? null : _start,
            child: _starting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Pornește serverul evenimentului'),
          ),
        ),
      ],
    );
  }

  Widget _buildRunning() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.circle, color: Colors.greenAccent, size: 12),
            SizedBox(width: 8),
            Text('Server activ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        if (_localIp != null) ...[
          Text('Adresă: $_localIp:${EventServerService.webPort}', style: const TextStyle(color: Colors.white70)),
          Text('Link pentru iPhone/browser: http://$_localIp:${EventServerService.webPort}',
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ] else
          const Text('IP-ul local nu a putut fi citit — invitații Android te găsesc automat oricum.',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 24),
        Text('Camere active (${_rooms.length})', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Expanded(
          child: _rooms.isEmpty
              ? const Center(child: Text('Nicio cameră deschisă încă.', style: TextStyle(color: Colors.white38)))
              : ListView.separated(
                  itemCount: _rooms.length,
                  separatorBuilder: (_, _) => const Divider(color: Colors.white24),
                  itemBuilder: (context, index) {
                    final room = _rooms[index];
                    return ListTile(
                      leading: const Icon(Icons.videogame_asset, color: Colors.white70),
                      title: Text(room.roomName, style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        '${room.gameTitle} · ${room.players}/${room.maxPlayers} jucători · cod ${room.code}'
                        '${room.started ? ' · în desfășurare' : ''}',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _stop,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
            child: const Text('Oprește serverul'),
          ),
        ),
      ],
    );
  }
}
