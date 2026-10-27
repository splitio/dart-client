// Attribute coercion (spec §4.1, §5.5): numeric and date matchers MUST
// accept `double` attribute values, comparing as numbers without
// truncation (`18.5 >= 18` is true, `18.5 == 18` is false, `18.0 == 18` is
// true), and collection matchers (`*_SET`) MUST accept any iterable runtime
// value, not just a `List` — a Dart `Set<String>` attribute MUST also
// match.
//
// Prior to the fix, coercion was integer-only (`asLong`) and collection
// matchers required a `List`, so a `double` attribute never matched a
// numeric/date matcher and a `Set<String>` attribute never matched a set
// matcher — diverging from the Node/JS SDK reference.
//
// Asserted via real HTTP interactions against a MockBackend (never against
// internal components), on both the client-side and server-side flavors,
// per the repo's e2e testing requirements.
import 'package:splitio_client_side/splitio_client_side.dart' as cs;
import 'package:splitio_server_side/splitio_server_side.dart' as ss;
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

/// A single-condition flag: an attribute-based matcher on treatment "on",
/// falling back to ALL_KEYS -> "off" as the default rule.
Map<String, dynamic> _attributeFlag({
  required String name,
  required int changeNumber,
  required Map<String, dynamic> matcher,
}) {
  return {
    'trafficTypeName': 'user',
    'name': name,
    'trafficAllocation': 100,
    'trafficAllocationSeed': changeNumber,
    'seed': changeNumber + 1000,
    'status': 'ACTIVE',
    'killed': false,
    'defaultTreatment': 'off',
    'changeNumber': changeNumber,
    'algo': 2,
    'conditions': [
      {
        'conditionType': 'WHITELIST',
        'matcherGroup': {
          'combiner': 'AND',
          'matchers': [matcher],
        },
        'partitions': [
          {'treatment': 'on', 'size': 100},
        ],
        'label': 'attribute matcher',
      },
      {
        'conditionType': 'ROLLOUT',
        'matcherGroup': {
          'combiner': 'AND',
          'matchers': [
            {
              'keySelector': null,
              'matcherType': 'ALL_KEYS',
              'negate': false,
              'userDefinedSegmentMatcherData': null,
              'whitelistMatcherData': null,
              'unaryNumericMatcherData': null,
              'betweenMatcherData': null,
              'booleanMatcherData': null,
              'dependencyMatcherData': null,
              'stringMatcherData': null,
            }
          ],
        },
        'partitions': [
          {'treatment': 'off', 'size': 100},
        ],
        'label': 'default rule',
      }
    ],
    'configurations': <String, dynamic>{},
    'sets': <dynamic>[],
  };
}

Map<String, dynamic> _unaryNumericMatcher({
  required String attribute,
  required String matcherType,
  required int value,
  String dataType = 'NUMBER',
}) {
  return {
    'keySelector': {'attribute': attribute},
    'matcherType': matcherType,
    'negate': false,
    'userDefinedSegmentMatcherData': null,
    'whitelistMatcherData': null,
    'unaryNumericMatcherData': {'value': value, 'dataType': dataType},
    'betweenMatcherData': null,
    'booleanMatcherData': null,
    'dependencyMatcherData': null,
    'stringMatcherData': null,
  };
}

Map<String, dynamic> _betweenMatcher({
  required String attribute,
  required int start,
  required int end,
  String dataType = 'NUMBER',
}) {
  return {
    'keySelector': {'attribute': attribute},
    'matcherType': 'BETWEEN',
    'negate': false,
    'userDefinedSegmentMatcherData': null,
    'whitelistMatcherData': null,
    'unaryNumericMatcherData': null,
    'betweenMatcherData': {'start': start, 'end': end, 'dataType': dataType},
    'booleanMatcherData': null,
    'dependencyMatcherData': null,
    'stringMatcherData': null,
  };
}

Map<String, dynamic> _setMatcher({
  required String attribute,
  required String matcherType,
  required List<String> whitelist,
}) {
  return {
    'keySelector': {'attribute': attribute},
    'matcherType': matcherType,
    'negate': false,
    'userDefinedSegmentMatcherData': null,
    'whitelistMatcherData': {'whitelist': whitelist},
    'unaryNumericMatcherData': null,
    'betweenMatcherData': null,
    'booleanMatcherData': null,
    'dependencyMatcherData': null,
    'stringMatcherData': null,
  };
}

/// 2024-01-01T00:00:00Z, used as the configured EQUAL_TO DATETIME value.
final int _signupDayMillis = DateTime.utc(2024, 1, 1).millisecondsSinceEpoch;

