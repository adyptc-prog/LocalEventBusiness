import 'dart:async';

import 'package:flutter/material.dart';

import '../core/bill_request.dart';
import '../core/menu_store.dart';
import '../core/order.dart';
import '../network/event_server_runner.dart';
import '../l10n/money.dart';
import '../widgets/language_button.dart';
import '../l10n/tr.dart';
import 'closed_orders_screen.dart';

/// Ecran de barman: coada live de comenzi, pe același dispozitiv care
/// rulează serverul — nu e un client WebSocket, ascultă direct
/// `EventServerRunner.ordersUpdates` (canalul de comenzi existent, la fel ca
/// `ParticipantsScreen`), fiindcă avansarea statusului nu trebuie să fie
/// posibilă de la niciun client obișnuit (vezi `MenuEngine`).
///
/// Pe ecran rămâne doar ce mai e de făcut: notele cerute, comenzile de
/// pregătit și cele gata de dus, plus o listă compactă a meselor deschise
/// (cu totalul de încasat și butonul „Închide masa"). Comenzile închise și
/// cele anulate stau în istoric ([ClosedOrdersScreen]), deschis din bara de
/// sus.
class OrdersDashboardScreen extends StatefulWidget {
  const OrdersDashboardScreen({super.key});

  @override
  State<OrdersDashboardScreen> createState() => _OrdersDashboardScreenState();
}

class _OrdersDashboardScreenState extends State<OrdersDashboardScreen> {
  StreamSubscription? _sub;
  StreamSubscription? _billsSub;
  List<Order> _orders = EventServerRunner.lastOrders;
  List<BillRequest> _bills = EventServerRunner.lastBills;

