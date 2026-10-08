import 'package:flutter/material.dart';

import '../models/card.dart';

class PlayingCardWidget extends StatelessWidget {
  final PlayingCard card;
  final bool enabled;
  final bool selected;
  final VoidCallback? onTap;
  final double width;

  const PlayingCardWidget({
    super.key,
    required this.card,
    this.enabled = true,
    this.selected = false,
    this.onTap,
    this.width = 64,
  });

  @override
  Widget build(BuildContext context) {
    final color = card.suit.isRed ? Colors.red.shade700 : Colors.grey.shade900;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: width,
        height: width * 1.4,
        transform: selected ? Matrix4.translationValues(0.0, -12.0, 0.0) : Matrix4.identity(),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Colors.amber.shade600 : Colors.black26,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(1, 2))],
        ),
        child: Opacity(
          opacity: enabled ? 1.0 : 0.45,
          child: Stack(
            children: [
              Positioned(
                left: 4,
                top: 2,
                child: _CornerLabel(card: card, color: color),
              ),
              Positioned(
                right: 4,
                bottom: 2,
                child: Transform.rotate(
                  angle: 3.14159,
                  child: _CornerLabel(card: card, color: color),
                ),
              ),
              Center(
                child: Text(
                  card.suit.symbol,
                  style: TextStyle(fontSize: width * 0.42, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CornerLabel extends StatelessWidget {
  final PlayingCard card;
  final Color color;

  const _CornerLabel({required this.card, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(card.rank.label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color, height: 1)),
        Text(card.suit.symbol, style: TextStyle(fontSize: 11, color: color, height: 1)),
      ],
    );
  }
}

class CardBackWidget extends StatelessWidget {
  final double width;

  const CardBackWidget({super.key, this.width = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width * 1.4,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: Colors.indigo.shade700,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Center(
        child: Icon(Icons.style, color: Colors.indigo.shade200, size: width * 0.5),
      ),
    );
  }
}
