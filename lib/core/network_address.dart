import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

/// Adresa IPv4 la care invitații de pe aceeași rețea pot ajunge la acest
/// telefon — pentru link-ul și codurile QR ale serverului.
///
/// `NetworkInfo().getWifiIP()` merge când telefonul e *conectat* la un Wi-Fi,
/// dar când telefonul *face* hotspot, Wi-Fi-ul lui e oprit și nu întoarce
/// nimic — atunci căutăm direct adresa interfeței de hotspot (`ap0`,
/// `swlan0`, `wlan1`…), ignorând datele mobile și VPN-urile.
Future<String?> localNetworkIp() async {
  try {
    final wifi = await NetworkInfo().getWifiIP();
    if (wifi != null && wifi.isNotEmpty && wifi != '0.0.0.0') return wifi;
  } catch (_) {
    // plugin indisponibil sau permisiune refuzată — încercăm interfețele
  }
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    String? fallback;
    for (final iface in interfaces) {
      final name = iface.name.toLowerCase();
      if (_isMobileOrVpn(name)) continue;
      for (final addr in iface.addresses) {
        if (addr.isLoopback || !_isPrivate(addr.address)) continue;
        if (_isLocalWireless(name)) return addr.address;
        fallback ??= addr.address;
      }
    }
    return fallback;
  } catch (_) {
    return null;
  }
}

bool _isLocalWireless(String name) =>
    name.startsWith('ap') || name.startsWith('swlan') || name.startsWith('wlan') || name.startsWith('softap');

bool _isMobileOrVpn(String name) =>
    name.startsWith('rmnet') ||
    name.startsWith('ccmni') ||
    name.startsWith('tun') ||
    name.startsWith('ppp') ||
    name.startsWith('dummy') ||
    name.startsWith('v4-');

bool _isPrivate(String ip) {
  final parts = ip.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null)) return false;
  final a = parts[0]!, b = parts[1]!;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}
