import '../../core/bill_request.dart';
import '../../core/game_engine.dart';
import '../../core/menu_store.dart';
import '../../core/order.dart';
import '../../l10n/tr.dart';

class _MenuPlayerInfo {
  final String id;
  final String name;
  bool connected = true;

  _MenuPlayerInfo({required this.id, required this.name});
}

/// Motorul camerei singleton „Meniu" — nu e o competiție (`lastMatchScores`
/// rămâne mereu `null`) și nu are fază de așteptare: [started] e `true` din
/// prima clipă, fiindcă orice client conectat trebuie să poată comanda
/// imediat, fără să depindă de o „gazdă" care apasă un buton de start.
///
/// Fiecare client își vede doar propriile comenzi (`snapshotFor`, filtrat
/// după `viewerId`) — clienții nu trebuie să vadă comenzile altor mese.
/// Avansarea statusului unei comenzi NU trece prin [applyAction] (niciun
/// client obișnuit nu are voie să schimbe statusul unei comenzi, iar camera
/// asta e creată de server, nu de un client, deci nu există un „host"
/// logic) — [advanceStatus]/[cancelOrder] sunt apelate direct de
/// `EventServerService`, la fel ca `BingoEngine.completePosition`.
class MenuEngine extends GameEngine {
  static const int minPlayersStatic = 0;
  static const int maxPlayersStatic = 500;

  @override
  int get minPlayers => minPlayersStatic;
  @override
  int get maxPlayers => maxPlayersStatic;

  @override
  bool started = true;

  @override
  Map<String, int>? lastMatchScores;

  /// Limite anti-abuz: un client nu poate inunda barul cu comenzi.
  static const int maxLinesPerOrder = 30;
  static const int maxQuantityPerLine = 20;
  static const int maxOpenOrdersPerCustomer = 5;
  static const int maxTableLabelLength = 20;
  static const int maxNoteLength = 200;

  /// Câte comenzi încheiate (gata/anulate) păstrăm — cele mai vechi ies din
  /// listă, ca memoria să nu crească nelimitat într-o seară lungă.
  static const int maxClosedOrdersKept = 300;

  final List<_MenuPlayerInfo> _players = [];
  final List<Order> _orders = [];
  final List<BillRequest> _bills = [];
  Set<String>? _affected;

  /// Câte cereri de notă rezolvate păstrăm în memorie.
  static const int maxHandledBillsKept = 200;

  /// Repune comenzile salvate (vezi `OrdersStore`) după o repornire a
  /// serverului — apelat o singură dată, înainte de orice client.
  void restoreOrders(List<Order> orders) {
    _orders
      ..clear()
      ..addAll(orders);
  }

  /// La fel ca [restoreOrders], pentru cererile de notă.
  void restoreBills(List<BillRequest> bills) {
    _bills
      ..clear()
      ..addAll(bills);
  }

  /// Toate cererile de notă, cele mai noi primele.
  List<BillRequest> get allBills => List.unmodifiable(_bills);

  /// Meniul s-a schimbat (organizatorul a editat produsele) — toți clienții
  /// conectați trebuie să primească noul meniu.
  void menuChanged() {
    _affected = null;
    notifyListeners();
  }

  void _notifyOnly(String viewerId) {
    _affected = {viewerId};
    notifyListeners();
  }

  @override
  Set<String>? takeAffectedViewers() {
    final a = _affected;
    _affected = null;
    return a;
  }

  @override
  bool get acceptsPlayersWhileStarted => true;

  List<Order> get allOrders => List.unmodifiable(_orders);

  @override
  void addPlayer({required String id, required String name, required bool isHost}) {
    _players.add(_MenuPlayerInfo(id: id, name: name));
    _notifyOnly(id);
  }

  @override
  void markDisconnected(String id) {
    final matches = _players.where((p) => p.id == id);
    if (matches.isEmpty) return;
    matches.first.connected = false;
    _affected = const {};
    notifyListeners();
  }

  @override
  void markConnected(String id) {
    final matches = _players.where((p) => p.id == id);
    if (matches.isEmpty) return;
    matches.first.connected = true;
    _notifyOnly(id);
  }


  @override
  void startGame() {
    started = true;
  }

  @override
  void applyAction(String playerId, Map<String, dynamic> action) {
    final type = action['type'];
    if (type == 'submit_order') {
      _submitOrder(playerId, action);
    } else if (type == 'request_bill') {
      _requestBill(playerId, action);
    } else {
      throw GameError('err.unknownAction');
    }
  }

  static String _readTableLabel(Map<String, dynamic> action) {
    final rawLabel = action['tableLabel'];
    final tableLabel = (rawLabel is String ? rawLabel : '').trim();
    if (tableLabel.isEmpty) {
      throw GameError('err.menu.tableRequired');
    }
    if (tableLabel.length > maxTableLabelLength) {
      throw GameError('err.menu.tableTooLong');
    }
    return tableLabel;
  }

  /// Comenzile clientului care încă n-au intrat pe nicio notă (și nu sunt
  /// anulate) — ce mai are de plătit.
  List<Order> _unbilledOrdersOf(String customerId) {
    final billed = {
      for (final b in _bills)
        if (b.customerId == customerId) ...b.orderIds,
    };
    return _orders
        .where((o) => o.customerId == customerId && o.status != OrderStatus.cancelled && !billed.contains(o.id))
        .toList();
  }

