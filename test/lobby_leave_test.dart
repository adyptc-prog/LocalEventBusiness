// Ieșirea dintr-un joc pornit: butonul Înapoi al telefonului trebuie să anunțe
// serverul (altfel camera rămâne „în desfășurare” cu jucătorul atașat), iar
// butonul „Ieși din joc” nu trebuie să-l anunțe de două ori.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_event_business/core/chat_message.dart';
import 'package:local_event_business/core/game_definition.dart';
import 'package:local_event_business/screens/lobby_screen.dart';

const _leaveKey = Key('iesi');

final _definition = GameDefinition(
  id: 'raffle',
  icon: Icons.celebration,
  accentColor: Colors.black,
  minPlayers: 1,
  maxPlayers: 10,
  createEngine: () => throw UnimplementedError(),
  buildGameScreen: (context, args) => Scaffold(
    appBar: AppBar(),
    body: TextButton(
      key: _leaveKey,
      onPressed: () {
        args.onLeave();
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
      child: const Text('Ieși'),
    ),
  ),
);

Future<(StreamController<Map<String, dynamic>>, List<int>)> _openStartedGame(WidgetTester tester) async {
  final states = StreamController<Map<String, dynamic>>.broadcast();
  final leaves = <int>[];
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LobbyScreen(
            definition: _definition,
            roomName: 'Camera',
            isHost: true,
            myId: 'p1',
            stateStream: states.stream,
            initialSnapshot: const {'started': false, 'players': []},
            onAction: (_) {},
            onLeave: () => leaves.add(1),
            chatStream: const Stream<ChatMessage>.empty(),
            onChat: (_, {toId}) {},
          ),
        )),
        child: const Text('Deschide'),
      ),
    ),
  ));
  await tester.tap(find.text('Deschide'));
  await tester.pumpAndSettle();
  states.add({'started': true, 'players': []});
  await tester.pumpAndSettle();
  expect(find.byKey(_leaveKey), findsOneWidget);
  return (states, leaves);
}

void main() {
  testWidgets('Înapoi din ecranul de joc anunță serverul', (tester) async {
    final (states, leaves) = await _openStartedGame(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Deschide'), findsOneWidget);
    expect(leaves, hasLength(1));
    await states.close();
  });

  testWidgets('„Ieși din joc” anunță serverul o singură dată', (tester) async {
    final (states, leaves) = await _openStartedGame(tester);
    await tester.tap(find.byKey(_leaveKey));
    await tester.pumpAndSettle();
    expect(find.text('Deschide'), findsOneWidget);
    expect(leaves, hasLength(1));
    await states.close();
  });
}
