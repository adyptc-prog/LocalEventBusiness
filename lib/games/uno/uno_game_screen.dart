import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../screens/leaderboard_screen.dart';
import 'color_picker_dialog.dart';
import 'uno_card.dart';
import 'uno_card_widget.dart';
import 'uno_opponent_widget.dart';
import 'uno_snapshot.dart';
import '../../l10n/tr.dart';
import '../../widgets/language_button.dart';

class UnoGameScreen extends StatefulWidget {
  final GameSessionArgs args;

  const UnoGameScreen({super.key, required this.args});

  @override
  State<UnoGameScreen> createState() => _UnoGameScreenState();
}

class _UnoGameScreenState extends State<UnoGameScreen> {
  late UnoSnapshot _snapshot;
  late Map<String, dynamic> _rawSnapshot;
  StreamSubscription? _stateSub;
  StreamSubscription? _errorSub;
  bool _winnerDialogShown = false;

  @override
  void initState() {
    super.initState();
    _rawSnapshot = widget.args.initialSnapshot;
    _snapshot = UnoSnapshot.fromJson(_rawSnapshot);
    _stateSub = widget.args.stateStream.listen((json) {
      if (!mounted) return;
      setState(() {
        _rawSnapshot = json;
        _snapshot = UnoSnapshot.fromJson(json);
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
    if (_winnerDialogShown || _snapshot.winnerName == null) return;
    _winnerDialogShown = true;
    final isMe = _snapshot.winnerId == _snapshot.viewerId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(isMe ? tr('game.youWon') : tr('game.over')),
          content: Text(tr('macao.winner', {'name': _snapshot.winnerName})),
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

  Future<void> _playCard(UnoCard card) async {
    if (!_snapshot.isCardPlayable(card)) return;
    UnoColor? chosenColor;
    if (card.isWild) {
      chosenColor = await showColorPicker(context);
      if (chosenColor == null) return;
    }
    widget.args.onAction({
      'type': 'play_card',
      'card': card.toJson(),
      if (chosenColor != null) 'chosenColor': chosenColor.name,
    });
  }

  void _handleDrawTap() {
    widget.args.onAction({'type': 'draw_card'});
  }

  void _handlePassTap() {
    widget.args.onAction({'type': 'pass_turn'});
  }

  @override
  Widget build(BuildContext context) {
    final me = _snapshot.me;
    final opponents = _snapshot.opponents;
    final canPass = _snapshot.isMyTurn && _snapshot.hasDrawnThisTurn;

    return Scaffold(
      backgroundColor: const Color(0xFF1B1B2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121F),
        title: Text(_snapshot.isMyTurn ? tr('game.yourTurn') : tr('game.playing')),
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
                    .map((p) => UnoOpponentWidget(player: p, isCurrentTurn: p.id == _snapshot.currentPlayerId))
                    .toList(),
              ),
            ),
            const Spacer(),
            if (_snapshot.lastEventMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _snapshot.lastEventMessage!.resolve(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold),
                ),
              ),
            const SizedBox(height: 8),
            _buildTable(),
            const Spacer(),
            if (canPass)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
                  onPressed: _handlePassTap,
                  child: Text(tr('uno.pass')),
                ),
              ),
            Text(me.name, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            _buildHand(_snapshot.myHand),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildHand(List<UnoCard> cards) {
    if (cards.isEmpty) return const SizedBox(height: 96);
    return SizedBox(
      height: 108,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: cards.map((card) {
          final playable = _snapshot.isCardPlayable(card);
          return UnoCardWidget(
            card: card,
            enabled: playable,
            selected: playable,
            width: 70,
            onTap: () => _playCard(card),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTable() {
    final canDraw = _snapshot.isMyTurn && !_snapshot.hasDrawnThisTurn;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: canDraw ? _handleDrawTap : null,
          child: Column(
            children: [
              Opacity(opacity: canDraw ? 1 : 0.6, child: const UnoCardBackWidget(width: 70)),
              const SizedBox(height: 4),
              Text('${_snapshot.drawPileCount}', style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(width: 28),
        Column(
          children: [
            if (_snapshot.discardTop != null)
              UnoCardWidget(card: _snapshot.discardTop!, width: 70)
            else
              const SizedBox(width: 70, height: 98),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_snapshot.activeColor != null)
                  Container(
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(color: colorFor(_snapshot.activeColor!), shape: BoxShape.circle),
                  ),
                Icon(
                  _snapshot.direction == 1 ? Icons.rotate_right : Icons.rotate_left,
                  color: Colors.white54,
                  size: 16,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
