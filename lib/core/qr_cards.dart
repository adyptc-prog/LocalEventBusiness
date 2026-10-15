import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/tr.dart';
import '../network/event_server_service.dart';

/// Link-ul tipărit în QR-ul de meniu: deschide direct meniul de comandă
/// (`?menu`), fără număr de masă — clientul și-l scrie singur.
String menuUrlFor(String ip) => 'http://$ip:${EventServerService.webPort}/?menu';

/// `true` când clientul web a fost deschis dintr-un QR de meniu — cel nou
/// (`?menu`) sau un cartonaș mai vechi, numerotat (`?table=N`).
bool openedFromMenuQr(Uri uri) => uri.queryParameters.containsKey('menu') || uri.queryParameters.containsKey('table');

/// Textul QR-ului care conectează telefonul la Wi-Fi (formatul `WIFI:`,
/// recunoscut de camera de pe Android și iPhone). Caracterele speciale din
/// nume și parolă se escapează cu `\`.
String wifiQrPayload({required String ssid, required String password}) {
  String esc(String v) => v.replaceAllMapped(RegExp(r'([\\;,:"])'), (m) => '\\${m[1]}');
  final security = password.isEmpty ? 'nopass' : 'WPA';
  return 'WIFI:T:$security;S:${esc(ssid)};${password.isEmpty ? '' : 'P:${esc(password)};'};';
}

/// Cartonașul de pus pe mese, gata de tipărit: imaginea lui
/// ([renderCardPng]) și un PDF A4 cu mai multe exemplare, câte 6 pe pagină
/// ([buildCardsPdf]). Același cartonaș pe toate mesele: QR-ul de Wi-Fi și
/// QR-ul de meniu. Textul e în ambele limbi — limba aplicației mare,
/// cealaltă dedesubt, mică — fiindcă un cartonaș tipărit rămâne pe masă
/// pentru orice invitat.
class QrCards {
  QrCards._();

  /// Lățimea în pixeli a unui cartonaș (cartonașul e pătrat) — destul pentru
  /// tipărire clară la ~9 cm, cât are un cartonaș pe o pagină A4 de 6.
  static const int cardPixels = 1200;

  static const int cardsPerPage = 6;

  static const _green = Color(0xFF0B5E3B);

  /// Fonturile incluse în aplicație — aceleași pe orice telefon.
  static const _fontFamily = 'Roboto';
  static const _fontFallback = ['NotoSansSymbols2'];