  @override
  void initState() {
    super.initState();
    EventServerRunner.requestState();
    _sub = EventServerRunner.ordersUpdates.listen((orders) {
      if (!mounted) return;
      setState(() => _orders = orders);
    });
    _billsSub = EventServerRunner.billsUpdates.listen((bills) {
      if (!mounted) return;
      setState(() => _bills = bills);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _billsSub?.cancel();
    super.dispose();
  }

  String _price(int cents) => formatPrice(cents, MenuStore.instance.currency);

  static String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _statusLabel(OrderStatus status) => switch (status) {
        OrderStatus.placed => tr('orders.status.placed'),
        OrderStatus.preparing => tr('orders.status.preparing'),
        OrderStatus.ready => tr('orders.status.ready'),
        OrderStatus.delivered => tr('orders.status.delivered'),
        OrderStatus.cancelled => tr('orders.status.cancelled'),
      };

  String? _nextActionLabel(OrderStatus status) => switch (status) {
        OrderStatus.placed => tr('orders.startPreparing'),
        OrderStatus.preparing => tr('orders.markReady'),
        OrderStatus.ready => tr('orders.markDelivered'),
        OrderStatus.delivered => null,
        OrderStatus.cancelled => null,
      };

  Color _statusColor(OrderStatus status) => switch (status) {
        OrderStatus.placed => Colors.white70,
        OrderStatus.preparing => Colors.amberAccent,
        OrderStatus.ready => Colors.lightGreenAccent,
        OrderStatus.delivered => Colors.lightBlueAccent,
        OrderStatus.cancelled => Colors.redAccent,
      };

  /// Mesele care au comenzi încă neînchise (de achitat), grupate după masă.
  List<_OpenTable> _openTables() {
    final byKey = <String, _OpenTable>{};
    for (final o in _orders) {
      if (o.isClosed || o.status == OrderStatus.cancelled) continue;
      final table = byKey.putIfAbsent(o.tableKey, () => _OpenTable(o.tableLabel.trim()));
      table.orders.add(o);
    }
    final tables = byKey.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    return tables;
  }

  Future<void> _confirmCloseTable(_OpenTable table) async {
    final unfinished = table.orders.where((o) => o.needsWork).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('orders.closeTable.title', {'table': table.label})),
        content: Text([
          tr('orders.closeTable.body', {'n': table.orders.length, 'amount': _price(table.totalCents)}),
          if (unfinished > 0) tr('orders.closeTable.unfinished', {'n': unfinished}),
        ].join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(tr('orders.closeTable.confirm'))),
        ],
      ),
    );
    if (confirmed != true) return;
    EventServerRunner.closeTable(table.label);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr('orders.closeTable.done', {'table': table.label, 'amount': _price(table.totalCents)})),
    ));
  }

  Future<void> _confirmCloseAll(List<_OpenTable> tables) async {
    final total = tables.fold<int>(0, (sum, t) => sum + t.totalCents);
    final unfinished = tables.expand((t) => t.orders).where((o) => o.needsWork).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('orders.closeAll.title')),
        content: Text([
          tr('orders.closeAll.body', {'n': tables.length, 'amount': _price(total)}),
          if (unfinished > 0) tr('orders.closeTable.unfinished', {'n': unfinished}),
        ].join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(tr('orders.closeAll.button'))),
        ],
      ),
    );
    if (confirmed != true) return;
    EventServerRunner.closeAllTables();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr('orders.closeAll.done', {'n': tables.length, 'amount': _price(total)})),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final inProgress = _orders.where((o) => o.needsWork && o.status != OrderStatus.ready).toList();
    final ready = _orders.where((o) => o.needsWork && o.status == OrderStatus.ready).toList();
    final openBills = _bills.where((b) => !b.handled).toList();
    final openTables = _openTables();
    final historyCount = _orders.where((o) => o.isClosed || o.status == OrderStatus.cancelled).length;
    final nothing = inProgress.isEmpty && ready.isEmpty && openBills.isEmpty && openTables.isEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(
        backgroundColor: Colors.black26,
        title: Text(tr('mainMenu.orders.title')),
        actions: [
          IconButton(
            tooltip: tr('orders.history.title'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const ClosedOrdersScreen()),
            ),
            icon: Badge(
              isLabelVisible: historyCount > 0,
              label: Text('$historyCount'),
              child: const Icon(Icons.history),
            ),
          ),
          const LanguageButton(),
        ],
      ),
      body: SafeArea(
        child: nothing
            ? Center(child: Text(tr('orders.none'), style: const TextStyle(color: Colors.white38)))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (openBills.isNotEmpty) ...[
                    _sectionTitle(tr('bills.requested', {'n': openBills.length}), color: Colors.amberAccent),
                    for (final bill in openBills) _buildBillCard(bill),
                    const SizedBox(height: 16),
                  ],
                  if (inProgress.isNotEmpty) ...[
                    _sectionTitle(tr('orders.inProgress', {'n': inProgress.length})),
                    for (final order in inProgress) _buildOrderCard(order),
                    const SizedBox(height: 16),
                  ],
                  if (ready.isNotEmpty) ...[
                    _sectionTitle(tr('orders.readyToServe', {'n': ready.length})),
                    for (final order in ready) _buildOrderCard(order),
                    const SizedBox(height: 16),
                  ],
                  if (openTables.isNotEmpty) ...[
                    Row(
                      children: [
                        Expanded(child: _sectionTitle(tr('orders.openTables', {'n': openTables.length}))),
                        if (openTables.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TextButton.icon(
                              style: TextButton.styleFrom(foregroundColor: Colors.lightGreenAccent),
                              icon: const Icon(Icons.done_all, size: 18),
                              label: Text(tr('orders.closeAll.button')),
                              onPressed: () => _confirmCloseAll(openTables),
                            ),
                          ),
                      ],
                    ),
                    for (final table in openTables) _buildOpenTableRow(table),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _sectionTitle(String text, {Color color = Colors.white70}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      );

  Widget _buildOpenTableRow(_OpenTable table) {
    final unfinished = table.orders.where((o) => o.needsWork).length;
    return Card(
      color: Colors.white10,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.table_restaurant, color: Colors.white70),
        title: Text(tr('orders.table', {'table': table.label}),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(
          [
            tr('orders.openTable.summary', {'n': table.orders.length, 'amount': _price(table.totalCents)}),
            if (unfinished > 0) tr('orders.openTable.unfinished', {'n': unfinished}),
          ].join(' · '),
          style: const TextStyle(color: Colors.white54),
        ),
        trailing: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.lightGreenAccent,
            side: const BorderSide(color: Colors.lightGreenAccent),
          ),
          onPressed: () => _confirmCloseTable(table),
          child: Text(tr('orders.closeTable.button')),
        ),
      ),
    );
  }

  Widget _buildBillCard(BillRequest bill) {
    return Card(
      color: Colors.amber.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.amberAccent),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.receipt_long, color: Colors.amberAccent, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('bills.tableAsks', {'table': bill.tableLabel}),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(
                    '${_time(bill.createdAt)} · '
                    '${bill.totalCents > 0 ? tr('orders.total', {'amount': _price(bill.totalCents)}) : tr('bills.noAppOrders')}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: () => EventServerRunner.handleBill(bill.id),
              child: Text(tr('bills.markHandled')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(Order order) {
    final nextLabel = _nextActionLabel(order.status);
    return Card(
      color: Colors.white10,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tr('orders.table', {'table': order.tableLabel}),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                Text(_statusLabel(order.status),
                    style: TextStyle(color: _statusColor(order.status), fontWeight: FontWeight.bold)),
              ],
            ),
            Text(_time(order.createdAt), style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 8),
            for (final line in order.lines)
              Text(
                '${line.quantity}x ${line.name}'
                '${line.unitPriceCents == null ? '' : ' — ${_price(line.lineTotalCents)}'}',
                style: const TextStyle(color: Colors.white),
              ),
            if (order.totalCents > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr('orders.total', {'amount': _price(order.totalCents)}),
                    style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            if (order.note != null)
              Text(tr('orders.note', {'note': order.note}), style: const TextStyle(color: Colors.amberAccent)),
            const SizedBox(height: 12),
            Row(
              children: [
                if (nextLabel != null)
                  Expanded(
                    child: FilledButton(
                      onPressed: () => EventServerRunner.advanceOrder(order.id),
                      child: Text(nextLabel),
                    ),
                  ),
                if (order.status == OrderStatus.placed || order.status == OrderStatus.preparing) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => EventServerRunner.cancelOrder(order.id),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                    child: Text(tr('orders.cancel')),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// O masă cu comenzi încă neachitate.
class _OpenTable {
  final String label;
  final List<Order> orders = [];

  _OpenTable(this.label);

  int get totalCents => orders.fold(0, (sum, o) => sum + o.totalCents);
}
