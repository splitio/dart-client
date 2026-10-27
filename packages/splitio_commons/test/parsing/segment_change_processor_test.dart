import 'package:splitio_commons/src/parsing/segment_change_processor.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:test/test.dart';

void main() {
  group('SegmentChangeProcessor', () {
    late InMemorySegmentStore store;
    late SegmentChangeProcessor processor;

    setUp(() {
      store = InMemorySegmentStore();
      processor = SegmentChangeProcessor(store: store);
    });

    test('applies added and removed keys and returns till', () {
      final result = processor.processSegmentChange({
        'name': 'seg_a',
        'added': ['k1', 'k2'],
        'removed': <String>[],
        'since': -1,
        'till': 42,
      });

      expect(result!.till, 42);
      expect(result.changed, isTrue);
      expect(store.isInSegment('seg_a', 'k1'), isTrue);
      expect(store.isInSegment('seg_a', 'k2'), isTrue);
      expect(store.changeNumber('seg_a'), 42);
    });

    test('applies a removal payload', () {
      store.update('seg_a', ['k1', 'k2'], const [], 10);

      final result = processor.processSegmentChange({
        'name': 'seg_a',
        'added': <String>[],
        'removed': ['k1'],
        'since': 10,
        'till': 11,
      });

      expect(result!.till, 11);
      expect(result.changed, isTrue);
      expect(store.isInSegment('seg_a', 'k1'), isFalse);
      expect(store.isInSegment('seg_a', 'k2'), isTrue);
    });

    test('accepts empty added and removed arrays (cursor-only advance)', () {
      store.update('seg_a', ['k1'], const [], 10);

      final result = processor.processSegmentChange({
        'name': 'seg_a',
        'added': <String>[],
        'removed': <String>[],
        'since': 10,
        'till': 15,
      });

      expect(result!.till, 15);
      // No key was added or removed — a cursor-only advance MUST NOT be
      // reported as a change (spec §4.6/§8.2: whenUpdated() MUST NOT fire
      // on a no-op fetch).
      expect(result.changed, isFalse);
      expect(store.changeNumber('seg_a'), 15);
      expect(store.isInSegment('seg_a', 'k1'), isTrue);
    });

    test('returns null when name is missing', () {
      final result = processor.processSegmentChange({
        'added': const [],
        'removed': const [],
        'since': 0,
        'till': 1,
      });

      expect(result, isNull);
      expect(store.getRegisteredSegments(), isEmpty);
    });

    test('returns null when till is missing', () {
      final result = processor.processSegmentChange({
        'name': 'seg_a',
        'added': const [],
        'removed': const [],
        'since': 0,
      });

      expect(result, isNull);
    });

    test('tolerates non-string entries by skipping them', () {
      final result = processor.processSegmentChange({
        'name': 'seg_a',
        'added': ['k1', 42, null, 'k2'],
        'removed': const [],
        'since': -1,
        'till': 5,
      });

      expect(result!.till, 5);
      expect(result.changed, isTrue);
      expect(store.isInSegment('seg_a', 'k1'), isTrue);
      expect(store.isInSegment('seg_a', 'k2'), isTrue);
    });
  });
}
