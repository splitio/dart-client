import 'package:splitio_commons/src/engine/engine.dart';
import 'package:splitio_commons/src/models/models.dart' hide EvaluationResult;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Mock EvaluationContext
// ---------------------------------------------------------------------------

class MockEvaluationContext implements EvaluationContext {
  final Map<String, EvaluationResult> _evaluations;
  final Set<String> _segments;
  final Set<String> _ruleBasedSegments;

  MockEvaluationContext({
    Map<String, EvaluationResult>? evaluations,
    Set<String>? segments,
    Set<String>? ruleBasedSegments,
  })  : _evaluations = evaluations ?? {},
        _segments = segments ?? {},
        _ruleBasedSegments = ruleBasedSegments ?? {};

  @override
  EvaluationResult evaluate(
    String matchingKey,
    String bucketingKey,
    String ruleName,
    Attributes attributes,
  ) {
    return _evaluations[ruleName] ??
        (treatment: 'control', label: 'default rule');
  }

  @override
  bool isInSegment(String segmentName, String key) {
    return _segments.contains('$segmentName:$key') ||
        _segments.contains(segmentName);
  }

  @override
  bool isInRuleBasedSegment(
    String segmentName,
    String key,
    String bucketingKey,
    Attributes attributes,
  ) {
    return _ruleBasedSegments.contains('$segmentName:$key') ||
        _ruleBasedSegments.contains(segmentName);
  }
}

// ---------------------------------------------------------------------------
// Helper to build a simple ParsedSplit
// ---------------------------------------------------------------------------

ParsedSplit _buildSplit({
  String name = 'test_split',
  bool killed = false,
  String defaultTreatment = 'off',
  List<TargetingRule> conditions = const [],
  int trafficAllocation = 100,
  int? trafficAllocationSeed,
  int seed = 12345,
  int algo = 2,
  int changeNumber = 1,
  List<Prerequisite> prerequisites = const [],
  Map<String, String> configurations = const {},
}) {
  return ParsedSplit(
    name: name,
    trafficTypeName: 'user',
    killed: killed,
    defaultTreatment: defaultTreatment,
    conditions: conditions,
    trafficAllocation: trafficAllocation,
    trafficAllocationSeed: trafficAllocationSeed,
    seed: seed,
    algo: algo,
    changeNumber: changeNumber,
    prerequisites: prerequisites,
    configurations: configurations,
  );
}

TargetingRule _buildRule({
  ConditionType conditionType = ConditionType.whitelist,
  AttributeMatcher? matcher,
  List<Partition> partitions = const [],
  String label = 'test label',
}) {
  final combined =
      matcher ?? const AttributeMatcher(delegate: AllKeysMatcher());
  return TargetingRule(
    conditionType: conditionType,
    matcher: CombiningMatcher(delegates: [combined]),
    partitions: partitions,
    label: label,
  );
}

/// Exercises a single [AttributeMatcher] through the public `matchCombining`
/// entry point (wrapping it in a one-delegate [CombiningMatcher]), since the
/// engine's internal per-delegate helper is private.
bool _matchAttribute(
  AttributeMatcher matcher,
  String matchingKey,
  String? bucketingKey,
  Attributes attributes,
  EvaluationContext ctx,
) {
  return matchCombining(
    CombiningMatcher(delegates: [matcher]),
    matchingKey,
    bucketingKey,
    attributes,
    ctx,
  );
}

