import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:test/test.dart';

// -- Test fixtures --

ParsedSplit _split(String name, {List<String> sets = const []}) => ParsedSplit(
      name: name,
      trafficTypeName: 'user',
      killed: false,
      defaultTreatment: 'off',
      conditions: [
        TargetingRule(
          conditionType: ConditionType.rollout,
          matcher: CombiningMatcher(
            delegates: [AttributeMatcher(delegate: AllKeysMatcher())],
          ),
          partitions: [Partition(treatment: 'on', size: 100)],
          label: 'default rule',
        ),
      ],
      trafficAllocation: 100,
      seed: 12345,
      algo: 2,
      changeNumber: 1,
      sets: sets,
    );

RuleBasedSegment _segment(String name, {int changeNumber = 1}) =>
    RuleBasedSegment(
      name: name,
      conditions: [
        TargetingRule(
          conditionType: ConditionType.rollout,
          matcher: CombiningMatcher(
            delegates: [AttributeMatcher(delegate: AllKeysMatcher())],
          ),
          partitions: [Partition(treatment: 'on', size: 100)],
          label: 'default rule',
        ),
      ],
      changeNumber: changeNumber,
    );

void main() {
  group('InMemoryRuleStore', () {
    late InMemoryRuleStore store;

    setUp(() {
      store = InMemoryRuleStore();
    });

    test('starts with changeNumber -1', () {
      expect(store.changeNumber(), equals(-1));
    });

    test('starts with empty getAll', () {
      expect(store.getAll(), isEmpty);
    });

    test('get returns null for unknown key', () {
      expect(store.get('unknown'), isNull);
    });

    test('applyChange adds splits', () {
      final split = _split('feature_a');
      store.applyChange(
          Change(changeNumber: 100, updates: {'feature_a': split}));

      expect(store.get('feature_a'), same(split));
      expect(store.changeNumber(), equals(100));
    });

    test('applyChange adds multiple splits at once', () {
      final splitA = _split('a');
      final splitB = _split('b');
      store.applyChange(
          Change(changeNumber: 50, updates: {'a': splitA, 'b': splitB}));

      expect(store.get('a'), same(splitA));
      expect(store.get('b'), same(splitB));
      expect(store.getAll().length, equals(2));
    });

    test('applyChange removes splits when value is null', () {
      final split = _split('feature_a');
      store.applyChange(Change(changeNumber: 1, updates: {'feature_a': split}));
      store.applyChange(Change(changeNumber: 2, updates: {'feature_a': null}));

      expect(store.get('feature_a'), isNull);
      expect(store.getAll(), isEmpty);
    });

    test('applyChange replaces existing split', () {
      final v1 = _split('feature_a');
      final v2 = _split('feature_a');
      store.applyChange(Change(changeNumber: 1, updates: {'feature_a': v1}));
      store.applyChange(Change(changeNumber: 2, updates: {'feature_a': v2}));

      expect(store.get('feature_a'), same(v2));
    });

    test('changeNumber advances with each applyChange', () {
      store.applyChange(Change(changeNumber: 10, updates: {'x': _split('x')}));
      expect(store.changeNumber(), equals(10));

      store.applyChange(Change(changeNumber: 20, updates: {'y': _split('y')}));
      expect(store.changeNumber(), equals(20));
    });

    test('getAll returns all stored splits', () {
      store.applyChange(Change(changeNumber: 1, updates: {
        'a': _split('a'),
        'b': _split('b'),
        'c': _split('c'),
      }));

      final all = store.getAll().toList();
      expect(all.length, equals(3));
    });

    group('getByFlagSets', () {
      test('returns splits matching any of the given sets', () {
        store.applyChange(Change(changeNumber: 1, updates: {
          'a': _split('a', sets: ['set_1', 'set_2']),
          'b': _split('b', sets: ['set_2']),
          'c': _split('c', sets: ['set_3']),
          'd': _split('d', sets: []),
        }));

        final result = store.getByFlagSets(['set_1']);
        expect(result.length, equals(1));
        expect(result.first.name, equals('a'));
      });

      test('returns multiple splits when sets overlap', () {
        store.applyChange(Change(changeNumber: 1, updates: {
          'a': _split('a', sets: ['set_1', 'set_2']),
          'b': _split('b', sets: ['set_2']),
          'c': _split('c', sets: ['set_3']),
        }));

        final result = store.getByFlagSets(['set_2']);
        expect(result.length, equals(2));
        final names = result.map((s) => s.name).toSet();
        expect(names, containsAll(['a', 'b']));
      });

      test('returns empty list when no sets match', () {
        store.applyChange(Change(changeNumber: 1, updates: {
          'a': _split('a', sets: ['set_1']),
        }));

        expect(store.getByFlagSets(['no_match']), isEmpty);
      });

      test('returns empty list when store is empty', () {
        expect(store.getByFlagSets(['set_1']), isEmpty);
      });
    });

    test('loadLocal completes without error', () async {
      await expectLater(store.loadLocal(), completes);
    });
  });

  group('InMemoryRuleBasedSegmentStore', () {
    late InMemoryRuleBasedSegmentStore store;

    setUp(() {
      store = InMemoryRuleBasedSegmentStore();
    });

    test('starts with changeNumber -1', () {
      expect(store.changeNumber(), equals(-1));
    });

    test('starts with empty getAll', () {
      expect(store.getAll(), isEmpty);
    });

    test('get returns null for unknown key', () {
      expect(store.get('unknown'), isNull);
    });

    test('applyChange adds segments', () {
      final segment = _segment('segment_a');
      store.applyChange(
          Change(changeNumber: 10, updates: {'segment_a': segment}));

      expect(store.get('segment_a'), same(segment));
      expect(store.changeNumber(), equals(10));
    });

    test('applyChange adds multiple segments', () {
      final a = _segment('a');
      final b = _segment('b');
      store.applyChange(Change(changeNumber: 5, updates: {'a': a, 'b': b}));

      expect(store.get('a'), same(a));
      expect(store.get('b'), same(b));
      expect(store.getAll().length, equals(2));
    });

    test('applyChange removes segments when value is null', () {
      final segment = _segment('segment_a');
      store.applyChange(
          Change(changeNumber: 1, updates: {'segment_a': segment}));
      store.applyChange(Change(changeNumber: 2, updates: {'segment_a': null}));

      expect(store.get('segment_a'), isNull);
      expect(store.getAll(), isEmpty);
    });

    test('applyChange replaces existing segment', () {
      final v1 = _segment('seg', changeNumber: 1);
      final v2 = _segment('seg', changeNumber: 2);
      store.applyChange(Change(changeNumber: 1, updates: {'seg': v1}));
      store.applyChange(Change(changeNumber: 2, updates: {'seg': v2}));

      expect(store.get('seg'), same(v2));
    });

    test('changeNumber advances with each applyChange', () {
      store.applyChange(
          Change(changeNumber: 100, updates: {'x': _segment('x')}));
      expect(store.changeNumber(), equals(100));

      store.applyChange(
          Change(changeNumber: 200, updates: {'y': _segment('y')}));
      expect(store.changeNumber(), equals(200));
    });

    test('getAll returns all stored segments', () {
      store.applyChange(Change(changeNumber: 1, updates: {
        'a': _segment('a'),
        'b': _segment('b'),
        'c': _segment('c'),
      }));

      expect(store.getAll().length, equals(3));
    });

    test('loadLocal completes without error', () async {
      await expectLater(store.loadLocal(), completes);
    });
  });

  group('InMemoryMembershipStore', () {
    late InMemoryMembershipStore store;

    setUp(() {
      store = InMemoryMembershipStore();
    });

    test('changeNumber returns -1 for unknown key', () {
      expect(store.changeNumber('user_1'), equals(-1));
    });

    test('isInSegment returns false for unknown key', () {
      expect(store.isInSegment('segment_a', 'user_1'), isFalse);
    });

    test('applyMembership stores mySegments', () {
      store.applyMembership(
        'user_1',
        MembershipChange(
          changeNumber: 10,
          mySegments: {'seg_a', 'seg_b'},
          largeSegments: {},
        ),
      );

      expect(store.isInSegment('seg_a', 'user_1'), isTrue);
      expect(store.isInSegment('seg_b', 'user_1'), isTrue);
      expect(store.isInSegment('seg_c', 'user_1'), isFalse);
    });

    test('applyMembership stores largeSegments', () {
      store.applyMembership(
        'user_1',
        MembershipChange(
          changeNumber: 5,
          mySegments: {},
          largeSegments: {'large_a'},
        ),
      );

      expect(store.isInSegment('large_a', 'user_1'), isTrue);
    });

    test('applyMembership merges mySegments and largeSegments', () {
      store.applyMembership(
        'user_1',
        MembershipChange(
          changeNumber: 7,
          mySegments: {'seg_a'},
          largeSegments: {'large_a'},
        ),
      );

      expect(store.isInSegment('seg_a', 'user_1'), isTrue);
      expect(store.isInSegment('large_a', 'user_1'), isTrue);
    });

    test('changeNumber returns correct value per key', () {
      store.applyMembership(
        'user_1',
        MembershipChange(
            changeNumber: 10, mySegments: {'a'}, largeSegments: {}),
      );
      store.applyMembership(
        'user_2',
        MembershipChange(
            changeNumber: 20, mySegments: {'b'}, largeSegments: {}),
      );

      expect(store.changeNumber('user_1'), equals(10));
      expect(store.changeNumber('user_2'), equals(20));
    });

    test('applyMembership replaces previous membership for key', () {
      store.applyMembership(
        'user_1',
        MembershipChange(
            changeNumber: 1, mySegments: {'old_seg'}, largeSegments: {}),
      );
      store.applyMembership(
        'user_1',
        MembershipChange(
            changeNumber: 2, mySegments: {'new_seg'}, largeSegments: {}),
      );

      expect(store.isInSegment('old_seg', 'user_1'), isFalse);
      expect(store.isInSegment('new_seg', 'user_1'), isTrue);
      expect(store.changeNumber('user_1'), equals(2));
    });

    test('clear removes key membership', () {
      store.applyMembership(
        'user_1',
        MembershipChange(
            changeNumber: 10, mySegments: {'seg_a'}, largeSegments: {}),
      );

      store.clear('user_1');

      expect(store.isInSegment('seg_a', 'user_1'), isFalse);
      expect(store.changeNumber('user_1'), equals(-1));
    });

    test('mySegmentsForKey / largeSegmentsForKey keep loci separate', () {
      store.applyMembership(
        'user_1',
        MembershipChange(
          changeNumber: 7,
          mySegments: {'ms_a', 'ms_b'},
          largeSegments: {'ls_a'},
        ),
      );

      expect(store.mySegmentsForKey('user_1'), equals({'ms_a', 'ms_b'}));
      expect(store.largeSegmentsForKey('user_1'), equals({'ls_a'}));
    });

    test('mySegmentsForKey / largeSegmentsForKey empty for unknown key', () {
      expect(store.mySegmentsForKey('nobody'), isEmpty);
      expect(store.largeSegmentsForKey('nobody'), isEmpty);
    });

    test('mySegmentsForKey returns a copy that does not mutate the store', () {
      store.applyMembership(
        'user_1',
        MembershipChange(
            changeNumber: 1, mySegments: {'ms_a'}, largeSegments: {}),
      );

      store.mySegmentsForKey('user_1').add('injected');

      expect(store.isInSegment('injected', 'user_1'), isFalse);
    });

    test('clear does not affect other keys', () {
      store.applyMembership(
        'user_1',
        MembershipChange(
            changeNumber: 10, mySegments: {'seg_a'}, largeSegments: {}),
      );
      store.applyMembership(
        'user_2',
        MembershipChange(
            changeNumber: 20, mySegments: {'seg_b'}, largeSegments: {}),
      );

      store.clear('user_1');

      expect(store.isInSegment('seg_b', 'user_2'), isTrue);
      expect(store.changeNumber('user_2'), equals(20));
    });
  });

  group('NoOpPersistentStore', () {
    late NoOpPersistentStore store;

    setUp(() {
      store = NoOpPersistentStore();
    });

    test('load returns null', () async {
      final result = await store.load('any_key');
      expect(result, isNull);
    });

    test('load returns null for different keys', () async {
      expect(await store.load('key_1'), isNull);
      expect(await store.load('key_2'), isNull);
    });

    test('save completes without error', () async {
      await expectLater(
        store.save('key', [1, 2, 3]),
        completes,
      );
    });

    test('save then load still returns null', () async {
      await store.save('key', [10, 20, 30]);
      final result = await store.load('key');
      expect(result, isNull);
    });
  });
}
