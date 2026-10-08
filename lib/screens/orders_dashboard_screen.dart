import 'dart:async';

import 'package:flutter/material.dart';

import '../core/order.dart';
import '../network/event_server_runner.dart';
import '../widgets/language_button.dart';
import '../l10n/tr.dart';

/// Ecran de barman: coada live de comenzi, pe același dispozitiv care
/// rulează serverul — nu e un client WebSocket, ascultă direct
/// `EventServerRunner.ordersUpdates` (canalul de comenzi existent, la fel ca
/// `ParticipantsScreen`), fiindcă avansarea statusului nu trebuie să fie
/// posibilă de la niciun client obișnuit (vezi `MenuEngine`).
class OrdersDashboardScreen extends StatefulWidget {
  const OrdersDashboardScreen({super.key});

  @override
  State<OrdersDashboardScreen> createState() => _OrdersDashboardScreenState();
}

class _OrdersDashboardScreenState extends State<OrdersDashboardScreen> {
  StreamSubscription? _sub;
  List<Order> _orders = [];

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

    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(backgroundColor: Colors.black26, title: Text(tr('mainMenu.orders.title')), actions: const [LanguageButton()]),
      body: SafeArea(
        child: _orders.isEmpty
            ? Center(child: Text(tr('orders.none'), style: const TextStyle(color: Colors.white38)))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
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
            Text('${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 8),
            for (final line in order.lines)
              Text('${line.quantity}x ${line.name}', style: const TextStyle(color: Colors.white)),
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
