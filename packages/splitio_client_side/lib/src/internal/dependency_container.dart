import 'dart:async';
import 'package:splitio_commons/src/auth/jwt_auth_provider.dart';
import 'package:splitio_commons/src/engine/targeting_engine.dart';
import 'package:splitio_commons/src/event_tracker/events_tracker.dart';
import 'package:splitio_commons/src/events/events_manager.dart';
import 'package:splitio_commons/src/http_client/split_http_client.dart';
import 'package:splitio_commons/src/http_client/streaming_transport_factory.dart';
import 'package:splitio_commons/src/local/local_evaluator.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/config.dart';
import 'package:splitio_commons/src/models/enums.dart';
import 'package:splitio_commons/src/parsing/rule_parser.dart';
import 'package:splitio_commons/src/parsing/split_change_processor.dart';
import 'package:splitio_commons/src/parsing/memberships_processor.dart';
import 'package:splitio_commons/src/impressions/impression_strategy.dart';
import 'package:splitio_commons/src/impressions/impressions_counter.dart';
import 'package:splitio_commons/src/impressions/impressions_manager.dart';
import 'package:splitio_commons/src/impressions/impressions_observer.dart';
import 'package:splitio_commons/src/storage/impressions_store.dart';
import 'package:splitio_commons/src/storage/membership_store.dart';
import 'package:splitio_commons/src/storage/rule_based_segment_store.dart';
import 'package:splitio_commons/src/storage/rule_store.dart';
import 'package:splitio_commons/src/sync/fetchers/flags_fetcher.dart';
import 'package:splitio_commons/src/sync/fetchers/memberships_fetcher.dart';
import 'package:splitio_commons/src/impressions/unique_keys_tracker.dart';
import 'package:splitio_commons/src/sync/recorders/events_recorder.dart';
import 'package:splitio_commons/src/sync/recorders/recorder.dart';
import 'package:splitio_commons/src/sync/recorders/impressions_count_recorder.dart';
import 'package:splitio_commons/src/sync/recorders/impressions_recorder.dart';
import 'package:splitio_commons/src/sync/recorders/unique_keys_recorder.dart';
import 'package:splitio_commons/src/sync/streaming/streaming_manager.dart';
import 'package:splitio_commons/src/sync/sync_manager.dart';
import 'package:splitio_commons/src/event_tracker/events_store.dart';
import 'split_manager.dart';
import 'user_consent.dart';

// LOC-exemption: DI composition root — inherently linear object-graph wiring; splitting adds indirection without reducing complexity. Approved 2026-07-22.
class DependencyContainer {
  final SplitLogger log;
  final InMemoryRuleStore ruleStore;
  final InMemoryRuleBasedSegmentStore rbsStore;
  final InMemoryMembershipStore membershipStore;
  final InMemoryImpressionsStore impressionsStore;
  final InMemoryEventsStore eventsStore;
  final EventsManager eventsManager;
  final EventsTracker eventsTracker;
  final UserConsentManager userConsent;
  final SplitHttpClient httpClient;
  final SyncManager syncManager;
  final LocalEvaluator evaluator;
  final ImpressionsManager impressions;
  final SplitManagerImpl manager;
  final SplitClientConfig config;

  /// The streaming coordinator, or null when streaming is disabled
  /// (poll-only). Exposed for wiring verification; teardown is handled by
  /// [syncManager] (its `stop()` also stops streaming).
  final StreamingManager? streamingManager;

  /// The JWT auth provider backing streaming, or null when streaming is
  /// disabled. Held only so [dispose] can clear its cached credential; not
  /// exposed otherwise.
  final JwtAuthProvider? _authProvider;

  DependencyContainer._({
    required this.log,
    required this.ruleStore,
    required this.rbsStore,
    required this.membershipStore,
    required this.impressionsStore,
    required this.eventsStore,
    required this.eventsManager,
    required this.eventsTracker,
    required this.userConsent,
    required this.httpClient,
    required this.syncManager,
    required this.evaluator,
    required this.impressions,
    required this.manager,
    required this.config,
    this.streamingManager,
    JwtAuthProvider? authProvider,
  }) : _authProvider = authProvider;

