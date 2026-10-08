import 'package:flutter/material.dart';

import 'core/event_config_store.dart';
import 'core/leaderboard_store.dart';
import 'core/menu_store.dart';
import 'core/organizer_key_store.dart';
import 'core/player_profile.dart';
import 'core/table_config_store.dart';
import 'network/event_server_runner.dart';
import 'screens/main_menu_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inițializează portul de comunicare cu foreground service-ul serverului
  // de eveniment (dacă rulează deja dintr-o sesiune anterioară, se
  // reatașează la el) — trebuie apelat înainte de `runApp`.
  EventServerRunner.initCommunicationPort();
  await PlayerProfileStore.instance.init();
  await LeaderboardStore.instance.init();
  await EventConfigStore.instance.init();
  await MenuStore.instance.init();
  await OrganizerKeyStore.instance.init();
  await TableConfigStore.instance.init();
  runApp(const MacaoApp());
}

class MacaoApp extends StatelessWidget {
  const MacaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LocalEventBusiness',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B5E3B), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const MainMenuScreen(),
    );
  }
}
