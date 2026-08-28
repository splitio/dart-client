import 'dart:convert';

import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/parsing/parsing.dart';
import 'package:splitio_commons/src/storage/storage.dart';

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
/// Decompression is DEFERRED: only `c == 0` (base64-only) `SPLIT_UPDATE`
/// payloads are applied in place. `c == 1` (gzip), `c == 2` (zlib), and unknown
/// compression bytes fall back to fetch (safe default per §12.3).
class FlagUpdateStrategy {
  final InMemoryRuleStore _ruleStore;
  final RuleParser _parser;

  FlagUpdateStrategy({
    required InMemoryRuleStore ruleStore,
    RuleParser? parser,
  })  : _ruleStore = ruleStore,
        _parser = parser ?? RuleParser();

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

    // In-place apply is only safe when the payload is uncompressed (c == 0) and
    // it applies exactly on top of the currently stored change (pcn matches).
    if (changeNumber is! int ||
        pcn is! int ||
        c != 0 ||
        d is! String ||
        pcn != _ruleStore.changeNumber()) {
      return FlagUpdateResult._fetch;
    }

    try {
      final dto = _decodeDefinition(d);
      if (dto == null) return FlagUpdateResult._fetch;
      final name = dto['name'] as String?;
      if (name == null || name.isEmpty) return FlagUpdateResult._fetch;

      // parseSplit returns null for ARCHIVED/inactive splits → remove in place.
      final parsed = _parser.parseSplit(dto);
      _ruleStore.applyChange(
        Change(changeNumber: changeNumber, updates: {name: parsed}),
      );
      return const FlagUpdateResult(
        outcome: FlagUpdateOutcome.appliedInPlace,
        didApplyInPlace: true,
      );
    } catch (_) {
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
        _ruleStore.applyChange(
          Change(
            changeNumber: changeNumber,
            updates: {
              splitName: _killed(existing, defaultTreatment, changeNumber),
            },
          ),
        );
        didApply = true;
      }
    }

    // SPLIT_KILL is always followed by a fetch (spec §12.1).
    return FlagUpdateResult(
      outcome: FlagUpdateOutcome.fetchRequired,
      didApplyInPlace: didApply,
    );
  }

  /// Base64-decode → utf8 → JSON the `SPLIT_UPDATE` definition `d`.
  /// Returns null when the decoded payload is not a JSON object.
  Map<String, dynamic>? _decodeDefinition(String d) {
    final bytes = base64.decode(d);
    final json = jsonDecode(utf8.decode(bytes));
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
