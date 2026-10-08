/// Starea unei comenzi, în ordinea firească de progres — `cancelled` e
/// singura stare terminală care nu vine din progresul normal (produs
/// epuizat, comandă greșită etc.).
enum OrderStatus { placed, preparing, ready, cancelled }

OrderStatus orderStatusFromJson(String value) =>
    OrderStatus.values.firstWhere((s) => s.name == value, orElse: () => OrderStatus.placed);

/// O linie din comandă — [name] e o copie a numelui produsului la momentul
/// comenzii, ca o comandă veche să rămână lizibilă chiar dacă organizatorul
/// redenumește sau șterge produsul din meniu ulterior.
class OrderLine {
  final String menuItemId;
  final String name;
  final int quantity;

  const OrderLine({required this.menuItemId, required this.name, required this.quantity});

  Map<String, dynamic> toJson() => {'menuItemId': menuItemId, 'name': name, 'quantity': quantity};

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
        menuItemId: json['menuItemId'] as String,
        name: json['name'] as String,
        quantity: json['quantity'] as int,
      );
}

/// O comandă trimisă la bar. Fără preț/total — e o notificare către bar, nu
/// o casă de marcat; plata rămâne cash, discutată direct la masă.
class Order {
  final String id;
  final String customerId;
  final String tableLabel;
  final List<OrderLine> lines;
  final String? note;
  final OrderStatus status;
  final DateTime createdAt;

  const Order({
    required this.id,
    required this.customerId,
    required this.tableLabel,
    required this.lines,
    this.note,
    required this.status,
    required this.createdAt,
  });

  Order copyWith({OrderStatus? status}) => Order(
        id: id,
        customerId: customerId,
        tableLabel: tableLabel,
        lines: lines,
        note: note,
        status: status ?? this.status,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerId': customerId,
        'tableLabel': tableLabel,
        'lines': lines.map((l) => l.toJson()).toList(),
        'note': note,
        'status': status.name,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as String,
        customerId: json['customerId'] as String,
        tableLabel: json['tableLabel'] as String,
        lines: (json['lines'] as List).map((l) => OrderLine.fromJson(Map<String, dynamic>.from(l as Map))).toList(),
        note: json['note'] as String?,
        status: orderStatusFromJson(json['status'] as String),
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      );
}
