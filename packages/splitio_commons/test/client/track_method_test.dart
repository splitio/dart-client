import 'dart:async';

import 'package:splitio_commons/src/client/client_state.dart';
import 'package:splitio_commons/src/client/track_method.dart';
import 'package:splitio_commons/src/event_tracker/events_store.dart';
import 'package:splitio_commons/src/event_tracker/events_tracker.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/rule_store.dart';
import 'package:splitio_commons/src/storage/store.dart';
import 'package:test/test.dart';

class _FakeState implements ClientState {
  @override
  bool isClientDestroyed = false;
  @override
  bool isEventsDestroyed = false;
  @override
  bool isReady = true;
}

ParsedSplit _split(String trafficType) => ParsedSplit(
      name: 'flag',
      trafficTypeName: trafficType,
      killed: false,
      defaultTreatment: 'off',
      conditions: const [],
      trafficAllocation: 100,
      seed: 1,
      algo: 2,
      changeNumber: 1,
    );

void main() {
  late _FakeState state;
  late InMemoryEventsStore store;
  late InMemoryRuleStore ruleStore;
  late ConsentStatus consent;
  late TrackMethod subject;
  late List<String> logs;

  const key = Key(matchingKey: 'user');

  setUp(() {
    state = _FakeState();
    store = InMemoryEventsStore();
    ruleStore = InMemoryRuleStore()
      ..applyChange(Change(changeNumber: 1, updates: {'flag': _split('user')}));
    consent = ConsentStatus.granted;
    logs = [];
    final logger = SplitLogger(level: LogLevel.verbose);
    subject = TrackMethod(
        eventsTracker: EventsTracker(
            store: store, consentProvider: () => consent, log: logger),
        ruleStore: ruleStore,
        logger: logger);
  });

  bool run(Key k, String eventType, String trafficType,
      {double? value, Map<String, Object?>? properties}) {
    late bool r;
    runZoned(
        () => r = subject.track(k, eventType, trafficType, state,
            value: value, properties: properties),
        zoneSpecification:
            ZoneSpecification(print: (_, __, ___, line) => logs.add(line)));
    return r;
  }

  test('happy path queues the event and returns true', () {
    final ok = run(key, 'purchase', 'user',
        value: 9.5, properties: {'a': 1, 'b': 'x'});
    expect(ok, isTrue);
    final event = store.popAll().single;
    expect(event.eventTypeId, 'purchase');
    expect(event.trafficTypeName, 'user');
    expect(event.key, 'user');
    expect(event.value, 9.5);
    expect(event.properties, {'a': 1, 'b': 'x'});
    expect(logs.where((l) => l.contains('[WARNING]')), isEmpty);
  });

  test('client destroyed: false and ERROR without trailing period', () {
    state.isClientDestroyed = true;
    expect(run(key, 'purchase', 'user'), isFalse);
    expect(store.isEmpty, isTrue);
    expect(logs.single,
        '[Split][ERROR] track: Client has already been destroyed - no calls possible');
  });

  test('events manager destroyed: false and ERROR from the second guard', () {
    state.isEventsDestroyed = true;
    expect(run(key, 'purchase', 'user'), isFalse);
    expect(store.isEmpty, isTrue);
    expect(logs.single, startsWith('[Split][ERROR] track:'));
    expect(logs.single, endsWith('no calls possible.'));
  });

  test('invalid key: false and ERROR', () {
    expect(run(const Key(matchingKey: ''), 'purchase', 'user'), isFalse);
    expect(store.isEmpty, isTrue);
    expect(logs.single, startsWith('[Split][ERROR] track:'));
  });

  test('invalid event type: false and ERROR', () {
    expect(run(key, 'bad type!', 'user'), isFalse);
    expect(store.isEmpty, isTrue);
    expect(logs.single, '[Split][ERROR] track: invalid event type "bad type!"');
  });

  test('invalid traffic type: false and ERROR', () {
    expect(run(key, 'purchase', ''), isFalse);
    expect(store.isEmpty, isTrue);
    expect(logs.single, '[Split][ERROR] track: invalid traffic type ""');
  });

  test('invalid value: false and ERROR', () {
    expect(run(key, 'purchase', 'user', value: double.nan), isFalse);
    expect(store.isEmpty, isTrue);
    expect(logs.single,
        '[Split][ERROR] track: value must be a finite number for event "purchase"');
  });

  test('uppercase traffic type: WARNING and tracked lowercased', () {
    expect(run(key, 'purchase', 'USER'), isTrue);
    expect(store.popAll().single.trafficTypeName, 'user');
    expect(
        logs,
        contains('[Split][WARNING] track: trafficType "USER" should be '
            'lowercase — normalized to "user"'));
  });

  test('unknown traffic type when READY: WARNING and still tracked', () {
    expect(run(key, 'purchase', 'account'), isTrue);
    expect(store.count, 1);
    expect(
        logs,
        contains('[Split][WARNING] track: trafficType "account" is not '
            'associated with any flag'));
  });

  test('unknown traffic type when not READY: no WARNING, still tracked', () {
    state.isReady = false;
    expect(run(key, 'purchase', 'account'), isTrue);
    expect(store.count, 1);
    expect(logs.where((l) => l.contains('not associated')), isEmpty);
  });

  test('properties over 32 KB: false and ERROR', () {
    expect(
        run(key, 'purchase', 'user', properties: {'k': 'x' * 40000}), isFalse);
    expect(store.isEmpty, isTrue);
    expect(
        logs.single,
        '[Split][ERROR] track: the maximum size allowed for the properties '
        'is 32768 bytes, which was exceeded.');
  });

  test('invalid property type: WARNING, value nulled, still tracked', () {
    expect(
        run(key, 'purchase', 'user', properties: {
          'a': [1],
          'b': 2
        }),
        isTrue);
    expect(store.popAll().single.properties, {'a': null, 'b': 2});
    expect(logs.where((l) => l.contains('[WARNING]')).single,
        startsWith('[Split][WARNING] track: Property "a"'));
  });

  test('more than 300 properties: WARNING and still tracked', () {
    final props = {for (var i = 0; i < 301; i++) 'p$i': i};
    expect(run(key, 'purchase', 'user', properties: props), isTrue);
    expect(store.popAll().single.properties, hasLength(301));
    expect(logs.where((l) => l.contains('[WARNING]')).single,
        contains('more than 300 properties'));
  });

  test('declined consent: returns false without queueing', () {
    consent = ConsentStatus.declined;
    expect(run(key, 'purchase', 'user'), isFalse);
    expect(store.isEmpty, isTrue);
  });

  test('the trimmed matching key is used in the Event', () {
    expect(
        run(const Key(matchingKey: '  user  ', bucketingKey: 'b'), 'purchase',
            'user'),
        isTrue);
    expect(store.popAll().single.key, 'user');
  });
}
