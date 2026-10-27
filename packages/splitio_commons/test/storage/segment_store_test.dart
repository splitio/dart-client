import 'package:splitio_commons/src/storage/storage.dart';
import 'package:test/test.dart';

void main() {
  group('InMemorySegmentStore', () {
    late InMemorySegmentStore store;

    setUp(() => store = InMemorySegmentStore());

    test('isInSegment returns false for unknown segment', () {
      expect(store.isInSegment('missing', 'user-1'), isFalse);
    });

    test('update adds keys and marks membership', () {
      final changed = store.update('seg', ['a', 'b'], const [], 10);

      expect(changed, isTrue);
      expect(store.isInSegment('seg', 'a'), isTrue);
      expect(store.isInSegment('seg', 'b'), isTrue);
      expect(store.isInSegment('seg', 'c'), isFalse);
      expect(store.changeNumber('seg'), 10);
    });

    test('update removes keys', () {
      store.update('seg', ['a', 'b'], const [], 10);

      final changed = store.update('seg', const [], ['a'], 11);

      expect(changed, isTrue);
      expect(store.isInSegment('seg', 'a'), isFalse);
      expect(store.isInSegment('seg', 'b'), isTrue);
      expect(store.changeNumber('seg'), 11);
    });

    test('update with no adds and no removes advances cursor only', () {
      store.update('seg', ['a'], const [], 5);

      final changed = store.update('seg', const [], const [], 6);

      expect(changed, isFalse);
      expect(store.changeNumber('seg'), 6);
      expect(store.isInSegment('seg', 'a'), isTrue);
    });

    test('re-applying keys already in the set reports no change', () {
      store.update('seg', ['a', 'b'], const [], 10);

      final changed = store.update('seg', ['a', 'b'], ['missing'], 10);

      expect(changed, isFalse);
      expect(store.isInSegment('seg', 'a'), isTrue);
    });

    test('changeNumber returns -1 for unknown segment', () {
      expect(store.changeNumber('missing'), -1);
    });

    test('registerSegments creates empty segment slots', () {
      store.registerSegments(['seg_x', 'seg_y']);

      expect(store.getRegisteredSegments(), containsAll(['seg_x', 'seg_y']));
      expect(store.isInSegment('seg_x', 'anyone'), isFalse);
      expect(store.changeNumber('seg_x'), -1);
    });

    test('registerSegments does not clobber existing members', () {
      store.update('seg', ['a'], const [], 5);

      store.registerSegments(['seg']);

      expect(store.isInSegment('seg', 'a'), isTrue);
      expect(store.changeNumber('seg'), 5);
    });

    test('getRegisteredSegments returns every known segment', () {
      store.update('seg_1', ['a'], const [], 1);
      store.registerSegments(['seg_2']);

      expect(store.getRegisteredSegments(), containsAll(['seg_1', 'seg_2']));
    });

    test('allRegisteredSegmentsFetched is true when nothing is registered', () {
      expect(store.allRegisteredSegmentsFetched(), isTrue);
    });

    test(
        'allRegisteredSegmentsFetched is false for a segment registered '
        'but never fetched', () {
      store.registerSegments(['seg_x']);

      expect(store.allRegisteredSegmentsFetched(), isFalse);
    });

    test(
        'allRegisteredSegmentsFetched is true once every registered '
        'segment has been fetched', () {
      store.registerSegments(['seg_x']);
      store.update('seg_x', const [], const [], 10);

      expect(store.allRegisteredSegmentsFetched(), isTrue);
    });

    test(
        'allRegisteredSegmentsFetched goes back to false when a new '
        'segment is registered after a prior one was already fetched', () {
      store.update('seg_x', const [], const [], 10);
      expect(store.allRegisteredSegmentsFetched(), isTrue);

      store.registerSegments(['seg_y']);

      expect(store.allRegisteredSegmentsFetched(), isFalse);
    });

    test('clear removes all state', () {
      store.update('seg', ['a'], const [], 5);
      store.registerSegments(['other']);

      store.clear();

      expect(store.getRegisteredSegments(), isEmpty);
      expect(store.isInSegment('seg', 'a'), isFalse);
      expect(store.changeNumber('seg'), -1);
    });

    test('implements SegmentStore and SegmentMembershipResolver', () {
      bool isSubtype<S, T>() => <S>[] is List<T>;

      expect(isSubtype<InMemorySegmentStore, SegmentStore>(), isTrue);
      expect(
        isSubtype<InMemorySegmentStore, SegmentMembershipResolver>(),
        isTrue,
      );
    });
  });
}
