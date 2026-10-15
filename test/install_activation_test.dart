import 'package:flutter_test/flutter_test.dart';
import 'package:local_event_business/core/install_activation.dart';
import 'package:local_event_business/screens/not_activated_screen.dart';

void main() {
  group('isTrustedInstallSource', () {
    test('instalarea de pe calculator (adb) activează aplicația', () {
      expect(isTrustedInstallSource(installer: null, initiator: 'com.android.shell', sdkInt: 34), isTrue);
      expect(isTrustedInstallSource(installer: 'com.android.shell', initiator: 'com.android.shell', sdkInt: 34), isTrue);
      expect(isTrustedInstallSource(installer: null, initiator: null, sdkInt: 28), isTrue);
    });

    test('instalarea din Google Play activează aplicația', () {
      expect(isTrustedInstallSource(installer: 'com.android.vending', initiator: 'com.android.vending', sdkInt: 34), isTrue);
    });

    test('APK descărcat de pe site sau primit pe WhatsApp nu activează aplicația', () {
      expect(
          isTrustedInstallSource(
              installer: 'com.google.android.packageinstaller', initiator: 'com.android.chrome', sdkInt: 34),
          isFalse);
      expect(
          isTrustedInstallSource(installer: 'com.miui.packageinstaller', initiator: 'com.whatsapp', sdkInt: 34),
          isFalse);
      expect(isTrustedInstallSource(installer: null, initiator: 'com.whatsapp', sdkInt: 34), isFalse);
      expect(isTrustedInstallSource(installer: 'com.google.android.packageinstaller', sdkInt: 28), isFalse);
    });
  });

  testWidgets('ecranul de blocare nu duce nicăieri în aplicație', (tester) async {
    await tester.pumpWidget(const NotActivatedApp());

    expect(find.text('Aplicația nu este activată pe acest telefon'), findsOneWidget);
    expect(find.text('Intră la eveniment'), findsNothing);
  });
}
