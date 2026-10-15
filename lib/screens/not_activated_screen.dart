import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/tr.dart';
import '../widgets/language_button.dart';
import '../widgets/version_badge.dart';

/// Aplicația pornită pe un telefon neactivat (vezi `InstallActivation`):
/// un singur ecran, fără nicio cale spre restul aplicației.
class NotActivatedApp extends StatelessWidget {
  const NotActivatedApp({super.key});

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
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B5E3B), brightness: Brightness.dark),
          useMaterial3: true,
        ),
        home: const NotActivatedScreen(),
      ),
    );
  }
}

class NotActivatedScreen extends StatelessWidget {
  const NotActivatedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: const [VersionBadge(), LanguageButton()],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 72, color: Colors.white54),
                const SizedBox(height: 20),
                Text(
                  tr('activation.title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  tr('activation.body'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
