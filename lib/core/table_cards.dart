import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/tr.dart';

/// Cartonașele cu codul QR al fiecărei mese, gata de tipărit: imaginea unui
/// cartonaș ([renderTableCardPng]) și un PDF A4 cu toate mesele, câte 6 pe
/// pagină ([buildTablesPdf]). Textul de pe cartonaș e în ambele limbi — limba
/// aplicației mare, cealaltă dedesubt, mică — fiindcă un cartonaș tipărit
/// rămâne pe masă pentru orice invitat.
class TableCards {
  TableCards._();

  /// Lățimea în pixeli a unui cartonaș (cartonașul e pătrat) — destul pentru
  /// tipărire clară la ~9 cm, cât are un cartonaș pe o pagină A4 de 6.
  static const int cardPixels = 1200;

  static const int cardsPerPage = 6;

  static const _green = Color(0xFF0B5E3B);

  /// Fonturile incluse în aplicație — aceleași pe orice telefon.
  static const _fontFamily = 'Roboto';
  static const _fontFallback = ['NotoSansSymbols2'];

  static String _inLanguage(AppLanguage language, String key, [Map<String, Object?> args = const {}]) =>
      trIn(language, key, args);

  /// Imaginea PNG a cartonașului mesei [table]: număr, cod QR către [url],
  /// instrucțiuni și, opțional, datele rețelei Wi-Fi ([wifiInfo]).
  static Future<Uint8List> renderTableCardPng({
    required int table,
    required String url,
    String? wifiInfo,
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

    var y = 70.0;
    y += _drawText(canvas, _inLanguage(primary, 'orders.table', {'table': table}), y,
        const TextStyle(color: _green, fontSize: 120, fontWeight: FontWeight.w900));

    const qrSize = 560.0;
    final qrTop = y + 20;
    canvas.save();
    canvas.translate((size - qrSize) / 2, qrTop);
    QrPainter(
      data: url,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: true,
    ).paint(canvas, const Size(qrSize, qrSize));
    canvas.restore();
    y = qrTop + qrSize + 26;

    y += _drawText(canvas, _inLanguage(primary, 'tables.card.scan'), y,
        const TextStyle(color: Colors.black, fontSize: 50, fontWeight: FontWeight.bold));
    y += _drawText(canvas, _inLanguage(secondary, 'tables.card.scan'), y,
        const TextStyle(color: Colors.black54, fontSize: 36, fontStyle: FontStyle.italic));
    final wifi = wifiInfo?.trim() ?? '';
    y += 10;
    y += _drawText(
      canvas,
      wifi.isEmpty ? _inLanguage(primary, 'tables.card.wifiFirst') : 'Wi-Fi: $wifi',
      y,
      const TextStyle(color: _green, fontSize: 38, fontWeight: FontWeight.w600),
    );
    _drawText(canvas, url, size - 92, const TextStyle(color: Colors.black38, fontSize: 26));

    final image = await recorder.endRecording().toImage(cardPixels, cardPixels);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  /// Scrie [text] centrat orizontal începând de la înălțimea [top] și
  /// întoarce înălțimea ocupată.
  static double _drawText(Canvas canvas, String text, double top, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(fontFamily: _fontFamily, fontFamilyFallback: _fontFallback)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: cardPixels - 140);
    painter.paint(canvas, Offset((cardPixels - painter.width) / 2, top));
    return painter.height;
  }

  /// PDF A4 cu cartonașele meselor 1…[tableCount], câte 6 pe pagină (2 × 3),
  /// cu contur punctat ca ghid de tăiere.
  static Future<Uint8List> buildTablesPdf({
    required int tableCount,
    required String Function(int table) urlFor,
    String? wifiInfo,
  }) async {
    final cards = <Uint8List>[
      for (var t = 1; t <= tableCount; t++) await renderTableCardPng(table: t, url: urlFor(t), wifiInfo: wifiInfo),
    ];
    final doc = pw.Document(title: tr('tables.share.subject'), creator: 'LocalEventBusiness');
    for (var start = 0; start < cards.length; start += cardsPerPage) {
      final page = cards.sublist(start, (start + cardsPerPage).clamp(0, cards.length));
      doc.addPage(pw.Page(
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
                        child: row * 2 + col < page.length
                            ? pw.Container(
                                margin: const pw.EdgeInsets.all(4),
                                padding: const pw.EdgeInsets.all(6),
                                decoration: pw.BoxDecoration(
                                  border: pw.Border.all(color: PdfColors.grey500, width: 0.6, style: pw.BorderStyle.dashed),
                                ),
                                child: pw.Center(
                                  child: pw.Image(pw.MemoryImage(page[row * 2 + col]), fit: pw.BoxFit.contain),
                                ),
                              )
                            : pw.SizedBox(),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ));
    }
    return doc.save();
  }
}
