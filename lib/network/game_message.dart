import 'dart:convert';

/// Mesajele circulă ca JSON, câte un obiect per mesaj WebSocket — spre
/// deosebire de un socket TCP brut, WebSocket încadrează mesajele automat,
/// deci nu mai e nevoie de niciun framing suplimentar (fără linii, fără utf8 manual).
class GameMessage {
  static String encode(Map<String, dynamic> message) => jsonEncode(message);

  static Map<String, dynamic> decode(dynamic raw) =>
      jsonDecode(raw as String) as Map<String, dynamic>;
}
