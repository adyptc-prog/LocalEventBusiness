// Motorul de traducere: integritatea dicționarului (verificată pe codul
// sursă), comportamentul la rulare și schimbarea limbii din UI.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_event_business/core/activity_catalog.dart';
import 'package:local_event_business/games/rent/rent_categories.dart';
import 'package:local_event_business/l10n/strings.dart';
import 'package:local_event_business/l10n/tr.dart';
import 'package:local_event_business/main.dart';
import 'package:local_event_business/network/event_server_service_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/server_harness.dart';

final _placeholder = RegExp(r'\{(\w+)\}');

Set<String> _placeholders(String s) => _placeholder.allMatches(s).map((m) => m.group(1)!).toSet();

/// Toate cheile literale folosite în `lib/` prin `tr`, `trIn`, `GameError`,
/// `LocalizedText` sau `_sendError`.
Map<String, String> _keysUsedInSource() {
  final call = RegExp(r"""(?:\btr|\btrIn\([^,]+,|GameError|LocalizedText|_sendError\([^,]+,)\(?\s*'([a-zA-Z_][\w.]*)'""");
  final used = <String, String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.replaceAll('\\', '/').contains('lib/l10n/strings')) continue;
    final source = entity.readAsStringSync();
    for (final m in call.allMatches(source)) {
      used[m.group(1)!] = entity.path;
    }
  }
  return used;
}

void main() {
  tearDown(() => LanguageController.instance.debugSetLanguage(AppLanguage.ro));

  group('dicționar', () {
    test('nicio cheie nu apare în două tabele', () {
      final seen = <String>{};
      final duplicates = <String>[];
      for (final table in stringTables) {
        for (final key in table.keys) {
          if (!seen.add(key)) duplicates.add(key);
        }
      }
      expect(duplicates, isEmpty);
    });

    test('fiecare intrare are ambele limbi completate, cu aceleași placeholder-e', () {
      final problems = <String>[];
      allStrings.forEach((key, value) {
        final (ro, en) = value;
        if (ro.trim().isEmpty || en.trim().isEmpty) problems.add('$key: traducere goală');
        if (_placeholders(ro).difference(_placeholders(en)).isNotEmpty ||
            _placeholders(en).difference(_placeholders(ro)).isNotEmpty) {
          problems.add('$key: {${_placeholders(ro).join(',')}} ≠ {${_placeholders(en).join(',')}}');
        }
      });
      expect(problems, isEmpty);
    });

    test('fiecare cheie folosită în cod există în dicționar', () {
      final used = _keysUsedInSource();
      expect(used.length, greaterThan(300), reason: 'scanarea surselor a găsit prea puține chei');
      final missing = [
        for (final entry in used.entries)
          if (!allStrings.containsKey(entry.key)) '${entry.key}  (${entry.value})',
      ];
      expect(missing, isEmpty);
    });

    test('cheile construite dinamic există: titluri de activități și categorii Rentz', () {
      for (final activity in activityCatalog) {
        expect(allStrings, contains('game.${activity.id}.title'));
        expect(allStrings, contains('game.${activity.id}.subtitle'));
      }
      for (final category in kRentCategories) {
        expect(allStrings, contains('rent.category.$category'));
      }
    });
  });

  group('la rulare', () {
    test('tr traduce în limba curentă și înlocuiește argumentele', () {
      LanguageController.instance.debugSetLanguage(AppLanguage.ro);
      expect(tr('rooms.roomSubtitle', {'players': 2, 'max': 4, 'code': 'K7QX'}), '2/4 jucători · cod K7QX');
      LanguageController.instance.debugSetLanguage(AppLanguage.en);
      expect(tr('rooms.roomSubtitle', {'players': 2, 'max': 4, 'code': 'K7QX'}), '2/4 players · code K7QX');
    });

    test('o cheie necunoscută se afișează ca atare, fără excepție', () {
      expect(tr('nu.exista.deloc'), 'nu.exista.deloc');
    });

    test('titlurile jocurilor urmează limba', () {
      final war = activityCatalog.firstWhere((a) => a.id == 'war');
      expect(war.title, 'Război');
      LanguageController.instance.debugSetLanguage(AppLanguage.en);
      expect(war.title, 'War');
      expect(war.playersLabel, '2 players');
    });

    test('LocalizedText: dus-întors prin JSON, plus text simplu de la un server vechi', () {
      const text = LocalizedText('uno.event.skipped', {'name': 'Ana'});
      final back = LocalizedText.fromJson(text.toJson())!;
      LanguageController.instance.debugSetLanguage(AppLanguage.en);
      expect(back.resolve(), 'Ana was skipped.');
      expect(LocalizedText.fromJson('text vechi')!.resolve(), 'text vechi');
      expect(LocalizedText.fromJson(42), isNull);
    });

    test('GameError păstrează cheia și are mesajul în română, indiferent de limba UI', () {
      LanguageController.instance.debugSetLanguage(AppLanguage.en);
      final e = GameError('err.roomFull', {'max': 6});
      expect(e.key, 'err.roomFull');
      expect(e.message, 'Camera este plină (maxim 6 jucători).');
      expect(e.text.resolve(), 'The room is full (max 6 players).');
    });
  });

  group('server', () {
    late EventServerService server;
    setUp(() async => server = await createTestServer());
    tearDown(() async => server.stop());

    test('erorile ajung la client ca cheie + argumente, cu text de rezervă în română', () async {
      final (host, _) = await createRoom(server, secret: 'secret-profil-l10n-0001');
      host.send({'type': 'chat', 'text': 'x' * (EventServerService.maxChatLength + 1)});
      await settle();
      final error = host.lastOfType('error')!;
      expect(error['messageKey'], 'err.chatTooLong');
      expect(error['messageArgs'], {'max': EventServerService.maxChatLength});
      expect(error['message'], contains('prea lung'));
    });

    test('erorile motoarelor de joc ajung și ele ca chei', () async {
      final (host, _) = await createRoom(server, secret: 'secret-profil-l10n-0002', gameId: 'poker');
      host.send({'type': 'start_game'});
      await settle();
      expect(host.lastOfType('error')?['messageKey'], 'err.playersRange');
    });
  });

  group('UI', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await LanguageController.instance.init();
    });

    testWidgets('butonul de limbă schimbă imediat textele, fără să părăsească ecranul', (tester) async {
      await tester.pumpWidget(const MacaoApp());
      expect(find.text('Intră la eveniment'), findsOneWidget);
      expect(find.text('RO'), findsOneWidget);

      await tester.tap(find.text('RO'));
      await tester.pumpAndSettle();
      expect(find.text('Join the event'), findsOneWidget);
      expect(find.text('Intră la eveniment'), findsNothing);
      expect(find.text('EN'), findsOneWidget);
      expect(LanguageController.instance.language, AppLanguage.en);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_language_v1'), 'en', reason: 'alegerea e persistată');

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      expect(find.text('Intră la eveniment'), findsOneWidget);
    });

    testWidgets('limba se schimbă și pe un ecran deschis deasupra meniului', (tester) async {
      await tester.pumpWidget(const MacaoApp());
      await tester.tap(find.text('Intră la eveniment'));
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);

      await tester.tap(find.text('RO'));
      await tester.pumpAndSettle();
      expect(find.text('Join the event'), findsOneWidget, reason: 'titlul ecranului curent');
      expect(find.byType(BackButton), findsOneWidget, reason: 'ruta a rămas deschisă');
    });
  });
}
