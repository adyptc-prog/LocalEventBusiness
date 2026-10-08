import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/table_config_store.dart';
import '../network/event_server_service.dart';

/// Ecran de organizator: câte mese are localul + un QR per masă, ca un
/// client să scaneze și să ajungă direct pe ecranul de comandă cu masa
/// precompletată (`?table=N`, citit direct de `MenuOrderScreen`). Fără
/// denumire individuală per masă în v1 — doar un număr, generat din numărul
/// total de mese introdus aici (vezi `TableConfigStore`).
class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  late final _countController = TextEditingController(text: '${TableConfigStore.instance.tableCount}');
  String? _localIp;

  @override
  void initState() {
    super.initState();
    NetworkInfo().getWifiIP().then((ip) {
      if (!mounted) return;
      setState(() => _localIp = ip);
    });
  }

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final count = int.tryParse(_countController.text.trim()) ?? 0;
    await TableConfigStore.instance.setTableCount(count);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ip = _localIp;
    final count = TableConfigStore.instance.tableCount;

    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(backgroundColor: Colors.black26, title: const Text('Mese / cod QR')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (ip == null)
              const Text(
                'Pornește serverul localului ca să afli adresa de rețea — fără ea, codurile QR nu pot fi generate.',
                style: TextStyle(color: Colors.orangeAccent),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _countController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Câte mese ai', labelStyle: TextStyle(color: Colors.white70)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(onPressed: _save, child: const Text('Generează')),
                ],
              ),
              const SizedBox(height: 24),
              if (count == 0)
                const Text('Introdu numărul de mese și apasă „Generează".', style: TextStyle(color: Colors.white54))
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.85),
                  itemCount: count,
                  itemBuilder: (context, index) {
                    final table = index + 1;
                    final url = 'http://$ip:${EventServerService.webPort}/?table=$table';
                    return Card(
                      color: Colors.white10,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Expanded(
                              child: QrImageView(data: url, backgroundColor: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            Text('Masa $table', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}
