import 'dart:async';

import 'package:splitio_client_side/src/client/split_client.dart';
import 'package:splitio_commons/src/core/factory_tracker.dart';
import 'package:splitio_commons/src/events/events_manager.dart';
import 'package:splitio_commons/src/input_validation/flag_names.dart';
import 'package:splitio_commons/src/input_validation/key.dart';
import 'package:splitio_commons/src/input_validation/sdk_key.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/config.dart';
import 'package:splitio_commons/src/models/evaluation_options.dart';
import 'package:splitio_commons/src/models/evaluation_result.dart';
import 'package:splitio_commons/src/models/key.dart';
import 'package:splitio_commons/src/models/split_view.dart';
import 'package:splitio_client_side/src/internal/client_readiness.dart';
import 'package:splitio_client_side/src/internal/dependency_container.dart';

import 'package:splitio_commons/src/client/split_manager.dart';
import 'package:splitio_commons/src/client/user_consent.dart';

abstract class SplitFactory {
  static SplitFactory create(
      String sdkKey, SplitClientConfig config, Object key) {
    final log = SplitLogger(level: config.logLevel);
    final sdkKeyResult = validateSdkKey(sdkKey, 'SplitFactory.create');
    if (!sdkKeyResult.isValid) {
      log.error(sdkKeyResult.error!);
      return _NoOpSplitFactory(config);
    }
    Key? normalized;
    if (key is Key) {
      normalized = key;
    } else if (key is String) {
      normalized = Key(matchingKey: key);
    } else {
      // Invalid type — neither String nor Key. Degrade to NoOp per spec §7.
      log.error('SplitFactory.create: key must be a String or Key, got '
          '${key.runtimeType}');
      return _NoOpSplitFactory(config);
    }
    final keyResult = validateKey(normalized, 'SplitFactory');
    if (!keyResult.isValid) {
      log.error(keyResult.error!);
      return _NoOpSplitFactory(config);
    }
    // Use the trimmed key (spec §16) — it becomes the bootstrap key for
    // memberships, the per-key client cache, evaluation and recording.
    return _SplitFactoryImpl(sdkKey, config, keyResult.value!);
  }

  SplitClient client([Object? key]);
  SplitManager manager();
  UserConsentManager userConsent();
  Future<void> destroy();
}

class _SplitFactoryImpl implements SplitFactory {
  // late final: assigned in the constructor body, after _readiness, which
  // the container wires into its fetchers.
  late final DependencyContainer _di;
  late final ClientReadiness _readiness;
  final Key _key;
  final String _sdkKey;
  final SplitClientConfig _config;
  // Lazily created on the first invalid key and shared by every later one,
  // so repeated invalid-key calls never accumulate instances or timers.
  _NoOpSplitFactory? _noOp;
  bool _factoryDestroyed = false;
  Future<void>? _destroyFuture;

  // Keys whose memberships have already been fetched (or are in flight). The
  // bootstrap key is synced by initialSync(); any other key gets an on-demand
  // fetch the first time a client is created for it.
  final Set<String> _membershipKeys = {};

  // Cache of issued clients keyed by instance ID (matching + bucketing key).
  // Subsequent factory.client(sameKey) calls return the same cached instance,
  // including when that instance has already been destroyed (spec §8.5).
  final Map<String, SplitClientImpl> _clients = {};

  _SplitFactoryImpl(this._sdkKey, this._config, this._key) {
    final config = _config;
    // The readyTimeout window starts here, at factory creation (spec §8.2).
    _readiness = ClientReadiness(
      log: SplitLogger(level: config.logLevel),
      readyTimeoutSeconds:
          config.sync.normalized(serverSide: false).readyTimeout,
    );
    _di = DependencyContainer.build(_sdkKey, config,
        bootstrapKey: _key.matchingKey,
        readiness: _readiness,
        isDestroyed: () => _factoryDestroyed);
    FactoryTracker.track(_sdkKey, _di.log);
    _membershipKeys.add(_key.matchingKey);
    _clients[_instanceId(_key)] = _createClient(_key);
    _startBackground();
  }

  static String _instanceId(Key key) =>
      '${key.matchingKey}#${key.bucketingKey ?? key.matchingKey}';

  void _ensureMembershipsFor(String matchingKey) {
    if (!_membershipKeys.add(matchingKey)) return;
    Future(() async {
      try {
        final ok = await _di.pollingManager.syncMembershipsFor(matchingKey);
        if (_factoryDestroyed) return;
        if (!ok) {
          _di.log.warning('On-demand memberships fetch failed for key: '
              '"$matchingKey"');
          _membershipKeys.remove(matchingKey);
        }
      } catch (e, s) {
        _di.log.error(
            'On-demand memberships fetch failed for key: '
                '"$matchingKey"',
            '$e\n$s');
        _membershipKeys.remove(matchingKey);
      }
    });
  }

