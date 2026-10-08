import '../l10n/tr.dart';

/// Un mesaj de chat din sesiunea curentă. `toId == null` înseamnă mesaj
/// public (vizibil tuturor din cameră); altfel e privat, între [fromId] și
/// [toId]. Nu se persistă — există doar cât ține sesiunea live.
class ChatMessage {
  final String fromId;
  final String fromName;
  final String text;
  final String? toId;
  final String? toName;
  final DateTime timestamp;

  ChatMessage({
    required this.fromId,
    required this.fromName,
    required this.text,
    this.toId,
    this.toName,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isPrivate => toId != null;

  /// Id-ul de expeditor al mesajelor organizatorului (anunțuri, chat-ul
  /// din ecranul de monitorizare) — nu e un jucător real.
  static const String organizerId = '__organizer__';

  /// Numele de afișat: „Organizator" e tradus pe fiecare client, în limba
  /// lui; restul sunt nume reale de jucători, afișate ca atare.
  String get displayName => fromId == organizerId ? tr('chat.organizer') : fromName;

  Map<String, dynamic> toJson() => {
        'fromId': fromId,
        'fromName': fromName,
        'text': text,
        if (toId != null) 'toId': toId,
        if (toName != null) 'toName': toName,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        fromId: json['fromId'] as String,
        fromName: json['fromName'] as String,
        text: json['text'] as String,
        toId: json['toId'] as String?,
        toName: json['toName'] as String?,
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      );
}
