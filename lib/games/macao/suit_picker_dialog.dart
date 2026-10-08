import 'package:flutter/material.dart';

import '../../models/card.dart';
import '../../l10n/tr.dart';

Future<Suit?> showSuitPicker(BuildContext context) {
  return showDialog<Suit>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(tr('macao.pickSuit')),
      content: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: Suit.values.map((suit) {
          final color = suit.isRed ? Colors.red.shade700 : Colors.grey.shade900;
          return InkWell(
            onTap: () => Navigator.of(context).pop(suit),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(suit.symbol, style: TextStyle(fontSize: 32, color: color)),
            ),
          );
        }).toList(),
      ),
    ),
  );
}