  // Fire-and-forget startup. Errors are logged, never escape the SDK, and a
  // destroy() that lands mid-startup stops it before anything is restarted.
  void _startBackground() {
    Future(() async {
      try {
        _di.log.debug('loadLocal started');
        await _di.ruleStore.loadLocal();
        await _di.rbsStore.loadLocal();
        _di.log.debug('loadLocal done');

        _di.log.info('Starting initial sync');
        _di.log.debug('Initial sync key: "${_key.matchingKey}"');
        final ok = await _di.syncManager.initialSync();
        if (_factoryDestroyed) return;
        if (!ok) {
          _di.log.warning('Initial sync failed — SDK not ready');
        }
        // Start syncing AFTER the initial fetch (spec §8.1). startStreaming()
        // starts streaming when a StreamingManager was injected
        // (streamingEnabled) and otherwise falls back to polling — see
        // SyncManager.startStreaming(). It is deliberately fire-and-forget
        // (unawaited): readiness was already notified above (§8.2), so a slow
        // auth/connect MUST NOT delay anything, and streaming failures fall
        // back to polling via SyncManager wiring. We do NOT gate this on `ok`:
        // even when the initial sync failed, we still start streaming/polling
        // so the SDK keeps retrying to sync (streaming's catch-up fetch or
        // polling will recover).
        unawaited(_di.syncManager
            .startStreaming()
            .catchError((Object e, StackTrace s) {
          _di.log.warning('startStreaming failed: $e');
        }));
        _di.syncManager.startRecorders();
      } catch (e, s) {
        _di.log.error('Background startup failed', '$e\n$s');
      }
    });
  }

  @override
  SplitClient client([Object? key]) {
    final effectiveKey = key == null ? _key : _resolveKey(key);
    if (effectiveKey == null) return _noOpClient();
    final id = _instanceId(effectiveKey);
    final cached = _clients[id];
    if (cached != null) return cached;
    _ensureMembershipsFor(effectiveKey.matchingKey);
    final created = _createClient(effectiveKey);
    _clients[id] = created;
    return created;
  }

  // Validates a non-null key passed to client() (spec §7, §16): returns the
  // trimmed Key, or null after logging an ERROR when it is invalid. A num is
  // converted with toString() and logs a WARNING.
  Key? _resolveKey(Object key) {
    final Key candidate;
    if (key is Key) {
      candidate = key;
    } else if (key is String) {
      candidate = Key(matchingKey: key);
    } else if (key is num) {
      _di.log.warning('SplitFactory.client: key must be a String or Key, got '
          '${key.runtimeType}; converting it with toString().');
      candidate = Key(matchingKey: key.toString());
    } else {
      _di.log.error('SplitFactory.client: key must be a String or Key, got '
          '${key.runtimeType}.');
      return null;
    }
    final result = validateKey(candidate, 'SplitFactory.client');
    if (!result.isValid) {
      _di.log.error(result.error!);
      return null;
    }
    return result.value;
  }

  // The shared NoOp client for invalid keys: control for evaluations, never
  // fetches memberships, whenReady() never completes, whenTimeout() fires
  // after readyTimeout. Its timer is cancelled on its destroy() or the
  // factory's; like real clients it stays cached once destroyed (spec §8.5).
  // One first requested after the factory's destroy() is destroyed at once,
  // so it never arms a timer that teardown would not cancel.
  SplitClient _noOpClient() {
    final noOp = _noOp ??= _NoOpSplitFactory(_config);
    if (_factoryDestroyed) unawaited(noOp.destroy());
    return noOp.client();
  }

  // Each client owns its EventsManager so readiness and UPDATE are tracked
  // per client (spec §8.2); ClientReadiness drives them.
  SplitClientImpl _createClient(Key key) {
    final events = EventsManager();
    _readiness.register(key.matchingKey, events);
    return SplitClientImpl(
      key: key,
      evaluator: _di.evaluator,
      impressions: _di.impressions,
      eventsManager: events,
      onDestroyed: () => _readiness.unregister(events),
      eventsTracker: _di.eventsTracker,
      ruleStore: _di.ruleStore,
      logger: _di.log,
      flushRecorders: _di.syncManager.flushRecorders,
    );
  }

  @override
  SplitManager manager() => _di.manager;

  @override
  UserConsentManager userConsent() => _di.userConsent;

  // Teardown runs at most once; every caller gets the same Future, so a
  // concurrent destroy() resolves only after the final flush completes.
  @override
  Future<void> destroy() => _destroyFuture ??= _teardown();

