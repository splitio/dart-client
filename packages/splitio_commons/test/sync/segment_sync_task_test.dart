import 'package:splitio_commons/src/sync/segment_sync_task.dart';
import 'package:splitio_commons/src/sync/fetchers/memberships_fetcher.dart';
import 'package:test/test.dart';

class _FakeSyncTask implements SegmentSyncTask {
  final bool result;
  int calls = 0;
  _FakeSyncTask(this.result);

  @override
  Future<bool> fetch() async {
    calls++;
    return result;
  }
}

void main() {
  group('SegmentSyncTask', () {
    test('exposes a fetch method returning Future<bool>', () async {
      final SegmentSyncTask t = _FakeSyncTask(true);
      expect(await t.fetch(), isTrue);
    });

    test('supports repeated invocation', () async {
      final t = _FakeSyncTask(false);
      final SegmentSyncTask st = t;
      await st.fetch();
      await st.fetch();
      expect(t.calls, 2);
    });
  });

  group('MembershipsFetcher implements SegmentSyncTask', () {
    test('is a compile-time subtype of SegmentSyncTask', () {
      // Compile-time subtype check via generic reification: a List<S> is
      // a List<T> only when S <: T. This avoids constructing a real
      // MembershipsFetcher (which needs HTTP client / logger / processor /
      // baseUrl) while still failing at test-runtime if the `implements`
      // clause is missing.
      bool isSubtype<S, T>() => <S>[] is List<T>;
      expect(isSubtype<MembershipsFetcher, SegmentSyncTask>(), isTrue);
    });
  });
}
