import 'dart:async';

import 'package:flutter/material.dart';

import '../core/menu_store.dart';
import '../core/order.dart';
import '../l10n/money.dart';
import '../l10n/tr.dart';
import '../network/event_server_runner.dart';
import '../widgets/language_button.dart';

/// Istoricul barului: mesele închise (comenzile achitate, grupate pe fiecare
/// închidere de masă) și comenzile anulate — scoase de pe ecranul de lucru
/// (`OrdersDashboardScreen`), dar încă la îndemână pentru o verificare.
class ClosedOrdersScreen extends StatefulWidget {
  const ClosedOrdersScreen({super.key});

  @override
  State<ClosedOrdersScreen> createState() => _ClosedOrdersScreenState();
}

class _ClosedOrdersScreenState extends State<ClosedOrdersScreen> {
  StreamSubscription? _sub;
  List<Order> _orders = EventServerRunner.lastOrders;

  @override
  void initState() {
    super.initState();
    _sub = EventServerRunner.ordersUpdates.listen((orders) {
      if (!mounted) return;
      setState(() => _orders = orders);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _price(int cents) => formatPrice(cents, MenuStore.instance.currency);

  static String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// O închidere de masă = comenzile aceleiași mese închise în același moment.
  List<_ClosedTable> _closedTables() {
    final groups = <String, _ClosedTable>{};
    for (final o in _orders) {
      final closedAt = o.closedAt;
      if (closedAt == null || o.status == OrderStatus.cancelled) continue;
      final key = '${o.tableKey}@${closedAt.millisecondsSinceEpoch}@${o.autoClosed}';
      groups.putIfAbsent(key, () => _ClosedTable(o.tableLabel.trim(), closedAt, autoClosed: o.autoClosed)).orders.add(o);
    }
    return groups.values.toList()..sort((a, b) => b.closedAt.compareTo(a.closedAt));
  }

  @override
  Widget build(BuildContext context) {
    final allClosed = _closedTables();
    final closed = allClosed.where((t) => !t.autoClosed).toList();
    final expired = allClosed.where((t) => t.autoClosed).toList();
    final cancelled = _orders.where((o) => o.status == OrderStatus.cancelled).toList();
    final totalToday = closed.fold<int>(0, (sum, t) => sum + t.totalCents);

    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(
        backgroundColor: Colors.black26,
        title: Text(tr('orders.history.title')),
        actions: const [LanguageButton()],
      ),
      body: SafeArea(
        child: allClosed.isEmpty && cancelled.isEmpty
            ? Center(child: Text(tr('orders.history.empty'), style: const TextStyle(color: Colors.white38)))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (closed.isNotEmpty) ...[
                    Text(
                      tr('orders.history.closedTables', {'n': closed.length, 'amount': _price(totalToday)}),
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    for (final table in closed) _buildClosedTable(table),
                    const SizedBox(height: 16),
                  ],
                  if (expired.isNotEmpty) ...[
                    Text(
                      tr('orders.history.expired', {
                        'n': expired.length,
                        'amount': _price(expired.fold<int>(0, (sum, t) => sum + t.totalCents)),
                      }),
                      style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(tr('orders.history.expiredHint'), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    const SizedBox(height: 8),
                    for (final table in expired) _buildClosedTable(table),
                    const SizedBox(height: 16),
                  ],
                  if (cancelled.isNotEmpty) ...[
                    Text(tr('orders.history.cancelled', {'n': cancelled.length}),
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    for (final order in cancelled) _buildOrderSummary(order, cancelled: true),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildClosedTable(_ClosedTable table) {
    return Card(
      color: Colors.white10,
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        iconColor: Colors.white70,
        collapsedIconColor: Colors.white70,
        leading: table.autoClosed
            ? const Icon(Icons.schedule, color: Colors.orangeAccent)
            : const Icon(Icons.check_circle, color: Colors.lightGreenAccent),
        title: Text(tr('orders.table', {'table': table.label}),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(
          tr(table.autoClosed ? 'orders.history.expiredAt' : 'orders.history.closedAt', {
            'time': _time(table.closedAt),
            'n': table.orders.length,
            'amount': _price(table.totalCents),
          }),
          style: const TextStyle(color: Colors.white54),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [for (final order in table.orders) _buildOrderSummary(order)],
      ),
    );
  }

  Widget _buildOrderSummary(Order order, {bool cancelled = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cancelled
                ? '${tr('orders.table', {'table': order.tableLabel})} · ${_time(order.createdAt)}'
                : _time(order.createdAt),
            style: TextStyle(color: cancelled ? Colors.redAccent : Colors.white38, fontSize: 12),
          ),
          for (final line in order.lines)
            Text(
              '${line.quantity}x ${line.name}'
              '${line.unitPriceCents == null ? '' : ' — ${_price(line.lineTotalCents)}'}',
              style: TextStyle(
                color: Colors.white70,
                decoration: cancelled ? TextDecoration.lineThrough : null,
              ),
            ),
          if (order.note != null)
            Text(tr('orders.note', {'note': order.note}), style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ClosedTable {
  final String label;
  final DateTime closedAt;
  final bool autoClosed;
  final List<Order> orders = [];

  _ClosedTable(this.label, this.closedAt, {this.autoClosed = false});

  int get totalCents => orders.fold(0, (sum, o) => sum + o.totalCents);
}
