import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../models/card.dart';
import '../../screens/leaderboard_screen.dart';
import '../../widgets/playing_card_widget.dart';
import 'war_snapshot.dart';
import '../../l10n/tr.dart';
import '../../widgets/language_button.dart';

class WarGameScreen extends StatefulWidget {
  final GameSessionArgs args;

  const WarGameScreen({super.key, required this.args});

  @override
  State<WarGameScreen> createState() => _WarGameScreenState();
}

class _WarGameScreenState extends State<WarGameScreen> {
  late WarSnapshot _snapshot;
  late Map<String, dynamic> _rawSnapshot;
  StreamSubscription? _stateSub;
  StreamSubscription? _errorSub;
  bool _winnerDialogShown = false;

  @override
  void initState() {
    super.initState();
    _rawSnapshot = widget.args.initialSnapshot;
    _snapshot = WarSnapshot.fromJson(_rawSnapshot);
    _stateSub = widget.args.stateStream.listen((json) {
      if (!mounted) return;
      setState(() {
        _rawSnapshot = json;
        _snapshot = WarSnapshot.fromJson(json);
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
    if (_winnerDialogShown || _snapshot.winnerId == null) return;
    _winnerDialogShown = true;
    final isMe = _snapshot.winnerId == widget.args.myId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(isMe ? tr('game.youWon') : tr('game.over')),
          content: Text(isMe
              ? tr('war.youTookAll')
              : tr('war.theyTookAll', {'name': _snapshot.opponentName ?? tr('war.opponentThe')})),
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

  void _flip() {
    widget.args.onAction({'type': 'flip'});
  }

  @override
  Widget build(BuildContext context) {
    final canFlip = _snapshot.started && _snapshot.winnerId == null && !_snapshot.iHaveFlipped;
    final waitingForOpponent = _snapshot.iHaveFlipped && !_snapshot.opponentHasFlipped;

    return Scaffold(
      backgroundColor: const Color(0xFF1B2A4A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121E38),
        title: Text(tr('game.war.title')),
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
            const SizedBox(height: 12),
            _buildDeckLabel(_snapshot.opponentName ?? tr('war.opponent'), _snapshot.opponentDeckCount),
            const Spacer(),
            if (_snapshot.warPending)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(tr('war.warPending'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
              ),
            Text(tr('war.lastRound'), style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 8),
            _buildLastRoundRow(),
            const SizedBox(height: 8),
            if (_snapshot.lastRoundOutcome != null) _buildLastRoundBanner(),
            if (_snapshot.potCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(tr('war.pot', {'n': _snapshot.potCount}), style: const TextStyle(color: Colors.white54)),
              ),
            const Spacer(),
            if (waitingForOpponent && _snapshot.myRevealedCard != null) _buildPendingCard(_snapshot.myRevealedCard!),
            const SizedBox(height: 8),
            _buildDeckLabel(tr('war.you'), _snapshot.myDeckCount),
            const SizedBox(height: 16),
            SizedBox(
              width: 220,
              child: FilledButton.icon(
                icon: const Icon(Icons.flip),
                label: Text(waitingForOpponent ? tr('war.waiting') : tr('war.flip')),
                onPressed: canFlip ? _flip : null,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDeckLabel(String name, int count) {
    return Text(tr('war.deckLabel', {'name': name, 'n': count}), style: const TextStyle(color: Colors.white70));
  }

  Widget _buildLastRoundRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildRevealedSlot(_snapshot.lastRoundOpponentCard),
        const SizedBox(width: 28),
        _buildRevealedSlot(_snapshot.lastRoundMyCard),
      ],
    );
  }

  Widget _buildRevealedSlot(PlayingCard? card) {
    if (card == null) return const CardBackWidget(width: 78);
    return PlayingCardWidget(card: card, width: 78);
  }

  Widget _buildPendingCard(PlayingCard card) {
    return Column(
      children: [
        Text(tr('war.yourCard'), style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 4),
        PlayingCardWidget(card: card, width: 60),
      ],
    );
  }

  Widget _buildLastRoundBanner() {
    final outcome = _snapshot.lastRoundOutcome;
    final text = switch (outcome) {
      'win' => tr('war.outcome.win'),
      'lose' => tr('war.outcome.lose'),
      'war' => tr('war.outcome.war'),
      _ => '',
    };
    final color = switch (outcome) {
      'win' => Colors.lightGreenAccent,
      'lose' => Colors.orangeAccent,
      _ => Colors.white54,
    };
    return Text(text, style: TextStyle(color: color));
  }
}
