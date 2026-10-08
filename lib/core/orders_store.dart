import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'order.dart';

const String _prefsKey = 'menu_orders_v1';

/// Comenzile la bar, persistate pe telefonul-server ca o repornire a
/// serverului (Android omoară service-ul, organizatorul îl repornește) să
/// nu golească coada barului. Folosit doar din isolate-ul serverului.
/// Comenzile mai vechi de [maxAge] sunt aruncate la încărcare — sunt dintr-o
/// seară anterioară, nu mai interesează pe nimeni.
class OrdersStore {
  OrdersStore._();
  static final OrdersStore instance = OrdersStore._();

  static const Duration maxAge = Duration(hours: 18);

  SharedPreferences? _prefs;
  List<Order> _loaded = const [];
  Timer? _saveDebounce;
  List<Order>? _pending;

  /// Comenzile încărcate la [init], cele mai noi primele.
  List<Order> get loaded => _loaded;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_prefsKey);
    if (raw == null) return;
    try {
      final cutoff = DateTime.now().subtract(maxAge);
      _loaded = (jsonDecode(raw) as List)
          .map((o) => Order.fromJson(Map<String, dynamic>.from(o as Map)))
          .where((o) => o.createdAt.isAfter(cutoff))
          .toList();
    } catch (_) {
      _loaded = const [];
    }
  }

  /// Programează salvarea — comasată pe o fereastră scurtă, ca o rafală de
  /// schimbări (mai multe comenzi deodată) să scrie pe disc o singură dată.
  void save(List<Order> orders) {
    _pending = orders;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), flush);
  }

  Future<void> flush() async {
    _saveDebounce?.cancel();
    final orders = _pending;
    _pending = null;
    if (orders == null) return;
    await _prefs?.setString(_prefsKey, jsonEncode(orders.map((o) => o.toJson()).toList()));
  }
}
