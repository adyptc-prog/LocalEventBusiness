import 'dart:async';

import 'package:flutter/material.dart';

import '../core/moderation_log_store.dart';
import '../network/event_server_runner.dart';
import '../network/participant_info.dart';

/// Ecran de organizator: cine e conectat la eveniment, în ce cameră, și
/// acțiuni de moderare — elimină (deconectare imediată), blochează
/// (deconectare + interzicere de a se mai alătura) sau silențiază (oprește
/// doar chat-ul, restul continuă normal). Plus un anunț trimis tuturor
/// camerelor deodată și istoricul acțiunilor de moderare. Randare pură din
/// `EventServerRunner`; nimic ținut local — comenzile trec direct spre
/// serverul care rulează în foreground service.
class ParticipantsScreen extends StatefulWidget {
  const ParticipantsScreen({super.key});

  @override
  State<ParticipantsScreen> createState() => _ParticipantsScreenState();
}

class _ParticipantsScreenState extends State<ParticipantsScreen> {
  final _announcementController = TextEditingController();
  StreamSubscription? _participantsSub;
  StreamSubscription? _logSub;
  List<ParticipantInfo> _participants = [];
  List<ModerationLogEntry> _log = [];

  @override
  void initState() {
    super.initState();
    _participantsSub = EventServerRunner.participantsUpdates.listen((participants) {
      if (!mounted) return;
      setState(() => _participants = participants);
    });
    _logSub = EventServerRunner.moderationLogUpdates.listen((log) {
      if (!mounted) return;
      setState(() => _log = log);
    });
  }

  @override
  void dispose() {
    _participantsSub?.cancel();
    _logSub?.cancel();
    _announcementController.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String title, String content) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Renunță')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Da')),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _kick(ParticipantInfo p) async {
    if (!await _confirm('Elimini pe ${p.name}?', 'I se închide conexiunea acum. Se poate alătura din nou mai târziu.')) return;
    EventServerRunner.kick(p.profileId);
  }

  Future<void> _block(ParticipantInfo p) async {
    if (!await _confirm('Blochezi pe ${p.name}?', 'I se închide conexiunea și nu se mai poate alătura până nu-l deblochezi.')) return;
    EventServerRunner.block(p.profileId, p.name);
  }

  void _unblock(ParticipantInfo p) => EventServerRunner.unblock(p.profileId);

  void _toggleMute(ParticipantInfo p) {
    if (p.muted) {
      EventServerRunner.unmute(p.profileId);
    } else {
      EventServerRunner.mute(p.profileId, p.name);
    }
  }

  void _sendAnnouncement() {
    final text = _announcementController.text.trim();
    if (text.isEmpty) return;
    EventServerRunner.announce(text);
    _announcementController.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Anunț trimis în toate camerele.')));
  }

  String _actionLabel(String action) => switch (action) {
        'kick' => 'Eliminat',
        'block' => 'Blocat',
        'unblock' => 'Deblocat',
        'mute' => 'Silențiat',
        'unmute' => 'Silențiere anulată',
        'announcement' => 'Anunț',
        _ => action,
      };

  @override
  Widget build(BuildContext context) {
    final inRoom = _participants.where((p) => p.roomCode != null).toList();
    final blocked = _participants.where((p) => p.blocked).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(backgroundColor: Colors.black26, title: const Text('Participanți')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Anunț către toate camerele', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _announcementController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(hintText: 'ex: Vă rugăm păstrați un limbaj decent'),
                    onSubmitted: (_) => _sendAnnouncement(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _sendAnnouncement, child: const Text('Trimite')),
              ],
            ),
            const SizedBox(height: 24),
            Text('Conectați acum (${inRoom.length})',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (inRoom.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Niciun invitat într-o cameră încă.', style: TextStyle(color: Colors.white38)),
              )
            else
              ...inRoom.map((p) => Card(
                    child: ListTile(
                      leading: Icon(Icons.person, color: p.connected ? Colors.lightGreenAccent : Colors.white38),
                      title: Text(p.name, style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        '${p.activityTitle} · cod ${p.roomCode}'
                        '${p.connected ? '' : ' · deconectat'}'
                        '${p.muted ? ' · silențiat' : ''}',
                        style: const TextStyle(color: Colors.white54),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(p.muted ? Icons.mic : Icons.mic_off, color: Colors.amberAccent),
                            tooltip: p.muted ? 'Anulează silențierea' : 'Silențiază',
                            onPressed: () => _toggleMute(p),
                          ),
                          IconButton(
                            icon: const Icon(Icons.person_remove, color: Colors.orangeAccent),
                            tooltip: 'Elimină',
                            onPressed: () => _kick(p),
                          ),
                          IconButton(
                            icon: const Icon(Icons.block, color: Colors.redAccent),
                            tooltip: 'Blochează',
                            onPressed: p.blocked ? null : () => _block(p),
                          ),
                        ],
                      ),
                    ),
                  )),
            const SizedBox(height: 24),
            Text('Blocați (${blocked.length})', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (blocked.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Niciun invitat blocat.', style: TextStyle(color: Colors.white38)),
              )
            else
              ...blocked.map((p) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.block, color: Colors.redAccent),
                      title: Text(p.name, style: const TextStyle(color: Colors.white)),
                      trailing: OutlinedButton(
                        onPressed: () => _unblock(p),
                        child: const Text('Deblochează'),
                      ),
                    ),
                  )),
            const SizedBox(height: 24),
            Text('Istoric moderare (${_log.length})', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_log.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Nicio acțiune încă.', style: TextStyle(color: Colors.white38)),
              )
            else
              ..._log.map((e) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.history, color: Colors.white38, size: 20),
                    title: Text(
                      '${_actionLabel(e.action)}${e.targetName != null ? ' — ${e.targetName}' : ''}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    subtitle: e.detail != null
                        ? Text(e.detail!, style: const TextStyle(color: Colors.white38), maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    trailing: Text(
                      '${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
