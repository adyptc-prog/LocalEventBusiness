import 'game_definition.dart';
import 'games_registry.dart';
import '../games/chat/chat_definition.dart';
import '../games/menu/menu_definition.dart';

/// Toate activitățile pe care aplicația știe să le ruleze — jocurile de
/// cărți din [availableGames], chat-ul general și meniul de comenzi la bar,
/// care nu apar în [availableGames] fiindcă nu sunt „mese de joc", ci
/// propriul buton în meniu. Acesta e catalogul *complet*, indiferent ce a
/// activat organizatorul pentru localul curent — vezi [EventConfigStore]
/// pentru selecția per-local.
final List<GameDefinition> activityCatalog = [
  ...availableGames,
  chatDefinition,
  menuDefinition,
];

/// Numele activității [id] în limba curentă — pentru ce vine de la server
/// doar ca id (lista de camere, rezultate de partide). [fallback] (titlul
/// trimis de server) rămâne pentru o activitate necunoscută acestui client.
String activityTitleFor(String id, {String? fallback}) {
  for (final activity in activityCatalog) {
    if (activity.id == id) return activity.title;
  }
  return fallback ?? id;
}
