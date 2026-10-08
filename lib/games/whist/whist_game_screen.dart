import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../models/card.dart';
import '../../screens/leaderboard_screen.dart';
import '../../widgets/hand_widget.dart';
import '../../widgets/playing_card_widget.dart';
import 'whist_scoresheet_screen.dart';
import 'whist_snapshot.dart';

class WhistGameScreen extends StatefulWidget {
  final GameSessionArgs args;

  const WhistGameScreen({super.key, required this.args});

  @override
  State<WhistGameScreen> createState() => _WhistGameScreenState();
}

class _WhistGameScreenState extends State<WhistGameScreen> {
  late WhistSnapshot _snapshot;
  late Map<String, dynamic> _rawSnapshot;
  StreamSubscription? _stateSub;
  StreamSubscription? _errorSub;
  bool _winnerDialogShown = false;

  @override
  void initState() {
    super.initState();
    _rawSnapshot = widget.args.initialSnapshot;
    _snapshot = WhistSnapshot.fromJson(_rawSnapshot);
    _stateSub = widget.args.stateStream.listen((json) {
      if (!mounted) return;
      setState(() {
        _rawSnapshot = json;
        _snapshot = WhistSnapshot.fromJson(json);
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
    final myScore = _snapshot.cumulativeScores[widget.args.myId] ?? 0;
    final title = _snapshot.isDraw ? 'Egalitate!' : (isMe ? 'Ai câștigat! 🎉' : 'Joc terminat');
    final content = _snapshot.isDraw
        ? 'Ai terminat la egalitate, cu $myScore puncte.'
        : (isMe
            ? 'Ai câștigat cu $myScore puncte.'
            : '${_snapshot.winnerName(widget.args.myId) ?? 'Adversarul'} a câștigat. Tu ai terminat cu $myScore puncte.');
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
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => WhistScoresheetScreen(snapshot: _snapshot, myId: widget.args.myId)),
              ),
              child: const Text('Vezi tabelul'),
            ),
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

  void _declareBid(int amount) {
    widget.args.onAction({'type': 'declare_bid', 'amount': amount});
  }

  void _playCard(PlayingCard card) {
    if (!_snapshot.isMyTurn(widget.args.myId) || _snapshot.isBidding) return;
    if (!_snapshot.isCardPlayable(card)) return;
    widget.args.onAction({'type': 'play_card', 'card': card.toJson()});
  }

  String _nameOf(String? playerId) {
    if (playerId == null) return '';
    final matches = _snapshot.players.where((p) => p.id == playerId);
    return matches.isEmpty ? '?' : matches.first.name;
  }

  @override
  Widget build(BuildContext context) {
    final isMyTurn = _snapshot.isMyTurn(widget.args.myId);

    return Scaffold(
      backgroundColor: const Color(0xFF213A2B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF152719),
        title: Text('Runda ${_snapshot.roundNumber}/${_snapshot.totalRounds} — mână de ${_snapshot.handSize}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_chart),
            tooltip: 'Tabel',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => WhistScoresheetScreen(snapshot: _snapshot, myId: widget.args.myId)),
            ),
          ),
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
            _buildScoreRow(),
            const Divider(height: 1, color: Colors.white24),
            Expanded(
              child: _snapshot.isBidding ? _buildBiddingArea(isMyTurn) : _buildTrickArea(isMyTurn),
            ),
            Text('Tu', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            HandWidget(
              cards: _snapshot.myHand,
              isPlayable: (card) => !_snapshot.isBidding && isMyTurn && _snapshot.isCardPlayable(card),
              onCardTap: _playCard,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        children: _snapshot.players.map((p) {
          final isTurn = p.id == _snapshot.currentPlayerId;
          final taken = _snapshot.tricksWonThisRound[p.id] ?? 0;
          final bid = _snapshot.bids[p.id];
          final score = _snapshot.cumulativeScores[p.id] ?? 0;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isTurn ? Colors.amber.shade700.withValues(alpha: 0.85) : Colors.black26,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                Text(
                  bid == null ? '$taken luate' : '$taken/$bid luate',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                Text('$score pct', style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBiddingArea(bool isMyTurn) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_snapshot.trumpCard != null) ...[
            const Text('Atu', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 4),
            PlayingCardWidget(card: _snapshot.trumpCard!, width: 64),
          ] else
            const Text('Fără atu — câștigă cea mai mare carte', style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 20),
          if (isMyTurn) ...[
            const Text('Câte levate crezi că iei?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i <= _snapshot.handSize; i++)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
                    onPressed: () => _declareBid(i),
                    child: Text('$i'),
                  ),
              ],
            ),
          ] else
            Text('${_nameOf(_snapshot.currentPlayerId)} licitează...', style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildTrickArea(bool isMyTurn) {
    final trick = _snapshot.currentTrick.isNotEmpty ? _snapshot.currentTrick : (_snapshot.lastTrick ?? const []);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_snapshot.trumpCard != null)
          Text('Atu: ${_snapshot.trumpCard!.suit.symbol}', style: const TextStyle(color: Colors.white70))
        else
          const Text('Fără atu', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: trick
              .map((tc) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_nameOf(tc.playerId), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 2),
                      PlayingCardWidget(card: tc.card, width: 56),
                    ],
                  ))
              .toList(),
        ),
        if (_snapshot.currentTrick.isEmpty && _snapshot.lastTrickWinnerId != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('${_nameOf(_snapshot.lastTrickWinnerId)} a luat levata',
                style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
          ),
        if (!isMyTurn)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('${_nameOf(_snapshot.currentPlayerId)} joacă...', style: const TextStyle(color: Colors.white54)),
          ),
      ],
    );
  }
}
