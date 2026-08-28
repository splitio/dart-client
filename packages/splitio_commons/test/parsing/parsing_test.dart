import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:test/test.dart';

import 'package:splitio_commons/src/parsing/parsing.dart';

void main() {
  group('RuleParser', () {
    late RuleParser parser;

    setUp(() {
      parser = RuleParser();
    });

    group('parseSplit', () {
      test('parses a complete split DTO', () {
        final dto = _completeSplitDto();
        final result = parser.parseSplit(dto);

        expect(result, isNotNull);
        expect(result!.name, 'my_flag');
        expect(result.trafficTypeName, 'user');
        expect(result.killed, false);
        expect(result.defaultTreatment, 'off');
        expect(result.trafficAllocation, 100);
        expect(result.trafficAllocationSeed, 123);
        expect(result.seed, 456);
        expect(result.algo, 2);
        expect(result.changeNumber, 123456);
        expect(result.sets, ['set_a']);
        expect(result.impressionsDisabled, false);
      });

      test('returns null for ARCHIVED status', () {
        final dto = _completeSplitDto();
        dto['status'] = 'ARCHIVED';

        final result = parser.parseSplit(dto);
        expect(result, isNull);
      });

      test('parses configurations map', () {
        final dto = _completeSplitDto();
        dto['configurations'] = {'on': '{"color":"red"}', 'off': '{}'};

        final result = parser.parseSplit(dto);
        expect(result, isNotNull);
        expect(result!.configurations, {'on': '{"color":"red"}', 'off': '{}'});
      });

      test('handles null configurations gracefully', () {
        final dto = _completeSplitDto();
        dto.remove('configurations');

        final result = parser.parseSplit(dto);
        expect(result, isNotNull);
        expect(result!.configurations, isEmpty);
      });

      test('parses prerequisites', () {
        final dto = _completeSplitDto();
        dto['prerequisites'] = [
          {
            'featureFlagName': 'other_flag',
            'treatments': ['on'],
          }
        ];

        final result = parser.parseSplit(dto);
        expect(result, isNotNull);
        expect(result!.prerequisites, hasLength(1));
        expect(result.prerequisites[0].featureFlagName, 'other_flag');
        expect(result.prerequisites[0].treatments, ['on']);
      });

      test('parses partitions correctly', () {
        final dto = _completeSplitDto();
        final result = parser.parseSplit(dto);

        expect(result, isNotNull);
        expect(result!.conditions, hasLength(1));
        expect(result.conditions[0].partitions, hasLength(2));
        expect(result.conditions[0].partitions[0].treatment, 'on');
        expect(result.conditions[0].partitions[0].size, 50);
        expect(result.conditions[0].partitions[1].treatment, 'off');
        expect(result.conditions[0].partitions[1].size, 50);
      });

      test('parses condition type WHITELIST', () {
        final dto = _completeSplitDto();
        (dto['conditions'] as List)[0]['conditionType'] = 'WHITELIST';

        final result = parser.parseSplit(dto);
        expect(result, isNotNull);
        expect(result!.conditions[0].conditionType, ConditionType.whitelist);
      });

      test('parses condition type ROLLOUT', () {
        final dto = _completeSplitDto();
        final result = parser.parseSplit(dto);

        expect(result, isNotNull);
        expect(result!.conditions[0].conditionType, ConditionType.rollout);
      });

      test('parses label from condition', () {
        final dto = _completeSplitDto();
        final result = parser.parseSplit(dto);

        expect(result, isNotNull);
        expect(result!.conditions[0].label, 'default rule');
      });

      test('handles killed flag', () {
        final dto = _completeSplitDto();
        dto['killed'] = true;

        final result = parser.parseSplit(dto);
        expect(result, isNotNull);
        expect(result!.killed, true);
      });

      test('handles impressionsDisabled flag', () {
        final dto = _completeSplitDto();
        dto['impressionsDisabled'] = true;

        final result = parser.parseSplit(dto);
        expect(result, isNotNull);
        expect(result!.impressionsDisabled, true);
      });

      test('handles empty conditions list', () {
        final dto = _completeSplitDto();
        dto['conditions'] = [];

        final result = parser.parseSplit(dto);
        expect(result, isNotNull);
        expect(result!.conditions, isEmpty);
      });

      test('handles missing optional fields with defaults', () {
        final dto = <String, dynamic>{
          'name': 'minimal_flag',
          'status': 'ACTIVE',
          'conditions': [],
        };

        final result = parser.parseSplit(dto);
        expect(result, isNotNull);
        expect(result!.name, 'minimal_flag');
        expect(result.trafficTypeName, '');
        expect(result.killed, false);
        expect(result.defaultTreatment, 'control');
        expect(result.trafficAllocation, 100);
        expect(result.trafficAllocationSeed, isNull);
        expect(result.seed, 0);
        expect(result.algo, 2);
        expect(result.changeNumber, 0);
        expect(result.configurations, isEmpty);
        expect(result.prerequisites, isEmpty);
        expect(result.sets, isEmpty);
        expect(result.impressionsDisabled, false);
      });

      group('matcher types', () {
        test('ALL_KEYS matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': null},
            'matcherType': 'ALL_KEYS',
            'negate': false,
            'userDefinedSegmentMatcherData': null,
            'whitelistMatcherData': null,
            'unaryNumericMatcherData': null,
            'betweenMatcherData': null,
            'booleanMatcherData': null,
            'stringMatcherData': null,
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final combined = result!.conditions[0].matcher.delegates[0];
          expect(combined.delegate, isA<AllKeysMatcher>());
          expect(combined.negate, false);
          expect(combined.attribute, isNull);
        });

        test('WHITELIST matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': null},
            'matcherType': 'WHITELIST',
            'negate': false,
            'whitelistMatcherData': {
              'whitelist': ['user1', 'user2', 'user3']
            },
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<WhitelistMatcher>());
          expect((delegate as WhitelistMatcher).whitelist,
              {'user1', 'user2', 'user3'});
        });

        test('IN_SEGMENT matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': null},
            'matcherType': 'IN_SEGMENT',
            'negate': false,
            'userDefinedSegmentMatcherData': {'segmentName': 'beta_users'},
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<UserDefinedSegmentMatcher>());
          expect((delegate as UserDefinedSegmentMatcher).segmentName,
              'beta_users');
        });

        test('IN_RULE_BASED_SEGMENT matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': null},
            'matcherType': 'IN_RULE_BASED_SEGMENT',
            'negate': false,
            'userDefinedSegmentMatcherData': {'segmentName': 'rbs_segment'},
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<RuleBasedSegmentMatcher>());
          expect(
              (delegate as RuleBasedSegmentMatcher).segmentName, 'rbs_segment');
        });

        test('MATCHES_STRING matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'email'},
            'matcherType': 'MATCHES_STRING',
            'negate': false,
            'stringMatcherData': {'value': r'^.*@example\.com$'},
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final combined = result!.conditions[0].matcher.delegates[0];
          expect(combined.attribute, 'email');
          final delegate = combined.delegate;
          expect(delegate, isA<RegularExpressionMatcher>());
          expect((delegate as RegularExpressionMatcher).pattern,
              r'^.*@example\.com$');
        });

        test('EQUAL_TO matcher with NUMBER dataType', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'age'},
            'matcherType': 'EQUAL_TO',
            'negate': false,
            'unaryNumericMatcherData': {'value': 25, 'dataType': 'NUMBER'},
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<EqualToMatcher>());
          final equalTo = delegate as EqualToMatcher;
          expect(equalTo.value, 25);
          expect(equalTo.dataType, DataType.number);
        });

        test('EQUAL_TO matcher with DATETIME dataType', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'created_at'},
            'matcherType': 'EQUAL_TO',
            'negate': false,
            'unaryNumericMatcherData': {
              'value': 1609459200000,
              'dataType': 'DATETIME'
            },
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<EqualToMatcher>());
          final equalTo = delegate as EqualToMatcher;
          expect(equalTo.value, 1609459200000);
          expect(equalTo.dataType, DataType.datetime);
        });

        test('GREATER_THAN_OR_EQUAL_TO matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'age'},
            'matcherType': 'GREATER_THAN_OR_EQUAL_TO',
            'negate': false,
            'unaryNumericMatcherData': {'value': 18, 'dataType': 'NUMBER'},
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<GreaterThanOrEqualToMatcher>());
          final gte = delegate as GreaterThanOrEqualToMatcher;
          expect(gte.value, 18);
          expect(gte.dataType, DataType.number);
        });

        test('LESS_THAN_OR_EQUAL_TO matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'age'},
            'matcherType': 'LESS_THAN_OR_EQUAL_TO',
            'negate': false,
            'unaryNumericMatcherData': {'value': 65, 'dataType': 'NUMBER'},
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<LessThanOrEqualToMatcher>());
          final lte = delegate as LessThanOrEqualToMatcher;
          expect(lte.value, 65);
          expect(lte.dataType, DataType.number);
        });

        test('BETWEEN matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'age'},
            'matcherType': 'BETWEEN',
            'negate': false,
            'betweenMatcherData': {
              'start': 18,
              'end': 65,
              'dataType': 'NUMBER'
            },
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<BetweenMatcher>());
          final between = delegate as BetweenMatcher;
          expect(between.start, 18);
          expect(between.end, 65);
          expect(between.dataType, DataType.number);
        });

        test('EQUAL_TO_SET matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'plan'},
            'matcherType': 'EQUAL_TO_SET',
            'negate': false,
            'whitelistMatcherData': {
              'whitelist': ['premium', 'enterprise']
            },
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<EqualToSetMatcher>());
          expect((delegate as EqualToSetMatcher).compareTo,
              {'premium', 'enterprise'});
        });

        test('CONTAINS_ANY_OF_SET matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'tags'},
            'matcherType': 'CONTAINS_ANY_OF_SET',
            'negate': false,
            'whitelistMatcherData': {
              'whitelist': ['vip', 'beta']
            },
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<ContainsAnyOfSetMatcher>());
          expect(
              (delegate as ContainsAnyOfSetMatcher).compareTo, {'vip', 'beta'});
        });

        test('CONTAINS_ALL_OF_SET matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'perms'},
            'matcherType': 'CONTAINS_ALL_OF_SET',
            'negate': false,
            'whitelistMatcherData': {
              'whitelist': ['read', 'write']
            },
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<ContainsAllOfSetMatcher>());
          expect((delegate as ContainsAllOfSetMatcher).compareTo,
              {'read', 'write'});
        });

        test('PART_OF_SET matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'roles'},
            'matcherType': 'PART_OF_SET',
            'negate': false,
            'whitelistMatcherData': {
              'whitelist': ['admin', 'editor', 'viewer']
            },
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<PartOfSetMatcher>());
          expect((delegate as PartOfSetMatcher).compareTo,
              {'admin', 'editor', 'viewer'});
        });

        test('STARTS_WITH matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'email'},
            'matcherType': 'STARTS_WITH',
            'negate': false,
            'whitelistMatcherData': {
              'whitelist': ['admin@', 'support@']
            },
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<StartsWithAnyOfMatcher>());
          expect((delegate as StartsWithAnyOfMatcher).values,
              ['admin@', 'support@']);
        });

        test('ENDS_WITH matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'email'},
            'matcherType': 'ENDS_WITH',
            'negate': false,
            'whitelistMatcherData': {
              'whitelist': ['@example.com', '@test.com']
            },
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<EndsWithAnyOfMatcher>());
          expect((delegate as EndsWithAnyOfMatcher).values,
              ['@example.com', '@test.com']);
        });

        test('CONTAINS_STRING matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'name'},
            'matcherType': 'CONTAINS_STRING',
            'negate': false,
            'whitelistMatcherData': {
              'whitelist': ['test', 'demo']
            },
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<ContainsAnyOfMatcher>());
          expect((delegate as ContainsAnyOfMatcher).values, ['test', 'demo']);
        });

        test('EQUAL_TO_BOOLEAN matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'is_active'},
            'matcherType': 'EQUAL_TO_BOOLEAN',
            'negate': false,
            'booleanMatcherData': true,
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<BooleanMatcher>());
          expect((delegate as BooleanMatcher).value, true);
        });

        test('EQUAL_TO_BOOLEAN matcher with false value', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'is_active'},
            'matcherType': 'EQUAL_TO_BOOLEAN',
            'negate': false,
            'booleanMatcherData': false,
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<BooleanMatcher>());
          expect((delegate as BooleanMatcher).value, false);
        });

        test('IN_SPLIT_TREATMENT (dependency) matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': null},
            'matcherType': 'IN_SPLIT_TREATMENT',
            'negate': false,
            'dependencyMatcherData': {
              'split': 'parent_flag',
              'treatments': ['on'],
            },
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<DependencyMatcher>());
          final dep = delegate as DependencyMatcher;
          expect(dep.split, 'parent_flag');
          expect(dep.treatments, ['on']);
        });

        test('EQUAL_TO_SEMVER matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'version'},
            'matcherType': 'EQUAL_TO_SEMVER',
            'negate': false,
            'stringMatcherData': {'value': '2.0.0'},
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<EqualToSemverMatcher>());
          expect((delegate as EqualToSemverMatcher).version, '2.0.0');
        });

        test('GREATER_THAN_OR_EQUAL_TO_SEMVER matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'version'},
            'matcherType': 'GREATER_THAN_OR_EQUAL_TO_SEMVER',
            'negate': false,
            'stringMatcherData': {'value': '1.5.0'},
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<GreaterThanOrEqualToSemverMatcher>());
          expect(
              (delegate as GreaterThanOrEqualToSemverMatcher).version, '1.5.0');
        });

        test('LESS_THAN_OR_EQUAL_TO_SEMVER matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'version'},
            'matcherType': 'LESS_THAN_OR_EQUAL_TO_SEMVER',
            'negate': false,
            'stringMatcherData': {'value': '3.0.0'},
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<LessThanOrEqualToSemverMatcher>());
          expect((delegate as LessThanOrEqualToSemverMatcher).version, '3.0.0');
        });

        test('BETWEEN_SEMVER matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'version'},
            'matcherType': 'BETWEEN_SEMVER',
            'negate': false,
            'betweenStringMatcherData': {'start': '1.0.0', 'end': '2.0.0'},
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<BetweenSemverMatcher>());
          final between = delegate as BetweenSemverMatcher;
          expect(between.start, '1.0.0');
          expect(between.end, '2.0.0');
        });

        test('IN_LIST_SEMVER matcher', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'version'},
            'matcherType': 'IN_LIST_SEMVER',
            'negate': false,
            'whitelistMatcherData': {
              'whitelist': ['1.0.0', '1.1.0', '2.0.0']
            },
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final delegate = result!.conditions[0].matcher.delegates[0].delegate;
          expect(delegate, isA<InListSemverMatcher>());
          expect((delegate as InListSemverMatcher).versions,
              ['1.0.0', '1.1.0', '2.0.0']);
        });

        test('negate flag is parsed correctly', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': null},
            'matcherType': 'ALL_KEYS',
            'negate': true,
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          expect(result!.conditions[0].matcher.delegates[0].negate, true);
        });

        test('attribute from keySelector is parsed', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': 'plan'},
            'matcherType': 'ALL_KEYS',
            'negate': false,
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          expect(result!.conditions[0].matcher.delegates[0].attribute, 'plan');
        });
      });

      group('multi-matcher matcher group (AND)', () {
        test(
            'single matcher condition produces a one-delegate CombiningMatcher',
            () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': null},
            'matcherType': 'ALL_KEYS',
            'negate': false,
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final combining = result!.conditions[0].matcher;
          expect(combining.combiner, equals(CombinerEnum.and));
          expect(combining.delegates, hasLength(1));
          expect(combining.delegates[0].delegate, isA<AllKeysMatcher>());
        });

        test('multiple matchers become multiple delegates under AND', () {
          final dto = _splitWithMatchers([
            {
              'keySelector': {'trafficType': 'user', 'attribute': null},
              'matcherType': 'ALL_KEYS',
              'negate': false,
            },
            {
              'keySelector': {'trafficType': 'user', 'attribute': 'age'},
              'matcherType': 'GREATER_THAN_OR_EQUAL_TO',
              'negate': false,
              'unaryNumericMatcherData': {'value': 18, 'dataType': 'NUMBER'},
            },
          ]);

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final combining = result!.conditions[0].matcher;
          expect(combining.combiner, equals(CombinerEnum.and));
          expect(combining.delegates, hasLength(2));

          expect(combining.delegates[0].delegate, isA<AllKeysMatcher>());
          expect(combining.delegates[1].delegate,
              isA<GreaterThanOrEqualToMatcher>());
          expect(combining.delegates[1].attribute, equals('age'));
        });

        test('preserves per-matcher negate flags across delegates', () {
          final dto = _splitWithMatchers([
            {
              'keySelector': {'trafficType': 'user', 'attribute': null},
              'matcherType': 'ALL_KEYS',
              'negate': true,
            },
            {
              'keySelector': {'trafficType': 'user', 'attribute': null},
              'matcherType': 'ALL_KEYS',
              'negate': false,
            },
          ]);

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          final combining = result!.conditions[0].matcher;
          expect(combining.delegates[0].negate, isTrue);
          expect(combining.delegates[1].negate, isFalse);
        });

        test(
            'returns unsupported template when any matcher in the group is unsupported',
            () {
          final dto = _splitWithMatchers([
            {
              'keySelector': {'trafficType': 'user', 'attribute': null},
              'matcherType': 'ALL_KEYS',
              'negate': false,
            },
            {
              'keySelector': {'trafficType': 'user', 'attribute': null},
              'matcherType': 'UNKNOWN_FUTURE_MATCHER',
              'negate': false,
            },
          ]);

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          expect(result!.defaultTreatment, 'control');
          expect(result.conditions[0].label, Labels.unsupportedMatcher);
        });
      });

      group('unsupported matcher', () {
        test('returns template with control treatment for unknown matcher type',
            () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': null},
            'matcherType': 'TOTALLY_UNKNOWN_MATCHER',
            'negate': false,
          });

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          expect(result!.name, 'test_flag');
          expect(result.defaultTreatment, 'control');
          expect(result.conditions, hasLength(1));
          expect(result.conditions[0].label, Labels.unsupportedMatcher);
          expect(result.conditions[0].matcher.delegates[0].delegate,
              isA<AllKeysMatcher>());
          expect(result.conditions[0].partitions, hasLength(1));
          expect(result.conditions[0].partitions[0].treatment, 'control');
          expect(result.conditions[0].partitions[0].size, 100);
        });

        test('unsupported template preserves name and sets from dto', () {
          final dto = _splitWithMatcher({
            'keySelector': {'trafficType': 'user', 'attribute': null},
            'matcherType': 'FUTURE_MATCHER_TYPE',
            'negate': false,
          });
          dto['sets'] = ['set_x', 'set_y'];

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          expect(result!.name, 'test_flag');
          expect(result.sets, ['set_x', 'set_y']);
        });

        test(
            'returns unsupported template when matcherGroup is null in a condition',
            () {
          final dto = <String, dynamic>{
            'name': 'broken_flag',
            'status': 'ACTIVE',
            'trafficTypeName': 'user',
            'killed': false,
            'defaultTreatment': 'off',
            'trafficAllocation': 100,
            'seed': 999,
            'algo': 2,
            'changeNumber': 100,
            'conditions': [
              {
                'conditionType': 'ROLLOUT',
                'label': 'some rule',
                'matcherGroup': null,
                'partitions': [
                  {'treatment': 'on', 'size': 100}
                ],
              }
            ],
            'sets': [],
          };

          final result = parser.parseSplit(dto);
          expect(result, isNotNull);
          expect(result!.defaultTreatment, 'control');
          expect(result.conditions[0].label, Labels.unsupportedMatcher);
        });
      });
    });

    group('parseRuleBasedSegment', () {
      test('parses a basic RBS DTO', () {
        final dto = <String, dynamic>{
          'name': 'rbs_employees',
          'status': 'ACTIVE',
          'changeNumber': 555,
          'conditions': [
            {
              'conditionType': 'ROLLOUT',
              'label': 'in segment',
              'matcherGroup': {
                'combiner': 'AND',
                'matchers': [
                  {
                    'keySelector': {'trafficType': 'user', 'attribute': null},
                    'matcherType': 'ALL_KEYS',
                    'negate': false,
                  }
                ],
              },
              'partitions': [
                {'treatment': 'on', 'size': 100}
              ],
            }
          ],
        };

        final result = parser.parseRuleBasedSegment(dto);
        expect(result, isNotNull);
        expect(result!.name, 'rbs_employees');
        expect(result.changeNumber, 555);
        expect(result.conditions, hasLength(1));
        expect(result.conditions[0].matcher.delegates[0].delegate,
            isA<AllKeysMatcher>());
      });

      test('returns null for ARCHIVED status', () {
        final dto = <String, dynamic>{
          'name': 'rbs_old',
          'status': 'ARCHIVED',
          'changeNumber': 100,
          'conditions': [],
        };

        final result = parser.parseRuleBasedSegment(dto);
        expect(result, isNull);
      });

      test('handles empty conditions', () {
        final dto = <String, dynamic>{
          'name': 'rbs_empty',
          'status': 'ACTIVE',
          'changeNumber': 10,
          'conditions': [],
        };

        final result = parser.parseRuleBasedSegment(dto);
        expect(result, isNotNull);
        expect(result!.conditions, isEmpty);
      });

      test('handles unsupported matcher in conditions gracefully', () {
        final dto = <String, dynamic>{
          'name': 'rbs_unsupported',
          'status': 'ACTIVE',
          'changeNumber': 20,
          'conditions': [
            {
              'conditionType': 'ROLLOUT',
              'label': 'future rule',
              'matcherGroup': {
                'combiner': 'AND',
                'matchers': [
                  {
                    'keySelector': {'trafficType': 'user', 'attribute': null},
                    'matcherType': 'FUTURE_UNKNOWN',
                    'negate': false,
                  }
                ],
              },
              'partitions': [
                {'treatment': 'on', 'size': 100}
              ],
            }
          ],
        };

        // RBS returns empty conditions when parsing fails (null from _parseConditions)
        final result = parser.parseRuleBasedSegment(dto);
        expect(result, isNotNull);
        expect(result!.conditions, isEmpty);
      });

      test('handles missing optional fields with defaults', () {
        final dto = <String, dynamic>{
          'name': 'rbs_minimal',
          'conditions': [],
        };

        final result = parser.parseRuleBasedSegment(dto);
        expect(result, isNotNull);
        expect(result!.name, 'rbs_minimal');
        expect(result.changeNumber, 0);
        expect(result.conditions, isEmpty);
      });
    });
  });

  group('SplitChangeProcessor', () {
    late SplitChangeProcessor processor;
    late InMemoryRuleStore ruleStore;
    late InMemoryRuleBasedSegmentStore rbsStore;

    setUp(() {
      ruleStore = InMemoryRuleStore();
      rbsStore = InMemoryRuleBasedSegmentStore();
      processor = SplitChangeProcessor(
        parser: RuleParser(),
        ruleStore: ruleStore,
        rbsStore: rbsStore,
      );
    });

    group('processTargetingRules', () {
      test('processes a complete response with feature flags', () {
        final response = _fullResponse();

        final result = processor.processTargetingRules(response);

        expect(result.ffTill, 123456);
        expect(result.rbsTill, -1);
        expect(result.changedFlags, ['my_flag']);
        expect(ruleStore.get('my_flag'), isNotNull);
        expect(ruleStore.changeNumber(), 123456);
      });

      test('advances cursor even when no splits are present', () {
        final response = <String, dynamic>{
          'ff': {'t': 500, 's': -1, 'd': []},
          'rbs': {'t': 300, 's': -1, 'd': []},
        };

        final result = processor.processTargetingRules(response);

        expect(result.ffTill, 500);
        expect(result.rbsTill, 300);
        expect(ruleStore.changeNumber(), 500);
        expect(rbsStore.changeNumber(), 300);
      });

      test('removes split from store when status is ARCHIVED', () {
        // First add a flag
        final addResponse = <String, dynamic>{
          'ff': {
            't': 100,
            's': -1,
            'd': [_completeSplitDto()]
          },
          'rbs': {'t': -1, 's': -1, 'd': []},
        };
        processor.processTargetingRules(addResponse);
        expect(ruleStore.get('my_flag'), isNotNull);

        // Then archive it
        final archiveDto = _completeSplitDto();
        archiveDto['status'] = 'ARCHIVED';
        archiveDto['changeNumber'] = 200;
        final archiveResponse = <String, dynamic>{
          'ff': {
            't': 200,
            's': -1,
            'd': [archiveDto]
          },
          'rbs': {'t': -1, 's': -1, 'd': []},
        };
        final result = processor.processTargetingRules(archiveResponse);

        expect(ruleStore.get('my_flag'), isNull);
        expect(result.changedFlags, contains('my_flag'));
        expect(ruleStore.changeNumber(), 200);
      });

      test('returns changed flag names', () {
        final dto1 = _completeSplitDto();
        dto1['name'] = 'flag_a';
        final dto2 = _completeSplitDto();
        dto2['name'] = 'flag_b';

        final response = <String, dynamic>{
          'ff': {
            't': 100,
            's': -1,
            'd': [dto1, dto2]
          },
          'rbs': {'t': -1, 's': -1, 'd': []},
        };

        final result = processor.processTargetingRules(response);

        expect(result.changedFlags, containsAll(['flag_a', 'flag_b']));
        expect(result.changedFlags, hasLength(2));
      });

      test('processes rule-based segments', () {
        final response = <String, dynamic>{
          'ff': {'t': -1, 's': -1, 'd': []},
          'rbs': {
            't': 200,
            's': -1,
            'd': [
              {
                'name': 'rbs_employees',
                'status': 'ACTIVE',
                'changeNumber': 200,
                'conditions': [
                  {
                    'conditionType': 'ROLLOUT',
                    'label': 'all keys',
                    'matcherGroup': {
                      'combiner': 'AND',
                      'matchers': [
                        {
                          'keySelector': {
                            'trafficType': 'user',
                            'attribute': null
                          },
                          'matcherType': 'ALL_KEYS',
                          'negate': false,
                        }
                      ],
                    },
                    'partitions': [
                      {'treatment': 'on', 'size': 100}
                    ],
                  }
                ],
              }
            ],
          },
        };

        final result = processor.processTargetingRules(response);

        expect(result.rbsTill, 200);
        expect(rbsStore.get('rbs_employees'), isNotNull);
        expect(rbsStore.changeNumber(), 200);
      });

      test('does not advance cursor when till is not greater than current', () {
        // First set the store to a known change number
        ruleStore.applyChange(
            const Change(changeNumber: 500, updates: <String, ParsedSplit?>{}));

        final response = <String, dynamic>{
          'ff': {'t': 300, 's': -1, 'd': []},
          'rbs': {'t': -1, 's': -1, 'd': []},
        };

        processor.processTargetingRules(response);

        // Store should keep its original change number since 300 < 500
        expect(ruleStore.changeNumber(), 500);
      });

      test('handles missing ff and rbs keys in response', () {
        final response = <String, dynamic>{};

        final result = processor.processTargetingRules(response);

        expect(result.ffTill, -1);
        expect(result.rbsTill, -1);
        expect(result.changedFlags, isEmpty);
      });

      test('handles multiple flags with mixed statuses', () {
        final activeDto = _completeSplitDto();
        activeDto['name'] = 'active_flag';

        final archivedDto = _completeSplitDto();
        archivedDto['name'] = 'archived_flag';
        archivedDto['status'] = 'ARCHIVED';

        final response = <String, dynamic>{
          'ff': {
            't': 100,
            's': -1,
            'd': [activeDto, archivedDto]
          },
          'rbs': {'t': -1, 's': -1, 'd': []},
        };

        final result = processor.processTargetingRules(response);

        expect(ruleStore.get('active_flag'), isNotNull);
        expect(ruleStore.get('archived_flag'), isNull);
        expect(
            result.changedFlags, containsAll(['active_flag', 'archived_flag']));
      });
    });

    group('processMemberships', () {
      late InMemoryMembershipStore membershipStore;
      late MembershipsProcessor membershipsProcessor;

      setUp(() {
        membershipStore = InMemoryMembershipStore();
        membershipsProcessor =
            MembershipsProcessor(membershipStore: membershipStore);
      });

      test('processes my_segments membership data', () {
        final response = <String, dynamic>{
          'ms': {
            'k': ['segment_a', 'segment_b'],
            'cn': 100,
          },
        };

        membershipsProcessor.processMemberships(response, 'user_key');

        expect(membershipStore.isInSegment('segment_a', 'user_key'), true);
        expect(membershipStore.isInSegment('segment_b', 'user_key'), true);
        expect(membershipStore.isInSegment('segment_c', 'user_key'), false);
        expect(membershipStore.changeNumber('user_key'), 100);
      });

      test('processes large_segments membership data', () {
        final response = <String, dynamic>{
          'ls': {
            'k': ['large_seg_1', 'large_seg_2'],
            'cn': 200,
          },
        };

        membershipsProcessor.processMemberships(response, 'user_key');

        expect(membershipStore.isInSegment('large_seg_1', 'user_key'), true);
        expect(membershipStore.isInSegment('large_seg_2', 'user_key'), true);
        expect(membershipStore.changeNumber('user_key'), 200);
      });

      test('combines both my_segments and large_segments', () {
        final response = <String, dynamic>{
          'ms': {
            'k': ['my_seg'],
            'cn': 150,
          },
          'ls': {
            'k': ['large_seg'],
            'cn': 200,
          },
        };

        membershipsProcessor.processMemberships(response, 'user_key');

        expect(membershipStore.isInSegment('my_seg', 'user_key'), true);
        expect(membershipStore.isInSegment('large_seg', 'user_key'), true);
      });

      test('handles empty membership lists', () {
        final response = <String, dynamic>{
          'ms': {
            'k': <String>[],
            'cn': 50,
          },
          'ls': {
            'k': <String>[],
            'cn': 50,
          },
        };

        membershipsProcessor.processMemberships(response, 'user_key');

        expect(membershipStore.changeNumber('user_key'), 50);
        expect(membershipStore.isInSegment('anything', 'user_key'), false);
      });

      test('handles missing ms and ls keys', () {
        final response = <String, dynamic>{};

        membershipsProcessor.processMemberships(response, 'user_key');

        expect(membershipStore.changeNumber('user_key'), -1);
      });

      test('processes memberships per key independently', () {
        final response1 = <String, dynamic>{
          'ms': {
            'k': ['seg_a'],
            'cn': 100,
          },
        };
        final response2 = <String, dynamic>{
          'ms': {
            'k': ['seg_b'],
            'cn': 200,
          },
        };

        membershipsProcessor.processMemberships(response1, 'key_1');
        membershipsProcessor.processMemberships(response2, 'key_2');

        expect(membershipStore.isInSegment('seg_a', 'key_1'), true);
        expect(membershipStore.isInSegment('seg_b', 'key_1'), false);
        expect(membershipStore.isInSegment('seg_a', 'key_2'), false);
        expect(membershipStore.isInSegment('seg_b', 'key_2'), true);
      });

      test('overwrites previous membership for same key', () {
        final response1 = <String, dynamic>{
          'ms': {
            'k': ['old_segment'],
            'cn': 100,
          },
        };
        membershipsProcessor.processMemberships(response1, 'user_key');
        expect(membershipStore.isInSegment('old_segment', 'user_key'), true);

        final response2 = <String, dynamic>{
          'ms': {
            'k': ['new_segment'],
            'cn': 200,
          },
        };
        membershipsProcessor.processMemberships(response2, 'user_key');

        expect(membershipStore.isInSegment('old_segment', 'user_key'), false);
        expect(membershipStore.isInSegment('new_segment', 'user_key'), true);
        expect(membershipStore.changeNumber('user_key'), 200);
      });

      test('uses cn from ms when ls is absent', () {
        final response = <String, dynamic>{
          'ms': {
            'k': ['seg'],
            'cn': 42,
          },
        };

        membershipsProcessor.processMemberships(response, 'user_key');
        expect(membershipStore.changeNumber('user_key'), 42);
      });

      test('uses cn from ls when ms cn is absent', () {
        final response = <String, dynamic>{
          'ms': {
            'k': ['seg'],
          },
          'ls': {
            'k': <String>[],
            'cn': 77,
          },
        };

        membershipsProcessor.processMemberships(response, 'user_key');
        expect(membershipStore.changeNumber('user_key'), 77);
      });
    });
  });
}

