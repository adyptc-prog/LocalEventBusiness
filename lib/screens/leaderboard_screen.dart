import 'package:flutter/material.dart';

import '../core/chat_message.dart';
import '../core/games_registry.dart';
import '../core/leaderboard_store.dart';
import '../core/player_profile.dart';
import '../widgets/chat_panel.dart';

/// Clasament + chat. Fără parametri live (`myId`/`stateStream`/...): arată
/// doar istoricul persistat pe acest telefon (folosit din meniul principal,
/// unde nu ești conectat la nimeni). Cu parametri live (folosit din
/// lobby/ecranele de joc): adaugă un tab de chat conectat la camera curentă.
class LeaderboardScreen extends StatefulWidget {
  final String? myId;
  final Stream<Map<String, dynamic>>? stateStream;
  final Map<String, dynamic>? initialSnapshot;
  final Stream<ChatMessage>? chatStream;
  final void Function(String text, {String? toId})? onChat;

  const LeaderboardScreen({
    super.key,
    this.myId,
    this.stateStream,
    this.initialSnapshot,
    this.chatStream,
    this.onChat,
  });

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _nameController;

  bool get _hasLiveSession =>
      widget.myId != null && widget.stateStream != null && widget.chatStream != null && widget.onChat != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: PlayerProfileStore.instance.profile.name);
    _tabController = TabController(length: 1 + availableGames.length + (_hasLiveSession ? 1 : 0), vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(
        backgroundColor: Colors.black26,
        title: const Text('Clasament'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            const Tab(text: 'General'),
            for (final def in availableGames) Tab(text: def.title),
            if (_hasLiveSession) const Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Chat'),
          ],
        ),
      ),
      body: Column(
        children: [
          _ProfileHeader(nameController: _nameController),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                const _RankingList(gameId: null),
                for (final def in availableGames) _RankingList(gameId: def.id),
                if (_hasLiveSession)
                  ChatPanel(
                    myId: widget.myId!,
                    stateStream: widget.stateStream!,
                    initialSnapshot: widget.initialSnapshot,
                    chatStream: widget.chatStream!,
                    onChat: widget.onChat!,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final TextEditingController nameController;

  const _ProfileHeader({required this.nameController});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          const CircleAvatar(backgroundColor: Colors.white24, child: Icon(Icons.person, color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Numele tău',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
              onSubmitted: (v) => PlayerProfileStore.instance.updateName(v),
              onTapOutside: (_) => PlayerProfileStore.instance.updateName(nameController.text),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Sold', style: TextStyle(color: Colors.white38, fontSize: 11)),
              Text('${PlayerProfileStore.instance.profile.balance}',
                  style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RankingList extends StatelessWidget {
  final String? gameId;

  const _RankingList({required this.gameId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LeaderboardStore.instance,
      builder: (context, _) {
        final rankings = LeaderboardStore.instance.rankingsFor(gameId: gameId);
        if (rankings.isEmpty) {
          return const Center(
            child: Text('Nicio partidă înregistrată încă pe acest telefon.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white38)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: rankings.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final r = rankings[index];
            final isMe = PlayerProfileStore.instance.isMine(r.playerId);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? Colors.amber.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: isMe ? Border.all(color: Colors.amberAccent.withValues(alpha: 0.4)) : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text('${index + 1}',
                        style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.playerName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        Text('${r.matchesPlayed} partide · ${r.wins} victorii',
                            style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${r.totalScore} pct',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      if (r.stakeBalance != 0)
                        Text(r.stakeBalance > 0 ? '+${r.stakeBalance} miză' : '${r.stakeBalance} miză',
                            style: TextStyle(
                                color: r.stakeBalance > 0 ? Colors.lightGreenAccent : Colors.orangeAccent,
                                fontSize: 12)),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
