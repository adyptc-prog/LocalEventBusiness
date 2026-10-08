import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../models/card.dart';
import '../../screens/leaderboard_screen.dart';
import '../../widgets/hand_widget.dart';
import '../../widgets/playing_card_widget.dart';
import 'septica_snapshot.dart';
import '../../l10n/tr.dart';
import '../../widgets/language_button.dart';

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
    final title = _snapshot.isDraw ? tr('game.draw') : (isMe ? tr('game.youWon') : tr('game.over'));
    final content = _snapshot.isDraw
        ? tr('septica.drawResult', {'score': _snapshot.me.score})
        : (isMe
            ? tr('septica.youCaptured', {'score': _snapshot.me.score})
            : tr('septica.theyWon', {
                'name': _snapshot.winnerName ?? tr('war.opponentThe'),
                'score': _snapshot.players.firstWhere((p) => p.id == _snapshot.winnerId).score,
                'mine': _snapshot.me.score,
              }));
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
              child: Text(tr('game.backToMenu')),
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
        ? tr('septica.fightTitle')
        : (_snapshot.isMyTurn ? tr('game.yourTurn') : tr('game.playing'));

    return Scaffold(
      backgroundColor: const Color(0xFF5A1A22),
      appBar: AppBar(
        backgroundColor: const Color(0xFF3D1116),
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.leaderboard),
            tooltip: tr('lobby.leaderboardAndChat'),
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
            tooltip: tr('game.leave'),
            onPressed: () {
              widget.args.onLeave();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
          const LanguageButton(),
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
                    Text(tr('war.you'), style: const TextStyle(color: Colors.white70)),
                  ]),
                  Text(tr('leaderboard.points', {'n': _snapshot.me.score}), style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
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
                  child: Text(tr('septica.concede')),
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
            Text(_snapshot.tableCards.length > 1 ? tr('septica.onTable', {'n': _snapshot.tableCards.length}) : '',
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
        ? tr('septica.fightMine', {'name': challengerName, 'rank': rankLabel})
        : tr('septica.fightOther', {'name': _nameOf(_snapshot.leaderId), 'rank': rankLabel});
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildLastMoveBanner() {
    if (!_snapshot.lastPlayQualified) return const SizedBox.shrink();
    final byMe = _snapshot.lastPlayedById == widget.args.myId;
    final text = byMe ? tr('septica.youCut') : tr('septica.theyCut', {'name': _nameOf(_snapshot.lastPlayedById)});
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
          Text(tr('septica.opponentStats', {'cards': player.handCount, 'score': player.score}), style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}
