import 'package:shared_preferences/shared_preferences.dart';

const String _cardCountKey = 'table_count_v1';
const String _wifiSsidKey = 'qr_wifi_ssid_v1';
const String _wifiPasswordKey = 'qr_wifi_password_v1';
const String _printedIpKey = 'qr_printed_ip_v1';

/// Datele cartonașelor cu coduri QR de pe mese (vezi `QrCardsScreen`):
/// același cartonaș pe toate mesele — un QR pentru Wi-Fi și unul pentru
/// meniu. Clientul își scrie singur masa în meniu, deci cartonașele nu mai
/// sunt numerotate.
///
/// [printedIp] e adresa tabletei pentru care s-au tipărit cartonașele. Dacă
/// tableta primește altă adresă, codul QR de meniu tipărit nu mai duce
/// nicăieri — `QrAddressMonitor` compară cele două și cere retipărirea.
class QrCardsStore {
  QrCardsStore._();
  static final QrCardsStore instance = QrCardsStore._();

  int _cardCount = 0;
  String _wifiSsid = '';
  String _wifiPassword = '';
  String? _printedIp;
  SharedPreferences? _prefs;

  /// Câte cartonașe se tipăresc (de obicei, câte mese are localul).
  int get cardCount => _cardCount;

  /// Numele rețelei Wi-Fi a localului — gol = cartonașul are doar QR-ul de meniu.
  String get wifiSsid => _wifiSsid;

  /// Parola Wi-Fi — goală = rețea deschisă.
  String get wifiPassword => _wifiPassword;

  String? get printedIp => _printedIp;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _cardCount = _prefs!.getInt(_cardCountKey) ?? 0;
    _wifiSsid = _prefs!.getString(_wifiSsidKey) ?? '';
    _wifiPassword = _prefs!.getString(_wifiPasswordKey) ?? '';
    _printedIp = _prefs!.getString(_printedIpKey);
  }

  Future<void> setCardCount(int count) async {
    _cardCount = count.clamp(0, 200);
    await _prefs?.setInt(_cardCountKey, _cardCount);
  }

  Future<void> setWifi({required String ssid, required String password}) async {
    _wifiSsid = ssid.trim();
    _wifiPassword = password;
    await _prefs?.setString(_wifiSsidKey, _wifiSsid);
    await _prefs?.setString(_wifiPasswordKey, _wifiPassword);
  }

  Future<void> setPrintedIp(String ip) async {
    _printedIp = ip;
    await _prefs?.setString(_printedIpKey, ip);
  }
}
