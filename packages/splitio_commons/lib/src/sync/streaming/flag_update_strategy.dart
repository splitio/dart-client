import 'dart:convert';

import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/parsing/parsing.dart';
import 'package:splitio_commons/src/storage/storage.dart';

import '../compression/compression_type.dart';
import '../compression/notification_payload_decoder.dart';
import 'notification_processor.dart';

/// Outcome of handling a flag-side [FeedUpdate] (spec §12.1).
///
/// [appliedInPlace] means the store was mutated directly and no fetch is
/// needed. [fetchRequired] means the caller (StreamingManager) MUST trigger a
/// full `/splitChanges` fetch — either because in-place apply was not safe, or
/// because the strategy mandates a follow-up fetch (SPLIT_KILL).
enum FlagUpdateOutcome { appliedInPlace, fetchRequired }

/// The result of a single [FlagUpdateStrategy.handle] call.
///
/// [didApplyInPlace] records whether the store was mutated regardless of the
/// [outcome] — a SPLIT_KILL can apply the kill in place AND still require a
/// follow-up fetch, so the two facts are tracked separately.
class FlagUpdateResult {
  final FlagUpdateOutcome outcome;
  final bool didApplyInPlace;

  const FlagUpdateResult({
    required this.outcome,
    required this.didApplyInPlace,
  });

  static const FlagUpdateResult _fetch = FlagUpdateResult(
    outcome: FlagUpdateOutcome.fetchRequired,
    didApplyInPlace: false,
  );
}

/// Flag-side instant-update strategies for `SPLIT_UPDATE` and `SPLIT_KILL`
/// (spec §12.1). Pure of network I/O: it either mutates [_ruleStore] in place
/// or signals the caller that a fetch fallback is required.
///
/// `SPLIT_UPDATE` payloads with `c == 0` (base64 only), `c == 1` (gzip) or
/// `c == 2` (zlib) are applied in place; unknown compression bytes and decode
/// errors fall back to fetch (safe default per §12.3). A decode error on a
/// non-empty `d` is logged at WARNING.
class FlagUpdateStrategy {
  final InMemoryRuleStore _ruleStore;
  final RuleParser _parser;
  final void Function(List<String> changedFlags) _onApplied;
  final NotificationPayloadDecoder _payloadDecoder;
  final SplitLogger? _logger;

  /// [onApplied] runs the same post-apply side effects a fetched change
  /// performs — the `whenUpdated`/SDK_UPDATE notification and, on
  /// server-side, segment registration (spec §12.1) — right after an
  /// in-place mutation. Callers MUST pass the identical callback wired as
  /// `FlagsFetcher.onUpdate` so the two paths can never drift on what "a
  /// flag changed" means. Defaults to a no-op (e.g. for tests that don't
  /// care about this side effect).
  FlagUpdateStrategy({
    required InMemoryRuleStore ruleStore,
    RuleParser? parser,
    void Function(List<String> changedFlags)? onApplied,
    NotificationPayloadDecoder? payloadDecoder,
    SplitLogger? logger,
  })  : _logger = logger,
        _ruleStore = ruleStore,
        _parser = parser ?? RuleParser(),
        _onApplied = onApplied ?? ((_) {}),
        _payloadDecoder = payloadDecoder ?? const NotificationPayloadDecoder();

  /// Handles a flag-side [update], mutating the store in place when safe and
  /// returning whether a fetch is still required. Never throws — any decode or
  /// parse error degrades to a fetch fallback.
  FlagUpdateResult handle(FeedUpdate update) {
    switch (update.type) {
      case 'SPLIT_UPDATE':
        return _handleSplitUpdate(update.payload);
      case 'SPLIT_KILL':
        return _handleSplitKill(update.payload);
      default:
        return FlagUpdateResult._fetch;
    }
  }

