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

    final ff = response['ff'] as Map<String, dynamic>?;
    if (ff != null) {
      final splits = ff['d'] as List? ?? [];
      final till = ff['t'] as int? ?? -1;
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

    final rbs = response['rbs'] as Map<String, dynamic>?;
    if (rbs != null) {
      final segments = rbs['d'] as List? ?? [];
      final till = rbs['t'] as int? ?? -1;
      final updates = <String, RuleBasedSegment?>{};

      for (final raw in segments) {
        final dto = raw as Map<String, dynamic>;
        final name = dto['name'] as String? ?? '';
        final parsed = _parser.parseRuleBasedSegment(dto);
        updates[name] = parsed;
      }

      if (updates.isNotEmpty || till > _rbsStore.changeNumber()) {
        _rbsStore.applyChange(Change(changeNumber: till, updates: updates));
      }
    }

    return ProcessResult(
      ffTill: (ff?['t'] as int?) ?? _ruleStore.changeNumber(),
      rbsTill: (rbs?['t'] as int?) ?? _rbsStore.changeNumber(),
      changedFlags: changedFlags,
    );
  }
}

class ProcessResult {
  final int ffTill;
  final int rbsTill;
  final List<String> changedFlags;

  const ProcessResult({
    required this.ffTill,
    required this.rbsTill,
    required this.changedFlags,
  });
}
