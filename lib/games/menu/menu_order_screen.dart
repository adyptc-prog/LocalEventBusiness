import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../widgets/language_button.dart';

import '../../core/game_definition.dart';
import '../../l10n/tr.dart';

/// Ecranul clientului: răsfoiește meniul localului, își compune o comandă și
/// vede live statusul comenzilor proprii — nimic din asta nu depinde de o
/// „gazdă" sau de un cod de cameră, camera „Meniu" fiind deja creată automat
/// de server (vezi `MenuConnectScreen`). Citește `?table=` din URL direct
/// aici (nu prin `GameSessionArgs`, care e generic pentru toate
/// activitățile) — același truc folosit deja de `RoomBrowserScreen` pentru
/// adresa serverului.
class MenuOrderScreen extends StatefulWidget {
  final GameSessionArgs args;

  const MenuOrderScreen({super.key, required this.args});

  @override
  State<MenuOrderScreen> createState() => _MenuOrderScreenState();
}

class _MenuOrderScreenState extends State<MenuOrderScreen> {
  late final _tableController = TextEditingController(
    text: kIsWeb ? (Uri.base.queryParameters['table'] ?? '') : '',
  );
  final _noteController = TextEditingController();
  final Map<String, int> _cart = {};
  StreamSubscription? _stateSub;
  Map<String, dynamic> _snapshot = {};
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.args.initialSnapshot;
    _stateSub = widget.args.stateStream.listen((snap) {
      if (!mounted) return;
      setState(() => _snapshot = snap);
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _tableController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _categories =>
      ((_snapshot['menu'] as Map?)?['categories'] as List<dynamic>? ?? const [])
          .map((c) => Map<String, dynamic>.from(c as Map))
          .toList();

  List<Map<String, dynamic>> get _items =>
      ((_snapshot['menu'] as Map?)?['items'] as List<dynamic>? ?? const [])
          .map((i) => Map<String, dynamic>.from(i as Map))
          .toList();

  List<Map<String, dynamic>> get _myOrders =>
      (_snapshot['myOrders'] as List<dynamic>? ?? const []).map((o) => Map<String, dynamic>.from(o as Map)).toList();

  int get _cartCount => _cart.values.fold(0, (sum, q) => sum + q);

  void _changeQty(String itemId, int delta) {
    setState(() {
      final next = (_cart[itemId] ?? 0) + delta;
      if (next <= 0) {
        _cart.remove(itemId);
      } else {
        _cart[itemId] = next;
      }
    });
  }

  Future<void> _submit() async {
    final table = _tableController.text.trim();
    if (table.isEmpty) {
      setState(() => _error = tr('menuOrder.enterTable'));
      return;
    }
    if (_cart.isEmpty) {
      setState(() => _error = tr('menuOrder.chooseItem'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    widget.args.onAction({
      'type': 'submit_order',
      'tableLabel': table,
      'lines': _cart.entries.map((e) => {'menuItemId': e.key, 'quantity': e.value}).toList(),
      'note': _noteController.text.trim(),
    });
    setState(() {
      _cart.clear();
      _noteController.clear();
      _submitting = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('menuOrder.sent'))));
    }
  }

  String? _photoUrl(String? photoFile) {
    final origin = widget.args.serverOrigin;
    if (origin == null || photoFile == null) return null;
    return '$origin/menu/photos/$photoFile';
  }

  String _statusLabel(String status) => switch (status) {
        'placed' => tr('menuOrder.status.placed'),
        'preparing' => tr('orders.status.preparing'),
        'ready' => tr('orders.status.ready'),
        'cancelled' => tr('orders.status.cancelled'),
        _ => status,
      };

  Color _statusColor(String status) => switch (status) {
        'placed' => Colors.white54,
        'preparing' => Colors.amberAccent,
        'ready' => Colors.lightGreenAccent,
        'cancelled' => Colors.redAccent,
        _ => Colors.white54,
      };

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    final items = _items;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) widget.args.onLeave();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF101418),
        appBar: AppBar(backgroundColor: Colors.black26, title: Text(tr('game.menu.title')), actions: const [LanguageButton()]),
        body: SafeArea(
          child: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr('menuOrder.empty'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  children: [
                    TextField(
                      controller: _tableController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: tr('menuOrder.table'),
                        labelStyle: const TextStyle(color: Colors.white70),
                        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final category in categories) ..._buildCategorySection(category, items),
                    ..._buildUncategorizedSection(categories, items),
                    if (_myOrders.isNotEmpty) ..._buildMyOrdersSection(),
                  ],
                ),
        ),
        bottomNavigationBar: _cartCount == 0 ? null : _buildCartBar(),
      ),
    );
  }

  List<Widget> _buildCategorySection(Map<String, dynamic> category, List<Map<String, dynamic>> allItems) {
    final categoryItems = allItems.where((i) => i['categoryId'] == category['id']).toList();
    if (categoryItems.isEmpty) return const [];
    return [
      Text(category['name'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 8),
      for (final item in categoryItems) _buildItemTile(item),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildUncategorizedSection(List<Map<String, dynamic>> categories, List<Map<String, dynamic>> allItems) {
    final categoryIds = categories.map((c) => c['id']).toSet();
    final orphaned = allItems.where((i) => !categoryIds.contains(i['categoryId'])).toList();
    if (orphaned.isEmpty) return const [];
    return [
      for (final item in orphaned) _buildItemTile(item),
      const SizedBox(height: 16),
    ];
  }

  Widget _buildItemTile(Map<String, dynamic> item) {
    final id = item['id'] as String;
    final available = item['available'] as bool? ?? true;
    final photoUrl = _photoUrl(item['photoFile'] as String?);
    final qty = _cart[id] ?? 0;

    return Opacity(
      opacity: available ? 1 : 0.4,
      child: Card(
        color: Colors.white10,
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: photoUrl == null
                      ? const ColoredBox(color: Colors.white12, child: Icon(Icons.restaurant_menu, color: Colors.white38))
                      : Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) =>
                              const ColoredBox(color: Colors.white12, child: Icon(Icons.restaurant_menu, color: Colors.white38)),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['name'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    if ((item['description'] as String?)?.isNotEmpty ?? false)
                      Text(item['description'] as String, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    if (!available) Text(tr('menuOrder.unavailable'), style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                  ],
                ),
              ),
              if (available)
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.white70),
                      onPressed: qty == 0 ? null : () => _changeQty(id, -1),
                    ),
                    Text('$qty', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: Colors.lightGreenAccent),
                      onPressed: () => _changeQty(id, 1),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMyOrdersSection() {
    return [
      const Divider(color: Colors.white24),
      Text(tr('menuOrder.myOrders'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 8),
      for (final order in _myOrders) _buildOrderTile(order),
    ];
  }

  Widget _buildOrderTile(Map<String, dynamic> order) {
    final lines = (order['lines'] as List<dynamic>).map((l) => Map<String, dynamic>.from(l as Map)).toList();
    final status = order['status'] as String;
    return Card(
      color: Colors.white10,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tr('orders.table', {'table': order['tableLabel']}), style: const TextStyle(color: Colors.white70)),
                Text(_statusLabel(status), style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            for (final line in lines)
              Text('${line['quantity']}x ${line['name']}', style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildCartBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      color: Colors.black45,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _noteController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: tr('menuOrder.noteHint'),
                hintStyle: const TextStyle(color: Colors.white38),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(tr('menuOrder.submit', {'n': _cartCount})),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
