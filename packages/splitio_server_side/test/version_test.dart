import 'dart:io';

import 'package:splitio_server_side/src/version.dart';
import 'package:test/test.dart';

final _versionRe = RegExp(r'^version:\s*(\S+)', multiLine: true);

void main() {
  test('sdkVersion matches the pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = _versionRe.firstMatch(pubspec);
    expect(match, isNotNull);
    expect(sdkVersion, equals('dart_mt-${match!.group(1)}'));
  });

  test('splitio_commons constraint matches the commons pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final commons = File('../splitio_commons/pubspec.yaml').readAsStringSync();
    final constraint = RegExp(r'^\s*splitio_commons:\s*(\S+)', multiLine: true)
        .firstMatch(pubspec);
    final version = _versionRe.firstMatch(commons);
    expect(constraint, isNotNull);
    expect(version, isNotNull);
    expect(constraint!.group(1), equals('^${version!.group(1)}'));
  });
}
