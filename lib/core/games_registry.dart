import 'game_definition.dart';
import '../games/macao/macao_definition.dart';
import '../games/poker/poker_definition.dart';
import '../games/rent/rent_definition.dart';
import '../games/septica/septica_definition.dart';
import '../games/uno/uno_definition.dart';
import '../games/war/war_definition.dart';
import '../games/whist/whist_definition.dart';

/// Toate jocurile disponibile în bibliotecă. Un joc nou se adaugă aici,
/// după ce îi definești motorul ([GameEngine]) și ecranul de joc.
final List<GameDefinition> availableGames = [
  macaoDefinition,
  warDefinition,
  septicaDefinition,
  whistDefinition,
  rentDefinition,
  pokerDefinition,
  unoDefinition,
];