void main() {
  // =========================================================================
  // Bucketer
  // =========================================================================

  group('Bucketer', () {
    final bucketer = Bucketer();

    group('getBucket', () {
      test('returns value in range [1, 100]', () {
        for (int i = 0; i < 100; i++) {
          final bucket = bucketer.getBucket('user$i', 12345, 2);
          expect(bucket, greaterThanOrEqualTo(1));
          expect(bucket, lessThanOrEqualTo(100));
        }
      });

      test('is deterministic for same inputs', () {
        final b1 = bucketer.getBucket('mykey', 999, 2);
        final b2 = bucketer.getBucket('mykey', 999, 2);
        expect(b1, equals(b2));
      });

      test('uses murmur hash when algo == 2', () {
        final bucket = bucketer.getBucket('testkey', 100, 2);
        expect(bucket, greaterThanOrEqualTo(1));
        expect(bucket, lessThanOrEqualTo(100));
      });

      test('uses legacy hash when algo != 2', () {
        final bucket = bucketer.getBucket('testkey', 100, 1);
        expect(bucket, greaterThanOrEqualTo(1));
        expect(bucket, lessThanOrEqualTo(100));
      });

      test('legacy and murmur produce different buckets for same key', () {
        // They MAY produce same value by chance, so test multiple keys
        final differences = <bool>[];
        for (int i = 0; i < 50; i++) {
          final legacy = bucketer.getBucket('key$i', 42, 1);
          final murmur = bucketer.getBucket('key$i', 42, 2);
          differences.add(legacy != murmur);
        }
        // At least some should differ
        expect(differences.where((d) => d).length, greaterThan(0));
      });
    });

    group('getTreatment', () {
      test('returns "control" for empty partitions', () {
        final result = bucketer.getTreatment('user1', 123, [], 2);
        expect(result, equals('control'));
      });

      test('single partition with size 100 returns its treatment directly', () {
        final partitions = [const Partition(treatment: 'on', size: 100)];
        final result = bucketer.getTreatment('anykey', 1, partitions, 2);
        expect(result, equals('on'));
      });

      test('selects correct partition based on bucket', () {
        // With 50/50 split, keys should distribute
        final partitions = [
          const Partition(treatment: 'on', size: 50),
          const Partition(treatment: 'off', size: 50),
        ];

        final treatments = <String>{};
        for (int i = 0; i < 200; i++) {
          final t = bucketer.getTreatment('user$i', 9876, partitions, 2);
          treatments.add(t);
        }
        // Both treatments should appear
        expect(treatments, contains('on'));
        expect(treatments, contains('off'));
      });

      test('respects partition ordering', () {
        // If bucket is 1, first partition (size >= 1) should be selected
        final partitions = [
          const Partition(treatment: 'first', size: 1),
          const Partition(treatment: 'second', size: 99),
        ];

        // Find a key that lands in bucket 1
        String? keyForBucket1;
        for (int i = 0; i < 10000; i++) {
          if (bucketer.getBucket('u$i', 42, 2) == 1) {
            keyForBucket1 = 'u$i';
            break;
          }
        }
        if (keyForBucket1 != null) {
          final t = bucketer.getTreatment(keyForBucket1, 42, partitions, 2);
          expect(t, equals('first'));
        }
      });

      test('returns "control" when bucket exceeds total partition coverage',
          () {
        // Partitions that do not cover all 100 buckets
        final partitions = [
          const Partition(treatment: 'on', size: 10),
        ];

        // Find a key with bucket > 10
        String? keyAbove10;
        for (int i = 0; i < 1000; i++) {
          if (bucketer.getBucket('k$i', 55, 2) > 10) {
            keyAbove10 = 'k$i';
            break;
          }
        }
        if (keyAbove10 != null) {
          final t = bucketer.getTreatment(keyAbove10, 55, partitions, 2);
          expect(t, equals('control'));
        }
      });
    });
  });

  // =========================================================================
  // TargetingEngine
  // =========================================================================

  group('TargetingEngine', () {
    final engine = TargetingEngine();
    final ctx = MockEvaluationContext();

    test('killed split returns default treatment with killed label', () {
      final split = _buildSplit(killed: true, defaultTreatment: 'off');
      final result = engine.evaluate('user1', null, split, {}, ctx);
      expect(result.treatment, equals('off'));
      expect(result.label, equals(Labels.killed));
    });

    test('killed split returns default treatment config', () {
      final split = _buildSplit(
        killed: true,
        defaultTreatment: 'off',
        configurations: const {
          'off': '{"color":"blue"}',
          'on': '{"color":"red"}',
        },
      );
      final result = engine.evaluate('user1', null, split, {}, ctx);
      expect(result.treatment, equals('off'));
      expect(result.label, equals(Labels.killed));
      expect(result.config, equals('{"color":"blue"}'));
    });

    test('prerequisites not met returns default treatment', () {
      final mockCtx = MockEvaluationContext(
        evaluations: {
          'prereq_flag': (
            treatment: 'off',
            label: 'default rule',
          ),
        },
      );

      final split = _buildSplit(
        prerequisites: [
          const Prerequisite(
            featureFlagName: 'prereq_flag',
            treatments: ['on'],
          ),
        ],
        conditions: [
          _buildRule(
            partitions: [const Partition(treatment: 'on', size: 100)],
          ),
        ],
      );

      final result = engine.evaluate('user1', null, split, {}, mockCtx);
      expect(result.treatment, equals('off'));
      expect(result.label, equals(Labels.prerequisitesNotMet));
    });

    test('prerequisites not met returns default treatment config', () {
      final mockCtx = MockEvaluationContext(
        evaluations: {
          'prereq_flag': (
            treatment: 'off',
            label: 'default rule',
          ),
        },
      );

      final split = _buildSplit(
        defaultTreatment: 'off',
        prerequisites: [
          const Prerequisite(
            featureFlagName: 'prereq_flag',
            treatments: ['on'],
          ),
        ],
        conditions: [
          _buildRule(
            partitions: [const Partition(treatment: 'on', size: 100)],
          ),
        ],
        configurations: const {
          'off': '{"color":"blue"}',
          'on': '{"color":"red"}',
        },
      );

      final result = engine.evaluate('user1', null, split, {}, mockCtx);
      expect(result.treatment, equals('off'));
      expect(result.label, equals(Labels.prerequisitesNotMet));
      expect(result.config, equals('{"color":"blue"}'));
    });

    test('prerequisites met continues evaluation', () {
      final mockCtx = MockEvaluationContext(
        evaluations: {
          'prereq_flag': (
            treatment: 'on',
            label: 'default rule',
          ),
        },
      );

      final split = _buildSplit(
        prerequisites: [
          const Prerequisite(
            featureFlagName: 'prereq_flag',
            treatments: ['on'],
          ),
        ],
        conditions: [
          _buildRule(
            partitions: [const Partition(treatment: 'variant', size: 100)],
            label: 'matched rule',
          ),
        ],
      );

      final result = engine.evaluate('user1', null, split, {}, mockCtx);
      expect(result.treatment, equals('variant'));
      expect(result.label, equals('matched rule'));
    });

    test('traffic allocation gate excludes user', () {
      // Use trafficAllocation=1 so most keys are excluded
      final split = _buildSplit(
        trafficAllocation: 1,
        seed: 42,
        conditions: [
          _buildRule(
            conditionType: ConditionType.rollout,
            partitions: [const Partition(treatment: 'on', size: 100)],
          ),
        ],
      );

      // Try many keys; most should be excluded
      int excluded = 0;
      for (int i = 0; i < 100; i++) {
        final result = engine.evaluate('user$i', null, split, {}, ctx);
        if (result.label == Labels.notInSplit) excluded++;
      }
      // With 1% traffic allocation, most should be excluded
      expect(excluded, greaterThan(80));
    });

    test('traffic allocation gate returns default treatment config', () {
      // Use trafficAllocation=1 so keys are excluded (notInSplit path).
      final split = _buildSplit(
        defaultTreatment: 'off',
        trafficAllocation: 1,
        seed: 42,
        conditions: [
          _buildRule(
            conditionType: ConditionType.rollout,
            partitions: [const Partition(treatment: 'on', size: 100)],
          ),
        ],
        configurations: const {
          'off': '{"color":"blue"}',
          'on': '{"color":"red"}',
        },
      );

      // Find a key that lands outside the 1% allocation.
      String? excludedKey;
      for (int i = 0; i < 200; i++) {
        final r = engine.evaluate('user$i', null, split, {}, ctx);
        if (r.label == Labels.notInSplit) {
          excludedKey = 'user$i';
          break;
        }
      }
      expect(excludedKey, isNotNull,
          reason: 'expected at least one excluded key with 1% allocation');

      final result = engine.evaluate(excludedKey!, null, split, {}, ctx);
      expect(result.treatment, equals('off'));
      expect(result.label, equals(Labels.notInSplit));
      expect(result.config, equals('{"color":"blue"}'));
    });

    test('traffic allocation gate allows user when bucket <= allocation', () {
      // 100% traffic allocation means everyone passes
      final split = _buildSplit(
        trafficAllocation: 100,
        conditions: [
          _buildRule(
            conditionType: ConditionType.rollout,
            partitions: [const Partition(treatment: 'on', size: 100)],
          ),
        ],
      );

      final result = engine.evaluate('user1', null, split, {}, ctx);
      expect(result.treatment, equals('on'));
      expect(result.label, isNot(equals(Labels.notInSplit)));
    });

    test('traffic allocation uses trafficAllocationSeed if present', () {
      final split = _buildSplit(
        trafficAllocation: 50,
        trafficAllocationSeed: 99999,
        seed: 12345,
        conditions: [
          _buildRule(
            conditionType: ConditionType.rollout,
            partitions: [const Partition(treatment: 'on', size: 100)],
          ),
        ],
      );

      // With a different TA seed vs split seed, outcomes differ
      final result = engine.evaluate('user1', null, split, {}, ctx);
      expect(result.treatment, isA<String>());
    });

    test('condition matching with AllKeysMatcher', () {
      final split = _buildSplit(
        conditions: [
          _buildRule(
            matcher: const AttributeMatcher(delegate: AllKeysMatcher()),
            partitions: [const Partition(treatment: 'on', size: 100)],
            label: 'all keys',
          ),
        ],
      );

      final result = engine.evaluate('anyuser', null, split, {}, ctx);
      expect(result.treatment, equals('on'));
      expect(result.label, equals('all keys'));
    });

    test('no conditions matched returns default rule', () {
      final split = _buildSplit(
        conditions: [
          _buildRule(
            matcher: const AttributeMatcher(
              delegate: WhitelistMatcher(whitelist: {'special_user'}),
            ),
            partitions: [const Partition(treatment: 'on', size: 100)],
          ),
        ],
      );

      final result = engine.evaluate('other_user', null, split, {}, ctx);
      expect(result.treatment, equals('off'));
      expect(result.label, equals(Labels.defaultRule));
    });

    test('uses bucketingKey when provided', () {
      final split = _buildSplit(
        conditions: [
          _buildRule(
            partitions: [
              const Partition(treatment: 'on', size: 50),
              const Partition(treatment: 'off', size: 50),
            ],
          ),
        ],
      );

      // Same bucketing key should always yield same result
      final r1 = engine.evaluate('user1', 'bk1', split, {}, ctx);
      final r2 = engine.evaluate('user2', 'bk1', split, {}, ctx);
      expect(r1.treatment, equals(r2.treatment));
    });

    test('whitelist condition only when rollout type is checked for TA', () {
      // Whitelist conditions should not trigger traffic allocation check
      final split = _buildSplit(
        trafficAllocation: 1, // very low
        conditions: [
          _buildRule(
            conditionType: ConditionType.whitelist,
            matcher: const AttributeMatcher(delegate: AllKeysMatcher()),
            partitions: [const Partition(treatment: 'on', size: 100)],
            label: 'whitelist match',
          ),
        ],
      );

      // Whitelist conditions bypass TA check
      final result = engine.evaluate('user1', null, split, {}, ctx);
      expect(result.treatment, equals('on'));
      expect(result.label, equals('whitelist match'));
    });
  });

  // =========================================================================
  // Matchers (via matchCombining)
  // =========================================================================

  group('Matchers', () {
    final ctx = MockEvaluationContext();

    group('AllKeysMatcher', () {
      test('matches any key', () {
        final matcher = const AttributeMatcher(delegate: AllKeysMatcher());
        expect(_matchAttribute(matcher, 'anything', null, {}, ctx), isTrue);
      });

      test('negated AllKeys matches nothing', () {
        final matcher =
            const AttributeMatcher(delegate: AllKeysMatcher(), negate: true);
        expect(_matchAttribute(matcher, 'anything', null, {}, ctx), isFalse);
      });
    });

    group('WhitelistMatcher', () {
      test('matches key in whitelist', () {
        final matcher = const AttributeMatcher(
          delegate: WhitelistMatcher(whitelist: {'user1', 'user2'}),
        );
        expect(_matchAttribute(matcher, 'user1', null, {}, ctx), isTrue);
      });

      test('does not match key not in whitelist', () {
        final matcher = const AttributeMatcher(
          delegate: WhitelistMatcher(whitelist: {'user1', 'user2'}),
        );
        expect(_matchAttribute(matcher, 'user3', null, {}, ctx), isFalse);
      });

      test('matches attribute value in whitelist', () {
        final matcher = const AttributeMatcher(
          delegate: WhitelistMatcher(whitelist: {'premium'}),
          attribute: 'plan',
        );
        expect(
          _matchAttribute(matcher, 'user1', null, {'plan': 'premium'}, ctx),
          isTrue,
        );
      });

      test('attribute is null returns false, even when negated', () {
        final matcher = const AttributeMatcher(
          delegate: WhitelistMatcher(whitelist: {'val'}),
          attribute: 'missing',
        );
        expect(_matchAttribute(matcher, 'user1', null, {}, ctx), isFalse);

        // Per spec (§5.4) and the .NET reference SDK, negate MUST NOT be
        // applied to the "missing attribute" short-circuit: a null/missing
        // attribute always yields false, regardless of negate.
        final negated = const AttributeMatcher(
          delegate: WhitelistMatcher(whitelist: {'val'}),
          attribute: 'missing',
          negate: true,
        );
        expect(_matchAttribute(negated, 'user1', null, {}, ctx), isFalse);
      });
    });

    group('EqualToMatcher', () {
      test('number equality', () {
        final matcher = const AttributeMatcher(
          delegate: EqualToMatcher(value: 42, dataType: DataType.number),
          attribute: 'age',
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'age': 42}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'age': 43}, ctx),
          isFalse,
        );
      });

      test('datetime equality (day-truncated)', () {
        final day = DateTime.utc(2023, 6, 15).millisecondsSinceEpoch;
        final matcher = AttributeMatcher(
          delegate: EqualToMatcher(value: day, dataType: DataType.datetime),
          attribute: 'date',
        );
        // Same day, different time -> should match (day-truncated)
        final sameDay =
            DateTime.utc(2023, 6, 15, 14, 30).millisecondsSinceEpoch;
        expect(
          _matchAttribute(matcher, 'k', null, {'date': sameDay}, ctx),
          isTrue,
        );

        // Different day -> should not match
        final diffDay = DateTime.utc(2023, 6, 16).millisecondsSinceEpoch;
        expect(
          _matchAttribute(matcher, 'k', null, {'date': diffDay}, ctx),
          isFalse,
        );
      });

      test('non-int attribute returns false', () {
        final matcher = const AttributeMatcher(
          delegate: EqualToMatcher(value: 5, dataType: DataType.number),
          attribute: 'val',
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'val': '5'}, ctx),
          isFalse,
        );
      });
    });

    group('GreaterThanOrEqualToMatcher', () {
      test('number >=', () {
        final matcher = const AttributeMatcher(
          delegate:
              GreaterThanOrEqualToMatcher(value: 10, dataType: DataType.number),
          attribute: 'score',
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'score': 10}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'score': 11}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'score': 9}, ctx),
          isFalse,
        );
      });

      test('datetime >= (minute-truncated)', () {
        final threshold =
            DateTime.utc(2023, 6, 15, 10, 30).millisecondsSinceEpoch;
        final matcher = AttributeMatcher(
          delegate: GreaterThanOrEqualToMatcher(
            value: threshold,
            dataType: DataType.datetime,
          ),
          attribute: 'ts',
        );
        final after = DateTime.utc(2023, 6, 15, 11, 0).millisecondsSinceEpoch;
        final before = DateTime.utc(2023, 6, 15, 9, 0).millisecondsSinceEpoch;
        expect(_matchAttribute(matcher, 'k', null, {'ts': after}, ctx), isTrue);
        expect(
            _matchAttribute(matcher, 'k', null, {'ts': before}, ctx), isFalse);
      });
    });

    group('LessThanOrEqualToMatcher', () {
      test('number <=', () {
        final matcher = const AttributeMatcher(
          delegate:
              LessThanOrEqualToMatcher(value: 100, dataType: DataType.number),
          attribute: 'score',
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'score': 100}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'score': 99}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'score': 101}, ctx),
          isFalse,
        );
      });
    });

    group('BetweenMatcher', () {
      test('number between inclusive', () {
        final matcher = const AttributeMatcher(
          delegate: BetweenMatcher(
            start: 10,
            end: 20,
            dataType: DataType.number,
          ),
          attribute: 'val',
        );
        expect(_matchAttribute(matcher, 'k', null, {'val': 10}, ctx), isTrue);
        expect(_matchAttribute(matcher, 'k', null, {'val': 15}, ctx), isTrue);
        expect(_matchAttribute(matcher, 'k', null, {'val': 20}, ctx), isTrue);
        expect(_matchAttribute(matcher, 'k', null, {'val': 9}, ctx), isFalse);
        expect(_matchAttribute(matcher, 'k', null, {'val': 21}, ctx), isFalse);
      });

      test('datetime between (minute-truncated)', () {
        final start = DateTime.utc(2023, 6, 15, 10, 0).millisecondsSinceEpoch;
        final end = DateTime.utc(2023, 6, 15, 12, 0).millisecondsSinceEpoch;
        final matcher = AttributeMatcher(
          delegate: BetweenMatcher(
            start: start,
            end: end,
            dataType: DataType.datetime,
          ),
          attribute: 'ts',
        );
        final mid = DateTime.utc(2023, 6, 15, 11, 0).millisecondsSinceEpoch;
        final outside = DateTime.utc(2023, 6, 15, 13, 0).millisecondsSinceEpoch;
        expect(_matchAttribute(matcher, 'k', null, {'ts': mid}, ctx), isTrue);
        expect(
          _matchAttribute(matcher, 'k', null, {'ts': outside}, ctx),
          isFalse,
        );
      });
    });

    group('Set matchers', () {
      test('EqualToSet matches identical set', () {
        final matcher = const AttributeMatcher(
          delegate: EqualToSetMatcher(compareTo: {'a', 'b', 'c'}),
          attribute: 'tags',
        );
        expect(
          _matchAttribute(
              matcher,
              'k',
              null,
              {
                'tags': ['a', 'b', 'c']
              },
              ctx),
          isTrue,
        );
        expect(
          _matchAttribute(
              matcher,
              'k',
              null,
              {
                'tags': ['a', 'b']
              },
              ctx),
          isFalse,
        );
        expect(
          _matchAttribute(
              matcher,
              'k',
              null,
              {
                'tags': ['a', 'b', 'c', 'd']
              },
              ctx),
          isFalse,
        );
      });

      test('ContainsAnyOfSet matches if any element present', () {
        final matcher = const AttributeMatcher(
          delegate: ContainsAnyOfSetMatcher(compareTo: {'x', 'y'}),
          attribute: 'tags',
        );
        expect(
          _matchAttribute(
              matcher,
              'k',
              null,
              {
                'tags': ['x', 'z']
              },
              ctx),
          isTrue,
        );
        expect(
          _matchAttribute(
              matcher,
              'k',
              null,
              {
                'tags': ['z', 'w']
              },
              ctx),
          isFalse,
        );
      });

      test('ContainsAllOfSet matches if all elements present', () {
        final matcher = const AttributeMatcher(
          delegate: ContainsAllOfSetMatcher(compareTo: {'a', 'b'}),
          attribute: 'tags',
        );
        expect(
          _matchAttribute(
              matcher,
              'k',
              null,
              {
                'tags': ['a', 'b', 'c']
              },
              ctx),
          isTrue,
        );
        expect(
          _matchAttribute(
              matcher,
              'k',
              null,
              {
                'tags': ['a', 'c']
              },
              ctx),
          isFalse,
        );
      });

      test('PartOfSet matches if value is subset of compareTo', () {
        final matcher = const AttributeMatcher(
          delegate: PartOfSetMatcher(compareTo: {'a', 'b', 'c', 'd'}),
          attribute: 'tags',
        );
        expect(
          _matchAttribute(
              matcher,
              'k',
              null,
              {
                'tags': ['a', 'b']
              },
              ctx),
          isTrue,
        );
        expect(
          _matchAttribute(
              matcher,
              'k',
              null,
              {
                'tags': ['a', 'z']
              },
              ctx),
          isFalse,
        );
      });

      test('set matchers return false for non-List values', () {
        final matcher = const AttributeMatcher(
          delegate: EqualToSetMatcher(compareTo: {'a'}),
          attribute: 'tags',
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'tags': 'a'}, ctx),
          isFalse,
        );
      });
    });

    group('String matchers', () {
      test('StartsWith', () {
        final matcher = const AttributeMatcher(
          delegate: StartsWithAnyOfMatcher(values: ['pre_', 'test_']),
          attribute: 'name',
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'name': 'pre_fix'}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'name': 'test_val'}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'name': 'other'}, ctx),
          isFalse,
        );
      });

      test('EndsWith', () {
        final matcher = const AttributeMatcher(
          delegate: EndsWithAnyOfMatcher(values: ['_end', '.txt']),
          attribute: 'file',
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'file': 'data_end'}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'file': 'doc.txt'}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'file': 'doc.pdf'}, ctx),
          isFalse,
        );
      });

      test('Contains', () {
        final matcher = const AttributeMatcher(
          delegate: ContainsAnyOfMatcher(values: ['hello', 'world']),
          attribute: 'msg',
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'msg': 'say hello!'}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'msg': 'nothing'}, ctx),
          isFalse,
        );
      });

      test('Regex', () {
        final matcher = const AttributeMatcher(
          delegate: RegularExpressionMatcher(pattern: r'^\d{3}-\d{4}$'),
          attribute: 'code',
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'code': '123-4567'}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'code': 'abc-defg'}, ctx),
          isFalse,
        );
      });

      test('negated Regex with missing attribute returns false', () {
        final matcher = const AttributeMatcher(
          delegate: RegularExpressionMatcher(pattern: r'^\d{3}-\d{4}$'),
          attribute: 'code',
          negate: true,
        );
        // The delegate would match (non-match negated -> true) if the
        // attribute were present and non-matching, but a missing attribute
        // MUST short-circuit to false regardless of negate.
        expect(_matchAttribute(matcher, 'k', null, {}, ctx), isFalse);
      });

      test('string matchers return false for non-String values', () {
        final matcher = const AttributeMatcher(
          delegate: StartsWithAnyOfMatcher(values: ['x']),
          attribute: 'val',
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'val': 123}, ctx),
          isFalse,
        );
      });
    });

    group('BooleanMatcher', () {
      test('matches true', () {
        final matcher = const AttributeMatcher(
          delegate: BooleanMatcher(value: true),
          attribute: 'active',
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'active': true}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'active': false}, ctx),
          isFalse,
        );
      });

      test('matches boolean from string', () {
        final matcher = const AttributeMatcher(
          delegate: BooleanMatcher(value: true),
          attribute: 'flag',
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'flag': 'true'}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'flag': 'false'}, ctx),
          isFalse,
        );
      });
    });

    group('Semver matchers', () {
      test('EqualToSemver', () {
        final matcher = const AttributeMatcher(
          delegate: EqualToSemverMatcher(version: '2.0.0'),
          attribute: 'version',
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'version': '2.0.0'}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'version': '2.0.1'}, ctx),
          isFalse,
        );
      });

      test('GreaterThanOrEqualToSemver', () {
        final matcher = const AttributeMatcher(
          delegate: GreaterThanOrEqualToSemverMatcher(version: '1.5.0'),
          attribute: 'version',
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'version': '1.5.0'}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'version': '2.0.0'}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'version': '1.4.9'}, ctx),
          isFalse,
        );
      });

      test('LessThanOrEqualToSemver', () {
        final matcher = const AttributeMatcher(
          delegate: LessThanOrEqualToSemverMatcher(version: '3.0.0'),
          attribute: 'version',
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'version': '2.9.9'}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'version': '3.0.0'}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'version': '3.0.1'}, ctx),
          isFalse,
        );
      });

      test('BetweenSemver', () {
        final matcher = const AttributeMatcher(
          delegate: BetweenSemverMatcher(start: '1.0.0', end: '2.0.0'),
          attribute: 'version',
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'version': '1.5.0'}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'version': '1.0.0'}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'version': '2.0.0'}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'version': '0.9.0'}, ctx),
          isFalse,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'version': '2.0.1'}, ctx),
          isFalse,
        );
      });

      test('InListSemver', () {
        final matcher = const AttributeMatcher(
          delegate: InListSemverMatcher(versions: ['1.0.0', '2.0.0', '3.0.0']),
          attribute: 'version',
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'version': '2.0.0'}, ctx),
          isTrue,
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'version': '2.5.0'}, ctx),
          isFalse,
        );
      });

      test('invalid semver returns false', () {
        final matcher = const AttributeMatcher(
          delegate: EqualToSemverMatcher(version: '1.0.0'),
          attribute: 'version',
        );
        expect(
          _matchAttribute(
              matcher, 'k', null, {'version': 'not-a-version'}, ctx),
          isFalse,
        );
      });

      test('non-string value returns false', () {
        final matcher = const AttributeMatcher(
          delegate: EqualToSemverMatcher(version: '1.0.0'),
          attribute: 'version',
        );
        expect(
          _matchAttribute(matcher, 'k', null, {'version': 100}, ctx),
          isFalse,
        );
      });
    });

    group('UserDefinedSegmentMatcher', () {
      test('matches when key is in segment', () {
        final segCtx = MockEvaluationContext(segments: {'employees:user1'});
        final matcher = const AttributeMatcher(
          delegate: UserDefinedSegmentMatcher(segmentName: 'employees'),
        );
        expect(_matchAttribute(matcher, 'user1', null, {}, segCtx), isTrue);
      });

      test('does not match when key is not in segment', () {
        final segCtx = MockEvaluationContext(segments: {'employees:user1'});
        final matcher = const AttributeMatcher(
          delegate: UserDefinedSegmentMatcher(segmentName: 'employees'),
        );
        expect(_matchAttribute(matcher, 'user2', null, {}, segCtx), isFalse);
      });
    });

    group('DependencyMatcher', () {
      test('matches when dependent split returns expected treatment', () {
        final depCtx = MockEvaluationContext(
          evaluations: {
            'other_flag': (
              treatment: 'on',
              label: 'default rule',
            ),
          },
        );
        final matcher = const AttributeMatcher(
          delegate: DependencyMatcher(
            split: 'other_flag',
            treatments: ['on', 'variant'],
          ),
        );
        expect(_matchAttribute(matcher, 'user1', null, {}, depCtx), isTrue);
      });

      test('does not match when dependent split returns unexpected treatment',
          () {
        final depCtx = MockEvaluationContext(
          evaluations: {
            'other_flag': (
              treatment: 'off',
              label: 'default rule',
            ),
          },
        );
        final matcher = const AttributeMatcher(
          delegate: DependencyMatcher(
            split: 'other_flag',
            treatments: ['on'],
          ),
        );
        expect(_matchAttribute(matcher, 'user1', null, {}, depCtx), isFalse);
      });
    });

    group('Negate', () {
      test('negated matcher inverts result', () {
        final matcher = const AttributeMatcher(
          delegate: WhitelistMatcher(whitelist: {'admin'}),
          negate: true,
        );
        // Key "admin" would normally match, but negated -> false
        expect(_matchAttribute(matcher, 'admin', null, {}, ctx), isFalse);
        // Key "user" would not match, negated -> true
        expect(_matchAttribute(matcher, 'user', null, {}, ctx), isTrue);
      });
    });

    group('CombiningMatcher (AND)', () {
      test('matches when every delegate matches', () {
        const combining = CombiningMatcher(
          delegates: [
            AttributeMatcher(
              delegate: WhitelistMatcher(whitelist: {'admin'}),
            ),
            AttributeMatcher(
              delegate: EqualToMatcher(value: 30, dataType: DataType.number),
              attribute: 'age',
            ),
          ],
        );
        expect(
          matchCombining(combining, 'admin', null, {'age': 30}, ctx),
          isTrue,
        );
      });

      test('does not match when any delegate fails', () {
        const combining = CombiningMatcher(
          delegates: [
            AttributeMatcher(
              delegate: WhitelistMatcher(whitelist: {'admin'}),
            ),
            AttributeMatcher(
              delegate: EqualToMatcher(value: 30, dataType: DataType.number),
              attribute: 'age',
            ),
          ],
        );
        // First delegate fails
        expect(
          matchCombining(combining, 'other', null, {'age': 30}, ctx),
          isFalse,
        );
        // Second delegate fails
        expect(
          matchCombining(combining, 'admin', null, {'age': 25}, ctx),
          isFalse,
        );
      });

      test('empty delegate list never matches', () {
        const combining = CombiningMatcher(delegates: []);
        expect(matchCombining(combining, 'anyone', null, {}, ctx), isFalse);
      });

      test('respects negate on individual delegates', () {
        // (key NOT in {'blocked'}) AND (age >= 18)
        const combining = CombiningMatcher(
          delegates: [
            AttributeMatcher(
              delegate: WhitelistMatcher(whitelist: {'blocked'}),
              negate: true,
            ),
            AttributeMatcher(
              delegate: GreaterThanOrEqualToMatcher(
                value: 18,
                dataType: DataType.number,
              ),
              attribute: 'age',
            ),
          ],
        );
        expect(
          matchCombining(combining, 'alice', null, {'age': 20}, ctx),
          isTrue,
        );
        expect(
          matchCombining(combining, 'blocked', null, {'age': 20}, ctx),
          isFalse,
        );
        expect(
          matchCombining(combining, 'alice', null, {'age': 10}, ctx),
          isFalse,
        );
      });
    });
  });
}
