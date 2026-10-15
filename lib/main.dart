import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/event_config_store.dart';
import 'core/install_activation.dart';
import 'core/leaderboard_store.dart';
import 'core/menu_store.dart';
import 'core/organizer_key_store.dart';
import 'core/player_profile.dart';
import 'core/table_config_store.dart';
import 'l10n/tr.dart';
import 'network/event_server_runner.dart';
import 'screens/main_menu_screen.dart';
import 'screens/menu_connect_screen.dart';
import 'screens/not_activated_screen.dart';
import 'widgets/language_button.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Pe un telefon unde aplicația n-a fost instalată de organizator nu
  // pornește nimic altceva — nici serverul, nici restul ecranelor.
  if (!await InstallActivation.check()) {
    await LanguageController.instance.init();
    runApp(const NotActivatedApp());
    return;
  }
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
  await TableConfigStore.instance.init();
  runApp(const MacaoApp());
}

/// `true` când clientul web a fost deschis prin codul QR al unei mese.
bool get openedFromTableQr => kIsWeb && Uri.base.queryParameters.containsKey('table');

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
        builder: (context, child) => LanguageRebuilder(child: child ?? const SizedBox.shrink()),
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: 'Roboto',
          fontFamilyFallback: const ['NotoSansSymbols2'],
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B5E3B), brightness: Brightness.dark),
          useMaterial3: true,
        ),
        // Un QR de masă (`/?table=N`) duce direct la meniu — invitatul care l-a
        // scanat vrea să comande, nu să aleagă din meniul principal.
        home: openedFromTableQr ? const MenuConnectScreen() : const MainMenuScreen(),
      ),
    );
  }
}
