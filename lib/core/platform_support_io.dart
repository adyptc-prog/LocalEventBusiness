import 'dart:io';

/// Găzduirea serverului evenimentului (foreground service, HttpServer,
/// beacon UDP) e disponibilă doar pe Android — pe desktop (Windows/Linux/
/// macOS) codul de rețea ar compila, dar `flutter_foreground_task` nu are
/// implementare nativă acolo, deci ar eșua la rulare.
bool get canHostEventServer => Platform.isAndroid;

/// Aplicația rulează pe un telefon Android (nu pe web sau desktop) — doar
/// acolo există licența (`LicenseService`).
bool get isAndroidApp => Platform.isAndroid;
