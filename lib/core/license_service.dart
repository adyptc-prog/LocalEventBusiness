import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform_support.dart';

/// Licența aplicației Android — același model ca în Organizator.
///
/// La prima pornire începe o perioadă de probă de 30 de zile, cu toate
/// funcțiile. După ea, aplicația cere o licență: un fișier semnat, emis pe
/// codul de instalare al telefonului — cumpărat de pe site sau emis manual
/// de organizator de pe PC. Verificarea (semnătură, cod, expirare, ceas dat
/// înapoi) și calculul probei se fac nativ (`LicenseStore`, Kotlin).
///
/// Clientul web (meniul din QR, în browser) nu are licență și nu e afectat.
class LicenseService extends ChangeNotifier {
  LicenseService._();
  static final LicenseService instance = LicenseService._();

  static const MethodChannel _channel = MethodChannel('local_event_business/license');
  static const String _expiryWarnedKey = 'license_expiry_warned_on';

  /// Pagina de unde se cumpără licența.
  static const String purchaseUrl = 'voltacademy.app/localeventbusiness.html';

  static const int expiryWarningDays = 10;

  /// Testele rulează pe desktop — permite simularea Android-ului.
  @visibleForTesting
  static bool? debugIsAndroid;

  static bool get isSupported => debugIsAndroid ?? isAndroidApp;

  String status = 'missing'; // 'active' | 'invalid' | 'missing'
  String message = '';
  String? validUntil;
  int? daysUntilExpiry;
  bool isLifetime = false;
  bool trialActive = false;
  int trialDaysLeft = 0;

  bool get isLicensed => status == 'active';

  /// `true` dacă aplicația poate fi folosită: licență activă sau probă în curs.
  bool get canUse => !isSupported || isLicensed || trialActive;

  bool get isExpiringSoon =>
      isLicensed && !isLifetime && daysUntilExpiry != null && daysUntilExpiry! <= expiryWarningDays;

  DateTime? get validUntilLocal => validUntil == null ? null : DateTime.tryParse(validUntil!)?.toLocal();

  void _apply(Map<Object?, Object?>? r) {
    status = (r?['status'] as String?) ?? 'missing';
    message = (r?['message'] as String?) ?? '';
    validUntil = r?['validUntil'] as String?;
    daysUntilExpiry = r?['daysUntilExpiry'] as int?;
    isLifetime = (r?['isLifetime'] as bool?) ?? false;
    trialActive = (r?['trialActive'] as bool?) ?? false;
    trialDaysLeft = (r?['trialDaysLeft'] as int?) ?? 0;
  }

  /// Recitește licența și proba. Prima apelare pornește și perioada de probă.
  Future<void> refresh() async {
    if (!isSupported) return;
    try {
      _apply(await _channel.invokeMapMethod<Object?, Object?>('checkLicense'));
    } catch (_) {
      // Fără răspuns de la partea nativă nu știm nimic — aplicația rămâne
      // blocată până la următoarea verificare reușită.
      _apply(null);
    }
    notifyListeners();
  }

  Future<String> getBusinessId() async {
    if (!isSupported) return '';
    try {
      return await _channel.invokeMethod<String>('getBusinessId') ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Deschide selectorul de fișiere și importă licența aleasă. Un fișier
  /// invalid NU înlocuiește licența existentă — mesajul explică de ce a fost
  /// respins. Selectorul închis fără alegere: `success: false, message: ''`.
  Future<({bool success, String message})> pickLicenseFile() async {
    if (!isSupported) return (success: false, message: '');
    ({bool success, String message}) result;
    try {
      final r = await _channel.invokeMapMethod<Object?, Object?>('pickLicenseFile');
      result = (success: r?['status'] == 'active', message: (r?['message'] as String?) ?? '');
    } on PlatformException catch (e) {
      result = e.code == 'LICENSE_PICK_CANCELLED'
          ? (success: false, message: '')
          : (success: false, message: e.message ?? e.code);
    }
    await refresh();
    return result;
  }

  /// Avertizarea de expirare apare cel mult o dată pe zi.
  Future<bool> shouldWarnExpiryToday() async {
    if (!isExpiringSoon) return false;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = '${now.year}-${now.month}-${now.day}';
    if (prefs.getString(_expiryWarnedKey) == today) return false;
    await prefs.setString(_expiryWarnedKey, today);
    return true;
  }

  @visibleForTesting
  void debugReset() {
    debugIsAndroid = null;
    _apply(null);
  }
}
