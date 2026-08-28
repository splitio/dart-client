import 'dart:async';

import 'package:splitio_client_side/src/client/split_client.dart';
import 'package:splitio_commons/src/input_validation/key.dart';
import 'package:splitio_commons/src/models/config.dart';
import 'package:splitio_commons/src/models/evaluation_options.dart';
import 'package:splitio_commons/src/models/evaluation_result.dart';
import 'package:splitio_commons/src/models/key.dart';
import 'package:splitio_commons/src/models/split_view.dart';
import 'package:splitio_client_side/src/internal/dependency_container.dart';

import 'split_manager.dart';
import 'user_consent.dart';

abstract class SplitFactory {
  static SplitFactory create(
      String sdkKey, SplitClientConfig config, Object key) {
    if (sdkKey.isEmpty) {
      return _NoOpSplitFactory();
    }
    Key? normalized;
    if (key is Key) {
      normalized = key;
    } else if (key is String) {
      normalized = Key(matchingKey: key);
    } else {
      // Invalid type — neither String nor Key. Degrade to NoOp per spec §7.
      return _NoOpSplitFactory();
    }
    final keyResult = validateKey(normalized, 'SplitFactory');
    if (!keyResult.isValid) {
      return _NoOpSplitFactory();
    }
    return _SplitFactoryImpl(sdkKey, config, normalized);
  }

  SplitClient client([Object? key]);
  SplitManager manager();
  UserConsentManager userConsent();
  Future<void> destroy();
}

class _SplitFactoryImpl implements SplitFactory {
  final DependencyContainer _di;
  final Key _key;
  bool _factoryDestroyed = false;

  // Keys whose memberships have already been fetched (or are in flight). The
  // bootstrap key is synced by initialSync(); any other key gets an on-demand
  // fetch the first time a client is created for it.
  final Set<String> _membershipKeys = {};

  // Cache of issued clients keyed by instance ID (matching + bucketing key).
  // Subsequent factory.client(sameKey) calls return the same cached instance,
  // including when that instance has already been destroyed (spec §8.5).
  final Map<String, SplitClientImpl> _clients = {};

  _SplitFactoryImpl(String sdkKey, SplitClientConfig config, this._key)
      : _di = DependencyContainer.build(sdkKey, config) {
    _membershipKeys.add(_key.matchingKey);
    _clients[_instanceId(_key)] = _createClient(_key);
    _startBackground();
  }

  static String _instanceId(Key key) =>
      '${key.matchingKey}#${key.bucketingKey ?? key.matchingKey}';

  void _ensureMembershipsFor(String matchingKey) {
    if (!_membershipKeys.add(matchingKey)) return;
    Future(() async {
      final ok = await _di.syncManager.syncMembershipsFor(matchingKey);
      if (!ok) {
        _di.log.warning('On-demand memberships fetch failed for key: '
            '"$matchingKey"');
        _membershipKeys.remove(matchingKey);
      }
    });
  }

  void _startBackground() {
    final syncConfig = _di.config.sync.normalized();
    Future(() async {
      _di.log.debug('loadLocal started');
      await _di.ruleStore.loadLocal();
      await _di.rbsStore.loadLocal();
      _di.log.debug('loadLocal done');

      _di.log.info('Starting initial sync for key: "${_key.matchingKey}"');
      final ok = await _di.syncManager.initialSync(_key.matchingKey);
      if (ok) {
        _di.log.info('SDK READY');
        _di.eventsManager.notifyReady();
      } else {
        _di.log.warning('Initial sync failed — SDK not ready');
      }
      // Start syncing AFTER the initial fetch (spec §8.1). startStreaming()
      // starts streaming when a StreamingManager was injected (streamingEnabled)
      // and otherwise falls back to polling — see SyncManager.startStreaming().
      // It is deliberately fire-and-forget (unawaited): readiness was already
      // notified above (§8.2), so a slow auth/connect MUST NOT delay anything,
      // and streaming failures fall back to polling via SyncManager wiring.
      // We do NOT gate this on `ok`: even when the initial sync failed, we still
      // start streaming/polling so the SDK keeps retrying to sync (streaming's
      // catch-up fetch or polling will recover).
      unawaited(
          _di.syncManager.startStreaming().catchError((Object e, StackTrace s) {
        _di.log.warning('startStreaming failed: $e');
      }));
      _di.syncManager.startRecorders();

      if (syncConfig.readyTimeout > 0) {
        Future.delayed(Duration(seconds: syncConfig.readyTimeout), () {
          if (!_di.eventsManager.isReady) {
            _di.log
                .warning('Ready timeout reached (${syncConfig.readyTimeout}s)');
            _di.eventsManager.notifyTimeout();
          }
        });
      }
    });
  }

