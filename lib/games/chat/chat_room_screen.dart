import 'package:flutter/material.dart';

import '../../core/game_definition.dart';
import '../../widgets/chat_panel.dart';

/// Chat general — ecran plin, fără regulile unui joc, deschis oricui de pe
/// rețea se alătură camerei de chat (nu doar celor de la o masă).
class ChatRoomScreen extends StatelessWidget {
  final GameSessionArgs args;

  const ChatRoomScreen({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E2A47),
      appBar: AppBar(
        backgroundColor: const Color(0xFF091C31),
        title: const Text('Chat general'),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: 'Ieși din chat',
            onPressed: () {
              args.onLeave();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ChatPanel(
          myId: args.myId,
          stateStream: args.stateStream,
          initialSnapshot: args.initialSnapshot,
          chatStream: args.chatStream,
          onChat: args.onChat,
        ),
      ),
    );
  }
}
