import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Activarea aplicației Android pe un telefon.
///
/// APK-ul e același oriunde ar fi descărcat (site, WhatsApp); ce diferă e
/// cine l-a instalat — Android reține asta. La prima pornire, aplicația se
/// activează doar dacă a fost instalată de organizator: de pe calculator
/// (cablu USB / adb) sau din Google Play. Activarea e salvată în datele
/// aplicației, deci rămâne și după update-uri instalate de pe site — dar
/// dispare la dezinstalare. Pe un telefon unde prima instalare vine din alt
/// loc, aplicația rămâne blocată (vezi `NotActivatedApp`).
///
/// Clientul web (meniul deschis din QR, în browser) nu e afectat.
class InstallActivation {
  InstallActivation._();

  static const MethodChannel _channel = MethodChannel('local_event_business/install_source');
  static const String _prefsKey = 'install_activated_v1';

  /// `true` dacă aplicația poate porni normal pe acest dispozitiv.
  static Future<bool> check() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefsKey) ?? false) return true;
    try {
      final source = await _channel.invokeMapMethod<String, Object?>('getInstallSource') ?? const {};
      final trusted = isTrustedInstallSource(
        installer: source['installer'] as String?,
        initiator: source['initiator'] as String?,
        sdkInt: source['sdk'] as int? ?? 0,
      );
      if (trusted) await prefs.setBool(_prefsKey, true);
      return trusted;
    } catch (_) {
      // Nu știm de unde vine instalarea — nu activăm.
      return false;
    }
  }
}

/// Instalatorii în care avem încredere: Google Play și calculatorul
/// organizatorului (`adb install`, care apare ca `com.android.shell`).
@visibleForTesting
bool isTrustedInstallSource({String? installer, String? initiator, required int sdkInt}) {
  const playStore = 'com.android.vending';
  const adbShell = 'com.android.shell';
  if (installer == playStore) return true;
  if (installer == adbShell || initiator == adbShell) return true;
  // Înainte de Android 11 nu se știe cine a pornit instalarea; `adb install`
  // nu înregistrează niciun instalator, pe când un APK deschis din browser
  // sau WhatsApp trece prin instalatorul de pachete al telefonului.
  if (sdkInt < 30 && installer == null) return true;
  return false;
}
