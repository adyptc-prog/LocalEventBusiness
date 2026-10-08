import 'uno_card.dart';

class UnoPlayer {
  final String id;
  final String name;
  final bool isHost;
  List<UnoCard> hand;
  bool connected;

  UnoPlayer({
    required this.id,
    required this.name,
    required this.isHost,
    List<UnoCard>? hand,
    this.connected = true,
  }) : hand = hand ?? [];
}
