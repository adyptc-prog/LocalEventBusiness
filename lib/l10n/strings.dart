import 'strings/errors.dart';
import 'strings/games.dart';
import 'strings/screens.dart';

/// Dicționarul complet al aplicației: cheie → (română, engleză). Împărțit pe
/// fișiere doar ca să rămână ușor de parcurs; testul
/// `test/l10n_test.dart` verifică să nu existe chei duplicate între ele,
/// chei folosite în cod dar lipsă de aici, ori placeholder-e `{nume}`
/// diferite între cele două limbi.
final Map<String, (String, String)> allStrings = {
  '_literal': ('{text}', '{text}'),
  ...errorStrings,
  ...gameStrings,
  ...screenStrings,
};

/// Toate hărțile, separat — doar pentru testul de chei duplicate.
const List<Map<String, (String, String)>> stringTables = [errorStrings, gameStrings, screenStrings];
