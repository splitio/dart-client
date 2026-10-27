import 'dart:async';

import 'package:splitio_commons/src/auth/jwt_auth_provider.dart';
import 'package:splitio_commons/src/engine/targeting_engine.dart';
import 'package:splitio_commons/src/event_tracker/events_store.dart';
import 'package:splitio_commons/src/event_tracker/events_tracker.dart';
import 'package:splitio_commons/src/events/events_manager.dart';
import '../version.dart';
import 'package:splitio_commons/src/http_client/split_http_client.dart';
import 'package:splitio_commons/src/http_client/streaming_transport_factory.dart';
import 'package:splitio_commons/src/impressions/impression_strategy.dart';
import 'package:splitio_commons/src/impressions/impressions_counter.dart';
import 'package:splitio_commons/src/impressions/impressions_manager.dart';
import 'package:splitio_commons/src/impressions/impressions_observer.dart';
import 'package:splitio_commons/src/impressions/unique_keys_tracker.dart';
import 'package:splitio_commons/src/local/local_evaluator.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/config.dart';
import 'package:splitio_commons/src/models/enums.dart';
import 'package:splitio_commons/src/parsing/rule_parser.dart';
import 'package:splitio_commons/src/parsing/segment_change_processor.dart';
import 'package:splitio_commons/src/parsing/split_change_processor.dart';
import 'package:splitio_commons/src/storage/impressions_store.dart';
import 'package:splitio_commons/src/storage/rule_based_segment_store.dart';
import 'package:splitio_commons/src/storage/rule_store.dart';
import 'package:splitio_commons/src/storage/segment_store.dart';
import 'package:splitio_commons/src/sync/fetchers/flags_fetcher.dart';
import 'package:splitio_commons/src/sync/fetchers/segment_changes_fetcher.dart';
import 'package:splitio_commons/src/sync/polling/polling_manager_ss.dart';
import 'package:splitio_commons/src/sync/readiness_tracker.dart';
import 'package:splitio_commons/src/sync/recorders/events_recorder.dart';
import 'package:splitio_commons/src/sync/recorders/impressions_count_recorder.dart';
import 'package:splitio_commons/src/sync/recorders/impressions_recorder.dart';
import 'package:splitio_commons/src/sync/recorders/recorder.dart';
import 'package:splitio_commons/src/sync/recorders/unique_keys_recorder.dart';
import 'package:splitio_commons/src/sync/streaming/streaming_manager.dart';
import 'package:splitio_commons/src/sync/sync_manager.dart';

import 'package:splitio_commons/src/client/split_manager.dart';
import 'package:splitio_commons/src/client/user_consent.dart';

import 'flags_segment_sync.dart';

// LOC-exemption: DI composition root — inherently linear object-graph wiring;
// splitting adds indirection without reducing complexity. Approved 2026-09-22.
class ServerDependencyContainer {
  final SplitLogger log;
  final InMemoryRuleStore ruleStore;
  final InMemoryRuleBasedSegmentStore rbsStore;
  final InMemorySegmentStore segmentStore;
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
  final FlagsSegmentSync flagsSegmentSync;

  /// The streaming coordinator, or null when streaming is disabled
  /// (poll-only). Teardown is handled by [syncManager] (its `stop()` also
  /// stops streaming).
  final StreamingManager? streamingManager;

  /// The JWT auth provider backing streaming, or null when streaming is
  /// disabled. Held only so [dispose] can clear its cached credential.
  final JwtAuthProvider? _authProvider;

  ServerDependencyContainer._({
    required this.log,
    required this.ruleStore,
    required this.rbsStore,
    required this.segmentStore,
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
    required this.flagsSegmentSync,
    required this.streamingManager,
    required JwtAuthProvider? authProvider,
  }) : _authProvider = authProvider;