  /// Imaginea PNG a cartonașului: QR-ul de Wi-Fi (dacă e completat
  /// [wifiSsid]) și QR-ul de meniu către [menuUrl].
  static Future<Uint8List> renderCardPng({
    required String menuUrl,
    String wifiSsid = '',
    String wifiPassword = '',
  }) async {
    const size = cardPixels * 1.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));

    canvas.drawRect(const Rect.fromLTWH(0, 0, size, size), Paint()..color = Colors.white);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(24, 24, size - 48, size - 48), const Radius.circular(48)),
      Paint()
        ..color = _green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14,
    );

    final primary = LanguageController.instance.language;
    final secondary = primary == AppLanguage.ro ? AppLanguage.en : AppLanguage.ro;
    String inPrimary(String key) => trIn(primary, key);
    String inSecondary(String key) => trIn(secondary, key);

    var y = 64.0;
    y += _drawText(
      canvas,
      inPrimary('qrCard.title'),
      y,
      size / 2,
      size - 140,
      const TextStyle(color: _green, fontSize: 84, fontWeight: FontWeight.w900),
    );
    y += _drawText(
      canvas,
      inSecondary('qrCard.title'),
      y,
      size / 2,
      size - 140,
      const TextStyle(color: Colors.black45, fontSize: 36, fontStyle: FontStyle.italic),
    );
    y += 28;

    final ssid = wifiSsid.trim();
    if (ssid.isEmpty) {
      // Doar QR-ul de meniu, mare, pe mijloc.
      const qrSize = 600.0;
      _drawQr(canvas, menuUrl, Offset((size - qrSize) / 2, y), qrSize);
      y += qrSize + 26;
      y += _drawText(
        canvas,
        inPrimary('qrCard.menu'),
        y,
        size / 2,
        size - 140,
        const TextStyle(color: Colors.black, fontSize: 46, fontWeight: FontWeight.bold),
      );
      y += _drawText(
        canvas,
        inSecondary('qrCard.menu'),
        y,
        size / 2,
        size - 140,
        const TextStyle(color: Colors.black54, fontSize: 32, fontStyle: FontStyle.italic),
      );
      y += 10;
      _drawText(
        canvas,
        inPrimary('qrCard.wifiFirst'),
        y,
        size / 2,
        size - 140,
        const TextStyle(color: _green, fontSize: 36, fontWeight: FontWeight.w600),
      );
    } else {
      // Două coloane: 1 = Wi-Fi, 2 = meniu.
      const qrSize = 470.0;
      const leftCenter = size * 0.27;
      const rightCenter = size * 0.73;
      const columnWidth = size * 0.44;
      const stepStyle = TextStyle(color: _green, fontSize: 52, fontWeight: FontWeight.w900);
      _drawText(canvas, '1 · Wi-Fi', y, leftCenter, columnWidth, stepStyle);
      y += _drawText(canvas, '2 · ${inPrimary('qrCard.menuShort')}', y, rightCenter, columnWidth, stepStyle);
      y += 14;
      _drawQr(canvas, wifiQrPayload(ssid: ssid, password: wifiPassword), Offset(leftCenter - qrSize / 2, y), qrSize);
      _drawQr(canvas, menuUrl, Offset(rightCenter - qrSize / 2, y), qrSize);
      y += qrSize + 18;
      const detailStyle = TextStyle(color: Colors.black87, fontSize: 32, fontWeight: FontWeight.w600);
      final wifiDetails = wifiPassword.isEmpty ? ssid : '$ssid\n${inPrimary('qrCard.password')}: $wifiPassword';
      final leftHeight = _drawText(canvas, wifiDetails, y, leftCenter, columnWidth, detailStyle);
      final rightHeight = _drawText(canvas, inPrimary('qrCard.menu'), y, rightCenter, columnWidth, detailStyle);
      y += (leftHeight > rightHeight ? leftHeight : rightHeight) + 18;
      y += _drawText(
        canvas,
        inPrimary('qrCard.steps'),
        y,
        size / 2,
        size - 140,
        const TextStyle(color: Colors.black, fontSize: 34, fontWeight: FontWeight.bold),
      );
      _drawText(
        canvas,
        inSecondary('qrCard.steps'),
        y,
        size / 2,
        size - 140,
        const TextStyle(color: Colors.black54, fontSize: 28, fontStyle: FontStyle.italic),
      );
    }
    _drawText(canvas, menuUrl, size - 84, size / 2, size - 140, const TextStyle(color: Colors.black38, fontSize: 24));

    final image = await recorder.endRecording().toImage(cardPixels, cardPixels);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  static void _drawQr(Canvas canvas, String data, Offset topLeft, double size) {
    canvas.save();
    canvas.translate(topLeft.dx, topLeft.dy);
    QrPainter(
      data: data,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: true,
    ).paint(canvas, Size(size, size));
    canvas.restore();
  }

  /// Scrie [text] centrat pe [centerX], cu lățimea maximă [maxWidth],
  /// începând de la înălțimea [top], și întoarce înălțimea ocupată.
  static double _drawText(Canvas canvas, String text, double top, double centerX, double maxWidth, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(fontFamily: _fontFamily, fontFamilyFallback: _fontFallback),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, Offset(centerX - painter.width / 2, top));
    return painter.height;
  }

  /// PDF A4 cu [copies] exemplare ale cartonașului [card], câte 6 pe pagină
  /// (2 × 3), cu contur punctat ca ghid de tăiere.
  static Future<Uint8List> buildCardsPdf({required Uint8List card, required int copies}) async {
    final image = pw.MemoryImage(card);
    final doc = pw.Document(title: tr('qrCards.share.subject'), creator: 'LocalEventBusiness');
    for (var start = 0; start < copies; start += cardsPerPage) {
      final onPage = (copies - start).clamp(0, cardsPerPage);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (context) => pw.Column(
            children: [
              for (var row = 0; row < cardsPerPage ~/ 2; row++)
                pw.Expanded(
                  child: pw.Row(
                    children: [
                      for (var col = 0; col < 2; col++)
                        pw.Expanded(
                          child: row * 2 + col < onPage
                              ? pw.Container(
                                  margin: const pw.EdgeInsets.all(4),
                                  padding: const pw.EdgeInsets.all(6),
                                  decoration: pw.BoxDecoration(
                                    border: pw.Border.all(
                                      color: PdfColors.grey500,
                                      width: 0.6,
                                      style: pw.BorderStyle.dashed,
                                    ),
                                  ),
                                  child: pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
                                )
                              : pw.SizedBox(),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }
}