  Future<void> _teardown() async {
    _factoryDestroyed = true;
    FactoryTracker.release(_sdkKey);
    unawaited(_noOp?.destroy());

    // Step 1: Mark every issued client destroyed synchronously — the `_destroyed`
    // flag in SplitClientImpl.destroy() is set before its first await, so
    // building the futures list here already blocks any in-flight evaluation
    // or track() from slipping through (spec §8.5). Their pending flushes
    // are awaited below, before we close the http client.
    final clientDestroys =
        _clients.values.map((c) => c.destroy()).toList(growable: false);

    // Step 2: Stop sync manager (cancels poll timers, stops streaming).
    await _di.syncManager.stop();

    // Step 3: Stop recorder timers (no flush yet).
    await _di.syncManager.stopRecorders();

    // Step 4: Wait for client-initiated flushes and run one final factory
    // flush. All in-flight POSTs MUST complete before dispose() closes the
    // http client, otherwise the POSTs get their connection killed mid-flight.
    await Future.wait([
      ...clientDestroys,
      _di.syncManager.flushRecorders(),
    ]);

    // Step 5: Dispose resources (cancels pending ready-timeout timers and
    // disposes every client's EventsManager).
    await _readiness.dispose();
    await _di.dispose();
  }
}

class _NoOpSplitFactory implements SplitFactory {
  final EventsManager _eventsManager = EventsManager();
  late final SplitClient _client;
  Timer? _readyTimeoutTimer;

  // readyTimeout starts at factory creation (spec §8.2), same as the real
  // factory. whenReady() never completes for a NoOp factory, so this timer
  // is the only way whenTimeout() ever fires — it MUST be cancelled by
  // destroy() so a destroyed NoOp factory never emits TIMEOUT either.
  _NoOpSplitFactory(SplitClientConfig config) {
    _client = _NoOpSplitClient(_eventsManager,
        onDestroy: () => _readyTimeoutTimer?.cancel());
    final readyTimeout = config.sync.normalized(serverSide: false).readyTimeout;
    if (readyTimeout > 0) {
      _readyTimeoutTimer =
          Timer(Duration(seconds: readyTimeout), _eventsManager.notifyTimeout);
    }
  }

  @override
  SplitClient client([Object? key]) => _client;

  @override
  SplitManager manager() => _NoOpSplitManager();

  @override
  UserConsentManager userConsent() => UserConsentManager();

  @override
  Future<void> destroy() async {
    _readyTimeoutTimer?.cancel();
  }
}

class _NoOpSplitClient implements SplitClient {
  final EventsManager _eventsManager;
  final void Function()? _onDestroy;

  _NoOpSplitClient(this._eventsManager, {void Function()? onDestroy})
      : _onDestroy = onDestroy;

  @override
  String getTreatment(String flag,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      'control';

  @override
  Map<String, String> getTreatments(List<String> flags,
      {Map<String, Object?>? attributes, EvaluationOptions? opts}) {
    final validated = validateFlagNames(flags, 'getTreatments');
    if (!validated.isValid) return <String, String>{};
    return {for (final f in validated.value!) f: 'control'};
  }

  @override
  Map<String, String> getTreatmentsByFlagSets(List<String> flagSets,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      <String, String>{};

  @override
  EvaluationResult getTreatmentWithConfig(String flag,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      const EvaluationResult(treatment: 'control');

  @override
  Map<String, EvaluationResult> getTreatmentsWithConfig(List<String> flags,
      {Map<String, Object?>? attributes, EvaluationOptions? opts}) {
    final validated = validateFlagNames(flags, 'getTreatmentsWithConfig');
    if (!validated.isValid) return <String, EvaluationResult>{};
    return {
      for (final f in validated.value!)
        f: const EvaluationResult(treatment: 'control')
    };
  }

  @override
  Map<String, EvaluationResult> getTreatmentsWithConfigByFlagSets(
          List<String> flagSets,
          {Map<String, Object?>? attributes,
          EvaluationOptions? opts}) =>
      <String, EvaluationResult>{};

  @override
  bool track(String eventType, String trafficType,
          {double? value, Map<String, Object?>? properties}) =>
      false;

  // A NoOp client's whenReady() MUST NOT complete — the invalid SDK/default
  // key MUST surface as a startup failure, not look like a ready SDK (spec
  // §7).
  @override
  Future<void> whenReady() => _eventsManager.onReady;

  // MUST complete after readyTimeout elapses (armed by the owning
  // _NoOpSplitFactory), not instantly and not never (spec §7, §8.2).
  @override
  Future<void> whenTimeout() => _eventsManager.onTimeout;

  @override
  Stream<List<String>> whenUpdated() => const Stream.empty();

  @override
  Future<void> flush() async {}

  @override
  Future<void> destroy() async => _onDestroy?.call();
}

class _NoOpSplitManager implements SplitManager {
  @override
  SplitView? split(String flag) => null;

  @override
  List<SplitView> splits() => [];

  @override
  List<String> names() => [];
}
