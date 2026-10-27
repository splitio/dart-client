import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/parsing/segment_change_processor.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/sync/fetchers/segment_changes_fetcher.dart';
import 'package:splitio_commons/src/sync/segment_sync_task.dart';
import 'package:test/test.dart';

typedef _Handler = Future<http.Response> Function(http.BaseRequest);

_TestSetup _setup(_Handler handler) {
  final store = InMemorySegmentStore();
  final processor = SegmentChangeProcessor(store: store);
  final httpClient = SplitHttpClient(
    sdkVersion: 'dart_test-1.0.0',
    apiKey: 'test-key',
    client: MockClient(handler),
  );
  final fetcher = SegmentChangesFetcher(
    httpClient: httpClient,
    log: SplitLogger(level: LogLevel.none),
    baseUrl: 'https://sdk.split.io/api',
    processor: processor,
    store: store,
    maxRetries: 1,
  );
  return _TestSetup(store, httpClient, fetcher);
}

class _TestSetup {
  final InMemorySegmentStore store;
  final SplitHttpClient httpClient;
  final SegmentChangesFetcher fetcher;
  _TestSetup(this.store, this.httpClient, this.fetcher);

  void close() => httpClient.close();
}

void main() {
  group('SegmentChangesFetcher', () {
    test('fetch returns true when no segments are registered', () async {
      final s = _setup((_) async => http.Response('{}', 200));

      final result = await s.fetcher.fetch();

      expect(result, isTrue);
      s.close();
    });

    test('fetchForSegment loops until since === till', () async {
      final calls = <String>[];
      final s = _setup((request) async {
        calls.add(request.url.toString());
        // First page: -1 → 100, add k1
        if (request.url.queryParameters['since'] == '-1') {
          return http.Response(
            jsonEncode({
              'name': 'seg_a',
              'added': ['k1'],
              'removed': <String>[],
              'since': -1,
              'till': 100,
            }),
            200,
          );
        }
        // Second page: 100 → 100, caught up
        return http.Response(
          jsonEncode({
            'name': 'seg_a',
            'added': <String>[],
            'removed': <String>[],
            'since': 100,
            'till': 100,
          }),
          200,
        );
      });
      s.store.registerSegments(['seg_a']);

      final result = await s.fetcher.fetchForSegment('seg_a');

      expect(result, isTrue);
      expect(calls, hasLength(2));
      expect(calls[0], contains('since=-1'));
      expect(calls[1], contains('since=100'));
      expect(s.store.isInSegment('seg_a', 'k1'), isTrue);
      expect(s.store.changeNumber('seg_a'), 100);
      s.close();
    });

    test('fetch iterates every registered segment', () async {
      final hits = <String>{};
      final s = _setup((request) async {
        final segment = request.url.pathSegments.last;
        hits.add(segment);
        return http.Response(
          jsonEncode({
            'name': segment,
            'added': <String>[],
            'removed': <String>[],
            'since': -1,
            'till': -1,
          }),
          200,
        );
      });
      s.store.registerSegments(['seg_a', 'seg_b']);

      final result = await s.fetcher.fetch();

      expect(result, isTrue);
      expect(hits, containsAll(['seg_a', 'seg_b']));
      s.close();
    });

    test('fetchForSegment returns false on non-200', () async {
      final s = _setup((_) async => http.Response('boom', 500));
      s.store.registerSegments(['seg_a']);

      final result = await s.fetcher.fetchForSegment('seg_a');

      expect(result, isFalse);
      s.close();
    });

    test('fetch returns false when any segment fetch fails', () async {
      final s = _setup((request) async {
        if (request.url.toString().contains('seg_b')) {
          return http.Response('boom', 500);
        }
        return http.Response(
          jsonEncode({
            'name': 'seg_a',
            'added': <String>[],
            'removed': <String>[],
            'since': -1,
            'till': -1,
          }),
          200,
        );
      });
      s.store.registerSegments(['seg_a', 'seg_b']);

      final result = await s.fetcher.fetch();

      expect(result, isFalse);
      s.close();
    });

    test('sends correct URL with segment name and cursor', () async {
      Uri? seenUri;
      final s = _setup((request) async {
        seenUri = request.url;
        return http.Response(
          jsonEncode({
            'name': 'seg_a',
            'added': <String>[],
            'removed': <String>[],
            'since': 42,
            'till': 42,
          }),
          200,
        );
      });
      s.store.update('seg_a', const [], const [], 42);

      await s.fetcher.fetchForSegment('seg_a');

      expect(seenUri, isNotNull);
      expect(seenUri!.path, endsWith('/segmentChanges/seg_a'));
      expect(seenUri!.queryParameters['since'], '42');
      s.close();
    });

    test('fetchForSegment returns false on malformed payload', () async {
      final s = _setup((_) async => http.Response('{"bogus": true}', 200));
      s.store.registerSegments(['seg_a']);

      final result = await s.fetcher.fetchForSegment('seg_a');

      expect(result, isFalse);
      s.close();
    });

    test(
        'plain fetchForSegment() (polling/initial sync/catch-up) does NOT '
        'send Cache-Control: no-cache (spec §10.2)', () async {
      String? capturedCacheControl;
      final s = _setup((request) async {
        capturedCacheControl = request.headers['cache-control'];
        return http.Response(
          jsonEncode({
            'name': 'seg_a',
            'added': <String>[],
            'removed': <String>[],
            'since': -1,
            'till': -1,
          }),
          200,
        );
      });
      s.store.registerSegments(['seg_a']);

      await s.fetcher.fetchForSegment('seg_a');

      expect(capturedCacheControl, isNull);
      s.close();
    });

    test(
        'fetchForSegment(noCache: true) sends Cache-Control: no-cache — the '
        'shape every streaming-notification-triggered attempt and its '
        'CDN-bypass fetch MUST use (spec §10.2)', () async {
      String? capturedCacheControl;
      final s = _setup((request) async {
        capturedCacheControl = request.headers['cache-control'];
        return http.Response(
          jsonEncode({
            'name': 'seg_a',
            'added': <String>[],
            'removed': <String>[],
            'since': -1,
            'till': -1,
          }),
          200,
        );
      });
      s.store.registerSegments(['seg_a']);

      await s.fetcher.fetchForSegment('seg_a', noCache: true);

      expect(capturedCacheControl, equals('no-cache'));
      s.close();
    });

    test(
        'fetchForSegment(till: ...) appends till LAST, after since '
        '(canonical query order, spec §10.4)', () async {
      Uri? capturedUri;
      final s = _setup((request) async {
        capturedUri = request.url;
        return http.Response(
          jsonEncode({
            'name': 'seg_a',
            'added': <String>[],
            'removed': <String>[],
            'since': -1,
            'till': -1,
          }),
          200,
        );
      });
      s.store.registerSegments(['seg_a']);

      await s.fetcher.fetchForSegment('seg_a', noCache: true, till: 1001);

      expect(capturedUri, isNotNull);
      expect(capturedUri!.queryParameters.keys.toList(), ['since', 'till']);
      expect(capturedUri!.queryParameters['till'], '1001');
      s.close();
    });

    test(
        'fetchForSegment() with no optional args behaves exactly like the '
        'plain shape — no header, no till', () async {
      String? capturedCacheControl;
      Uri? capturedUri;
      final s = _setup((request) async {
        capturedCacheControl = request.headers['cache-control'];
        capturedUri = request.url;
        return http.Response(
          jsonEncode({
            'name': 'seg_a',
            'added': <String>[],
            'removed': <String>[],
            'since': -1,
            'till': -1,
          }),
          200,
        );
      });
      s.store.registerSegments(['seg_a']);

      await s.fetcher.fetchForSegment('seg_a');

      expect(capturedCacheControl, isNull);
      expect(capturedUri!.queryParameters.containsKey('till'), isFalse);
      s.close();
    });

    test('implements SegmentSyncTask', () {
      bool isSubtype<S, T>() => <S>[] is List<T>;
      expect(isSubtype<SegmentChangesFetcher, SegmentSyncTask>(), isTrue);
    });

    test(
        'fetch invokes onResult with true when there are no registered '
        'segments', () async {
      final results = <bool>[];
      final store = InMemorySegmentStore();
      final processor = SegmentChangeProcessor(store: store);
      final httpClient = SplitHttpClient(
        sdkVersion: 'dart_test-1.0.0',
        apiKey: 'test-key',
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      final fetcher = SegmentChangesFetcher(
        httpClient: httpClient,
        log: SplitLogger(level: LogLevel.none),
        baseUrl: 'https://sdk.split.io/api',
        processor: processor,
        store: store,
        onResult: results.add,
      );

      final result = await fetcher.fetch();

      expect(result, isTrue);
      expect(results, equals([true]));
      httpClient.close();
    });

    test('fetch invokes onResult with false when any segment fetch fails',
        () async {
      final results = <bool>[];
      final s = _setupWithResult((request) async {
        if (request.url.toString().contains('seg_b')) {
          return http.Response('boom', 500);
        }
        return http.Response(
          jsonEncode({
            'name': 'seg_a',
            'added': <String>[],
            'removed': <String>[],
            'since': -1,
            'till': -1,
          }),
          200,
        );
      }, results.add);
      s.store.registerSegments(['seg_a', 'seg_b']);

      final result = await s.fetcher.fetch();

      expect(result, isFalse);
      expect(results, equals([false]));
      s.close();
    });
    // whenUpdated() wiring (spec §4.6/§8.2, BUG #12): onUpdate MUST fire
    // exactly once when a fetchForSegment call adds/removes at least one
    // key, and MUST NOT fire on a wholly no-op fetch (cursor-only advance).
    test('onUpdate fires once when fetchForSegment adds a key', () async {
      final updates = <void>[];
      final s = _setupWithUpdate((_) async {
        return http.Response(
          jsonEncode({
            'name': 'seg_a',
            'added': ['k1'],
            'removed': <String>[],
            'since': -1,
            'till': 1,
          }),
          200,
        );
      }, () => updates.add(null));
      s.store.registerSegments(['seg_a']);

      final result = await s.fetcher.fetchForSegment('seg_a');

      expect(result, isTrue);
      expect(updates, hasLength(1));
      s.close();
    });

    test('onUpdate does NOT fire on a wholly no-op fetch', () async {
      final updates = <void>[];
      final s = _setupWithUpdate((_) async {
        return http.Response(
          jsonEncode({
            'name': 'seg_a',
            'added': <String>[],
            'removed': <String>[],
            'since': -1,
            'till': -1,
          }),
          200,
        );
      }, () => updates.add(null));
      s.store.registerSegments(['seg_a']);

      final result = await s.fetcher.fetchForSegment('seg_a');

      expect(result, isTrue);
      expect(updates, isEmpty);
      s.close();
    });

    test(
        'onUpdate fires exactly once even when the loop takes multiple '
        'round-trips to converge (a real diff followed by a confirming '
        'no-op call)', () async {
      final updates = <void>[];
      var call = 0;
      final s = _setupWithUpdate((_) async {
        call++;
        if (call == 1) {
          return http.Response(
            jsonEncode({
              'name': 'seg_a',
              'added': ['k1'],
              'removed': <String>[],
              'since': -1,
              'till': 50,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'name': 'seg_a',
            'added': <String>[],
            'removed': <String>[],
            'since': 50,
            'till': 50,
          }),
          200,
        );
      }, () => updates.add(null));
      s.store.registerSegments(['seg_a']);

      final result = await s.fetcher.fetchForSegment('seg_a');

      expect(result, isTrue);
      expect(call, 2);
      expect(updates, hasLength(1));
      s.close();
    });

    // In-flight dedupe (review finding on FlagsSegmentSync.onFlagsChanged):
    // SyncManager.initialSync()'s own `await segmentsTask.fetch()` and
    // FlagsSegmentSync's immediate, unawaited trigger both call this exact
    // same shared SegmentChangesFetcher instance's fetch() for the same
    // newly-registered segment. Without a guard, that is two concurrent
    // `GET /segmentChanges/{name}?since=-1` requests instead of one, and —
    // because InMemorySegmentStore.update() reports "changed" from the
    // response payload rather than from an actual set mutation — the second,
    // redundant application can re-fire onUpdate() for data already applied,
    // producing a spurious whenUpdated with no real backend change if it
    // resolves after the first one let readiness fire.
    group('fetch() in-flight dedupe', () {
      test(
          'two concurrent fetch() calls share the same in-flight request — '
          'only one HTTP call per registered segment, and both callers '
          'observe the same result', () async {
        final gate = Completer<void>();
        var callCount = 0;
        final results = <bool>[];
        final s = _setupWithResult((_) async {
          callCount++;
          await gate.future;
          return http.Response(
            jsonEncode({
              'name': 'seg_a',
              'added': ['k1'],
              'removed': <String>[],
              'since': -1,
              'till': -1,
            }),
            200,
          );
        }, results.add);
        s.store.registerSegments(['seg_a']);

        final first = s.fetcher.fetch();
        final second = s.fetcher.fetch();
        // Give both calls a turn to start before the HTTP response resolves.
        await Future<void>.delayed(Duration.zero);
        expect(callCount, 1,
            reason: 'The second fetch() MUST reuse the first\'s in-flight '
                'Future rather than issuing its own HTTP request');

        gate.complete();
        final firstResult = await first;
        final secondResult = await second;

        expect(firstResult, isTrue);
        expect(secondResult, isTrue);
        expect(results, equals([true]),
            reason: 'onResult MUST fire once — the two calls share one '
                'underlying fetch execution, not two');
        s.close();
      });

      test(
          'a fetch() call after the previous one has already completed '
          'starts a brand-new request (no permanent dedupe)', () async {
        var callCount = 0;
        final s = _setup((_) async {
          callCount++;
          return http.Response(
            jsonEncode({
              'name': 'seg_a',
              'added': <String>[],
              'removed': <String>[],
              'since': -1,
              'till': -1,
            }),
            200,
          );
        });
        s.store.registerSegments(['seg_a']);

        await s.fetcher.fetch();
        await s.fetcher.fetch();

        expect(callCount, 2,
            reason: 'Only genuinely CONCURRENT fetch() calls dedupe — a '
                'later poll tick after the previous fetch finished MUST '
                'still refresh the segment');
        s.close();
      });

      // Regression guard: a fetch() call with zero registered segments
      // resolves synchronously (no `await` on that path). An earlier,
      // broken version of the dedupe guard set `_inFlightFetch` from the
      // CALLER after invoking the fetch body, which — for a synchronously
      // resolving body — ran its cleanup (nulling the field) before that
      // very assignment, permanently stuck non-null. Every later fetch()
      // call then silently reused that stale, already-resolved Future
      // instead of doing real work.
      test(
          'a fetch() with zero registered segments does not permanently '
          'wedge later fetch() calls that register real segments', () async {
        var callCount = 0;
        final s = _setup((_) async {
          callCount++;
          return http.Response(
            jsonEncode({
              'name': 'seg_a',
              'added': ['k1'],
              'removed': <String>[],
              'since': -1,
              'till': -1,
            }),
            200,
          );
        });

        // Zero segments registered — resolves synchronously.
        final first = await s.fetcher.fetch();
        expect(first, isTrue);

        // Now a segment gets registered (e.g. by a flags change) and a
        // later fetch() call MUST actually fetch it, not silently reuse
        // the empty-segments fetch's stale, already-completed Future.
        s.store.registerSegments(['seg_a']);
        final second = await s.fetcher.fetch();

        expect(second, isTrue);
        expect(callCount, 1,
            reason: 'The real HTTP call for seg_a MUST have happened — a '
                'wedged dedupe guard would skip it entirely, leaving '
                'seg_a unfetched with callCount still 0');
        expect(s.store.isInSegment('seg_a', 'k1'), isTrue);
        s.close();
      });

      // Regression guard: a segment registered WHILE a different fetch is
      // genuinely in flight (not yet resolved) must still get fetched
      // promptly — not left waiting for the next poll tick — because the
      // in-flight call's snapshot was taken before the new segment existed.
      test(
          'a segment registered while an unrelated fetch() is still in '
          'flight is fetched by a chained follow-up call, not dropped',
          () async {
        final gate = Completer<void>();
        var callCountSegA = 0;
        var callCountSegB = 0;
        final s = _setupWithResult((request) async {
          final name = request.url.pathSegments.last;
          if (name == 'seg_a') {
            callCountSegA++;
            await gate.future;
            return http.Response(
              jsonEncode({
                'name': 'seg_a',
                'added': <String>[],
                'removed': <String>[],
                'since': -1,
                'till': -1,
              }),
              200,
            );
          }
          callCountSegB++;
          return http.Response(
            jsonEncode({
              'name': 'seg_b',
              'added': ['k2'],
              'removed': <String>[],
              'since': -1,
              'till': -1,
            }),
            200,
          );
        }, (_) {});
        s.store.registerSegments(['seg_a']);

        // Starts a genuinely in-flight fetch for {seg_a} — gated, so it
        // won't resolve until `gate.complete()` below.
        final firstFetch = s.fetcher.fetch();
        await Future<void>.delayed(Duration.zero);
        expect(callCountSegA, 1);

        // A new segment is registered mid-flight (as FlagsSegmentSync
        // would do on a flags change) and an immediate fetch is triggered.
        s.store.registerSegments(['seg_b']);
        final secondFetch = s.fetcher.fetch();

        gate.complete();
        await firstFetch;
        await secondFetch;

        expect(callCountSegB, 1,
            reason: 'seg_b was registered after seg_a\'s fetch snapshot '
                'was taken — it MUST still be fetched via a chained '
                'follow-up call once that fetch completes, not silently '
                'dropped');
        expect(s.store.isInSegment('seg_b', 'k2'), isTrue);
        s.close();
      });
    });
  });
}

_TestSetup _setupWithUpdate(_Handler handler, void Function() onUpdate) {
  final store = InMemorySegmentStore();
  final processor = SegmentChangeProcessor(store: store);
  final httpClient = SplitHttpClient(
    sdkVersion: 'dart_test-1.0.0',
    apiKey: 'test-key',
    client: MockClient(handler),
  );
  final fetcher = SegmentChangesFetcher(
    httpClient: httpClient,
    log: SplitLogger(level: LogLevel.none),
    baseUrl: 'https://sdk.split.io/api',
    processor: processor,
    store: store,
    maxRetries: 1,
    onUpdate: onUpdate,
  );
  return _TestSetup(store, httpClient, fetcher);
}

_TestSetup _setupWithResult(_Handler handler, void Function(bool) onResult) {
  final store = InMemorySegmentStore();
  final processor = SegmentChangeProcessor(store: store);
  final httpClient = SplitHttpClient(
    sdkVersion: 'dart_test-1.0.0',
    apiKey: 'test-key',
    client: MockClient(handler),
  );
  final fetcher = SegmentChangesFetcher(
    httpClient: httpClient,
    log: SplitLogger(level: LogLevel.none),
    baseUrl: 'https://sdk.split.io/api',
    processor: processor,
    store: store,
    maxRetries: 1,
    onResult: onResult,
  );
  return _TestSetup(store, httpClient, fetcher);
}
