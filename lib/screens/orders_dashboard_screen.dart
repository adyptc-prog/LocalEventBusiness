import 'dart:async';

import 'package:flutter/material.dart';

import '../core/bill_request.dart';
import '../core/menu_store.dart';
import '../core/order.dart';
import '../network/event_server_runner.dart';
import '../l10n/money.dart';
import '../widgets/language_button.dart';
import '../l10n/tr.dart';

/// Ecran de barman: coada live de comenzi, pe același dispozitiv care
/// rulează serverul — nu e un client WebSocket, ascultă direct
/// `EventServerRunner.ordersUpdates` (canalul de comenzi existent, la fel ca
/// `ParticipantsScreen`), fiindcă avansarea statusului nu trebuie să fie
/// posibilă de la niciun client obișnuit (vezi `MenuEngine`). Deasupra
/// comenzilor apar mesele care au cerut nota, cu totalul de încasat.
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
        OrderStatus.cancelled => tr('orders.status.cancelled'),
      };

  String? _nextActionLabel(OrderStatus status) => switch (status) {
        OrderStatus.placed => tr('orders.startPreparing'),
        OrderStatus.preparing => tr('orders.markReady'),
        OrderStatus.ready => null,
        OrderStatus.cancelled => null,
      };

  Color _statusColor(OrderStatus status) => switch (status) {
        OrderStatus.placed => Colors.white70,
        OrderStatus.preparing => Colors.amberAccent,
        OrderStatus.ready => Colors.lightGreenAccent,
        OrderStatus.cancelled => Colors.redAccent,
      };

  @override
  Widget build(BuildContext context) {
    final active = _orders.where((o) => o.status != OrderStatus.cancelled && o.status != OrderStatus.ready).toList();
    final ready = _orders.where((o) => o.status == OrderStatus.ready).toList();
    final openBills = _bills.where((b) => !b.handled).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(backgroundColor: Colors.black26, title: Text(tr('mainMenu.orders.title')), actions: const [LanguageButton()]),
      body: SafeArea(
        child: _orders.isEmpty && openBills.isEmpty
            ? Center(child: Text(tr('orders.none'), style: const TextStyle(color: Colors.white38)))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (openBills.isNotEmpty) ...[
                    Text(tr('bills.requested', {'n': openBills.length}),
                        style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    for (final bill in openBills) _buildBillCard(bill),
                    const SizedBox(height: 16),
                  ],
                  Text(tr('orders.inProgress', {'n': active.length}), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  for (final order in active) _buildOrderCard(order),
                  if (ready.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(tr('orders.readyToServe', {'n': ready.length}), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    for (final order in ready) _buildOrderCard(order),
                  ],
                ],
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
                Text(tr('orders.table', {'table': order.tableLabel}), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                Text(_statusLabel(order.status), style: TextStyle(color: _statusColor(order.status), fontWeight: FontWeight.bold)),
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
            if (order.note != null) Text(tr('orders.note', {'note': order.note}), style: const TextStyle(color: Colors.amberAccent)),
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
                if (order.status != OrderStatus.ready) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => EventServerRunner.cancelOrder(order.id),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
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
