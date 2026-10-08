import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../models/card.dart';
import '../../screens/leaderboard_screen.dart';
import '../../widgets/playing_card_widget.dart';
import 'macao_snapshot.dart';
import 'opponent_widget.dart';
import 'suit_picker_dialog.dart';

class MacaoGameScreen extends StatefulWidget {
  final GameSessionArgs args;

  const MacaoGameScreen({super.key, required this.args});

  @override
  State<MacaoGameScreen> createState() => _MacaoGameScreenState();
}

class _MacaoGameScreenState extends State<MacaoGameScreen> {
  late MacaoSnapshot _snapshot;
  late Map<String, dynamic> _rawSnapshot;
  StreamSubscription? _stateSub;
  StreamSubscription? _errorSub;
  bool _winnerDialogShown = false;

  /// Cărțile alese pentru a fi jucate deodată — toate trebuie să aibă
  /// aceeași valoare; se joacă efectiv doar la apăsarea „Joacă”.
  final Set<PlayingCard> _selectedCards = {};

  @override
  void initState() {
    super.initState();
    _rawSnapshot = widget.args.initialSnapshot;
    _snapshot = MacaoSnapshot.fromJson(_rawSnapshot);
    _stateSub = widget.args.stateStream.listen((json) {
      if (!mounted) return;
      setState(() {
        _rawSnapshot = json;
        _snapshot = MacaoSnapshot.fromJson(json);
        if (!_snapshot.isMyTurn) _selectedCards.clear();
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
          title: Text(isMe ? 'Ai câștigat! 🎉' : 'Joc terminat'),
          content: Text('${_snapshot.winnerName} a scăpat primul de cărți.'),
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

  /// O carte poate fi adăugată la selecție dacă e prima (deci trebuie să fie
  /// jucabilă normal) sau dacă are aceeași valoare cu ce e deja selectat —
  /// cărțile de aceeași valoare se pot juca toate deodată, într-o mutare.
  bool _isSelectable(PlayingCard card) {
    if (!_snapshot.isMyTurn) return false;
    if (_selectedCards.isEmpty) return _snapshot.isCardPlayable(card);
    return card.rank == _selectedCards.first.rank;
  }

  void _toggleCard(PlayingCard card) {
    if (_selectedCards.contains(card)) {
      setState(() => _selectedCards.remove(card));
      return;
    }
    if (!_isSelectable(card)) return;
    setState(() => _selectedCards.add(card));
  }

  Future<void> _playSelected() async {
    if (_selectedCards.isEmpty) return;
    final cards = _selectedCards.toList();
    Suit? chosenSuit;
    if (cards.first.isWild) {
      chosenSuit = await showSuitPicker(context);
      if (chosenSuit == null) return;
    }
    widget.args.onAction({
      'type': 'play_card',
      'cards': cards.map((c) => c.toJson()).toList(),
      if (chosenSuit != null) 'chosenSuit': chosenSuit.name,
    });
    if (mounted) setState(() => _selectedCards.clear());
  }

  void _handleDrawTap() {
    widget.args.onAction({'type': 'draw_card'});
  }

  @override
  Widget build(BuildContext context) {
    final me = _snapshot.me;
    final opponents = _snapshot.opponents;

    return Scaffold(
      backgroundColor: const Color(0xFF0B5E3B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08462C),
        title: Text(_snapshot.isMyTurn ? 'Rândul tău' : 'Se joacă...'),
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
                    .map((p) => OpponentWidget(player: p, isCurrentTurn: p.id == _snapshot.currentPlayerId))
                    .toList(),
              ),
            ),
            const Spacer(),
            _buildTable(),
            const Spacer(),
            if (_snapshot.pendingDraw > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Trebuie tras ${_snapshot.pendingDraw} — sau răspunde cu un 2 sau 3 care se leagă la număr sau culoare!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold),
                ),
              ),
            if (_snapshot.pendingSkip > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _snapshot.isMyTurn
                      ? 'Trebuie să stai ${_snapshot.pendingSkip} tur(e) — sau răspunde cu o carte de 4!'
                      : 'Așteaptă să stea ${_snapshot.pendingSkip} tur(e) sau să răspundă cu un 4.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold),
                ),
              ),
            Text(me.name, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            _buildHand(me.hand ?? const []),
            const SizedBox(height: 8),
            if (_selectedCards.isNotEmpty) _buildPlayBar(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildHand(List<PlayingCard> cards) {
    if (cards.isEmpty) return const SizedBox(height: 96);
    return SizedBox(
      height: 108,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: cards.map((card) {
          final selected = _selectedCards.contains(card);
          final selectable = selected || _isSelectable(card);
          return PlayingCardWidget(
            card: card,
            enabled: selectable,
            selected: selected,
            width: 70,
            onTap: () => _toggleCard(card),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPlayBar() {
    return SizedBox(
      width: 220,
      child: FilledButton.icon(
        icon: const Icon(Icons.style),
        label: Text(_selectedCards.length == 1 ? 'Joacă' : 'Joacă ${_selectedCards.length} cărți'),
        onPressed: _playSelected,
      ),
    );
  }

  Widget _buildTable() {
    final canDraw = _snapshot.isMyTurn;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: canDraw ? _handleDrawTap : null,
          child: Column(
            children: [
              Opacity(opacity: canDraw ? 1 : 0.6, child: const CardBackWidget(width: 70)),
              const SizedBox(height: 4),
              Text('${_snapshot.drawPileCount}', style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(width: 28),
        Column(
          children: [
            if (_snapshot.discardTop != null)
              PlayingCardWidget(card: _snapshot.discardTop!, width: 70)
            else
              const SizedBox(width: 70, height: 98),
            const SizedBox(height: 4),
            Text(
              _snapshot.requestedSuit == null ? '' : 'Culoare: ${_snapshot.requestedSuit!.symbol}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ],
    );
  }
}
