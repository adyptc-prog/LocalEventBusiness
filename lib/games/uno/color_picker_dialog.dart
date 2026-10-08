import 'package:flutter/material.dart';

import 'uno_card.dart';
import '../../l10n/tr.dart';

Color colorFor(UnoColor color) {
  switch (color) {
    case UnoColor.red:
      return Colors.red.shade600;
    case UnoColor.yellow:
      return Colors.yellow.shade700;
    case UnoColor.green:
      return Colors.green.shade600;
    case UnoColor.blue:
      return Colors.blue.shade700;
  }
}

Future<UnoColor?> showColorPicker(BuildContext context) {
  return showDialog<UnoColor>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(tr('uno.pickColor')),
      content: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: UnoColor.values.map((color) {
          return InkWell(
            onTap: () => Navigator.of(context).pop(color),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colorFor(color),
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }).toList(),
      ),
    ),
  );
}