  FlagUpdateResult _handleSplitUpdate(Map<String, dynamic> payload) {
    final changeNumber = payload['changeNumber'];
    final pcn = payload['pcn'];
    final c = payload['c'];
    final d = payload['d'];

    // In-place apply is only safe when the compression byte is known (0/1/2)
    // and it applies exactly on top of the currently stored change (pcn
    // matches).
    if (changeNumber is! int ||
        pcn is! int ||
        CompressionType.fromWire(c) == null ||
        d is! String ||
        pcn != _ruleStore.changeNumber()) {
      return FlagUpdateResult._fetch;
    }

    try {
      final dto = _decodeDefinition(c, d);
      if (dto == null) return FlagUpdateResult._fetch;
      final name = dto['name'] as String?;
      if (name == null || name.isEmpty) return FlagUpdateResult._fetch;

      // parseSplit returns null for non-ACTIVE (ARCHIVED/DELETED) splits → remove in place.
      final parsed = _parser.parseSplit(dto);
      _ruleStore.applyChange(
        Change(changeNumber: changeNumber, updates: {name: parsed}),
      );
      _onApplied([name]);
      return const FlagUpdateResult(
        outcome: FlagUpdateOutcome.appliedInPlace,
        didApplyInPlace: true,
      );
    } catch (e) {
      // An absent or empty `d` falls back silently (JS parity, spec §12.2).
      if (d.isNotEmpty) {
        _logger?.warning('Fetching SplitChanges due to an error processing '
            'SPLIT_UPDATE notification: $e');
      }
      return FlagUpdateResult._fetch;
    }
  }

  FlagUpdateResult _handleSplitKill(Map<String, dynamic> payload) {
    final changeNumber = payload['changeNumber'];
    final splitName = payload['splitName'];
    final defaultTreatment = payload['defaultTreatment'];

    var didApply = false;

    // Apply the kill in place only when the payload is well-formed and newer
    // than the stored change. If the flag is absent or the change is stale we
    // still fall through to request a fetch (kill is always followed by one).
    if (changeNumber is int &&
        splitName is String &&
        defaultTreatment is String &&
        changeNumber > _ruleStore.changeNumber()) {
      final existing = _ruleStore.get(splitName);
      if (existing != null) {
        // The store-wide `ff` cursor MUST NOT advance from an in-place kill
        // (spec §10.2): pass the store's OWN current cursor as a no-op, so
        // the on-demand fetch coordinator still sees the kill's
        // changeNumber as "ahead" and converges to it via the follow-up
        // fetch below. The killed split's OWN changeNumber field (set by
        // _killed) still records the kill's real changeNumber.
        _ruleStore.applyChange(
          Change(
            changeNumber: _ruleStore.changeNumber(),
            updates: {
              splitName: _killed(existing, defaultTreatment, changeNumber),
            },
          ),
        );
        didApply = true;
        _onApplied([splitName]);
      }
    }

    // SPLIT_KILL is always followed by a fetch (spec §12.1).
    return FlagUpdateResult(
      outcome: FlagUpdateOutcome.fetchRequired,
      didApplyInPlace: didApply,
    );
  }

  /// Base64-decode → decompress per [c] → utf8 → JSON the `SPLIT_UPDATE`
  /// definition `d`. Returns null when the decoded payload is not a JSON
  /// object.
  Map<String, dynamic>? _decodeDefinition(Object? c, String d) {
    final json = jsonDecode(_payloadDecoder.text(c, d));
    return json is Map<String, dynamic> ? json : null;
  }

  /// Reconstructs [existing] as a killed flag with the given [defaultTreatment]
  /// and [changeNumber]. ParsedSplit is immutable, so a new instance is built
  /// preserving all other fields.
  ParsedSplit _killed(
    ParsedSplit existing,
    String defaultTreatment,
    int changeNumber,
  ) {
    return ParsedSplit(
      name: existing.name,
      trafficTypeName: existing.trafficTypeName,
      killed: true,
      defaultTreatment: defaultTreatment,
      conditions: existing.conditions,
      trafficAllocation: existing.trafficAllocation,
      trafficAllocationSeed: existing.trafficAllocationSeed,
      seed: existing.seed,
      algo: existing.algo,
      changeNumber: changeNumber,
      configurations: existing.configurations,
      prerequisites: existing.prerequisites,
      sets: existing.sets,
      impressionsDisabled: existing.impressionsDisabled,
    );
  }
}
