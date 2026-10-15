import 'dart:async';

import 'package:flutter/foundation.dart';

import '../network/event_server_runner.dart';
import 'network_address.dart';
import 'qr_cards_store.dart';

/// Urmărește adresa de rețea a tabletei-server și o compară cu cea pentru
/// care s-au tipărit cartonașele QR ([QrCardsStore.printedIp]). Când diferă,
/// QR-ul de meniu de pe mese nu mai duce nicăieri și `QrAddressBanner` cere
/// retipărirea.
///
/// Verifică doar pe telefonul pe care rulează serverul — pe celelalte (și
/// în browser) nu e nimic de tipărit. Adresa se poate schimba și cu serverul
/// pornit (Wi-Fi reconectat), deci verificarea se repetă periodic cât timp
/// e afișat cel puțin un banner.
class QrAddressMonitor extends ChangeNotifier {
  QrAddressMonitor._();
  static final QrAddressMonitor instance = QrAddressMonitor._();

  static const Duration pollInterval = Duration(seconds: 10);

  String? _currentIp;
  bool _serverRunning = false;
  bool _generated = false;
  bool _minimized = false;
  int _attached = 0;
  Timer? _timer;

  String? get currentIp => _currentIp;

  bool get serverRunning => _serverRunning;

  /// `true` dacă tableta are altă adresă decât cea de pe cartonașele tipărite
  /// (sau cartonașele n-au fost tipărite niciodată).
  bool get needsReprint => _serverRunning && _currentIp != null && _currentIp != QrCardsStore.instance.printedIp;

  /// Cartonașele n-au fost tipărite niciodată pe acest telefon.
  bool get neverPrinted => QrCardsStore.instance.printedIp == null;

  /// Ospătarul a deschis deja „Generează QR" pentru adresa curentă.
  bool get generated => _generated;

  /// Avertizarea a fost restrânsă la o bară subțire.
  bool get minimized => _minimized;

  void attach() {
    _attached++;
    if (_attached == 1) {
      refresh();
      _timer = Timer.periodic(pollInterval, (_) => refresh());
    }
  }

  void detach() {
    _attached--;
    if (_attached <= 0) {
      _attached = 0;
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> refresh() async {
    final running = await EventServerRunner.isRunning;
    final ip = running ? await localNetworkIp() : null;
    if (running == _serverRunning && ip == _currentIp) return;
    if (ip != _currentIp) {
      // Adresă nouă: avertizarea pornește din nou, desfășurată.
      _generated = false;
      _minimized = false;
    }
    _serverRunning = running;
    _currentIp = ip;
    notifyListeners();
  }

  void markGenerated() {
    if (_generated) return;
    _generated = true;
    notifyListeners();
  }

  void setMinimized(bool value) {
    if (_minimized == value) return;
    _minimized = value;
    notifyListeners();
  }

  /// „Gata": cartonașele pentru adresa curentă sunt tipărite și puse pe mese.
  Future<void> confirmPrinted() async {
    final ip = _currentIp;
    if (ip == null) return;
    await QrCardsStore.instance.setPrintedIp(ip);
    _generated = false;
    _minimized = false;
    notifyListeners();
  }
}
