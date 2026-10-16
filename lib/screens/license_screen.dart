import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/license_service.dart';
import '../l10n/tr.dart';
import '../widgets/language_button.dart';
import '../widgets/version_badge.dart';
import 'backup_screen.dart';

/// Ecranul de licență: starea (licență / probă), codul de instalare și
/// importul fișierului de licență.
///
/// [locked]: proba s-a terminat și nu există licență activă — ecranul e
/// singurul accesibil (vezi `LicenseGate`), fără buton înapoi, dar cu acces
/// la restaurarea unui backup care conține licența (telefon nou).
class LicenseScreen extends StatefulWidget {
  final bool locked;

  const LicenseScreen({super.key, this.locked = false});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _license = LicenseService.instance;
  String _businessId = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() => _run(() async {
        await _license.refresh();
        _businessId = await _license.getBusinessId();
      });

  void _snack(String text, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  Future<void> _pick() => _run(() async {
        final r = await _license.pickLicenseFile();
        if (!mounted) return;
        if (!r.success && r.message.isEmpty) return; // selector anulat
        if (r.success) {
          _snack(tr('license.activated'), color: Colors.green.shade700);
        } else {
          _snack(tr('license.rejected', {'reason': r.message}), color: Colors.red.shade700);
        }
      });

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  ({IconData icon, Color color, String title, String subtitle}) _status() {
    if (_license.isLicensed) {
      if (_license.isLifetime) {
        return (
          icon: Icons.verified_user,
          color: Colors.lightGreenAccent,
          title: tr('license.status.lifetime'),
          subtitle: tr('license.status.lifetimeHint'),
        );
      }
      final until = _license.validUntilLocal;
      return (
        icon: _license.isExpiringSoon ? Icons.warning_amber_rounded : Icons.verified_user,
        color: _license.isExpiringSoon ? Colors.orangeAccent : Colors.lightGreenAccent,
        title: _license.isExpiringSoon ? tr('license.status.expiringSoon') : tr('license.status.active'),
        subtitle: tr('license.status.validUntil', {
          'date': until == null ? '?' : _formatDate(until),
          'days': _license.daysUntilExpiry ?? 0,
        }),
      );
    }
    final rejected = _license.status == 'invalid' && _license.message.isNotEmpty
        ? '\n${tr('license.rejected', {'reason': _license.message})}'
        : '';
    if (_license.trialActive) {
      return (
        icon: Icons.lock_open_outlined,
        color: Colors.orangeAccent,
        title: tr('license.status.trial'),
        subtitle: tr('license.status.trialDays', {'days': _license.trialDaysLeft}) + rejected,
      );
    }
    return (
      icon: Icons.lock_outline,
      color: Colors.redAccent,
      title: tr('license.status.none'),
      subtitle: tr('license.status.noneHint') + rejected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status();
    const cardColor = Colors.white10;

    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(
        backgroundColor: Colors.black26,
        automaticallyImplyLeading: !widget.locked,
        title: Text(tr('license.title')),
        actions: const [VersionBadge(), LanguageButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: cardColor,
            child: ListTile(
              leading: Icon(status.icon, color: status.color, size: 32),
              title: Text(status.title, style: TextStyle(color: status.color, fontWeight: FontWeight.w600)),
              subtitle: Text(status.subtitle, style: const TextStyle(color: Colors.white70)),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: cardColor,
            child: ListTile(
              leading: const Icon(Icons.qr_code_2, color: Colors.white70),
              title: Text(tr('license.code'), style: const TextStyle(color: Colors.white)),
              subtitle: SelectableText(
                _businessId,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.white70),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.copy, color: Colors.white70),
                tooltip: tr('license.copyCode'),
                onPressed: _businessId.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: _businessId));
                        if (mounted) _snack(tr('license.codeCopied'));
                      },
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.folder_open),
            label: Text(tr('license.pickFile')),
            onPressed: _busy ? null : _pick,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text(tr('license.recheck')),
            onPressed: _busy ? null : _refresh,
          ),
          if (widget.locked) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.settings_backup_restore),
              label: Text(tr('license.restoreBackup')),
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BackupScreen())),
            ),
          ],
          const SizedBox(height: 16),
          Card(
            color: cardColor,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                tr('license.howTo', {'url': LicenseService.purchaseUrl}),
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
