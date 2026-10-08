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
  Set<String>? _affected;

  /// Repune comenzile salvate (vezi `OrdersStore`) după o repornire a
  /// serverului — apelat o singură dată, înainte de orice client.
  void restoreOrders(List<Order> orders) {
    _orders
      ..clear()
      ..addAll(orders);
  }

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
    } else {
      throw GameError('err.unknownAction');
    }
  }

  void _submitOrder(String playerId, Map<String, dynamic> action) {
    final rawLabel = action['tableLabel'];
    final tableLabel = (rawLabel is String ? rawLabel : '').trim();
    if (tableLabel.isEmpty) {
      throw GameError('err.menu.tableRequired');
    }
    if (tableLabel.length > maxTableLabelLength) {
      throw GameError('err.menu.tableTooLong');
    }
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
      lines.add(OrderLine(menuItemId: item.id, name: item.name, quantity: quantity));
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
      },
      'myOrders': _orders.where((o) => o.customerId == viewerId).map((o) => o.toJson()).toList(),
    };
  }
}
