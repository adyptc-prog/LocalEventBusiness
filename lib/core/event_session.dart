/// Serverul de eveniment ales de invitat la „Intră la eveniment” — ca
/// Chat, Jocuri și Meniu să se conecteze direct la el, fără ca invitatul
/// să aleagă încă o dată serverul.
class EventSession {
  EventSession._();

  static String? host;
  static int? port;

  static void remember(String host, int port) {
    EventSession.host = host;
    EventSession.port = port;
  }
}