  @override
  SplitClient client([Object? key]) {
    final normalized = _normalizeKey(key, source: 'SplitFactory.client');
    final effectiveKey = normalized ?? _key;
    final id = _instanceId(effectiveKey);
    final cached = _clients[id];
    if (cached != null) return cached;
    _ensureMembershipsFor(effectiveKey.matchingKey);
    final created = _createClient(effectiveKey);
    _clients[id] = created;
    return created;
  }

  Key? _normalizeKey(Object? key, {required String source}) {
    if (key == null) return null;
    if (key is Key) return key;
    if (key is String) return Key(matchingKey: key);
    _di.log
        .warning('$source: key must be String or Key, got ${key.runtimeType}');
    return null;
  }

  SplitClientImpl _createClient(Key key) {
    return SplitClientImpl(
      key: key,
      evaluator: _di.evaluator,
      impressions: _di.impressions,
      eventsManager: _di.eventsManager,
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

  @override
  Future<void> destroy() async {
    if (_factoryDestroyed) return;
    _factoryDestroyed = true;

    // Step 1: Mark every issued client destroyed synchronously — the `_destroyed`
    // flag in SplitClientImpl.destroy() is set before its first await, so
    // building the futures list here already blocks any in-flight evaluation
    // or track() from slipping through (spec §8.5). Their pending flushes
    // are awaited below, before we close the http client.
    final clientDestroys =
        _clients.values.map((c) => c.destroy()).toList(growable: false);

    // Step 2: Stop sync manager (cancels poll timers, stops streaming).
    _di.syncManager.stop();

    // Step 3: Stop recorder timers (no flush yet).
    await _di.syncManager.stopRecorders();

    // Step 4: Wait for client-initiated flushes and run one final factory
    // flush. All in-flight POSTs MUST complete before dispose() closes the
    // http client, otherwise the POSTs get their connection killed mid-flight.
    await Future.wait([
      ...clientDestroys,
      _di.syncManager.flushRecorders(),
    ]);

    // Step 5: Dispose resources.
    await _di.dispose();
  }
}

class _NoOpSplitFactory implements SplitFactory {
  @override
  SplitClient client([Object? key]) => _NoOpSplitClient();

  @override
  SplitManager manager() => _NoOpSplitManager();

  @override
  UserConsentManager userConsent() => UserConsentManager();

  @override
  Future<void> destroy() async {}
}

class _NoOpSplitClient implements SplitClient {
  @override
  String getTreatment(String flag,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      'control';

  @override
  List<String> getTreatments(List<String> flags,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      flags.map((_) => 'control').toList();

  @override
  List<String> getTreatmentsByFlagSets(List<String> flagSets,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      [];

  @override
  EvaluationResult getTreatmentWithConfig(String flag,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      const EvaluationResult(treatment: 'control');

  @override
  List<EvaluationResult> getTreatmentsWithConfig(List<String> flags,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      flags.map((_) => const EvaluationResult(treatment: 'control')).toList();

  @override
  List<EvaluationResult> getTreatmentsWithConfigByFlagSets(
          List<String> flagSets,
          {Map<String, Object?>? attributes,
          EvaluationOptions? opts}) =>
      [];

  @override
  bool track(String eventType, String trafficType,
          {double? value, Map<String, Object?>? properties}) =>
      false;

  @override
  Future<void> whenReady() async {}

  @override
  Future<void> whenTimeout() async {}

  @override
  Stream<List<String>> whenUpdated() => const Stream.empty();

  @override
  Future<void> flush() async {}

  @override
  Future<void> destroy() async {}
}

class _NoOpSplitManager implements SplitManager {
  @override
  SplitView? split(String flag) => null;

  @override
  List<SplitView> splits() => [];

  @override
  List<String> names() => [];
}
