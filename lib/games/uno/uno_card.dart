enum UnoColor { red, yellow, green, blue }

enum UnoCardType { number, skip, reverse, drawTwo, wild, wildDrawFour }

extension UnoColorDisplay on UnoColor {
  String get label {
    switch (this) {
      case UnoColor.red:
        return 'Roșu';
      case UnoColor.yellow:
        return 'Galben';
      case UnoColor.green:
        return 'Verde';
      case UnoColor.blue:
        return 'Albastru';
    }
  }
}

/// O carte UNO: cărțile colorate (number/skip/reverse/drawTwo) au mereu o
/// [color]; cărțile wild (wild/wildDrawFour) sunt necolorate în mână —
/// culoarea aleasă la joc se ține separat, în starea motorului
/// ([UnoEngine.activeColor]), nu pe carte.
class UnoCard {
  final UnoColor? color;
  final UnoCardType type;
  final int? number;

  const UnoCard({this.color, required this.type, this.number});

  bool get isWild => type == UnoCardType.wild || type == UnoCardType.wildDrawFour;

  /// Punctajul cărții pentru scorul de final de mână: cărțile numerice
  /// valorează cifra lor, cele de acțiune colorate 20, iar wild-urile 50.
  int get points {
    switch (type) {
      case UnoCardType.number:
        return number!;
      case UnoCardType.skip:
      case UnoCardType.reverse:
      case UnoCardType.drawTwo:
        return 20;
      case UnoCardType.wild:
      case UnoCardType.wildDrawFour:
        return 50;
    }
  }

  Map<String, dynamic> toJson() => {
        'color': color?.name,
        'type': type.name,
        'number': number,
      };

  factory UnoCard.fromJson(Map<String, dynamic> json) => UnoCard(
        color: json['color'] == null ? null : UnoColor.values.byName(json['color'] as String),
        type: UnoCardType.values.byName(json['type'] as String),
        number: json['number'] as int?,
      );

  @override
  bool operator ==(Object other) =>
      other is UnoCard && other.color == color && other.type == type && other.number == number;

  @override
  int get hashCode => Object.hash(color, type, number);

  @override
  String toString() => isWild ? type.name : '${color!.name}-${number ?? type.name}';

  /// Pachetul complet, 108 cărți: per culoare — un 0, câte două cărți de la
  /// 1 la 9, câte două Skip/Reverse/+2 (25 cărți × 4 culori = 100), plus 4
  /// Wild și 4 Wild +4.
  static List<UnoCard> fullDeck() {
    final cards = <UnoCard>[];
    for (final color in UnoColor.values) {
      cards.add(UnoCard(color: color, type: UnoCardType.number, number: 0));
      for (var n = 1; n <= 9; n++) {
        cards.add(UnoCard(color: color, type: UnoCardType.number, number: n));
        cards.add(UnoCard(color: color, type: UnoCardType.number, number: n));
      }
      for (var i = 0; i < 2; i++) {
        cards.add(UnoCard(color: color, type: UnoCardType.skip));
        cards.add(UnoCard(color: color, type: UnoCardType.reverse));
        cards.add(UnoCard(color: color, type: UnoCardType.drawTwo));
      }
    }
    for (var i = 0; i < 4; i++) {
      cards.add(const UnoCard(type: UnoCardType.wild));
      cards.add(const UnoCard(type: UnoCardType.wildDrawFour));
    }
    return cards;
  }
}
