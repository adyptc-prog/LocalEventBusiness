import '../../models/card.dart';

class MacaoPlayer {
  final String id;
  final String name;
  final bool isHost;
  List<PlayingCard> hand;
  bool connected;

  /// Câte din tururile *lui* mai are de stat pe loc (după ce a acceptat o
  /// pedeapsă de mai multe cărți de 4) — se consumă câte unul de fiecare dată
  /// când rândul ar ajunge la el.
  int skipTurns = 0;

  MacaoPlayer({
    required this.id,
    required this.name,
    required this.isHost,
    List<PlayingCard>? hand,
    this.connected = true,
  }) : hand = hand ?? [];
}
