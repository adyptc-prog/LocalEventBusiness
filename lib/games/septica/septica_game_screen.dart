import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../models/card.dart';
import '../../screens/leaderboard_screen.dart';
import '../../widgets/hand_widget.dart';
import '../../widgets/playing_card_widget.dart';
import 'septica_snapshot.dart';

class SepticaGameScreen extends StatefulWidget {
  final GameSessionArgs args;

  const SepticaGameScreen({super.key, required this.args});

  @override
  State<SepticaGameScreen> createState() => _SepticaGameScreenState();
}

class _SepticaGameScreenState extends State<SepticaGameScreen> {
  late SepticaSnapshot _snapshot;
  late Map<String, dynamic> _rawSnapshot;
  StreamSubscription? _stateSub;
  StreamSubscription? _errorSub;
  bool _winnerDialogShown = false;

  @override
  void initState() {
    super.initState();
    _rawSnapshot = widget.args.initialSnapshot;
    _snapshot = SepticaSnapshot.fromJson(_rawSnapshot);
    _stateSub = widget.args.stateStream.listen((json) {
      if (!mounted) return;
      setState(() {
        _rawSnapshot = json;
        _snapshot = SepticaSnapshot.fromJson(json);
      });
      _maybeShowWinnerDialog();
    });
    _errorSub = widget.args.errorStream?.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWinnerDialog());
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }

  void _maybeShowWinnerDialog() {
    if (_winnerDialogShown || _snapshot.started) return;
    _winnerDialogShown = true;
    final isMe = _snapshot.winnerId == _snapshot.viewerId;
    final title = _snapshot.isDraw ? 'Egalitate!' : (isMe ? 'Ai câștigat! 🎉' : 'Joc terminat');
    final content = _snapshot.isDraw
        ? 'Ai terminat la egalitate cu ${_snapshot.me.score} puncte.'
        : (isMe
            ? 'Ai capturat ${_snapshot.me.score} puncte.'
            : '${_snapshot.winnerName ?? 'Adversarul'} a câștigat cu ${_snapshot.players.firstWhere((p) => p.id == _snapshot.winnerId).score} puncte (tu ai ${_snapshot.me.score}).');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () {
                widget.args.onLeave();
                Navigator.of(context)
                  ..pop()
                  ..popUntil((route) => route.isFirst);
              },
              child: const Text('Înapoi la meniu'),
            ),
          ],
        ),
      );
    });
  }

  void _playCard(PlayingCard card) {
    if (!_snapshot.isMyTurn) return;
    widget.args.onAction({'type': 'play_card', 'card': card.toJson()});
  }

  void _concede() {
    widget.args.onAction({'type': 'concede'});
  }

  String _nameOf(String? playerId) {
    if (playerId == null) return '';
    final matches = _snapshot.players.where((p) => p.id == playerId);
    return matches.isEmpty ? '?' : matches.first.name;
  }

  @override
  Widget build(BuildContext context) {
    final opponents = _snapshot.opponents;
    final title = _snapshot.isMyFightDecision
        ? 'Luptă! Continui sau renunți?'
        : (_snapshot.isMyTurn ? 'Rândul tău' : 'Se joacă...');

    return Scaffold(
      backgroundColor: const Color(0xFF5A1A22),
      appBar: AppBar(
        backgroundColor: const Color(0xFF3D1116),
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.leaderboard),
            tooltip: 'Clasament și chat',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => LeaderboardScreen(
                  myId: widget.args.myId,
                  stateStream: widget.args.stateStream,
                  initialSnapshot: _rawSnapshot,
                  chatStream: widget.args.chatStream,
                  onChat: widget.args.onChat,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: 'Ieși din joc',
            onPressed: () {
              widget.args.onLeave();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Wrap(
                alignment: WrapAlignment.center,
                children: opponents
                    .map((p) => _OpponentChip(
                          player: p,
                          isCurrentTurn: p.id == _snapshot.currentPlayerId,
                          isLeader: p.id == _snapshot.leaderId,
                          isChallenger: p.id == _snapshot.challengerId,
                        ))
                    .toList(),
              ),
            ),
            const Spacer(),
            if (_snapshot.awaitingLeaderDecision) _buildFightBanner(),
            if (!_snapshot.awaitingLeaderDecision && _snapshot.lastPlayedCard != null) _buildLastMoveBanner(),
            const SizedBox(height: 8),
            _buildTable(),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    if (_snapshot.leaderId == widget.args.myId)
                      const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.shield, size: 14, color: Colors.amberAccent)),
                    const Text('Tu', style: TextStyle(color: Colors.white70)),
                  ]),
                  Text('${_snapshot.me.score} pct', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            HandWidget(
              cards: _snapshot.myHand,
              isPlayable: _snapshot.isCardPlayable,
              onCardTap: _playCard,
            ),
            if (_snapshot.isMyFightDecision)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
                  onPressed: _concede,
                  child: const Text('Renunță — lasă-l pe celălalt să ia cărțile'),
                ),
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildTable() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Column(
          children: [
            Opacity(opacity: _snapshot.drawPileCount > 0 ? 1 : 0.4, child: const CardBackWidget(width: 64)),
            const SizedBox(height: 4),
            Text('${_snapshot.drawPileCount}', style: const TextStyle(color: Colors.white70)),
          ],
        ),
        const SizedBox(width: 24),
        Column(
          children: [
            if (_snapshot.tableTop != null)
              Stack(
                alignment: Alignment.center,
                children: [
                  if (_snapshot.tableCards.length > 1)
                    Transform.translate(offset: const Offset(4, 4), child: const CardBackWidget(width: 72)),
                  PlayingCardWidget(card: _snapshot.tableTop!, width: 72),
                ],
              )
            else
              const SizedBox(width: 72, height: 100),
            const SizedBox(height: 4),
            Text(_snapshot.tableCards.length > 1 ? '${_snapshot.tableCards.length} pe masă' : '',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      ],
    );
  }

  Widget _buildFightBanner() {
    final isMine = _snapshot.isMyFightDecision;
    final challengerName = _nameOf(_snapshot.challengerId);
    final rankLabel = _snapshot.contestedRank?.label ?? '';
    final text = isMine
        ? '$challengerName a tăiat pe $rankLabel — mai pui o carte, sau renunți?'
        : '${_nameOf(_snapshot.leaderId)} decide dacă mai continuă lupta pe $rankLabel.';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildLastMoveBanner() {
    if (!_snapshot.lastPlayQualified) return const SizedBox.shrink();
    final byMe = _snapshot.lastPlayedById == widget.args.myId;
    final text = byMe ? 'Ai tăiat!' : '${_nameOf(_snapshot.lastPlayedById)} a tăiat!';
    return Text(text, style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold));
  }
}

class _OpponentChip extends StatelessWidget {
  final SepticaPlayerSummary player;
  final bool isCurrentTurn;
  final bool isLeader;
  final bool isChallenger;

  const _OpponentChip({
    required this.player,
    required this.isCurrentTurn,
    required this.isLeader,
    required this.isChallenger,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: isCurrentTurn ? Colors.amber.shade700.withValues(alpha: 0.85) : Colors.black26,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLeader)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.shield, size: 14, color: Colors.white),
                ),
              if (isChallenger)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.local_fire_department, size: 14, color: Colors.orangeAccent),
                ),
              if (!player.connected)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.wifi_off, size: 14, color: Colors.white70),
                ),
              Text(
                player.name,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: isCurrentTurn ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const CardBackWidget(width: 30),
          const SizedBox(height: 2),
          Text('${player.handCount} cărți · ${player.score} pct', style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}
