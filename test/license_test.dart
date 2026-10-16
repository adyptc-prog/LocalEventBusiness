import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_event_business/core/license_service.dart';
import 'package:local_event_business/screens/license_screen.dart';
import 'package:local_event_business/widgets/license_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('local_event_business/license');

/// Simulează partea nativă (`LicenseStore`): răspunsul la `checkLicense`.
void _native(Map<String, Object?> status, {Map<String, Object?>? picked}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
    switch (call.method) {
      case 'checkLicense':
        return status;
      case 'getBusinessId':
        return 'localeventbusiness-1700000000000';
      case 'pickLicenseFile':
        if (picked == null) throw PlatformException(code: 'LICENSE_PICK_CANCELLED');
        status = {...picked, 'trialActive': false, 'trialDaysLeft': 0};
        return picked;
    }
    return null;
  });
}

const _trial = {'status': 'missing', 'message': '', 'trialActive': true, 'trialDaysLeft': 12};
const _expired = {'status': 'missing', 'message': '', 'trialActive': false, 'trialDaysLeft': 0};
const _active = {
  'status': 'active',
  'message': 'ok',
  'isLifetime': false,
  'validUntil': '2030-01-01T00:00:00Z',
  'daysUntilExpiry': 400,
  'trialActive': false,
  'trialDaysLeft': 0,
};

void main() {
  final license = LicenseService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    license.debugReset();
    LicenseService.debugIsAndroid = true;
  });

  tearDown(() {
    license.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  test('în perioada de probă aplicația poate fi folosită', () async {
    _native(_trial);
    await license.refresh();
    expect(license.canUse, isTrue);
    expect(license.isLicensed, isFalse);
    expect(license.trialDaysLeft, 12);
  });

  test('după probă, fără licență, aplicația e blocată', () async {
    _native(_expired);
    await license.refresh();
    expect(license.canUse, isFalse);
  });

  test('o licență activă deblochează aplicația după probă', () async {
    _native(_active);
    await license.refresh();
    expect(license.canUse, isTrue);
    expect(license.isExpiringSoon, isFalse);
  });

  test('fără răspuns de la partea nativă, aplicația rămâne blocată', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel, (call) async => throw PlatformException(code: 'X'));
    await license.refresh();
    expect(license.canUse, isFalse);
  });

  test('clientul web și alte platforme nu au licență', () async {
    LicenseService.debugIsAndroid = false;
    expect(license.canUse, isTrue);
  });

  test('avertizarea de expirare apare cel mult o dată pe zi', () async {
    _native({..._active, 'daysUntilExpiry': 5});
    await license.refresh();
    expect(license.isExpiringSoon, isTrue);
    expect(await license.shouldWarnExpiryToday(), isTrue);
    expect(await license.shouldWarnExpiryToday(), isFalse);
  });

  test('selectorul închis fără alegere nu e o eroare', () async {
    _native(_expired);
    final r = await license.pickLicenseFile();
    expect(r.success, isFalse);
    expect(r.message, isEmpty);
  });

  Widget app() => MaterialApp(
        builder: (context, child) => LicenseGate(child: child!),
        home: const Scaffold(body: Text('aplicația')),
      );

  testWidgets('poarta: în probă se vede aplicația', (tester) async {
    _native(_trial);
    await license.refresh();
    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.text('aplicația'), findsOneWidget);
    expect(find.byType(LicenseScreen), findsNothing);
  });

  testWidgets('poarta: după probă se vede doar ecranul de licență, iar importul deblochează', (tester) async {
    _native(_expired, picked: _active);
    await license.refresh();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('aplicația'), findsNothing);
    expect(find.byType(LicenseScreen), findsOneWidget);
    expect(find.text('localeventbusiness-1700000000000'), findsOneWidget);

    await tester.tap(find.text('Selectează fișierul de licență'));
    await tester.pumpAndSettle();
    expect(find.text('aplicația'), findsOneWidget);
  });
}
