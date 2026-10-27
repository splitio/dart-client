import 'dart:async';

import 'package:splitio_commons/src/core/factory_tracker.dart';
import 'package:splitio_commons/src/events/events_manager.dart';
import 'package:splitio_commons/src/input_validation/sdk_key.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/config.dart';

import '../client/split_client.dart';
import 'dependency_container.dart';
import 'signal_listener.dart';
import 'split_manager.dart';

abstract class SplitFactory {
  static SplitFactory create(String sdkKey, SplitClientConfig config) {
    final sdkKeyResult = validateSdkKey(sdkKey, 'SplitFactory.create');
    if (!sdkKeyResult.isValid) {
      SplitLogger(level: config.logLevel).error(sdkKeyResult.error!);
      return _NoOpSplitFactory(config);
    }
    return _SplitFactoryImpl(sdkKey, config);
  }

  ServerSplitClient client();
  SplitManager manager();
  Future<void> destroy();
}

class _SplitFactoryImpl implements SplitFactory {
  // late final (not initializer-list-assigned): onSynced below is a tear-off
  // of _handleSynced, an instance method, and `this` cannot be referenced in
  // a constructor initializer list.
  late final ServerDependencyContainer _di;
  late final SplitClientImpl _client;
  late final SplitManager _manager;
  final String _sdkKey;
  SignalListener? _signalListener;
  bool _factoryDestroyed = false;
  Future<void>? _destroyFuture;
  Timer? _readyTimeoutTimer;

  _SplitFactoryImpl(this._sdkKey, SplitClientConfig config) {
    _di = ServerDependencyContainer.build(_sdkKey, config,
        onSynced: _handleSynced, isDestroyed: () => _factoryDestroyed);
    _client = SplitClientImpl(
      evaluator: _di.evaluator,
      impressions: _di.impressions,
      eventsManager: _di.eventsManager,
      eventsTracker: _di.eventsTracker,
      ruleStore: _di.ruleStore,
      logger: _di.log,
      flushRecorders: _di.syncManager.flushRecorders,
    );
    FactoryTracker.track(_sdkKey, _di.log);
    _manager = SplitManagerImpl(_di.manager);
    if (config.installSignalHandler) {
      _signalListener = SignalListener.forDefaults(
        onSignal: destroy,
        logger: _di.log,
      );
      _signalListener!.install();
    }
    _startReadyTimeout();
    _startBackground();
  }

  // The readyTimeout window is measured from factory creation, not from the
  // end of the initial sync (spec §8.2).
  void _startReadyTimeout() {
    final readyTimeout = _di.config.sync.normalized().readyTimeout;
    if (readyTimeout <= 0) return;
    _readyTimeoutTimer = Timer(Duration(seconds: readyTimeout), () {
      if (_di.eventsManager.isReady) return;
      _di.log.warning('Ready timeout reached (${readyTimeout}s)');
      _di.eventsManager.notifyTimeout();
    });
  }

  // Called once flags AND segments have each synced successfully at least
  // once (via ReadinessTracker in ServerDependencyContainer), regardless of
  // which path got there — initial sync, a periodic poll, or a streaming
  // catch-up fetch (spec §8.2). A failed initial sync MUST NOT prevent this
  // from firing later.
  void _handleSynced() {
    if (_factoryDestroyed) return;
    _readyTimeoutTimer?.cancel();
    _di.log.info('SDK READY');
    _di.eventsManager.notifyReady();
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

        _di.log.info('Starting initial sync (server-side)');
        final ok = await _di.syncManager.initialSync();
        if (_factoryDestroyed) return;
        if (!ok) {
          _di.log.warning('Initial sync failed — SDK not ready');
        }
        // Streaming-preferred: if a StreamingManager is present, start it and let
        // its onPushEnabled/onPushDisabled callbacks drive the poll timers. When
        // streaming is disabled or push comes back false, this falls through to
        // plain polling. Off the readiness critical path (§8.2).
        unawaited(_di.syncManager.startStreaming().catchError(
            (Object e, StackTrace s) =>
                _di.log.error('startStreaming failed', '$e\n$s')));
        _di.syncManager.startRecorders();
      } catch (e, s) {
        _di.log.error('Background startup failed', '$e\n$s');
      }
    });
  }

  @override
  ServerSplitClient client() => _client;

  @override
  SplitManager manager() => _manager;

  // Teardown runs at most once; every caller gets the same Future, so a
  // SIGTERM/SIGINT landing mid-destroy waits for the final flush before the
  // signal listener exits the process.
  @override
  Future<void> destroy() => _destroyFuture ??= _teardown();

  Future<void> _teardown() async {
    _factoryDestroyed = true;
    FactoryTracker.release(_sdkKey);
    _readyTimeoutTimer?.cancel();

    await _di.syncManager.stop();
    await _di.syncManager.stopRecorders();
    await _client.destroy();
    await _signalListener?.dispose();
    await _di.dispose();
  }
}

class _NoOpSplitFactory implements SplitFactory {
  final EventsManager _eventsManager = EventsManager();
  late final ServerSplitClient _client;
  final SplitManager _manager = noOpSplitManager();
  Timer? _readyTimeoutTimer;

  // readyTimeout starts at factory creation (spec §8.2), same as the real
  // factory. whenReady() never completes for a NoOp factory, so this timer
  // is the only way whenTimeout() ever fires — it MUST be cancelled by
  // destroy() so a destroyed NoOp factory never emits TIMEOUT either.
  _NoOpSplitFactory(SplitClientConfig config) {
    _client = noOpServerSplitClient(_eventsManager);
    final readyTimeout = config.sync.normalized().readyTimeout;
    if (readyTimeout > 0) {
      _readyTimeoutTimer =
          Timer(Duration(seconds: readyTimeout), _eventsManager.notifyTimeout);
    }
  }

  @override
  ServerSplitClient client() => _client;

  @override
  SplitManager manager() => _manager;

  @override
  Future<void> destroy() async {
    _readyTimeoutTimer?.cancel();
  }
}