  factory DependencyContainer.build(String sdkKey, SplitClientConfig config) {
    final syncConfig = config.sync.normalized();
    final endpoints = syncConfig.serviceEndpoints ?? const ServiceEndpoints();
    final baseUrl = endpoints.resolvedSdkUrl;
    final log = SplitLogger(level: config.logLevel);

    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    final membershipStore = InMemoryMembershipStore();
    final eventsManager = EventsManager();
    final userConsent = UserConsentManager(initialStatus: config.userConsent);
    final httpClient = SplitHttpClient(apiKey: sdkKey);
    final engine = TargetingEngine();

    final evaluator = LocalEvaluator(
      engine: engine,
      ruleStore: ruleStore,
      rbsStore: rbsStore,
      membershipStore: membershipStore,
    );
    final impressionsStore = InMemoryImpressionsStore();
    final observer = ImpressionsObserver();
    final counter = ImpressionsCounter();
    UniqueKeysTracker? uniqueKeysTracker;

    final ImpressionStrategy strategy;
    switch (config.impressionsMode) {
      case ImpressionsMode.debug:
        strategy = DebugImpressionStrategy(
            observer: observer, store: impressionsStore);
      case ImpressionsMode.optimized:
        strategy = OptimizedImpressionStrategy(
            observer: observer, counter: counter, store: impressionsStore);
      case ImpressionsMode.none:
        uniqueKeysTracker = UniqueKeysTracker();
        strategy = NoneImpressionStrategy(
            counter: counter, tracker: uniqueKeysTracker);
    }

    final impressions = ImpressionsManager(
        listener: config.impressionListener,
        consentProvider: () => userConsent.status,
        strategy: strategy,
        log: log);
    final ruleParser = RuleParser();
    final splitChangeProcessor = SplitChangeProcessor(
      parser: ruleParser,
      rbsStore: rbsStore,
      ruleStore: ruleStore,
    );
    final flagsFetcher = FlagsFetcher(
      httpClient: httpClient,
      log: log,
      baseUrl: baseUrl,
      processor: splitChangeProcessor,
      ruleStore: ruleStore,
      rbsStore: rbsStore,
      onUpdate: (flags) => eventsManager.notifyUpdate(flags),
    );
    final membershipsProcessor = MembershipsProcessor(
      membershipStore: membershipStore,
    );
    final membershipsFetcher = MembershipsFetcher(
      httpClient: httpClient,
      log: log,
      baseUrl: baseUrl,
      processor: membershipsProcessor,
    );
    final manager = SplitManagerImpl(ruleStore: ruleStore, logger: log);
    final eventsUrl = endpoints.resolvedEventsUrl;
    final telemetryUrl = endpoints.resolvedTelemetryUrl;
    final impressionsPushRate = config.impressionsMode == ImpressionsMode.debug
        ? 60
        : syncConfig.impressionsPushRate;
    final impressionsRecorder = ImpressionsRecorder(
      store: impressionsStore,
      httpClient: httpClient,
      url: eventsUrl,
      mode: config.impressionsMode,
      pushRateSeconds: impressionsPushRate,
      log: log,
    );
    // Streaming stack (spec §11). Only constructed when streaming is enabled;
    // otherwise SyncManager runs poll-only (streamingManager stays null).
    //
    // Construction ordering: StreamingManager needs onPushEnabled/onPushDisabled
    // callbacks that target the SyncManager, but SyncManager needs the
    // StreamingManager in its constructor. Resolved via a `late final
    // SyncManager` captured by the callback closures — they are only invoked
    // once streaming starts (task 5.3, after init fetch), by which time
    // syncManager is assigned, so there is no null-deref.
    late final SyncManager syncManager;
    StreamingManager? streamingManager;
    JwtAuthProvider? authProvider;
    if (syncConfig.streamingEnabled) {
      final authUrl = endpoints.resolvedAuthUrl;
      final streamingBaseUrl = endpoints.resolvedStreamingUrl;
      // The auth fetch is authenticated with the static Bearer <sdkKey> header,
      // which the shared httpClient (SplitHttpClient(apiKey: sdkKey)) already
      // attaches, so we reuse it. activeKeys/matchingKeys read the live set of
      // bound matching keys from the memberships fetcher. Assumption: the key is
      // bound by initialSync (task 5.1) before streaming starts (task 5.3), so
      // boundKeys is populated by the time the JWT/channel request is made.
      authProvider = JwtAuthProvider(
        httpClient: httpClient,
        authUrl: authUrl,
        activeKeys: () => membershipsFetcher.boundKeys.toList(),
        logger: log,
      );
      streamingManager = StreamingManager(
        transport: createStreamingTransport(),
        authProvider: authProvider,
        flagsFetcher: flagsFetcher,
        membershipsFetcher: membershipsFetcher,
        ruleStore: ruleStore,
        membershipStore: membershipStore,
        streamingBaseUri: Uri.parse(streamingBaseUrl),
        logger: log,
        matchingKeys: () => membershipsFetcher.boundKeys.toList(),
        onPushEnabled: () => syncManager.onStreamingUp(),
        onPushDisabled: () => syncManager.onStreamingDown(),
      );
    }

    final eventsStore = InMemoryEventsStore();
    final eventsTracker = EventsTracker(
      store: eventsStore,
      consentProvider: () => userConsent.status,
      log: log,
    );
    final eventsRecorder = EventsRecorder(
      store: eventsStore,
      httpClient: httpClient,
      url: eventsUrl,
      pushRateSeconds: syncConfig.eventsPushRate,
      log: log,
    );
    eventsStore.setOnFullQueue(() {
      if (eventsRecorder.isRunning) {
        log.info('Events queue is full — flushing');
        eventsRecorder.flush();
      }
    });
    final recorders = <Recorder>[impressionsRecorder, eventsRecorder];
    if (config.impressionsMode != ImpressionsMode.debug) {
      recorders.add(ImpressionsCountRecorder(
        counter: counter,
        consentProvider: () => userConsent.status,
        httpClient: httpClient,
        url: eventsUrl,
        log: log,
      ));
    }
    final capturedTracker = uniqueKeysTracker;
    if (capturedTracker != null) {
      recorders.add(UniqueKeysRecorder(
        tracker: capturedTracker,
        consentProvider: () => userConsent.status,
        httpClient: httpClient,
        url: telemetryUrl,
        log: log,
      ));
    }

    // §7.2: DECLINED must drop already-queued data, not just pause sending.
    userConsent.setOnDeclined(() {
      log.debug('Consent declined — dropping queued impressions/events data');
      impressionsStore.clear();
      eventsStore.clear();
      counter.clear();
      capturedTracker?.clear();
    });

    syncManager = SyncManager(
        httpClient: httpClient,
        ruleStore: ruleStore,
        rbsStore: rbsStore,
        membershipStore: membershipStore,
        config: syncConfig,
        baseUrl: baseUrl,
        logger: log,
        flagsFetcher: flagsFetcher,
        membershipsFetcher: membershipsFetcher,
        recorders: recorders,
        streamingManager: streamingManager);

    return DependencyContainer._(
      log: log,
      ruleStore: ruleStore,
      rbsStore: rbsStore,
      membershipStore: membershipStore,
      impressionsStore: impressionsStore,
      eventsStore: eventsStore,
      eventsManager: eventsManager,
      eventsTracker: eventsTracker,
      userConsent: userConsent,
      httpClient: httpClient,
      syncManager: syncManager,
      evaluator: evaluator,
      impressions: impressions,
      manager: manager,
      config: config,
      streamingManager: streamingManager,
      authProvider: authProvider,
    );
  }

  Future<void> dispose() async {
    // Cleanup-only. factory.destroy() owns the stop/flush ordering; dispose()
    // just cleans up resources. Safe to call multiple times.
    _authProvider?.clearAll();
    httpClient.close();
    await eventsManager.dispose();
  }
}
