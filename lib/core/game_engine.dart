import 'package:flutter/foundation.dart';

/// Id-ul sintetic de „viewer" folosit de un spectator (organizatorul, prin
/// `RoomSession.attachSpectator` — vezi `room_session.dart`), niciodată un
/// id real de jucător. Definit aici, nu în `room_session.dart`, ca motoarele
/// de joc care trebuie să dezvăluie mai mult unui spectator decât unui
/// jucător obișnuit (ex: `WishEngine`, identitatea reală din spatele unei
/// urări anonime) să-l poată recunoaște fără să depindă de stratul de rețea.
const String spectatorViewerId = '__spectator__';

/// Contract comun pe care trebuie să-l respecte motorul de reguli al
/// oricărui joc din bibliotecă, pentru ca `RoomSession`/[ClientService] și
/// ecranele generice (lobby) să poată lucra cu el fără să știe nimic despre
/// regulile specifice jocului.
///
/// [snapshotFor] întoarce JSON brut, personalizat per-viewer (ex: fiecare
/// jucător își vede doar propria mână). Contractul minim pe care trebuie
/// să-l respecte acel JSON — folosit generic de ecranul de lobby — este să
/// includă cheile:
///  - `players`: listă de `{id, name, isHost, connected}`
///  - `started`: bool
/// Restul cheilor sunt specifice jocului și decodate doar de ecranul lui.
abstract class GameEngine extends ChangeNotifier {
  int get minPlayers;
  int get maxPlayers;
  bool get started;

  /// Adaugă un jucător în cameră (înainte de începerea jocului).
  /// Aruncă [StateError] dacă regulile jocului nu permit (ex: cameră plină).
  void addPlayer({required String id, required String name, required bool isHost});

  /// Marchează un jucător ca deconectat, fără să-l scoată din partidă.
  void markDisconnected(String id);

  /// Marchează un jucător reconectat (același profil revine cu un canal
  /// nou) ca fiind din nou conectat — oglinda lui [markDisconnected].
  void markConnected(String id);

  /// Pornește partida. Aruncă [StateError] dacă precondițiile nu sunt îndeplinite.
  void startGame();

  /// Aplică o acțiune trimisă de un jucător (mesaj generic, specific jocului).
  /// Aruncă [StateError] la o mutare invalidă.
  void applyAction(String playerId, Map<String, dynamic> action);

  /// `true` doar pentru activitățile „mereu deschise" (chat, meniu), unde un
  /// participant nou poate intra oricând. Pentru un joc, cât [started] e
  /// `true`, serverul refuză jucători noi (doar reconectările celor deja în
  /// partidă trec) — altfel ar apărea în ordinea turelor fără mână/fise.
  bool get acceptsPlayersWhileStarted => false;

  /// Acțiuni pe care serverul le poate încerca, în ordine, în numele unui
  /// jucător deconectat de prea mult timp, ca partida să nu rămână blocată
  /// pe tura lui (vezi `RoomSession`). Se aplică prima pe care
  /// [applyAction] o acceptă — validarea rămâne cea normală a motorului,
  /// deci o candidată ilegală (nu e rândul lui, carte nepermisă) e pur și
  /// simplu sărită. Ordinea preferă acțiunile cele mai pasive (trage, pas,
  /// fold) înaintea jucării unei cărți.
  List<Map<String, dynamic>> autoActionCandidates(String playerId) => const [];

  /// Pe cine afectează ultima schimbare notificată — `null` înseamnă „pe
  /// toți" (implicit). Un motor cu sute de participanți independenți (Meniu)
  /// îl folosește ca o comandă nouă să nu retrimită starea tuturor
  /// clienților, ci doar celui care a comandat. Citirea îl resetează.
  Set<String>? takeAffectedViewers() => null;

  /// Starea jocului așa cum trebuie văzută de [viewerId], ca JSON.
  Map<String, dynamic> snapshotFor(String viewerId);

  /// Punctajul specific jocului (regulile lui de scor) pentru fiecare
  /// jucător din ultima partidă încheiată — `null` cât timp jocul e activ
  /// sau înainte să fi fost jucată vreo partidă. Motorul îl calculează o
  /// singură dată, exact când partida se termină (când setează un
  /// câștigător); rămâne populat până la următorul `startGame()`.
  Map<String, int>? get lastMatchScores;
}
