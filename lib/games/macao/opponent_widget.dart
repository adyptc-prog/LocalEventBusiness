import 'package:flutter/material.dart';

import '../../widgets/playing_card_widget.dart';
import 'macao_snapshot.dart';

class OpponentWidget extends StatelessWidget {
  final PlayerSummary player;
  final bool isCurrentTurn;

  const OpponentWidget({super.key, required this.player, required this.isCurrentTurn});

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
          CardBackWidget(width: 30),
          const SizedBox(height: 2),
          Text('${player.handCount}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
