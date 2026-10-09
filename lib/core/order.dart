/// Starea unei comenzi, în ordinea firească de progres — `cancelled` e
/// singura stare terminală care nu vine din progresul normal (produs
/// epuizat, comandă greșită etc.).
enum OrderStatus { placed, preparing, ready, delivered, cancelled }

OrderStatus orderStatusFromJson(String value) =>
    OrderStatus.values.firstWhere((s) => s.name == value, orElse: () => OrderStatus.placed);

/// O linie din comandă — [name] și [unitPriceCents] sunt copii ale numelui
/// și prețului produsului la momentul comenzii, ca o comandă veche să rămână
/// corectă chiar dacă organizatorul schimbă sau șterge produsul ulterior.
class OrderLine {
  final String menuItemId;
  final String name;
  final int quantity;

  /// Prețul unitar în bani; `null` pentru produse fără preț setat.
  final int? unitPriceCents;

  const OrderLine({required this.menuItemId, required this.name, required this.quantity, this.unitPriceCents});

  int get lineTotalCents => (unitPriceCents ?? 0) * quantity;

  Map<String, dynamic> toJson() => {
        'menuItemId': menuItemId,
        'name': name,
        'quantity': quantity,
        if (unitPriceCents != null) 'unitPriceCents': unitPriceCents,
      };

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
        menuItemId: json['menuItemId'] as String,
        name: json['name'] as String,
        quantity: json['quantity'] as int,
        unitPriceCents: json['unitPriceCents'] as int?,
      );
}

/// O comandă trimisă la bar, cu prețurile din momentul comenzii — barul vede
/// totalul de încasat, plata se face la masă.
class Order {
  final String id;
  final String customerId;
  final String tableLabel;
  final List<OrderLine> lines;
  final String? note;
  final OrderStatus status;
  final DateTime createdAt;

  /// Când a fost închisă masa (comanda achitată) — `null` cât timp comanda
  /// e încă „deschisă" pe masă. O comandă închisă trece în istoricul barului.
  final DateTime? closedAt;

  /// `true` dacă n-a închis-o barul, ci a expirat singură (masa a rămas
  /// deschisă prea mult) — în istoric apare ca neachitată.
  final bool autoClosed;

  const Order({
    required this.id,
    required this.customerId,
    required this.tableLabel,
    required this.lines,
    this.note,
    required this.status,
    required this.createdAt,
    this.closedAt,
    this.autoClosed = false,
  });

  /// Totalul comenzii, în bani.
  int get totalCents => lines.fold(0, (sum, l) => sum + l.lineTotalCents);

  bool get isClosed => closedAt != null;

  /// Comenzile pe care barul încă le are de făcut sau de dus la masă.
  bool get needsWork =>
      !isClosed && (status == OrderStatus.placed || status == OrderStatus.preparing || status == OrderStatus.ready);

  /// Masa, normalizată pentru grupare („ 3", „3" și „Masa 3" scrise diferit
  /// de clienți nu se potrivesc — dar spațiile și literele mari/mici da).
  String get tableKey => tableKeyOf(tableLabel);

  static String tableKeyOf(String label) => label.trim().toLowerCase();

  Order copyWith({OrderStatus? status, DateTime? closedAt, bool? autoClosed}) => Order(
        id: id,
        customerId: customerId,
        tableLabel: tableLabel,
        lines: lines,
        note: note,
        status: status ?? this.status,
        createdAt: createdAt,
        closedAt: closedAt ?? this.closedAt,
        autoClosed: autoClosed ?? this.autoClosed,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerId': customerId,
        'tableLabel': tableLabel,
        'lines': lines.map((l) => l.toJson()).toList(),
        'note': note,
        'status': status.name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        if (closedAt != null) 'closedAt': closedAt!.millisecondsSinceEpoch,
        if (autoClosed) 'autoClosed': true,
      };

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as String,
        customerId: json['customerId'] as String,
        tableLabel: json['tableLabel'] as String,
        lines: (json['lines'] as List).map((l) => OrderLine.fromJson(Map<String, dynamic>.from(l as Map))).toList(),
        note: json['note'] as String?,
        status: orderStatusFromJson(json['status'] as String),
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        closedAt: json['closedAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(json['closedAt'] as int),
        autoClosed: json['autoClosed'] as bool? ?? false,
      );
}
