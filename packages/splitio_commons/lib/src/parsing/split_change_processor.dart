import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/storage.dart';

import 'rule_parser.dart';

class SplitChangeProcessor {
  final RuleParser _parser;
  final Store<ParsedSplit> _ruleStore;
  final Store<RuleBasedSegment> _rbsStore;

  SplitChangeProcessor({
    required RuleParser parser,
    required Store<ParsedSplit> ruleStore,
    required Store<RuleBasedSegment> rbsStore,
  })  : _parser = parser,
        _ruleStore = ruleStore,
        _rbsStore = rbsStore;

  ProcessResult processTargetingRules(
    Map<String, dynamic> response,
  ) {
    final changedFlags = <String>[];

    // A response whose `t` is below the stored cursor is stale: typically a
    // fetch that was in flight while newer changes were applied in place via
    // streaming (spec §10.1). Applying it would overwrite newer definitions
    // and roll the cursor back, so the whole section is skipped.
    var ffTill = _ruleStore.changeNumber();
    final ff = response['ff'] as Map<String, dynamic>?;
    if (ff != null && (ff['t'] as int? ?? -1) >= ffTill) {
      final splits = ff['d'] as List? ?? [];
      final till = ff['t'] as int? ?? -1;
      ffTill = till;
      final updates = <String, ParsedSplit?>{};

      for (final raw in splits) {
        final dto = raw as Map<String, dynamic>;
        final name = dto['name'] as String? ?? '';
        final parsed = _parser.parseSplit(dto);
        updates[name] = parsed;
        changedFlags.add(name);
      }

      if (updates.isNotEmpty || till > _ruleStore.changeNumber()) {
        _ruleStore.applyChange(Change(changeNumber: till, updates: updates));
      }
    }

    var rbsChanged = false;
    var rbsTill = _rbsStore.changeNumber();
    final rbs = response['rbs'] as Map<String, dynamic>?;
    if (rbs != null && (rbs['t'] as int? ?? -1) >= rbsTill) {
      final segments = rbs['d'] as List? ?? [];
      final till = rbs['t'] as int? ?? -1;
      rbsTill = till;
      final updates = <String, RuleBasedSegment?>{};

      for (final raw in segments) {
        final dto = raw as Map<String, dynamic>;
        final name = dto['name'] as String? ?? '';
        final parsed = _parser.parseRuleBasedSegment(dto);
        updates[name] = parsed;
      }

      rbsChanged = updates.isNotEmpty;
      if (updates.isNotEmpty || till > _rbsStore.changeNumber()) {
        _rbsStore.applyChange(Change(changeNumber: till, updates: updates));
      }
    }

    return ProcessResult(
      ffTill: ffTill,
      rbsTill: rbsTill,
      changedFlags: changedFlags,
      rbsChanged: rbsChanged,
    );
  }
}

class ProcessResult {
  final int ffTill;
  final int rbsTill;
  final List<String> changedFlags;

  /// Whether this response carried any rule-based segment data (spec
  /// §4.6/§8.2: an rbs-only change still MUST emit `whenUpdated()` — with
  /// an empty payload, same as a plain segment-only change — even when
  /// [changedFlags] is empty.
  final bool rbsChanged;

  const ProcessResult({
    required this.ffTill,
    required this.rbsTill,
    required this.changedFlags,
    this.rbsChanged = false,
  });
}
