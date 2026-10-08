import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

/// Dezarhivează în memorie clientul web (`assets/web_client.zip`, produs de
/// `flutter build web` + `build_web_client.ps1`) ca gazda să-l poată servi
/// direct printr-un [HttpServer], fără să scrie fișiere reale pe disc.
/// Dezarhivarea se face o singură dată per rulare a aplicației (cache static).
class WebAssetBundle {
  static Map<String, Uint8List>? _cache;

  /// Cale (relativă la rădăcina site-ului, ex: `index.html`, `main.dart.js`,
  /// `assets/AssetManifest.json`) → conținutul fișierului.
  static Future<Map<String, Uint8List>> load() async {
    final cached = _cache;
    if (cached != null) return cached;

    final data = await rootBundle.load('assets/web_client.zip');
    final archive = ZipDecoder().decodeBytes(data.buffer.asUint8List());

    final files = <String, Uint8List>{};
    for (final file in archive) {
      if (!file.isFile) continue;
      files[file.name] = file.content as Uint8List;
    }
    _cache = files;
    return files;
  }

  /// Ghicește `Content-Type` din extensia fișierului, suficient pentru un
  /// build Flutter Web (HTML/JS, JSON, fonturi, imagini, WASM pentru CanvasKit).
  static String contentTypeFor(String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot == -1 ? '' : path.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'html':
        return 'text/html; charset=utf-8';
      case 'js':
      case 'mjs':
        return 'application/javascript; charset=utf-8';
      case 'json':
        return 'application/json; charset=utf-8';
      case 'css':
        return 'text/css; charset=utf-8';
      case 'wasm':
        return 'application/wasm';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'svg':
        return 'image/svg+xml';
      case 'ico':
        return 'image/x-icon';
      case 'ttf':
        return 'font/ttf';
      case 'otf':
        return 'font/otf';
      case 'woff':
        return 'font/woff';
      case 'woff2':
        return 'font/woff2';
      default:
        return 'application/octet-stream';
    }
  }
}