  factory ServerDependencyContainer.build(
    String sdkKey,
    SplitClientConfig config, {
    void Function()? onSynced,
    bool Function()? isDestroyed,
  }) {
    final log = SplitLogger(level: config.logLevel);
    final syncConfig = config.sync.normalized(onWarning: log.warning);
    final endpoints = syncConfig.serviceEndpoints ?? const ServiceEndpoints();
    final baseUrl = endpoints.resolvedSdkUrl;
    final eventsUrl = endpoints.resolvedEventsUrl;
    final telemetryUrl = endpoints.resolvedTelemetryUrl;

    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    final segmentStore = InMemorySegmentStore();
    final eventsManager = EventsManager();
    final userConsent = UserConsentManager(initialStatus: config.userConsent);
    final httpClient = SplitHttpClient(apiKey: sdkKey, sdkVersion: sdkVersion);
    final engine = TargetingEngine();

    final evaluator = LocalEvaluator(
      engine: engine,
      ruleStore: ruleStore,
      rbsStore: rbsStore,
      // On server-side, segment membership answers come from `segmentStore`,
      // not the per-key store. `LocalEvaluator` accepts any
      // `SegmentMembershipResolver` — both stores implement it (Plan A).
      membershipStore: segmentStore,
      logger: log,
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
        log: log,
        sdkVersion: sdkVersion);

    // READY MUST fire the first time flags AND segments have each synced
    // successfully at least once, regardless of which sync path (initial
    // sync, a periodic poll, or a streaming catch-up fetch) got there first
    // (spec §8.2) — a failed initial sync MUST NOT block it. flagsFetcher
    // and segmentChangesFetcher below are shared with both PollingManagerSS
    // (polling/initial sync) and StreamingManager (catch-up), so wiring their
    // result callbacks here covers every path with no changes to either
    // manager.
    final readinessTracker = onSynced == null
        ? null
        : ReadinessTracker(
            requiredFeeds: const {'flags', 'segments'},
            onSynced: onSynced,
          );

    // A successful flags fetch can register a brand-new segment (via
    // `onUpdate` below) that has never actually been fetched yet. Marking
    // 'flags' synced the moment the HTTP call succeeds — without checking
    // that every segment it just registered already has data — lets READY
    // fire while an IN_SEGMENT rule still evaluates against an empty
    // segment. This is a race regardless of which feed happens to complete
    // last: a segments fetch that ran before the segment was even
    // registered can also latch 'segments' trivially (zero segments at the
    // time), so neither feed's own success alone is a safe signal.
    //
    // `flagsFetchSucceeded` records that the flags endpoint itself has
    // responded successfully at least once. `_tryMarkFlagsArrived` only
    // turns that into the 'flags' latch once every segment currently known
    // to the store has actually been fetched (mirrors the JS SDK's
    // `checkAllSegmentsExist` in splitChangesUpdater.ts). It is re-run from
    // the segments fetcher's own callback too, so a segment that arrives
    // *after* the flags fetch re-evaluates the gate instead of leaving it
    // permanently blocked.
    bool flagsFetchSucceeded = false;
    void tryMarkFlagsArrived() {
      if (flagsFetchSucceeded && segmentStore.allRegisteredSegmentsFetched()) {
        readinessTracker?.markSynced('flags', true);
      }
    }

    final ruleParser = RuleParser();
    final splitChangeProcessor = SplitChangeProcessor(
      parser: ruleParser,
      ruleStore: ruleStore,
      rbsStore: rbsStore,
    );

    // Assigned below, right after `segmentChangesFetcher` is built —
    // `onFlagsChanged` only runs later, asynchronously, once a fetch
    // actually completes, so by then this is always set.
    late final FlagsSegmentSync flagsSegmentSync;

    // The post-apply side effect a flag change performs regardless of
    // HOW it arrived: a fetched `/splitChanges` diff AND an in-place
    // `SPLIT_UPDATE`/`SPLIT_KILL` streaming apply (spec §12.1) MUST both
    // register newly-referenced segments — immediately fetching any that
    // registration exposes as unfetched, rather than waiting for the next
    // segments polling interval (spec §8.2; see [FlagsSegmentSync]) — and
    // emit `whenUpdated`/SDK_UPDATE. Shared by reference between
    // `flagsFetcher.onUpdate` below and `StreamingManager.onFlagsUpdated`
    // so the two paths can never drift.
    void onFlagsChanged(List<String> changedFlags) {
      flagsSegmentSync.onFlagsChanged();
      eventsManager.notifyUpdate(changedFlags);
    }

    final flagsFetcher = FlagsFetcher(
      httpClient: httpClient,
      log: log,
      baseUrl: baseUrl,
      processor: splitChangeProcessor,
      ruleStore: ruleStore,
      rbsStore: rbsStore,
      onUpdate: onFlagsChanged,
      onResult: (success) {
        if (success) flagsFetchSucceeded = true;
        tryMarkFlagsArrived();
      },
    );

    final segmentChangeProcessor = SegmentChangeProcessor(store: segmentStore);
    final segmentChangesFetcher = SegmentChangesFetcher(
      httpClient: httpClient,
      log: log,
      baseUrl: baseUrl,
      processor: segmentChangeProcessor,
      store: segmentStore,
      onUpdate: () => eventsManager.notifyUpdate(const []),
      onResult: (success) {
        readinessTracker?.markSynced('segments', success);
        // A segment that just finished fetching may be the one 'flags' was
        // waiting on.
        if (success) tryMarkFlagsArrived();
      },
    );
    flagsSegmentSync = FlagsSegmentSync(
      ruleStore: ruleStore,
      segmentStore: segmentStore,
      fetchSegments: segmentChangesFetcher.fetch,
      logger: log,
    );

    final manager = SplitManagerImpl(
        ruleStore: ruleStore, logger: log, isDestroyed: isDestroyed);

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
        payloadFormat: UniqueKeysPayloadFormat.serverSide,
        httpClient: httpClient,
        url: telemetryUrl,
        log: log,
      ));
    }

    // §7.2: DECLINED must drop already-queued data, not just pause sending.
    // This includes each recorder's BatchSubmitter-retained retry batch, not
    // just the live stores — otherwise a batch retained after a transient
    // POST failure would still go out on the recorder's next flush.
    userConsent.setOnDeclined(() {
      log.debug('Consent declined — dropping queued impressions/events data');
      impressionsStore.clear();
      eventsStore.clear();
      counter.clear();
      capturedTracker?.clear();
      for (final recorder in recorders) {
        recorder.clearRetained();
      }
    });

    // Streaming stack (spec §11). Only constructed when streaming is enabled;
    // otherwise the SyncManager runs poll-only (streamingManager stays null).
    //
    // Construction ordering: StreamingManager needs onPushEnabled/onPushDisabled
    // callbacks that target the SyncManager, but the SyncManager needs
    // the StreamingManager in its constructor. Resolved via a `late final
    // SyncManager` captured by the callback closures — they are only
    // invoked once streaming starts (after initialSync), by which time
    // syncManager is assigned.
    late final SyncManager syncManager;
    StreamingManager? streamingManager;
    JwtAuthProvider? authProvider;
    if (syncConfig.streamingEnabled) {
      final authUrl = endpoints.resolvedAuthUrl;
      final streamingBaseUrl = endpoints.resolvedStreamingUrl;
      // The auth fetch is authenticated with the static Bearer <sdkKey> header,
      // which the shared httpClient (SplitHttpClient(apiKey: sdkKey)) already
      // attaches, so we reuse it. Server-side omits the `users=` query param
      // per spec §19.3 — the provider's activeKeys defaults to an empty list.
      authProvider = JwtAuthProvider(
        httpClient: httpClient,
        authUrl: authUrl,
        logger: log,
      );
      streamingManager = StreamingManager(
        transport: createStreamingTransport(),
        authProvider: authProvider,
        flagsFetcher: flagsFetcher,
        // Server-side topology: no per-key memberships or membership store.
        // MEMBERSHIPS_MS/LS_UPDATE frames are ignored (spec §17.2 Axis 3).
        // SEGMENT_UPDATE frames route to a single-segment fetch via
        // SegmentChangesFetcher.fetchForSegment (the SS analogue of the
        // per-key membership refresh used on client-side).
        segmentFetcher: segmentChangesFetcher.fetchForSegment,
        // Backs the per-segment on-demand fetch coordinator (spec §10.2):
        // a stale/0-change `/segmentChanges` response to a SEGMENT_UPDATE
        // notification is retried with backoff, then one CDN-bypass fetch,
        // converging on the segment's own cursor read via segmentCursor.
        segmentFetcherWithOptions: segmentChangesFetcher.fetchForSegment,
        segmentCursor: segmentStore.changeNumber,
        // Catch-up (§11.3) MUST also refresh every tracked segment, not just
        // rules: SyncManager.onStreamingUp() cancels the segments poll
        // timer while push is up, so without this, segment stores would stay
        // stale until an unrelated SEGMENT_UPDATE frame happened to arrive
        // for each one.
        allSegmentsFetcher: segmentChangesFetcher.fetch,
        ruleStore: ruleStore,
        rbsStore: rbsStore,
        streamingBaseUri: Uri.parse(streamingBaseUrl),
        logger: log,
        onPushEnabled: () => syncManager.onStreamingUp(),
        onPushDisabled: () => syncManager.onStreamingDown(),
        onFlagsUpdated: onFlagsChanged,
      );
    }

    syncManager = SyncManager(
      polling: PollingManagerSS(
        fetchFlags: flagsFetcher.fetch,
        fetchSegments: segmentChangesFetcher.fetch,
        featuresRefreshRate:
            Duration(seconds: syncConfig.featureFlagsPollingRate),
        segmentsRefreshRate: Duration(seconds: syncConfig.segmentsPollingRate),
      ),
      recorders: recorders,
      streamingManager: streamingManager,
      logger: log,
    );

    return ServerDependencyContainer._(
      log: log,
      ruleStore: ruleStore,
      rbsStore: rbsStore,
      segmentStore: segmentStore,
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
      flagsSegmentSync: flagsSegmentSync,
      streamingManager: streamingManager,
      authProvider: authProvider,
    );
  }

  Future<void> dispose() async {
    // No HTTP may originate from a flags-change hook once the factory is
    // torn down (review finding on FlagsSegmentSync.onFlagsChanged).
    flagsSegmentSync.destroy();
    _authProvider?.clearAll();
    httpClient.close();
    await eventsManager.dispose();
  }
}
