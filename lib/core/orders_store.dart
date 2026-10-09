import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'bill_request.dart';
import 'order.dart';

const String _prefsKey = 'menu_orders_v1';
const String _billsKey = 'menu_bills_v1';

/// Comenzile la bar și cererile de notă, persistate pe telefonul-server ca o
/// repornire a serverului (Android omoară service-ul, organizatorul îl
/// repornește) să nu golească coada barului. Folosit doar din isolate-ul
/// serverului. Ce e mai vechi de [maxAge] e aruncat la încărcare — e dintr-o
/// seară anterioară, nu mai interesează pe nimeni.
class OrdersStore {
  OrdersStore._();
  static final OrdersStore instance = OrdersStore._();

  static const Duration maxAge = Duration(hours: 18);

  SharedPreferences? _prefs;
  List<Order> _loaded = const [];
  List<BillRequest> _loadedBills = const [];
  Timer? _saveDebounce;
  List<Order>? _pendingOrders;
  List<BillRequest>? _pendingBills;

  /// Comenzile încărcate la [init], cele mai noi primele.
  List<Order> get loaded => _loaded;

  /// Cererile de notă încărcate la [init], cele mai noi primele.
  List<BillRequest> get loadedBills => _loadedBills;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final cutoff = DateTime.now().subtract(maxAge);
    _loaded = _decode(_prefs!.getString(_prefsKey), Order.fromJson).where((o) => o.createdAt.isAfter(cutoff)).toList();
    _loadedBills =
        _decode(_prefs!.getString(_billsKey), BillRequest.fromJson).where((b) => b.createdAt.isAfter(cutoff)).toList();
  }

  static List<T> _decode<T>(String? raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Programează salvarea — comasată pe o fereastră scurtă, ca o rafală de
  /// schimbări (mai multe comenzi deodată) să scrie pe disc o singură dată.
  void save(List<Order> orders, List<BillRequest> bills) {
    _pendingOrders = orders;
    _pendingBills = bills;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), flush);
  }

  Future<void> flush() async {
    _saveDebounce?.cancel();
    final orders = _pendingOrders;
    final bills = _pendingBills;
    _pendingOrders = null;
    _pendingBills = null;
    if (orders != null) {
      await _prefs?.setString(_prefsKey, jsonEncode(orders.map((o) => o.toJson()).toList()));
    }
    if (bills != null) {
      await _prefs?.setString(_billsKey, jsonEncode(bills.map((b) => b.toJson()).toList()));
    }
  }
}
