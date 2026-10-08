import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../models/card.dart';
import '../../screens/leaderboard_screen.dart';
import '../../widgets/hand_widget.dart';
import '../../widgets/playing_card_widget.dart';
import 'rent_categories.dart';
import 'rent_scoresheet_screen.dart';
import 'rent_snapshot.dart';
import '../../l10n/tr.dart';
import '../../widgets/language_button.dart';

class RentGameScreen extends StatefulWidget {
  final GameSessionArgs args;

  const RentGameScreen({super.key, required this.args});

  @override
  State<RentGameScreen> createState() => _RentGameScreenState();
}

class _RentGameScreenState extends State<RentGameScreen> {
  late RentSnapshot _snapshot;
  late Map<String, dynamic> _rawSnapshot;
  StreamSubscription? _stateSub;
  StreamSubscription? _errorSub;
  bool _winnerDialogShown = false;

  @override
  void initState() {
    super.initState();
    _rawSnapshot = widget.args.initialSnapshot;
    _snapshot = RentSnapshot.fromJson(_rawSnapshot);
    _stateSub = widget.args.stateStream.listen((json) {
      if (!mounted) return;
      setState(() {
        _rawSnapshot = json;
        _snapshot = RentSnapshot.fromJson(json);
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
    final title = _snapshot.isDraw ? tr('game.draw') : (isMe ? tr('game.youWon') : tr('game.over'));
    final content = _snapshot.isDraw
        ? tr('game.drawWithScore', {'score': myScore})
        : (isMe
            ? tr('game.wonWithScore', {'score': myScore})
            : tr('game.theyWonYouScored', {'name': _snapshot.winnerName(widget.args.myId) ?? tr('war.opponentThe'), 'score': myScore}));
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
                MaterialPageRoute(builder: (context) => RentScoresheetScreen(snapshot: _snapshot, myId: widget.args.myId)),
              ),
              child: Text(tr('game.viewScoresheet')),
            ),
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

  void _chooseCategory(String category) {
    widget.args.onAction({'type': 'choose_category', 'category': category});
  }

  void _playCard(PlayingCard card) {
    final isMyTurn = _snapshot.isMyTurn(widget.args.myId);
    if (!isMyTurn || !_snapshot.isCardPlayable(card)) return;
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
    final activeCategory = _snapshot.activeCategory;
    final categoryLabel = activeCategory == null ? tr('rent.chooseCategoryTitle') : rentCategoryLabel(activeCategory);

    return Scaffold(
      backgroundColor: const Color(0xFF3A1F1F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF241010),
        title: Text(categoryLabel),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_chart),
            tooltip: tr('game.scoresheet'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => RentScoresheetScreen(snapshot: _snapshot, myId: widget.args.myId)),
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
            _buildScoreRow(),
            const Divider(height: 1, color: Colors.white24),
            Expanded(
              child: _snapshot.choosingCategory
                  ? _buildCategoryPicker()
                  : (_snapshot.isRentCategory ? _buildRentArea() : _buildTrickArea(isMyTurn)),
            ),
            if (!_snapshot.choosingCategory) ...[
              Text(tr('war.you'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
              HandWidget(
                cards: _snapshot.myHand,
                isPlayable: (card) => isMyTurn && _snapshot.isCardPlayable(card),
                onCardTap: _playCard,
              ),
              const SizedBox(height: 8),
            ],
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
          final isTurn = p.id == _snapshot.currentPlayerId || (_snapshot.choosingCategory && p.id == _snapshot.chooserId);
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
                Text(tr('game.cardsCount', {'n': p.handCount}), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                Text(tr('leaderboard.points', {'n': score}), style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCategoryPicker() {
    final isMyChoice = _snapshot.isMyTurnToChoose(widget.args.myId);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isMyChoice) ...[
            Text(tr('rent.chooseCategory'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _snapshot.availableCategories)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
                    onPressed: () => _chooseCategory(c),
                    child: Text(rentCategoryLabel(c)),
                  ),
              ],
            ),
          ] else
            Text(tr('rent.isChoosing', {'name': _nameOf(_snapshot.chooserId)}), style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 20),
          Text(
            tr('rent.played', {'list': _snapshot.usedCategories.map((c) => rentCategoryLabel(c)).join(', ').ifEmpty('—')}),
            style: const TextStyle(color: Colors.white38, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTrickArea(bool isMyTurn) {
    final trick = _snapshot.currentTrick.isNotEmpty ? _snapshot.currentTrick : (_snapshot.lastTrick ?? const []);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
            child: Text(tr('whist.tookTrick', {'name': _nameOf(_snapshot.lastTrickWinnerId)}),
                style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
          ),
        if (!isMyTurn)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(tr('game.isPlaying', {'name': _nameOf(_snapshot.currentPlayerId)}), style: const TextStyle(color: Colors.white54)),
          ),
      ],
    );
  }

  Widget _buildRentArea() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final suit in Suit.values) _buildSequenceRow(suit),
          const SizedBox(height: 12),
          if (_snapshot.rentFinishOrder.isNotEmpty)
            Text(
              tr('rent.finished', {'list': _snapshot.rentFinishOrder.map(_nameOf).join(' > ')}),
              style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 8),
          if (_snapshot.currentPlayerId != null && _snapshot.currentPlayerId != widget.args.myId)
            Text(tr('game.isPlaying', {'name': _nameOf(_snapshot.currentPlayerId)}), style: const TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildSequenceRow(Suit suit) {
    final cards = _snapshot.rentSequences[suit] ?? const <PlayingCard>[];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text(suit.symbol, style: TextStyle(color: suit.isRed ? Colors.redAccent : Colors.white, fontSize: 20))),
          const SizedBox(width: 8),
          Expanded(
            child: cards.isEmpty
                ? Text(tr('rent.notOpened'), style: const TextStyle(color: Colors.white24))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: cards.map((c) => PlayingCardWidget(card: c, width: 40)).toList()),
                  ),
          ),
        ],
      ),
    );
  }
}

extension _StringOrEmpty on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