  /// Cererea invitatului să i se aducă nota — una deschisă odată; totalul
  /// cuprinde comenzile lui încă nefacturate (poate fi și 0, dacă a comandat
  /// direct la ospătar).
  void _requestBill(String playerId, Map<String, dynamic> action) {
    final tableLabel = _readTableLabel(action);
    if (_bills.any((b) => b.customerId == playerId && !b.handled)) {
      throw GameError('err.menu.billAlreadyRequested');
    }
    final orders = _unbilledOrdersOf(playerId);
    _bills.insert(
      0,
      BillRequest(
        id: 'bill-${DateTime.now().microsecondsSinceEpoch}',
        customerId: playerId,
        tableLabel: tableLabel,
        totalCents: orders.fold(0, (sum, o) => sum + o.totalCents),
        orderIds: [for (final o in orders) o.id],
        createdAt: DateTime.now(),
      ),
    );
    var handled = 0;
    _bills.removeWhere((b) => b.handled && ++handled > maxHandledBillsKept);
    _notifyOnly(playerId);
  }

  /// Barul a dus nota la masă — apelat prin canalul de comenzi
  /// (`EventServerService.handleBill`), niciodată de un client.
  void markBillHandled(String billId) {
    final index = _bills.indexWhere((b) => b.id == billId);
    if (index == -1 || _bills[index].handled) return;
    _bills[index] = _bills[index].markHandled();
    _notifyOnly(_bills[index].customerId);
  }

  void _submitOrder(String playerId, Map<String, dynamic> action) {
    final tableLabel = _readTableLabel(action);
    final openOrders = _orders.where((o) =>
        o.customerId == playerId && (o.status == OrderStatus.placed || o.status == OrderStatus.preparing));
    if (openOrders.length >= maxOpenOrdersPerCustomer) {
      throw GameError('err.menu.tooManyOpen', {'max': maxOpenOrdersPerCustomer});
    }
    final rawLinesValue = action['lines'];
    final rawLines = rawLinesValue is List ? rawLinesValue : const [];
    if (rawLines.length > maxLinesPerOrder) {
      throw GameError('err.menu.tooManyLines');
    }
    final availableIds = MenuStore.instance.items.where((i) => i.available).map((i) => i.id).toSet();
    final lines = <OrderLine>[];
    for (final raw in rawLines) {
      if (raw is! Map) continue;
      final menuItemId = raw['menuItemId'];
      final quantity = raw['quantity'];
      if (menuItemId is! String || quantity is! int || quantity <= 0) continue;
      if (quantity > maxQuantityPerLine) {
        throw GameError('err.menu.maxQuantity', {'max': maxQuantityPerLine});
      }
      if (!availableIds.contains(menuItemId)) continue;
      final item = MenuStore.instance.items.firstWhere((i) => i.id == menuItemId);
      lines.add(OrderLine(menuItemId: item.id, name: item.name, quantity: quantity, unitPriceCents: item.priceCents));
    }
    if (lines.isEmpty) {
      throw GameError('err.menu.empty');
    }
    final rawNote = action['note'];
    var note = rawNote is String ? rawNote.trim() : null;
    if (note != null && note.length > maxNoteLength) note = note.substring(0, maxNoteLength);
    _orders.insert(
      0,
      Order(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        customerId: playerId,
        tableLabel: tableLabel,
        lines: lines,
        note: note == null || note.isEmpty ? null : note,
        status: OrderStatus.placed,
        createdAt: DateTime.now(),
      ),
    );
    _pruneClosedOrders();
    _notifyOnly(playerId);
  }

  void _pruneClosedOrders() {
    var closed = 0;
    for (var i = 0; i < _orders.length; i++) {
      final s = _orders[i].status;
      if (s != OrderStatus.ready && s != OrderStatus.cancelled) continue;
      closed++;
      if (closed > maxClosedOrdersKept) {
        _orders.removeAt(i);
        i--;
      }
    }
  }

  /// Trece comanda [orderId] în starea imediat următoare firească
  /// (nouă → în pregătire → livrată) — apelat de barman prin canalul de
  /// comenzi (`EventServerService.advanceOrder`), niciodată de un client.
  void advanceStatus(String orderId) {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) return;
    final current = _orders[index];
    final next = switch (current.status) {
      OrderStatus.placed => OrderStatus.preparing,
      OrderStatus.preparing => OrderStatus.ready,
      OrderStatus.ready => OrderStatus.ready,
      OrderStatus.cancelled => OrderStatus.cancelled,
    };
    _orders[index] = current.copyWith(status: next);
    _notifyOnly(current.customerId);
  }

  void cancelOrder(String orderId) {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) return;
    _orders[index] = _orders[index].copyWith(status: OrderStatus.cancelled);
    _notifyOnly(_orders[index].customerId);
  }

  @override
  Map<String, dynamic> snapshotFor(String viewerId) {
    return {
      'players': _players
          .where((p) => p.id == viewerId)
          .map((p) => {'id': p.id, 'name': p.name, 'isHost': false, 'connected': p.connected})
          .toList(),
      'started': started,
      'finished': false,
      'winnerId': null,
      'menu': {
        'categories': MenuStore.instance.categories.map((c) => c.toJson()).toList(),
        'items': MenuStore.instance.items.map((i) => i.toJson()).toList(),
        'currency': MenuStore.instance.currency,
      },
      'myOrders': _orders.where((o) => o.customerId == viewerId).map((o) => o.toJson()).toList(),
      // Cât ar fi pe nota cerută acum, și ultima cerere de notă a clientului.
      'billableTotalCents': _unbilledOrdersOf(viewerId).fold<int>(0, (sum, o) => sum + o.totalCents),
      'myBill': _bills.where((b) => b.customerId == viewerId).firstOrNull?.toJson(),
    };
  }
}
