import 'dart:async';

import 'package:flutter/material.dart';

import '../core/chat_message.dart';
import '../l10n/tr.dart';

/// Chat live al camerei curente: mesaje publice (toți jucătorii) sau
/// private (1-la-1, alese dintr-un selector de destinatar). Presupune o
/// sesiune conectată — ecranul care îl folosește decide ce afișează în
/// locul lui când nu există nicio cameră activă.
class ChatPanel extends StatefulWidget {
  final String myId;
  final Stream<Map<String, dynamic>> stateStream;
  final Map<String, dynamic>? initialSnapshot;
  final Stream<ChatMessage> chatStream;
  final void Function(String text, {String? toId}) onChat;

  const ChatPanel({
    super.key,
    required this.myId,
    required this.stateStream,
    required this.initialSnapshot,
    required this.chatStream,
    required this.onChat,
  });

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription? _stateSub;
  StreamSubscription? _chatSub;
  List<Map<String, dynamic>> _players = [];
  final List<ChatMessage> _messages = [];
  String? _selectedTargetId;

  @override
  void initState() {
    super.initState();
    _players = _playersFrom(widget.initialSnapshot);
    _stateSub = widget.stateStream.listen((snap) {
      if (!mounted) return;
      setState(() => _players = _playersFrom(snap));
    });
    _chatSub = widget.chatStream.listen((msg) {
      if (!mounted) return;
      setState(() => _messages.add(msg));
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    });
  }

  List<Map<String, dynamic>> _playersFrom(Map<String, dynamic>? snap) => (snap?['players'] as List<dynamic>? ?? const [])
      .map((p) => Map<String, dynamic>.from(p as Map))
      .where((p) => p['id'] != widget.myId)
      .toList();

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _chatSub?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    widget.onChat(text, toId: _selectedTargetId);
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    // dacă destinatarul selectat a plecat din cameră, revenim la public
    if (_selectedTargetId != null && !_players.any((p) => p['id'] == _selectedTargetId)) {
      _selectedTargetId = null;
    }

    return Column(
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              _TargetChip(
                label: tr('chat.public'),
                selected: _selectedTargetId == null,
                onTap: () => setState(() => _selectedTargetId = null),
              ),
              for (final p in _players)
                _TargetChip(
                  label: p['name'] as String? ?? '?',
                  selected: _selectedTargetId == p['id'],
                  onTap: () => setState(() => _selectedTargetId = p['id'] as String),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Text(tr('chat.emptyHint'), style: const TextStyle(color: Colors.white38)),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) => _MessageBubble(message: _messages[index], myId: widget.myId),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: _selectedTargetId == null ? tr('chat.hintPublic') : tr('chat.hintPrivate'),
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white10,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(icon: const Icon(Icons.send), onPressed: _send),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TargetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TargetChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        labelStyle: TextStyle(color: selected ? Colors.black : Colors.white70, fontSize: 12),
        backgroundColor: Colors.white10,
        selectedColor: Colors.amberAccent,
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String myId;

  const _MessageBubble({required this.message, required this.myId});

  @override
  Widget build(BuildContext context) {
    final isMine = message.fromId == myId;
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleColor = isMine ? Colors.amber.shade700 : Colors.white12;
    final textColor = isMine ? Colors.black : Colors.white;

    String? tag;
    if (message.isPrivate) {
      tag = isMine ? tr('chat.privateTo', {'name': message.toName ?? '...'}) : tr('chat.private');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (!isMine)
            Padding(
              padding: const EdgeInsets.only(left: 10, bottom: 2),
              child: Text(message.displayName, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ),
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: bubbleColor, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tag != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(tag, style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 10)),
                  ),
                Text(message.text, style: TextStyle(color: textColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
