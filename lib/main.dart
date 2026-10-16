import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/event_config_store.dart';
import 'core/leaderboard_store.dart';
import 'core/license_service.dart';
import 'core/menu_store.dart';
import 'core/organizer_key_store.dart';
import 'core/player_profile.dart';
import 'core/qr_cards.dart';
import 'core/qr_cards_store.dart';
import 'l10n/tr.dart';
import 'network/event_server_runner.dart';
import 'screens/main_menu_screen.dart';
import 'screens/menu_connect_screen.dart';
import 'widgets/language_button.dart';
import 'widgets/license_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inițializează portul de comunicare cu foreground service-ul serverului
  // de eveniment (dacă rulează deja dintr-o sesiune anterioară, se
  // reatașează la el) — trebuie apelat înainte de `runApp`.
  EventServerRunner.initCommunicationPort();
  await LanguageController.instance.init();
  await PlayerProfileStore.instance.init();
  await LeaderboardStore.instance.init();
  await EventConfigStore.instance.init();
  await MenuStore.instance.init();
  await OrganizerKeyStore.instance.init();
  await QrCardsStore.instance.init();
  // Licența / proba (doar Android) — `LicenseGate` decide ce se afișează.
  await LicenseService.instance.refresh();
  runApp(const MacaoApp());
}

/// `true` când clientul web a fost deschis din codul QR de meniu de pe mese.
bool get openedFromQr => kIsWeb && openedFromMenuQr(Uri.base);

class MacaoApp extends StatelessWidget {
  const MacaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LanguageController.instance,
      builder: (context, _) => MaterialApp(
        title: 'LocalEventBusiness',
        locale: LanguageController.instance.language.locale,
        supportedLocales: [for (final l in AppLanguage.values) l.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => LanguageRebuilder(child: LicenseGate(child: child ?? const SizedBox.shrink())),
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: 'Roboto',
          fontFamilyFallback: const ['NotoSansSymbols2'],
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B5E3B), brightness: Brightness.dark),
          useMaterial3: true,
        ),
        // QR-ul de meniu de pe mese (`/?menu`) duce direct la meniu — invitatul
        // care l-a scanat vrea să comande, nu să aleagă din meniul principal.
        home: openedFromQr ? const MenuConnectScreen() : const MainMenuScreen(),
      ),
    );
  }
}
