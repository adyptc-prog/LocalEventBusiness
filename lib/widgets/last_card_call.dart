import 'package:flutter/material.dart';

import '../l10n/tr.dart';

/// Opțiunea de a anunța ultima carte („Macao!" / „UNO!") odată cu mutarea
/// care te lasă cu o singură carte în mână.
class LastCardAnnounceChip extends StatelessWidget {
  final String word;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const LastCardAnnounceChip({super.key, required this.word, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(tr('lastCard.announceChip', {'word': word})),
      selected: selected,
      onSelected: onChanged,
      selectedColor: Colors.amberAccent,
      checkmarkColor: Colors.black,
      labelStyle: TextStyle(color: selected ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
      backgroundColor: Colors.white10,
    );
  }
}

/// Bara care apare cât timp cineva a rămas cu o carte fără să anunțe:
/// jucătorul vizat poate anunța încă, ceilalți îl pot prinde.
class LastCardCallBar extends StatelessWidget {
  final String word;
  final String myId;
  final String? unannouncedId;
  final String Function(String playerId) nameOf;
  final VoidCallback onAnnounce;
  final VoidCallback onCatch;

  const LastCardCallBar({
    super.key,
    required this.word,
    required this.myId,
    required this.unannouncedId,
    required this.nameOf,
    required this.onAnnounce,
    required this.onCatch,
  });

  @override
  Widget build(BuildContext context) {
    final target = unannouncedId;
    if (target == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: target == myId
          ? FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.amberAccent, foregroundColor: Colors.black),
              icon: const Icon(Icons.campaign),
              label: Text(tr('lastCard.announceNow', {'word': word})),
              onPressed: onAnnounce,
            )
          : OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.amberAccent,
                side: const BorderSide(color: Colors.amberAccent),
              ),
              icon: const Icon(Icons.pan_tool),
              label: Text(tr('lastCard.catch', {'name': nameOf(target), 'word': word})),
              onPressed: onCatch,
            ),
    );
  }
}
