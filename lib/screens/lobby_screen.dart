import 'dart:async';

import 'package:flutter/material.dart';

import '../core/chat_message.dart';
import '../core/game_definition.dart';
import '../widgets/language_button.dart';
import 'leaderboard_screen.dart';
import '../l10n/tr.dart';

/// Cameră de așteptare, folosită identic de gazdă (după ce creează camera)
/// și de clienți (după ce se alătură) — se transformă automat în ecranul de
/// joc al [definition] când gazda apasă "Începe jocul". Generic: citește
/// doar cheile comune `players`/`started`/`tableStake` din snapshot-ul JSON
/// brut, restul e ignorat aici și decodat doar de ecranul jocului.
class LobbyScreen extends StatefulWidget {
  final GameDefinition definition;
  final String roomName;
  final bool isHost;
  final String myId;
  final String? roomCode;
  final Stream<Map<String, dynamic>> stateStream;
  final Map<String, dynamic>? initialSnapshot;
  final VoidCallback? onStartGame;
  final void Function(Map<String, dynamic> action) onAction;
  final Stream<String>? errorStream;
  final VoidCallback onLeave;
  final Stream<ChatMessage> chatStream;
  final void Function(String text, {String? toId}) onChat;
  final String? serverOrigin;

  const LobbyScreen({
    super.key,
    required this.definition,
    required this.roomName,
    required this.isHost,
    required this.myId,
    this.roomCode,
    required this.stateStream,
    required this.initialSnapshot,
    this.onStartGame,
    required this.onAction,
    this.errorStream,
    required this.onLeave,
    required this.chatStream,
    required this.onChat,
    this.serverOrigin,
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  Map<String, dynamic>? _snapshot;
  StreamSubscription? _sub;
  StreamSubscription? _errorSub;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.initialSnapshot;
    _sub = widget.stateStream.listen((snap) {
      if (!mounted) return;
      setState(() => _snapshot = snap);
      _maybeNavigateToGame();
    });
    _errorSub = widget.errorStream?.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
    _maybeNavigateToGame();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }

  void _maybeNavigateToGame() {
    final snap = _snapshot;
    if (_navigated || snap == null || snap['started'] != true) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => widget.definition.buildGameScreen(
          context,
          GameSessionArgs(
            myId: widget.myId,
            stateStream: widget.stateStream,
            initialSnapshot: snap,
            onAction: widget.onAction,
            errorStream: widget.errorStream,
            onLeave: widget.onLeave,
            chatStream: widget.chatStream,
            onChat: widget.onChat,
            serverOrigin: widget.serverOrigin,
            roomCode: widget.roomCode,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final players = (_snapshot?['players'] as List<dynamic>? ?? const [])
        .map((p) => Map<String, dynamic>.from(p as Map))
        .toList();
    final tableStake = _snapshot?['tableStake'] as int? ?? 0;
    final canStart = widget.isHost &&
        players.length >= widget.definition.minPlayers &&
        players.length <= widget.definition.maxPlayers;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) widget.onLeave();
      },
      child: Scaffold(
        backgroundColor: widget.definition.accentColor,
        appBar: AppBar(
          backgroundColor: Colors.black26,
          title: Text(widget.roomName),
          actions: [
            IconButton(
              icon: const Icon(Icons.leaderboard),
              tooltip: tr('lobby.leaderboardAndChat'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => LeaderboardScreen(
                    myId: widget.myId,
                    stateStream: widget.stateStream,
                    initialSnapshot: _snapshot,
                    chatStream: widget.chatStream,
                    onChat: widget.onChat,
                  ),
                ),
              ),
            ),
            const LanguageButton(),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  widget.isHost ? tr('lobby.hostOpen') : tr('lobby.waitingHost'),
                  style: const TextStyle(color: Colors.white70),
                ),
                if (widget.isHost && widget.roomCode != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      tr('lobby.roomCode', {'code': widget.roomCode}),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                if (tableStake > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(tr('lobby.stake', {'amount': tableStake}),
                        style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    itemCount: players.length,
                    separatorBuilder: (_, _) => const Divider(color: Colors.white24),
                    itemBuilder: (context, index) {
                      final p = players[index];
                      final isHostPlayer = p['isHost'] as bool? ?? false;
                      final connected = p['connected'] as bool? ?? true;
                      return ListTile(
                        leading: Icon(isHostPlayer ? Icons.star : Icons.person, color: Colors.amberAccent),
                        title: Text(p['name'] as String? ?? '', style: const TextStyle(color: Colors.white)),
                        trailing: connected ? null : const Icon(Icons.wifi_off, color: Colors.white38),
                      );
                    },
                  ),
                ),
                if (players.length < widget.definition.minPlayers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(tr('lobby.minPlayers', {'n': widget.definition.minPlayers}),
                        style: const TextStyle(color: Colors.white54)),
                  ),
                if (widget.isHost)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: canStart ? widget.onStartGame : null,
                      child: Text(tr('lobby.start')),
                    ),
                  )
                else
                  Text(tr('lobby.onlyHost'), style: const TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
