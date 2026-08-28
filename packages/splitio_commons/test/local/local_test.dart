import 'package:splitio_commons/src/engine/engine.dart';
import 'package:splitio_commons/src/local/local.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:test/test.dart';

ParsedSplit _simpleSplit(String name, {bool killed = false}) {
  return ParsedSplit(
    name: name,
    trafficTypeName: 'user',
    killed: killed,
    defaultTreatment: 'off',
    conditions: [
      TargetingRule(
        conditionType: ConditionType.rollout,
        matcher: const CombiningMatcher(
          delegates: [AttributeMatcher(delegate: AllKeysMatcher())],
        ),
        partitions: const [
          Partition(treatment: 'on', size: 100),
          Partition(treatment: 'off', size: 0),
        ],
        label: 'in segment all',
      ),
    ],
    trafficAllocation: 100,
    seed: 12345,
    algo: 2,
    changeNumber: 1,
  );
}

void main() {
  late InMemoryRuleStore ruleStore;
  late InMemoryRuleBasedSegmentStore rbsStore;
  late InMemoryMembershipStore membershipStore;
  late TargetingEngine engine;
  late LocalEvaluator evaluator;

  setUp(() {
    ruleStore = InMemoryRuleStore();
    rbsStore = InMemoryRuleBasedSegmentStore();
    membershipStore = InMemoryMembershipStore();
    engine = TargetingEngine();
    evaluator = LocalEvaluator(
      engine: engine,
      ruleStore: ruleStore,
      rbsStore: rbsStore,
      membershipStore: membershipStore,
    );
  });

  group('LocalEvaluator', () {
    test('evaluate returns null for unknown flag', () {
      final result = evaluator.evaluate('user1', null, 'unknown_flag', {});
      expect(result, isNull);
    });

    test('evaluate returns engine result for known flag', () {
      final split = _simpleSplit('my_flag');
      ruleStore
          .applyChange(Change(changeNumber: 1, updates: {'my_flag': split}));

      final result = evaluator.evaluate('user1', null, 'my_flag', {});
      expect(result, isNotNull);
      expect(result!.treatment, equals('on'));
      expect(result.label, equals('in segment all'));
    });

    test('evaluate returns default treatment for killed flag', () {
      final split = _simpleSplit('killed_flag', killed: true);
      ruleStore.applyChange(
          Change(changeNumber: 1, updates: {'killed_flag': split}));

      final result = evaluator.evaluate('user1', null, 'killed_flag', {});
      expect(result, isNotNull);
      expect(result!.treatment, equals('off'));
      expect(result.label, equals(Labels.killed));
    });

    test('getRule returns the parsed split', () {
      final split = _simpleSplit('my_flag');
      ruleStore
          .applyChange(Change(changeNumber: 1, updates: {'my_flag': split}));

      final rule = evaluator.getRule('my_flag');
      expect(rule, isNotNull);
      expect(rule!.name, equals('my_flag'));
      expect(rule.defaultTreatment, equals('off'));
    });

    test('getRule returns null for unknown flag', () {
      final rule = evaluator.getRule('nonexistent');
      expect(rule, isNull);
    });

    test('recursive evaluation via dependency matcher', () {
      final flagA = _simpleSplit('flag_a');

      final flagB = ParsedSplit(
        name: 'flag_b',
        trafficTypeName: 'user',
        killed: false,
        defaultTreatment: 'off',
        conditions: [
          TargetingRule(
            conditionType: ConditionType.rollout,
            matcher: CombiningMatcher(
              delegates: [
                AttributeMatcher(
                  delegate: DependencyMatcher(
                    split: 'flag_a',
                    treatments: ['on'],
                  ),
                ),
              ],
            ),
            partitions: const [
              Partition(treatment: 'yes', size: 100),
              Partition(treatment: 'no', size: 0),
            ],
            label: 'depends on flag_a',
          ),
        ],
        trafficAllocation: 100,
        seed: 67890,
        algo: 2,
        changeNumber: 2,
      );

      ruleStore.applyChange(Change(
        changeNumber: 2,
        updates: {'flag_a': flagA, 'flag_b': flagB},
      ));

      final result = evaluator.evaluate('user1', null, 'flag_b', {});
      expect(result, isNotNull);
      expect(result!.treatment, equals('yes'));
    });

    test('dependency matcher returns default when dependency not found', () {
      final flagB = ParsedSplit(
        name: 'flag_b',
        trafficTypeName: 'user',
        killed: false,
        defaultTreatment: 'off',
        conditions: [
          TargetingRule(
            conditionType: ConditionType.rollout,
            matcher: CombiningMatcher(
              delegates: [
                AttributeMatcher(
                  delegate: DependencyMatcher(
                    split: 'nonexistent',
                    treatments: ['on'],
                  ),
                ),
              ],
            ),
            partitions: const [
              Partition(treatment: 'yes', size: 100),
              Partition(treatment: 'no', size: 0),
            ],
            label: 'depends on nonexistent',
          ),
        ],
        trafficAllocation: 100,
        seed: 67890,
        algo: 2,
        changeNumber: 2,
      );

      ruleStore
          .applyChange(Change(changeNumber: 2, updates: {'flag_b': flagB}));

      final result = evaluator.evaluate('user1', null, 'flag_b', {});
      expect(result, isNotNull);
      expect(result!.treatment, equals('off'));
      expect(result.label, equals(Labels.defaultRule));
    });

    test('isInSegment delegates to membership store', () {
      final flag = ParsedSplit(
        name: 'seg_flag',
        trafficTypeName: 'user',
        killed: false,
        defaultTreatment: 'off',
        conditions: [
          TargetingRule(
            conditionType: ConditionType.whitelist,
            matcher: CombiningMatcher(
              delegates: [
                AttributeMatcher(
                  delegate:
                      UserDefinedSegmentMatcher(segmentName: 'beta_users'),
                ),
              ],
            ),
            partitions: const [
              Partition(treatment: 'on', size: 100),
              Partition(treatment: 'off', size: 0),
            ],
            label: 'in segment beta_users',
          ),
        ],
        trafficAllocation: 100,
        seed: 11111,
        algo: 2,
        changeNumber: 3,
      );

      ruleStore
          .applyChange(Change(changeNumber: 3, updates: {'seg_flag': flag}));

      // User NOT in segment -> default
      var result = evaluator.evaluate('user1', null, 'seg_flag', {});
      expect(result, isNotNull);
      expect(result!.treatment, equals('off'));

      // Add user to segment
      membershipStore.applyMembership(
        'user1',
        MembershipChange(
          changeNumber: 1,
          mySegments: {'beta_users'},
          largeSegments: {},
        ),
      );

      // User IS in segment -> 'on'
      result = evaluator.evaluate('user1', null, 'seg_flag', {});
      expect(result, isNotNull);
      expect(result!.treatment, equals('on'));
      expect(result.label, equals('in segment beta_users'));
    });

    test('isInRuleBasedSegment evaluates RBS conditions', () {
      final rbs = RuleBasedSegment(
        name: 'rbs_premium',
        conditions: [
          TargetingRule(
            conditionType: ConditionType.whitelist,
            matcher: CombiningMatcher(
              delegates: [
                AttributeMatcher(
                  delegate: WhitelistMatcher(whitelist: {'vip_user'}),
                ),
              ],
            ),
            partitions: const [],
            label: 'whitelist',
          ),
        ],
        changeNumber: 1,
      );

      rbsStore
          .applyChange(Change(changeNumber: 1, updates: {'rbs_premium': rbs}));

      final flag = ParsedSplit(
        name: 'rbs_flag',
        trafficTypeName: 'user',
        killed: false,
        defaultTreatment: 'off',
        conditions: [
          TargetingRule(
            conditionType: ConditionType.whitelist,
            matcher: CombiningMatcher(
              delegates: [
                AttributeMatcher(
                  delegate: RuleBasedSegmentMatcher(segmentName: 'rbs_premium'),
                ),
              ],
            ),
            partitions: const [
              Partition(treatment: 'premium', size: 100),
              Partition(treatment: 'off', size: 0),
            ],
            label: 'in rbs premium',
          ),
        ],
        trafficAllocation: 100,
        seed: 22222,
        algo: 2,
        changeNumber: 4,
      );

      ruleStore
          .applyChange(Change(changeNumber: 4, updates: {'rbs_flag': flag}));

      // vip_user matches the RBS whitelist
      var result = evaluator.evaluate('vip_user', null, 'rbs_flag', {});
      expect(result, isNotNull);
      expect(result!.treatment, equals('premium'));

      // regular_user does NOT match
      result = evaluator.evaluate('regular_user', null, 'rbs_flag', {});
      expect(result, isNotNull);
      expect(result!.treatment, equals('off'));
    });
  });
}
