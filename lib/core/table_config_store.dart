import 'package:shared_preferences/shared_preferences.dart';

const String _prefsKey = 'table_count_v1';
const String _wifiKey = 'table_wifi_info_v1';

/// Câte mese are localul — folosit doar de `TablesScreen` ca să genereze
/// codurile QR („Masa 1".."Masa N"). Serverul nu are nevoie să știe de mese:
/// eticheta mesei vine direct din parametrul `?table=N` al link-ului scanat,
/// nu e validată central — la fel ca profilul jucătorului, e o comoditate
/// locală a acestui ecran, nu o regulă de rețea.
class TableConfigStore {
  TableConfigStore._();
  static final TableConfigStore instance = TableConfigStore._();

  int _tableCount = 0;
  String _wifiInfo = '';
  SharedPreferences? _prefs;

  int get tableCount => _tableCount;

  /// Text opțional tipărit pe cartonașele meselor (ex: numele rețelei Wi-Fi
  /// și parola) — invitatul trebuie să fie pe rețeaua localului ca să
  /// deschidă meniul din QR.
  String get wifiInfo => _wifiInfo;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _tableCount = _prefs!.getInt(_prefsKey) ?? 0;
    _wifiInfo = _prefs!.getString(_wifiKey) ?? '';
  }

  Future<void> setWifiInfo(String info) async {
    _wifiInfo = info.trim();
    await _prefs?.setString(_wifiKey, _wifiInfo);
  }

  Future<void> setTableCount(int count) async {
    _tableCount = count < 0 ? 0 : count;
    await _prefs?.setInt(_prefsKey, _tableCount);
  }
}
