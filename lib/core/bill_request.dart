/// Cererea unui invitat ca barul să-i aducă nota la masă. [totalCents] și
/// [orderIds] cuprind comenzile lui încă nefacturate (nici anulate, nici
/// incluse într-o notă anterioară) — o comandă nouă după o notă adusă intră
/// în nota următoare.
class BillRequest {
  final String id;
  final String customerId;
  final String tableLabel;
  final int totalCents;
  final List<String> orderIds;
  final DateTime createdAt;

  /// `true` după ce barul a marcat nota ca adusă la masă.
  final bool handled;

  const BillRequest({
    required this.id,
    required this.customerId,
    required this.tableLabel,
    required this.totalCents,
    required this.orderIds,
    required this.createdAt,
    this.handled = false,
  });

  BillRequest markHandled() => BillRequest(
        id: id,
        customerId: customerId,
        tableLabel: tableLabel,
        totalCents: totalCents,
        orderIds: orderIds,
        createdAt: createdAt,
        handled: true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerId': customerId,
        'tableLabel': tableLabel,
        'totalCents': totalCents,
        'orderIds': orderIds,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'handled': handled,
      };

  factory BillRequest.fromJson(Map<String, dynamic> json) => BillRequest(
        id: json['id'] as String,
        customerId: json['customerId'] as String,
        tableLabel: json['tableLabel'] as String,
        totalCents: json['totalCents'] as int? ?? 0,
        orderIds: (json['orderIds'] as List? ?? const []).cast<String>(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        handled: json['handled'] as bool? ?? false,
      );
}
