import 'dart:io';

import 'package:splitio_commons/src/core/core.dart';
import 'package:splitio_commons/src/engine/bucketer.dart';
import 'package:test/test.dart';

/// Cross-language parity test. Consumes CSV fixtures copied verbatim from
/// javascript-commons/src/utils/murmur3/__tests__/mocks/, each row
/// `seed,key,expected_hash,expected_bucket`. Every row MUST produce identical
/// hash and bucket in Dart to keep the two SDKs treatment-equivalent (§10).
void main() {
  final fixtures = <String>[
    'murmur3-sample-v3.csv',
    'murmur3-sample-v4.csv',
    'murmur3-sample-double-treatment-users.csv',
  ];

  final bucketer = Bucketer();

  for (final filename in fixtures) {
    test('js parity: $filename', () {
      final file = File('test/engine/mocks/$filename');
      final lines = file.readAsLinesSync();
      expect(lines, isNotEmpty, reason: 'fixture $filename is empty');

      for (final line in lines) {
        if (line.isEmpty) continue;
        final parts = line.split(',');
        final seed = int.parse(parts[0]);
        final key = parts[1];
        final expectedHash = int.parse(parts[2]);
        final expectedBucket = int.parse(parts[3]);

        expect(murmurhash3X8632(key, seed), expectedHash,
            reason: 'hash mismatch for key="$key" seed=$seed');
        expect(bucketer.getBucket(key, seed, 2), expectedBucket,
            reason: 'bucket mismatch for key="$key" seed=$seed');
      }
    });
  }
}
