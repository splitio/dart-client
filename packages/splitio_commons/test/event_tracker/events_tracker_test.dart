import 'package:splitio_commons/src/event_tracker/event_tracker.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:test/test.dart';

Event _event() => const Event(
      eventTypeId: 'purchase',
      trafficTypeName: 'user',
      key: 'user_a',
      timestamp: 1,
    );

void main() {
  group('EventsTracker', () {
    late InMemoryEventsStore store;
    late SplitLogger log;
    ConsentStatus consent = ConsentStatus.granted;

    setUp(() {
      store = InMemoryEventsStore();
      log = SplitLogger(level: LogLevel.none);
      consent = ConsentStatus.granted;
    });

    EventsTracker build() => EventsTracker(
          store: store,
          consentProvider: () => consent,
          log: log,
        );

    test('queues event when consent granted', () {
      expect(build().track(_event(), 1024), isTrue);
      expect(store.count, 1);
    });

    test('does not queue when consent declined', () {
      consent = ConsentStatus.declined;
      expect(build().track(_event(), 1024), isFalse);
      expect(store.count, 0);
    });
  });
}
