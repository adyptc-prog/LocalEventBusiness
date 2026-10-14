import 'package:flutter/material.dart';

import '../core/app_version.dart';
import '../l10n/tr.dart';

/// Eticheta mică „v1.1.0" din bara de sus — utilizatorul vede dintr-o
/// privire ce versiune are și o poate compara cu ultima de pe site.
class VersionBadge extends StatelessWidget {
  const VersionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tr('app.version', {'version': appVersion}),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'v$appVersion',
          style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