// --- Test Helpers ---

Map<String, dynamic> _completeSplitDto() {
  return <String, dynamic>{
    'name': 'my_flag',
    'trafficTypeName': 'user',
    'killed': false,
    'defaultTreatment': 'off',
    'trafficAllocation': 100,
    'trafficAllocationSeed': 123,
    'seed': 456,
    'algo': 2,
    'status': 'ACTIVE',
    'changeNumber': 123456,
    'conditions': [
      {
        'conditionType': 'ROLLOUT',
        'label': 'default rule',
        'matcherGroup': {
          'combiner': 'AND',
          'matchers': [
            {
              'keySelector': {'trafficType': 'user', 'attribute': null},
              'matcherType': 'ALL_KEYS',
              'negate': false,
              'userDefinedSegmentMatcherData': null,
              'whitelistMatcherData': null,
              'unaryNumericMatcherData': null,
              'betweenMatcherData': null,
              'booleanMatcherData': null,
              'stringMatcherData': null,
            }
          ],
        },
        'partitions': [
          {'treatment': 'on', 'size': 50},
          {'treatment': 'off', 'size': 50},
        ],
      }
    ],
    'configurations': {'on': '{"color":"red"}'},
    'sets': ['set_a'],
    'impressionsDisabled': false,
  };
}

