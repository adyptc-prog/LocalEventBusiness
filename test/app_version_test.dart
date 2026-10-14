import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_event_business/core/app_version.dart';

void main() {
  test('appVersion e aceeași cu versiunea din pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*([^+\s]+)', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(appVersion, match!.group(1));
  });
}
