import '../../models/card.dart';

class MacaoPlayer {
  final String id;
  final String name;
  final bool isHost;
  List<PlayingCard> hand;
  bool connected;

  MacaoPlayer({
    required this.id,
    required this.name,
    required this.isHost,
    List<PlayingCard>? hand,
    this.connected = true,
  }) : hand = hand ?? [];
}
