import 'package:flutter/material.dart';

import 'color_picker_dialog.dart';
import 'uno_card.dart';

class UnoCardWidget extends StatelessWidget {
  final UnoCard card;
  final bool enabled;
  final bool selected;
  final VoidCallback? onTap;
  final double width;

  const UnoCardWidget({
    super.key,
    required this.card,
    this.enabled = true,
    this.selected = false,
    this.onTap,
    this.width = 64,
  });

  @override
  Widget build(BuildContext context) {
    final bg = card.color != null ? colorFor(card.color!) : Colors.black87;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: width,
        height: width * 1.4,
        transform: selected ? Matrix4.translationValues(0.0, -12.0, 0.0) : Matrix4.identity(),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Colors.amber.shade400 : Colors.white70,
            width: selected ? 2.5 : 1.5,
          ),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(1, 2))],
        ),
        child: Opacity(
          opacity: enabled ? 1.0 : 0.45,
          child: Center(child: _CardFace(card: card, width: width)),
        ),
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  final UnoCard card;
  final double width;

  const _CardFace({required this.card, required this.width});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: width * 0.4);
    switch (card.type) {
      case UnoCardType.number:
        return Text('${card.number}', style: style);
      case UnoCardType.skip:
        return Icon(Icons.block, color: Colors.white, size: width * 0.5);
      case UnoCardType.reverse:
        return Icon(Icons.sync, color: Colors.white, size: width * 0.5);
      case UnoCardType.drawTwo:
        return Text('+2', style: style.copyWith(fontSize: width * 0.32));
      case UnoCardType.wild:
        return _WildDots(width: width);
      case UnoCardType.wildDrawFour:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _WildDots(width: width * 0.6),
            Text('+4', style: style.copyWith(fontSize: width * 0.28)),
          ],
        );
    }
  }
}

class _WildDots extends StatelessWidget {
  final double width;

  const _WildDots({required this.width});

  @override
  Widget build(BuildContext context) {
    Widget dot(UnoColor c) => Container(
          width: width * 0.28,
          height: width * 0.28,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(color: colorFor(c), shape: BoxShape.circle),
        );
    return SizedBox(
      width: width * 0.6,
      height: width * 0.6,
      child: Wrap(
        children: UnoColor.values.map(dot).toList(),
      ),
    );
  }
}

class UnoCardBackWidget extends StatelessWidget {
  final double width;

  const UnoCardBackWidget({super.key, this.width = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width * 1.4,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Center(
        child: Text('UNO', style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.bold, fontSize: width * 0.24)),
      ),
    );
  }
}