List<Map<String, dynamic>> _flags() => [
      _attributeFlag(
        name: 'flag_gte_number',
        changeNumber: 1001,
        matcher: _unaryNumericMatcher(
          attribute: 'age',
          matcherType: 'GREATER_THAN_OR_EQUAL_TO',
          value: 18,
        ),
      ),
      _attributeFlag(
        name: 'flag_eq_number',
        changeNumber: 1002,
        matcher: _unaryNumericMatcher(
          attribute: 'age',
          matcherType: 'EQUAL_TO',
          value: 18,
        ),
      ),
      _attributeFlag(
        name: 'flag_between_number',
        changeNumber: 1003,
        matcher: _betweenMatcher(attribute: 'age', start: 18, end: 65),
      ),
      _attributeFlag(
        name: 'flag_eq_datetime',
        changeNumber: 1004,
        matcher: _unaryNumericMatcher(
          attribute: 'signup_date',
          matcherType: 'EQUAL_TO',
          value: _signupDayMillis,
          dataType: 'DATETIME',
        ),
      ),
      _attributeFlag(
        name: 'flag_part_of_set',
        changeNumber: 1005,
        matcher: _setMatcher(
          attribute: 'roles',
          matcherType: 'PART_OF_SET',
          whitelist: ['admin', 'editor', 'viewer'],
        ),
      ),
      _attributeFlag(
        name: 'flag_contains_any_of_set',
        changeNumber: 1006,
        matcher: _setMatcher(
          attribute: 'tags',
          matcherType: 'CONTAINS_ANY_OF_SET',
          whitelist: ['vip', 'beta'],
        ),
      ),
    ];

void main() {
  group('Client-side attribute coercion e2e (spec §4.1, §5.5)', () {
    late MockBackend backend;
    late cs.SplitFactory factory;
    late cs.SplitClient client;

    setUpAll(() async {
      backend = MockBackend();
      await backend.start();
      backend.stubSplitChanges(splits: _flags());
      backend.stubMemberships();

      final config = cs.SplitClientConfig(
        sync: cs.SyncConfig(
          serviceEndpoints: cs.ServiceEndpoints(
            sdkUrl: _baseUrl(backend),
            eventsUrl: _baseUrl(backend),
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
        ),
        logLevel: cs.LogLevel.warning,
      );

      final key = cs.Key(matchingKey: 'user_a');
      factory = cs.SplitFactory.create('fake-api-key', config, key);
      client = factory.client(key);
      await client.whenReady().timeout(const Duration(seconds: 5));
    });

    tearDownAll(() async {
      await factory.destroy();
      await backend.shutdown();
    });

    test('double attribute >= int configured value matches (18.5 >= 18)', () {
      expect(client.getTreatment('flag_gte_number', attributes: {'age': 18.5}),
          'on');
    });

    test('double attribute does not equal int configured value (18.5 != 18)',
        () {
      expect(client.getTreatment('flag_eq_number', attributes: {'age': 18.5}),
          'off');
    });

    test(
        'whole-valued double attribute equals int configured value '
        '(18.0 == 18)', () {
      expect(client.getTreatment('flag_eq_number', attributes: {'age': 18.0}),
          'on');
    });

    test('double attribute inside a BETWEEN range matches', () {
      expect(
          client.getTreatment('flag_between_number', attributes: {'age': 18.5}),
          'on');
    });

    test('datetime attribute supplied as a double of epoch millis matches', () {
      final sameDayAsDouble =
          DateTime.utc(2024, 1, 1, 14, 30).millisecondsSinceEpoch.toDouble();
      expect(
          client.getTreatment('flag_eq_datetime',
              attributes: {'signup_date': sameDayAsDouble}),
          'on');
    });

    test('Set<String> attribute matches a PART_OF_SET matcher', () {
      expect(
          client.getTreatment('flag_part_of_set', attributes: {
            'roles': <String>{'admin', 'editor'}
          }),
          'on');
    });

    test('Set<String> attribute matches a CONTAINS_ANY_OF_SET matcher', () {
      expect(
          client.getTreatment('flag_contains_any_of_set', attributes: {
            'tags': <String>{'vip'}
          }),
          'on');
    });
  });

  group('Server-side attribute coercion e2e (spec §4.1, §5.5 — other flavor)',
      () {
    late MockBackend backend;
    late ss.SplitFactory factory;
    late ss.ServerSplitClient client;

    setUpAll(() async {
      backend = MockBackend();
      await backend.start();
      backend.stubSplitChanges(splits: _flags());

      final config = ss.SplitClientConfig(
        sync: ss.SyncConfig(
          serviceEndpoints: ss.ServiceEndpoints(
            sdkUrl: _baseUrl(backend),
            eventsUrl: _baseUrl(backend),
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          streamingEnabled: false,
        ),
        installSignalHandler: false,
        logLevel: ss.LogLevel.warning,
      );

      factory = ss.SplitFactory.create('fake-api-key', config);
      client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));
    });

    tearDownAll(() async {
      await factory.destroy();
      await backend.shutdown();
    });

    test('double attribute >= int configured value matches (18.5 >= 18)', () {
      expect(
          client.getTreatment('user_a', 'flag_gte_number',
              attributes: {'age': 18.5}),
          'on');
    });

    test('double attribute does not equal int configured value (18.5 != 18)',
        () {
      expect(
          client.getTreatment('user_a', 'flag_eq_number',
              attributes: {'age': 18.5}),
          'off');
    });

    test(
        'whole-valued double attribute equals int configured value '
        '(18.0 == 18)', () {
      expect(
          client.getTreatment('user_a', 'flag_eq_number',
              attributes: {'age': 18.0}),
          'on');
    });

    test('Set<String> attribute matches a PART_OF_SET matcher', () {
      expect(
          client.getTreatment('user_a', 'flag_part_of_set', attributes: {
            'roles': <String>{'admin', 'editor'}
          }),
          'on');
    });
  });
}
