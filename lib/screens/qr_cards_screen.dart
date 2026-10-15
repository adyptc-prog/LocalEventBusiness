import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/network_address.dart';
import '../core/qr_address_monitor.dart';
import '../core/qr_cards.dart';
import '../core/qr_cards_store.dart';
import '../widgets/language_button.dart';
import '../l10n/tr.dart';

/// Ecran de organizator: cartonașul de pus pe toate mesele — QR-ul de Wi-Fi
/// și QR-ul care deschide meniul de comandă. Același cartonaș pe fiecare
/// masă; clientul își scrie singur masa în meniu. Codurile se văd mari pe
/// ecran (ospătarul le poate arăta direct de aici) și se pot distribui
/// pentru tipărit: PDF A4 cu câte 6 cartonașe pe pagină, sau o imagine.
///
/// Codul de meniu conține adresa tabletei. Dacă adresa se schimbă,
/// `QrAddressBanner` cere un cartonaș nou; „Gata" de aici sau din banner
/// confirmă că cele noi sunt tipărite.
class QrCardsScreen extends StatefulWidget {
  const QrCardsScreen({super.key});

  @override
  State<QrCardsScreen> createState() => _QrCardsScreenState();
}

class _QrCardsScreenState extends State<QrCardsScreen> {
  final _store = QrCardsStore.instance;
  final _monitor = QrAddressMonitor.instance;
  late final _ssidController = TextEditingController(text: _store.wifiSsid);
  late final _passwordController = TextEditingController(text: _store.wifiPassword);
  late final _countController = TextEditingController(text: _store.cardCount > 0 ? '${_store.cardCount}' : '');
  String? _localIp;
  bool _loadingIp = true;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _monitor.attach();
    localNetworkIp().then((ip) {
      if (!mounted) return;
      setState(() {
        _localIp = ip;
        _loadingIp = false;
      });
    });
  }

  @override
  void dispose() {
    _monitor.detach();
    _ssidController.dispose();
    _passwordController.dispose();
    _countController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _store.setWifi(ssid: _ssidController.text, password: _passwordController.text);
    await _store.setCardCount(int.tryParse(_countController.text.trim()) ?? 0);
    if (mounted) setState(() {});
  }

  /// Scrie [bytes] într-un fișier temporar și deschide meniul de distribuire
  /// al telefonului (WhatsApp, e-mail, Drive, imprimantă etc.).
  Future<void> _shareFile(Uint8List bytes, String fileName, String mimeType) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType, name: fileName)],
        subject: tr('qrCards.share.subject'),
        text: tr('qrCards.share.text'),
      ),
    );
  }

  Future<void> _runSharing(Future<void> Function() action) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await _save();
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('qrCards.share.failed', {'error': e}))));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<Uint8List> _renderCard(String ip) =>
      QrCards.renderCardPng(menuUrl: menuUrlFor(ip), wifiSsid: _store.wifiSsid, wifiPassword: _store.wifiPassword);

  Future<void> _sharePdf(String ip) => _runSharing(() async {
    final copies = _store.cardCount > 0 ? _store.cardCount : QrCards.cardsPerPage;
    final pdf = await QrCards.buildCardsPdf(card: await _renderCard(ip), copies: copies);
    await _shareFile(pdf, 'cod-qr-meniu.pdf', 'application/pdf');
  });

  Future<void> _shareImage(String ip) => _runSharing(() async {
    await _shareFile(await _renderCard(ip), 'cod-qr-meniu.png', 'image/png');
  });

  Future<void> _confirmPrinted() async {
    await _monitor.confirmPrinted();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('qrCards.doneSaved'))));
  }

  InputDecoration _decoration(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white24),
    labelStyle: const TextStyle(color: Colors.white70),
  );

  @override
  Widget build(BuildContext context) {
    final ip = _localIp;
    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(
        backgroundColor: Colors.black26,
        title: Text(tr('mainMenu.tables')),
        actions: const [LanguageButton()],
      ),
      body: SafeArea(
        child: _loadingIp
            ? const Center(child: CircularProgressIndicator())
            : ip == null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('qrCards.noIp'), style: const TextStyle(color: Colors.orangeAccent)),
              )
            : _buildContent(ip),
      ),
    );
  }

  Widget _buildContent(String ip) {
    final ssid = _store.wifiSsid;
    final count = _store.cardCount;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(tr('qrCards.intro'), style: const TextStyle(color: Colors.white60)),
        const SizedBox(height: 16),
        // Codurile mari, pe ecran — ospătarul le poate arăta direct de aici.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ssid.isNotEmpty) ...[
              Expanded(
                child: _qrTile(
                  '1 · Wi-Fi',
                  wifiQrPayload(ssid: ssid, password: _store.wifiPassword),
                  _store.wifiPassword.isEmpty ? ssid : '$ssid\n${tr('qrCard.password')}: ${_store.wifiPassword}',
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: _qrTile(
                ssid.isNotEmpty ? '2 · ${tr('qrCard.menuShort')}' : tr('qrCard.menuShort'),
                menuUrlFor(ip),
                tr('qrCard.menu'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _ssidController,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration(tr('qrCards.wifiSsid'), hint: tr('qrCards.wifiSsidHint')),
          onSubmitted: (_) => _save(),
        ),
        TextField(
          controller: _passwordController,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration(tr('qrCards.wifiPassword'), hint: tr('qrCards.wifiPasswordHint')),
          onSubmitted: (_) => _save(),
        ),
        TextField(
          controller: _countController,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: _decoration(tr('qrCards.count'), hint: tr('qrCards.countHint')),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(icon: const Icon(Icons.refresh), label: Text(tr('qrCards.update')), onPressed: _save),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: _sharing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.print),
          label: Text(tr('qrCards.sharePdf', {'n': count > 0 ? count : QrCards.cardsPerPage})),
          onPressed: _sharing ? null : () => _sharePdf(ip),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.image_outlined),
          label: Text(tr('qrCards.shareImage')),
          onPressed: _sharing ? null : () => _shareImage(ip),
        ),
        const SizedBox(height: 4),
        Text(tr('qrCards.printHint'), style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: _monitor,
          builder: (context, _) => _monitor.needsReprint
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                  icon: const Icon(Icons.check),
                  label: Text(tr('qrCards.done')),
                  onPressed: _confirmPrinted,
                )
              : !_monitor.serverRunning
              ? const SizedBox.shrink()
              : Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.lightGreenAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(tr('qrCards.upToDate'), style: const TextStyle(color: Colors.white60, fontSize: 13)),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _qrTile(String title, String data, String caption) {
    return Card(
      color: Colors.white10,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            QrImageView(data: data, backgroundColor: Colors.white),
            const SizedBox(height: 8),
            Text(
              caption,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
