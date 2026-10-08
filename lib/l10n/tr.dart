import 'language_controller.dart';
import 'strings.dart';

export 'language_controller.dart' show AppLanguage, LanguageController;

/// Traduce cheia [key] în limba curentă a aplicației, înlocuind fiecare
/// `{nume}` din șablon cu `args['nume']`. O cheie lipsă din limba curentă
/// cade pe română, iar una lipsă cu totul se afișează ca atare (ușor de
/// observat în UI, fără să strice aplicația).
String tr(String key, [Map<String, Object?> args = const {}]) =>
    trIn(LanguageController.instance.language, key, args);

/// Ca [tr], dar într-o limbă anume — folosit de server pentru textul de
/// rezervă (în română) trimis clienților vechi, care nu știu de chei.
String trIn(AppLanguage language, String key, [Map<String, Object?> args = const {}]) {
  final entry = allStrings[key];
  if (entry == null) return key;
  var template = language == AppLanguage.en ? entry.$2 : entry.$1;
  if (args.isEmpty) return template;
  args.forEach((name, value) {
    template = template.replaceAll('{$name}', '${value ?? ''}');
  });
  return template;
}

/// Un text de afișat, transportat ca cheie + argumente în loc de text gata
/// tradus — pentru tot ce generează serverul (erori, rezumate de mână,
/// evenimente de joc). Serverul e comun, dar fiecare client își alege limba,
/// deci traducerea se face abia pe client, la afișare.
class LocalizedText {
  final String key;
  final Map<String, Object?> args;

  const LocalizedText(this.key, [this.args = const {}]);

  String resolve() => tr(key, args);

  Map<String, dynamic> toJson() => {'key': key, if (args.isNotEmpty) 'args': args};

  /// Acceptă și un text simplu (de la un server vechi, dinainte de chei) —
  /// afișat atunci exact cum a venit.
  static LocalizedText? fromJson(Object? json) {
    if (json == null) return null;
    if (json is String) return LocalizedText.literal(json);
    if (json is Map) {
      final key = json['key'];
      if (key is! String) return null;
      final rawArgs = json['args'];
      return LocalizedText(key, rawArgs is Map ? Map<String, Object?>.from(rawArgs) : const {});
    }
    return null;
  }

  /// Un text deja final, netradus (ex: de la un server vechi).
  factory LocalizedText.literal(String text) => LocalizedText(literalKey, {'text': text});

  static const String literalKey = '_literal';
}

/// Eroare de joc/server cu mesaj traductibil. Motoarele de joc o aruncă în
/// loc de un `StateError` simplu; serverul trimite clientului cheia și
/// argumentele, iar clientul afișează mesajul în limba lui.
class GameError extends StateError {
  final String key;
  final Map<String, Object?> args;

  GameError(this.key, [this.args = const {}]) : super(trIn(AppLanguage.ro, key, args));

  LocalizedText get text => LocalizedText(key, args);

  @override
  String toString() => message;
}
