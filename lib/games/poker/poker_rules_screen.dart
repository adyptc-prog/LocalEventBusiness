import 'package:flutter/material.dart';

import 'poker_engine.dart';

/// Regulile complete de Texas Hold'em, așa cum sunt implementate în acest
/// joc — deschis din butonul „i” din bara de sus a mesei de poker.
class PokerRulesScreen extends StatelessWidget {
  const PokerRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10331F),
      appBar: AppBar(backgroundColor: const Color(0xFF092013), title: const Text('Regulile jocului')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: const [
            _Section(
              title: 'Fise și mize',
              body:
                  'Fiecare jucător pornește cu ${PokerEngine.startingStack} de fise. Mizele sunt fixe: '
                  '${PokerEngine.smallBlind} mica miză, ${PokerEngine.bigBlind} marea miză, pe toată durata jocului. '
                  'Se joacă mâini succesive — dealerul (și mizele) se rotesc la fiecare mână — '
                  'până rămâne un singur jucător cu fise: acela câștigă masa.',
            ),
            _Section(
              title: 'O mână, pas cu pas',
              body:
                  '1. Cei doi din stânga dealerului pun mica și marea miză.\n'
                  '2. Fiecare primește 2 cărți în mână (Preflop) — urmează prima rundă de pariere.\n'
                  '3. Se deschid 3 cărți comune pe masă (Flop) — a doua rundă de pariere.\n'
                  '4. Se deschide a 4-a carte comună (Turn) — a treia rundă.\n'
                  '5. Se deschide a 5-a carte comună (River) — ultima rundă.\n'
                  '6. Showdown: cine n-a renunțat își arată cărțile — câștigă cea mai bună '
                  'combinație de 5 cărți, formată din cele 2 din mână și cele 5 de pe masă.',
            ),
            _Section(
              title: 'Acțiunile posibile',
              body:
                  '• Fold — renunți la mână, pierzi ce ai pus până acum.\n'
                  '• Check — treci, fără să adaugi fise (doar dacă nimeni n-a pariat încă în runda asta).\n'
                  '• Call — egalezi pariul curent.\n'
                  '• Raise — ridici pariul (minim cât ultima ridicare).\n'
                  '• All-in — pui tot ce ai. Dacă ai mai puține fise decât restul, se formează '
                  'un pot secundar — poți câștiga doar din potul la care ai contribuit.',
            ),
            _Section(
              title: 'Combinațiile de cărți (de la cea mai mare)',
              body:
                  '1. Chintă royală — 10-J-Q-K-A, aceeași culoare\n'
                  '2. Chintă culoare — 5 cărți consecutive, aceeași culoare\n'
                  '3. Careu — 4 cărți de aceeași valoare\n'
                  '4. Full — trei la fel + o pereche\n'
                  '5. Culoare — 5 cărți de aceeași culoare (nu neapărat consecutive)\n'
                  '6. Chintă — 5 cărți consecutive (culori diferite; Asul poate fi și cel mai mic, în A-2-3-4-5)\n'
                  '7. Trei la fel — 3 cărți de aceeași valoare\n'
                  '8. Două perechi\n'
                  '9. O pereche\n'
                  '10. Cartea mare — dacă nimeni nu are nimic din de mai sus, câștigă cartea cea mai mare',
            ),
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
