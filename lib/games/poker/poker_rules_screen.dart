import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../widgets/language_button.dart';
import 'poker_engine.dart';

/// Regulile complete de Texas Hold'em, așa cum sunt implementate în acest
/// joc — deschis din butonul „i” din bara de sus a mesei de poker.
class PokerRulesScreen extends StatelessWidget {
  const PokerRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10331F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF092013),
        title: Text(tr('poker.rules')),
        actions: const [LanguageButton()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _Section(
              title: tr('poker.rules.chips.title'),
              body: tr('poker.rules.chips.body', {
                'stack': PokerEngine.startingStack,
                'small': PokerEngine.smallBlind,
                'big': PokerEngine.bigBlind,
              }),
            ),
            _Section(title: tr('poker.rules.hand.title'), body: tr('poker.rules.hand.body')),
            _Section(title: tr('poker.rules.actions.title'), body: tr('poker.rules.actions.body')),
            _Section(title: tr('poker.rules.combos.title'), body: tr('poker.rules.combos.body')),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;

  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.amberAccent, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(color: Colors.white70, height: 1.4)),
        ],
      ),
    );
  }
}
