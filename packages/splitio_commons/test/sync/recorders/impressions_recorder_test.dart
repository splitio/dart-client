import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/sync/sync.dart';
import 'package:test/test.dart';

KeyImpression _impression(String feature, {int time = 1000, int? pt}) =>
    KeyImpression(
      feature: feature,
      keyName: 'user1',
      bucketingKey: null,
      treatment: 'on',
      label: 'default rule',
      changeNumber: 42,
      time: time,
      pt: pt,
    );

void main() {
  group('ImpressionsRecorder', () {
    late InMemoryImpressionsStore store;
    late List<http.Request> capturedRequests;

    setUp(() {
      store = InMemoryImpressionsStore();
      capturedRequests = [];
    });

    ImpressionsRecorder makeRecorder({
      ImpressionsMode mode = ImpressionsMode.optimized,
      int pushRateSeconds = 300,
      http.Client? mockClient,
    }) {
      final client = SplitHttpClient(
        apiKey: 'test-api-key',
        client: mockClient ??
            MockClient((req) async {
              capturedRequests.add(req);
              return http.Response('', 200);
            }),
      );
      return ImpressionsRecorder(
        store: store,
        httpClient: client,
        url: 'https://events.split.io/api',
        mode: mode,
        pushRateSeconds: pushRateSeconds,
        log: SplitLogger(level: LogLevel.none),
      );
    }

    test('flush does nothing when store is empty', () async {
      final recorder = makeRecorder();

      await recorder.flush();

      expect(capturedRequests, isEmpty);
    });

    test('flush posts impressions grouped by feature', () async {
      store.push(_impression('feat_a', time: 1000));
      store.push(_impression('feat_b', time: 2000));
      store.push(_impression('feat_a', time: 3000, pt: 1000));

      final recorder = makeRecorder();
      await recorder.flush();

      expect(capturedRequests, hasLength(1));
      final req = capturedRequests.first;
      expect(req.url.toString(),
          'https://events.split.io/api/testImpressions/bulk');

      final body = jsonDecode(req.body) as List;
      expect(body, hasLength(2));

      final featA = body.firstWhere((e) => e['f'] == 'feat_a');
      expect(featA['i'], hasLength(2));
      expect(featA['i'][0]['k'], 'user1');
      expect(featA['i'][0]['t'], 'on');
      expect(featA['i'][0]['m'], 1000);
      expect(featA['i'][0]['c'], 42);
      expect(featA['i'][0]['r'], 'default rule');
      expect(featA['i'][1]['pt'], 1000);

      final featB = body.firstWhere((e) => e['f'] == 'feat_b');
      expect(featB['i'], hasLength(1));
    });

    test('flush sends SplitSDKImpressionsMode header', () async {
      store.push(_impression('feat'));

      final recorder = makeRecorder(mode: ImpressionsMode.debug);
      await recorder.flush();

      expect(
          capturedRequests.first.headers['SplitSDKImpressionsMode'], 'DEBUG');
    });

    test('flush sends OPTIMIZED mode header', () async {
      store.push(_impression('feat'));

      final recorder = makeRecorder(mode: ImpressionsMode.optimized);
      await recorder.flush();

      expect(capturedRequests.first.headers['SplitSDKImpressionsMode'],
          'OPTIMIZED');
    });

    test('flush batches into groups of 500', () async {
      for (var i = 0; i < 1200; i++) {
        store.push(_impression('feat', time: i));
      }

      final recorder = makeRecorder();
      await recorder.flush();

      expect(capturedRequests, hasLength(3));
    });

    test('flush clears the store', () async {
      store.push(_impression('feat'));

      final recorder = makeRecorder();
      await recorder.flush();

      expect(store.isEmpty, isTrue);
    });

    test('flush handles HTTP errors gracefully', () async {
      store.push(_impression('feat'));

      final recorder = makeRecorder(
        mockClient: MockClient((req) async {
          throw Exception('network error');
        }),
      );

      await recorder.flush();
      expect(store.isEmpty, isTrue);
    });

    test('start creates periodic timer', () async {
      final recorder = makeRecorder(pushRateSeconds: 1);
      recorder.start();

      store.push(_impression('feat'));

      await Future.delayed(Duration(milliseconds: 1100));
      expect(capturedRequests, hasLength(1));

      recorder.stop();
    });

    test('stop cancels periodic timer', () async {
      final recorder = makeRecorder(pushRateSeconds: 1);
      recorder.start();
      recorder.stop();

      store.push(_impression('feat'));

      await Future.delayed(Duration(milliseconds: 1100));
      expect(capturedRequests, isEmpty);
    });

    test('does not include null bucketingKey or pt in payload', () async {
      store.push(_impression('feat'));

      final recorder = makeRecorder();
      await recorder.flush();

      final body = jsonDecode(capturedRequests.first.body) as List;
      final imp = (body.first['i'] as List).first as Map<String, dynamic>;
      expect(imp.containsKey('b'), isFalse);
      expect(imp.containsKey('pt'), isFalse);
    });

    test('includes bucketingKey when present', () async {
      store.push(KeyImpression(
        feature: 'feat',
        keyName: 'user1',
        bucketingKey: 'bucket1',
        treatment: 'on',
        label: 'rule',
        changeNumber: 1,
        time: 1000,
      ));

      final recorder = makeRecorder();
      await recorder.flush();

      final body = jsonDecode(capturedRequests.first.body) as List;
      final imp = (body.first['i'] as List).first as Map<String, dynamic>;
      expect(imp['b'], 'bucket1');
    });
  });
}
