import 'package:flutter/material.dart';

import '../models/card.dart';
import 'playing_card_widget.dart';

class HandWidget extends StatelessWidget {
  final List<PlayingCard> cards;
  final bool Function(PlayingCard) isPlayable;
  final void Function(PlayingCard) onCardTap;

  const HandWidget({
    super.key,
    required this.cards,
    required this.isPlayable,
    required this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const SizedBox(height: 96);
    }
    return SizedBox(
      height: 108,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: cards.map((card) {
          final playable = isPlayable(card);
          return PlayingCardWidget(
            card: card,
            enabled: playable,
            selected: playable,
            width: 70,
            onTap: () => onCardTap(card),
          );
        }).toList(),
      ),
    );
  }
}
