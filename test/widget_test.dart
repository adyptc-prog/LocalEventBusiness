// Smoke test: meniul principal arată cardul de conectare la eveniment, iar
// biblioteca de jocuri filtrează corect după activitățile activate de
// organizator (`enabledGameIds`, vezi `EventMenuScreen`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_event_business/main.dart';
import 'package:local_event_business/screens/game_library_screen.dart';

void main() {
  testWidgets('Meniul principal are cardul de conectare la eveniment', (WidgetTester tester) async {
    await tester.pumpWidget(const MacaoApp());

    expect(find.text('LocalEventBusiness'), findsOneWidget);
    expect(find.text('Intră la eveniment'), findsOneWidget);
  });

  testWidgets('Biblioteca de jocuri arată doar jocurile activate de organizator', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: GameLibraryScreen(enabledGameIds: ['macao', 'war']),
    ));

    expect(find.text('Macao'), findsOneWidget);
    expect(find.text('Război'), findsOneWidget);
    expect(find.text('Poker'), findsNothing);
  });
}
