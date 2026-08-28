import 'package:splitio_commons/src/sync/streaming/event_source_client.dart';
import 'package:splitio_commons/src/sync/streaming/notification_processor.dart';
import 'package:splitio_commons/src/sync/streaming/streaming_event.dart';
import 'package:test/test.dart';

RawNotification dataNotification(Map<String, dynamic> data) =>
    RawNotification(event: 'message', channel: 'xxxx_splits', data: data);

void main() {
  final processor = NotificationProcessor();

  group('data notifications', () {
    for (final type in const [
      'SPLIT_UPDATE',
      'SPLIT_KILL',
      'MEMBERSHIPS_MS_UPDATE',
      'MEMBERSHIPS_LS_UPDATE',
      'RB_SEGMENT_UPDATE',
    ]) {
      test('$type → FeedUpdate with type + payload passthrough', () {
        final payload = {
          'type': type,
          'changeNumber': 42,
          'pcn': 41,
          'c': 1,
          'd': 'abc',
        };
        final result = processor.process(dataNotification(payload));

        expect(result.fsmEvent, isNull);
        expect(result.feedUpdates, hasLength(1));
        expect(result.feedUpdates.single.type, type);
        expect(result.feedUpdates.single.payload, same(payload));
      });
    }

    test('SPLIT_UPDATE with incidental code field → FeedUpdate, NOT error', () {
      final payload = {
        'type': 'SPLIT_UPDATE',
        'changeNumber': 42,
        'code': 12345
      };
      final result = processor.process(dataNotification(payload));

      expect(result.fsmEvent, isNull);
      expect(result.feedUpdates, hasLength(1));
      expect(result.feedUpdates.single.type, 'SPLIT_UPDATE');
      expect(result.feedUpdates.single.payload, same(payload));
    });

    test('MEMBERSHIPS_MS_UPDATE with incidental code → FeedUpdate, NOT error',
        () {
      final payload = {
        'type': 'MEMBERSHIPS_MS_UPDATE',
        'changeNumber': 7,
        'code': 12345,
      };
      final result = processor.process(dataNotification(payload));

      expect(result.fsmEvent, isNull);
      expect(result.feedUpdates, hasLength(1));
      expect(result.feedUpdates.single.type, 'MEMBERSHIPS_MS_UPDATE');
    });

    test('EVALUATION_UPDATE (remote reserved) → ignored', () {
      final result = processor.process(
        dataNotification({'type': 'EVALUATION_UPDATE', 'changeNumber': 1}),
      );
      expect(result.isEmpty, isTrue);
    });

    test('unknown data type → ignored', () {
      final result = processor.process(
        dataNotification({'type': 'SOMETHING_NEW', 'changeNumber': 1}),
      );
      expect(result.isEmpty, isTrue);
    });
  });

  group('control notifications', () {
    NotificationResult control(String controlType, {Object? ts}) =>
        processor.process(
          dataNotification({
            'type': 'CONTROL',
            'controlType': controlType,
            if (ts != null) 'timestamp': ts,
          }),
        );

    test('STREAMING_PAUSED → ControlPaused with timestamp', () {
      final result = control('STREAMING_PAUSED', ts: 123);
      expect(result.feedUpdates, isEmpty);
      expect(result.fsmEvent, const ControlPaused(123));
    });

    test('STREAMING_RESUMED → ControlResumed with timestamp', () {
      expect(control('STREAMING_RESUMED', ts: 456).fsmEvent,
          const ControlResumed(456));
    });

    test('STREAMING_DISABLED → ControlDisabled with timestamp', () {
      expect(control('STREAMING_DISABLED', ts: 789).fsmEvent,
          const ControlDisabled(789));
    });

    test('STREAMING_RESET → ControlReset with timestamp', () {
      expect(control('STREAMING_RESET', ts: 5).fsmEvent, const ControlReset(5));
    });

    test('missing timestamp defaults to 0', () {
      expect(control('STREAMING_PAUSED').fsmEvent, const ControlPaused(0));
    });

    test('unknown controlType → ignored', () {
      expect(control('STREAMING_WAT', ts: 1).isEmpty, isTrue);
    });
  });

  group('occupancy notifications', () {
    NotificationResult occupancy(Object? publishers) => processor.process(
          RawNotification(
            event: 'message',
            channel: '[?occupancy=metrics.publishers]control_pri',
            data: {
              'type': 'OCCUPANCY',
              'metrics': {'publishers': publishers},
            },
          ),
        );

    test('publishers == 0 → OccupancyChanged(isZero: true)', () {
      expect(occupancy(0).fsmEvent, const OccupancyChanged(isZero: true));
    });

    test('publishers > 0 → OccupancyChanged(isZero: false)', () {
      expect(occupancy(2).fsmEvent, const OccupancyChanged(isZero: false));
    });

    test('missing metrics → ignored', () {
      final result = processor.process(RawNotification(
        event: 'message',
        channel: '[meta]occupancy',
        data: {'type': 'OCCUPANCY'},
      ));
      expect(result.isEmpty, isTrue);
    });
  });

  group('error notifications', () {
    NotificationResult error(Object? code, {String event = 'error'}) =>
        processor.process(RawNotification(event: event, data: {'code': code}));

    test('code 401 → isTokenError: true', () {
      expect(error(401).fsmEvent, const ErrorFrame(isTokenError: true));
    });

    test('code 40140 (lower bound) → isTokenError: true', () {
      expect(error(40140).fsmEvent, const ErrorFrame(isTokenError: true));
    });

    test('code 40149 (upper bound) → isTokenError: true', () {
      expect(error(40149).fsmEvent, const ErrorFrame(isTokenError: true));
    });

    test('code 40139 (just below range) → isTokenError: false', () {
      expect(error(40139).fsmEvent, const ErrorFrame(isTokenError: false));
    });

    test('code 40150 (just above range) → isTokenError: false', () {
      expect(error(40150).fsmEvent, const ErrorFrame(isTokenError: false));
    });

    test('generic code 500 → ErrorFrame(isTokenError: false)', () {
      expect(error(500).fsmEvent, const ErrorFrame(isTokenError: false));
    });

    test('inner error code on a message frame → ErrorFrame', () {
      expect(error(401, event: 'message').fsmEvent,
          const ErrorFrame(isTokenError: true));
    });

    test('malformed error (non-int code) → ignored', () {
      expect(error('nope').isEmpty, isTrue);
    });

    test('error event with no data → ignored', () {
      final result = processor.process(const RawNotification(event: 'error'));
      expect(result.isEmpty, isTrue);
    });
  });

  group('malformed notifications', () {
    test('null data map → ignored', () {
      expect(processor.process(const RawNotification(event: 'message')).isEmpty,
          isTrue);
    });

    test('empty data map → ignored', () {
      expect(processor.process(dataNotification({})).isEmpty, isTrue);
    });

    test('non-string type → ignored', () {
      expect(processor.process(dataNotification({'type': 42})).isEmpty, isTrue);
    });
  });
}
