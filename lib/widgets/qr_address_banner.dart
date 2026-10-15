import 'package:flutter/material.dart';

import '../core/qr_address_monitor.dart';
import '../l10n/tr.dart';
import '../screens/qr_cards_screen.dart';

/// Avertizarea din partea de sus a ecranelor folosite la bar: tableta are
/// altă adresă decât cea de pe cartonașele QR tipărite, deci clienții nu mai
/// ajung la meniu. „Generează QR" deschide cartonașul nou (de tipărit sau de
/// arătat direct de pe ecran); după aceea avertizarea se poate restrânge
/// sau închide cu „Gata", când cartonașele noi sunt pe mese.
class QrAddressBanner extends StatefulWidget {
  const QrAddressBanner({super.key});

  @override
  State<QrAddressBanner> createState() => _QrAddressBannerState();
}

class _QrAddressBannerState extends State<QrAddressBanner> {
  final _monitor = QrAddressMonitor.instance;

  @override
  void initState() {
    super.initState();
    _monitor.attach();
  }

  @override
  void dispose() {
    _monitor.detach();
    super.dispose();
  }

  void _openGenerator() {
    _monitor.markGenerated();
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const QrCardsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _monitor,
      builder: (context, _) {
        if (!_monitor.needsReprint) return const SizedBox.shrink();
        return _monitor.minimized ? _buildMinimized() : _buildExpanded();
      },
    );
  }

  Widget _buildExpanded() {
    final generated = _monitor.generated;
    return Material(
      color: Colors.orange.withValues(alpha: 0.18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.qr_code_2, color: Colors.orangeAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _monitor.neverPrinted ? tr('qrBanner.first') : tr('qrBanner.changed'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
                if (generated)
                  IconButton(
                    icon: const Icon(Icons.expand_less, color: Colors.white70),
                    tooltip: tr('qrBanner.minimize'),
                    onPressed: () => _monitor.setMinimized(true),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.qr_code),
                  label: Text(tr('qrBanner.generate')),
                  onPressed: _openGenerator,
                ),
                if (generated)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.check),
                    label: Text(tr('qrBanner.done')),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.lightGreenAccent),
                    onPressed: _monitor.confirmPrinted,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMinimized() {
    return Material(
      color: Colors.orange.withValues(alpha: 0.18),
      child: InkWell(
        onTap: () => _monitor.setMinimized(false),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.qr_code_2, color: Colors.orangeAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('qrBanner.minimized'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ),
              TextButton(onPressed: _monitor.confirmPrinted, child: Text(tr('qrBanner.done'))),
              const Icon(Icons.expand_more, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}
