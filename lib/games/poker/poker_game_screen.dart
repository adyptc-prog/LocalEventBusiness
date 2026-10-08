import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../screens/leaderboard_screen.dart';
import '../../widgets/playing_card_widget.dart';
import 'poker_rules_screen.dart';
import 'poker_snapshot.dart';
import '../../l10n/tr.dart';
import '../../widgets/language_button.dart';

class PokerGameScreen extends StatefulWidget {
  final GameSessionArgs args;

  const PokerGameScreen({super.key, required this.args});

  @override
  State<PokerGameScreen> createState() => _PokerGameScreenState();
}

const _streetLabels = {
  'preflop': 'Preflop',
  'flop': 'Flop',
  'turn': 'Turn',
  'river': 'River',
  'showdown': 'Showdown',
};

class _PokerGameScreenState extends State<PokerGameScreen> {
  late PokerSnapshot _snapshot;
  late Map<String, dynamic> _rawSnapshot;
  StreamSubscription? _stateSub;
  StreamSubscription? _errorSub;
  bool _winnerDialogShown = false;
  int? _raiseAmount;

  @override
  void initState() {
    super.initState();
    _rawSnapshot = widget.args.initialSnapshot;
    _snapshot = PokerSnapshot.fromJson(_rawSnapshot);
    _stateSub = widget.args.stateStream.listen((json) {
      if (!mounted) return;
      setState(() {
        _rawSnapshot = json;
        _snapshot = PokerSnapshot.fromJson(json);
        _raiseAmount = null;
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
    final isMe = _snapshot.winnerId == widget.args.myId;
    final title = isMe ? tr('game.youWonAll') : tr('game.over');
    final content = isMe
        ? tr('poker.youTookAll')
        : tr('poker.theyTookAll', {'name': _snapshot.winnerName(widget.args.myId) ?? tr('poker.theWinner')});
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

  void _act(String action, {int? amount}) {
    widget.args.onAction({
      'type': 'poker_action',
      'action': action,
      'amount': ?amount,
    });
  }

  String _nameOf(String? playerId) {
    if (playerId == null) return '';
    return _snapshot.forId(playerId)?.name ?? '?';
  }

  @override
  Widget build(BuildContext context) {
    final me = _snapshot.forId(widget.args.myId);
    final isMyTurn = _snapshot.isMyTurn(widget.args.myId);
    final opponents = _snapshot.players.where((p) => p.id != widget.args.myId).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF10331F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF092013),
        title: Text(_streetLabels[_snapshot.street] ?? 'Poker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: tr('poker.rules'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const PokerRulesScreen()),
            ),
          ),
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
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: opponents.map((p) => _PlayerChip(player: p, snapshot: _snapshot)).toList(),
              ),
            ),
            const Spacer(),
            if (_snapshot.lastHandSummary != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_snapshot.lastHandSummary!.resolve(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
              ),
            if (_snapshot.lastShowdown != null) _buildShowdown(),
            Text(tr('poker.pot', {'n': _snapshot.pot}), style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 8),
            _buildCommunityCards(),
            const Spacer(),
            if (me != null) _buildMeRow(me),
            const SizedBox(height: 8),
            if (isMyTurn) _buildActionBar() else _buildWaitingBar(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildCommunityCards() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: i < _snapshot.community.length
                ? PlayingCardWidget(card: _snapshot.community[i], width: 52)
                : Container(
                    width: 52,
                    height: 52 * 1.4,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
          ),
      ],
    );
  }

  Widget _buildShowdown() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        children: _snapshot.lastShowdown!.map((s) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_nameOf(s.playerId), style: const TextStyle(color: Colors.white70, fontSize: 11)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: s.cards.map((c) => PlayingCardWidget(card: c, width: 34)).toList(),
              ),
              Text(s.handLabel.resolve(), style: const TextStyle(color: Colors.white54, fontSize: 10)),
              if (s.won > 0)
                Text('+${s.won}', style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMeRow(PokerPlayerSummary me) {
    return Column(
      children: [
        Text(tr('poker.meRow', {'name': me.name, 'chips': me.chips}) + (me.betThisRound > 0 ? tr('poker.betSuffix', {'n': me.betThisRound}) : ''),
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _snapshot.myHoleCards.map((c) => PlayingCardWidget(card: c, width: 60)).toList(),
        ),
      ],
    );
  }

  Widget _buildWaitingBar() {
    if (_snapshot.currentPlayerId == null) return const SizedBox(height: 40);
    return Text(tr('game.isPlaying', {'name': _nameOf(_snapshot.currentPlayerId)}), style: const TextStyle(color: Colors.white54));
  }

  Widget _buildActionBar() {
    final myId = widget.args.myId;
    final me = _snapshot.forId(myId)!;
    final toCall = _snapshot.amountToCall(myId);
    final minRaise = _snapshot.minRaiseTotal.clamp(0, me.chips + me.betThisRound);
    final maxRaise = me.chips + me.betThisRound;
    final canRaise = maxRaise > _snapshot.currentBet && me.chips > toCall;
    _raiseAmount ??= minRaise;

    return Column(
      children: [
        if (canRaise && maxRaise > minRaise)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Text('Raise: $_raiseAmount', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _raiseAmount!.toDouble().clamp(minRaise.toDouble(), maxRaise.toDouble()),
                    min: minRaise.toDouble(),
                    max: maxRaise.toDouble(),
                    divisions: (maxRaise - minRaise) > 0 ? (maxRaise - minRaise).clamp(1, 50) : null,
                    onChanged: (v) => setState(() => _raiseAmount = v.round()),
                  ),
                ),
              ],
            ),
          ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
              onPressed: () => _act('fold'),
              child: const Text('Fold'),
            ),
            FilledButton(
              onPressed: () => _act(toCall == 0 ? 'check' : 'call'),
              child: Text(toCall == 0 ? 'Check' : 'Call $toCall'),
            ),
            if (canRaise && maxRaise > minRaise)
              FilledButton(
                onPressed: () => _act('raise', amount: _raiseAmount),
                child: const Text('Raise'),
              ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.amberAccent, side: const BorderSide(color: Colors.amberAccent)),
              onPressed: () => _act('all_in'),
              child: const Text('All-in'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlayerChip extends StatelessWidget {
  final PokerPlayerSummary player;
  final PokerSnapshot snapshot;

  const _PlayerChip({required this.player, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final isTurn = player.id == snapshot.currentPlayerId;
    final isDealer = player.id == snapshot.dealerId;
    return Opacity(
      opacity: player.busted ? 0.35 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isTurn ? Colors.amber.shade700.withValues(alpha: 0.85) : Colors.black26,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDealer)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.circle, size: 10, color: Colors.white),
                  ),
                if (!player.connected)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.wifi_off, size: 12, color: Colors.white70),
                  ),
                Text(player.name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            Text(tr('poker.chips', {'n': player.chips}), style: const TextStyle(color: Colors.white70, fontSize: 11)),
            if (player.busted)
              Text(tr('poker.busted'), style: const TextStyle(color: Colors.redAccent, fontSize: 10))
            else if (player.folded)
              Text(tr('poker.folded'), style: const TextStyle(color: Colors.white38, fontSize: 10))
            else if (player.allIn)
              const Text('all-in', style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold))
            else if (player.betThisRound > 0)
              Text(tr('poker.bet', {'n': player.betThisRound}), style: const TextStyle(color: Colors.amberAccent, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