Map<String, dynamic> _splitWithMatchers(List<Map<String, dynamic>> matchers) {
  return <String, dynamic>{
    'name': 'test_flag',
    'trafficTypeName': 'user',
    'killed': false,
    'defaultTreatment': 'off',
    'trafficAllocation': 100,
    'trafficAllocationSeed': 789,
    'seed': 101,
    'algo': 2,
    'status': 'ACTIVE',
    'changeNumber': 100,
    'conditions': [
      {
        'conditionType': 'ROLLOUT',
        'label': 'custom rule',
        'matcherGroup': {
          'combiner': 'AND',
          'matchers': matchers,
        },
        'partitions': [
          {'treatment': 'on', 'size': 100},
        ],
      }
    ],
    'configurations': null,
    'sets': [],
  };
}

Map<String, dynamic> _splitWithMatcher(Map<String, dynamic> matcherDto) {
  return <String, dynamic>{
    'name': 'test_flag',
    'trafficTypeName': 'user',
    'killed': false,
    'defaultTreatment': 'off',
    'trafficAllocation': 100,
    'trafficAllocationSeed': 789,
    'seed': 101,
    'algo': 2,
    'status': 'ACTIVE',
    'changeNumber': 100,
    'conditions': [
      {
        'conditionType': 'ROLLOUT',
        'label': 'custom rule',
        'matcherGroup': {
          'combiner': 'AND',
          'matchers': [matcherDto],
        },
        'partitions': [
          {'treatment': 'on', 'size': 100},
        ],
      }
    ],
    'configurations': null,
    'sets': [],
  };
}

Map<String, dynamic> _fullResponse() {
  return <String, dynamic>{
    'ff': {
      't': 123456,
      's': -1,
      'd': [_completeSplitDto()],
    },
    'rbs': {
      't': -1,
      's': -1,
      'd': [],
    },
  };
}
