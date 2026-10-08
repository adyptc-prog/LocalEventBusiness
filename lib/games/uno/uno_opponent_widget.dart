import 'package:flutter/material.dart';

import 'uno_card_widget.dart';
import 'uno_snapshot.dart';
import '../../l10n/tr.dart';

class UnoOpponentWidget extends StatelessWidget {
  final UnoPlayerSummary player;
  final bool isCurrentTurn;

  const UnoOpponentWidget({super.key, required this.player, required this.isCurrentTurn});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: isCurrentTurn ? Colors.amber.shade700.withValues(alpha: 0.85) : Colors.black26,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!player.connected)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.wifi_off, size: 14, color: Colors.white70),
                ),
              if (player.handCount == 1)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.priority_high, size: 14, color: Colors.redAccent),
                ),
              Text(
                player.name,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: isCurrentTurn ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const UnoCardBackWidget(width: 30),
          const SizedBox(height: 2),
          Text(tr('game.cardsCount', {'n': player.handCount}), style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
