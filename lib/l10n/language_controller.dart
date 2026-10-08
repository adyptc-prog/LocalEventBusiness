import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _prefsKey = 'app_language_v1';

/// Limbile în care poate rula aplicația. Codul limbii e și cel folosit de
/// `Locale` (pentru textele generate de Flutter însuși: butoane de sistem,
/// tooltip-uri etc.).
enum AppLanguage {
  ro('RO', 'Română'),
  en('EN', 'English');

  final String shortLabel;
  final String nativeName;
  const AppLanguage(this.shortLabel, this.nativeName);

  Locale get locale => Locale(name);
}

/// Limba curentă a aplicației — persistată per dispozitiv (fiecare telefon
/// sau browser își alege singur limba, independent de server și de ceilalți
/// jucători). Trebuie inițializat (`await init()`) înainte de `runApp` și,
/// separat, în isolate-ul serverului (pentru textele notificării Android).
class LanguageController extends ChangeNotifier {
  LanguageController._();
  static final LanguageController instance = LanguageController._();

  AppLanguage _language = AppLanguage.ro;
  SharedPreferences? _prefs;

  AppLanguage get language => _language;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final stored = _prefs!.getString(_prefsKey);
    _language = AppLanguage.values.firstWhere((l) => l.name == stored, orElse: () => AppLanguage.ro);
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (language == _language) return;
    _language = language;
    notifyListeners();
    await _prefs?.setString(_prefsKey, language.name);
  }

  /// Trece la următoarea limbă disponibilă (butonul din bara de sus).
  Future<void> toggle() {
    final next = AppLanguage.values[(_language.index + 1) % AppLanguage.values.length];
    return setLanguage(next);
  }

  /// Doar pentru teste — setează limba fără persistență.
  @visibleForTesting
  void debugSetLanguage(AppLanguage language) {
    _language = language;
    notifyListeners();
  }
}
