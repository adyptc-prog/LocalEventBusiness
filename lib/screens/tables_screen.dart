import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/network_address.dart';
import '../core/table_cards.dart';
import '../core/table_config_store.dart';
import '../network/event_server_service.dart';
import '../widgets/language_button.dart';
import '../l10n/tr.dart';

/// Ecran de organizator: câte mese are localul + un QR per masă, ca un
/// client să scaneze și să ajungă direct pe ecranul de comandă cu masa
/// precompletată (`?table=N`). Cartonașele se pot distribui pentru tipărit —
/// toate odată, ca PDF A4 (6 pe pagină), sau câte unul, ca imagine (vezi
/// [TableCards]).
class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  late final _countController = TextEditingController(text: '${TableConfigStore.instance.tableCount}');
  late final _wifiController = TextEditingController(text: TableConfigStore.instance.wifiInfo);
  String? _localIp;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    localNetworkIp().then((ip) {
      if (!mounted) return;
      setState(() => _localIp = ip);
    });
  }

  @override
  void dispose() {
    _countController.dispose();
    _wifiController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final count = int.tryParse(_countController.text.trim()) ?? 0;
    await TableConfigStore.instance.setTableCount(count);
    await TableConfigStore.instance.setWifiInfo(_wifiController.text);
    setState(() {});
  }

  String _urlFor(String ip, int table) => 'http://$ip:${EventServerService.webPort}/?table=$table';

  /// Scrie [bytes] într-un fișier temporar și deschide meniul de distribuire
  /// al telefonului (WhatsApp, e-mail, Drive, imprimantă etc.).
  Future<void> _shareFile(Uint8List bytes, String fileName, String mimeType) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: mimeType, name: fileName)],
      subject: tr('tables.share.subject'),
      text: tr('tables.share.text'),
    ));
  }

  Future<void> _runSharing(Future<void> Function() action) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('tables.share.failed', {'error': e}))));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _shareAllAsPdf(String ip) => _runSharing(() async {
        await _save();
        final pdf = await TableCards.buildTablesPdf(
          tableCount: TableConfigStore.instance.tableCount,
          urlFor: (t) => _urlFor(ip, t),
          wifiInfo: TableConfigStore.instance.wifiInfo,
        );
        await _shareFile(pdf, 'mese-qr.pdf', 'application/pdf');
      });

  Future<void> _shareOne(String ip, int table) => _runSharing(() async {
        final png = await TableCards.renderTableCardPng(
          table: table,
          url: _urlFor(ip, table),
          wifiInfo: TableConfigStore.instance.wifiInfo,
        );
        await _shareFile(png, 'masa-$table.png', 'image/png');
      });

  @override
  Widget build(BuildContext context) {
    final ip = _localIp;
    final count = TableConfigStore.instance.tableCount;

    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(backgroundColor: Colors.black26, title: Text(tr('mainMenu.tables')), actions: const [LanguageButton()]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (ip == null)
              Text(
                tr('tables.noIp'),
                style: const TextStyle(color: Colors.orangeAccent),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _countController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(labelText: tr('tables.count'), labelStyle: const TextStyle(color: Colors.white70)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(onPressed: _save, child: Text(tr('tables.generate'))),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _wifiController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: tr('tables.wifiInfo'),
                  hintText: tr('tables.wifiInfoHint'),
                  hintStyle: const TextStyle(color: Colors.white24),
                  labelStyle: const TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 16),
              if (count > 0)
                FilledButton.icon(
                  icon: _sharing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.print),
                  label: Text(tr('tables.sharePdf', {'n': count})),
                  onPressed: _sharing ? null : () => _shareAllAsPdf(ip),
                ),
              const SizedBox(height: 8),
              if (count == 0)
                Text(tr('tables.hint'), style: const TextStyle(color: Colors.white54))
              else ...[
                Text(tr('tables.printHint'), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.8),
                  itemCount: count,
                  itemBuilder: (context, index) {
                    final table = index + 1;
                    return Card(
                      color: Colors.white10,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Expanded(
                              child: QrImageView(data: _urlFor(ip, table), backgroundColor: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(tr('orders.table', {'table': table}),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon: const Icon(Icons.share, color: Colors.white70, size: 20),
                                  tooltip: tr('tables.shareOne'),
                                  onPressed: _sharing ? null : () => _shareOne(ip, table),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
