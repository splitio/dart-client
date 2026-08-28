import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/storage.dart';

import 'matcher_parser.dart';

class RuleParser {
  final MatcherParser _matcherParser = MatcherParser();

  ParsedSplit? parseSplit(Map<String, dynamic> dto) {
    final status = dto['status'] as String?;
    if (status == 'ARCHIVED') return null;

    final name = dto['name'] as String? ?? '';
    final conditions = _parseConditions(dto['conditions'] as List? ?? []);
    if (conditions == null) {
      return _unsupportedTemplate(dto);
    }

    return ParsedSplit(
      name: name,
      trafficTypeName: dto['trafficTypeName'] as String? ?? '',
      killed: dto['killed'] as bool? ?? false,
      defaultTreatment: dto['defaultTreatment'] as String? ?? 'control',
      conditions: conditions,
      trafficAllocation: dto['trafficAllocation'] as int? ?? 100,
      trafficAllocationSeed: dto['trafficAllocationSeed'] as int?,
      seed: dto['seed'] as int? ?? 0,
      algo: dto['algo'] as int? ?? 2,
      changeNumber: dto['changeNumber'] as int? ?? 0,
      configurations: _parseConfigs(dto['configurations']),
      prerequisites: _parsePrerequisites(dto['prerequisites'] as List?),
      sets: (dto['sets'] as List?)?.cast<String>() ?? [],
      impressionsDisabled: dto['impressionsDisabled'] as bool? ?? false,
    );
  }

  RuleBasedSegment? parseRuleBasedSegment(Map<String, dynamic> dto) {
    final status = dto['status'] as String?;
    if (status == 'ARCHIVED') return null;

    final name = dto['name'] as String? ?? '';
    final conditions = _parseConditions(dto['conditions'] as List? ?? []);

    return RuleBasedSegment(
      name: name,
      conditions: conditions ?? [],
      changeNumber: dto['changeNumber'] as int? ?? 0,
      excluded: _parseExcluded(dto['excluded']),
    );
  }

  RbsExcluded _parseExcluded(Object? data) {
    if (data is! Map<String, dynamic>) return const RbsExcluded();
    final keys = (data['keys'] as List?)?.cast<String>().toSet() ?? const {};
    final segments = (data['segments'] as List? ?? []).map((s) {
      final map = s as Map<String, dynamic>;
      return ExcludedSegment(
        type: map['type'] as String? ?? '',
        name: map['name'] as String? ?? '',
      );
    }).toList();
    return RbsExcluded(keys: keys, segments: segments);
  }

  List<TargetingRule>? _parseConditions(List conditions) {
    final result = <TargetingRule>[];
    for (final c in conditions) {
      final map = c as Map<String, dynamic>;
      final rule = _parseCondition(map);
      if (rule == null) return null;
      result.add(rule);
    }
    return result;
  }

  TargetingRule? _parseCondition(Map<String, dynamic> dto) {
    final condType = dto['conditionType'] as String? ?? 'ROLLOUT';
    final label = dto['label'] as String? ?? '';
    final partitions = _parsePartitions(dto['partitions'] as List? ?? []);

    final matcherGroup = dto['matcherGroup'] as Map<String, dynamic>?;
    if (matcherGroup == null) return null;

    final matchers = matcherGroup['matchers'] as List? ?? [];
    if (matchers.isEmpty) return null;

    final delegates = <AttributeMatcher>[];
    for (final m in matchers) {
      final cm = _parseMatcher(m as Map<String, dynamic>);
      if (cm == null) return null;
      delegates.add(cm);
    }

    return TargetingRule(
      conditionType: condType == 'WHITELIST'
          ? ConditionType.whitelist
          : ConditionType.rollout,
      matcher: CombiningMatcher(
        combiner: _parseCombiner(matcherGroup['combiner'] as String?),
        delegates: delegates,
      ),
      partitions: partitions,
      label: label,
    );
  }

  AttributeMatcher? _parseMatcher(Map<String, dynamic> dto) {
    final matcherType = dto['matcherType'] as String?;
    final negate = dto['negate'] as bool? ?? false;

    final keySelector = dto['keySelector'] as Map<String, dynamic>?;
    final attribute = keySelector?['attribute'] as String?;

    final delegate = _matcherParser.parseMatcherType(matcherType, dto);
    if (delegate == null) return null;

    return AttributeMatcher(
      delegate: delegate,
      negate: negate,
      attribute: attribute,
    );
  }

  CombinerEnum _parseCombiner(String? value) {
    // Only AND is used by the backend today; default to it for anything else.
    return CombinerEnum.and;
  }

  List<Partition> _parsePartitions(List partitions) {
    return partitions.map((p) {
      final map = p as Map<String, dynamic>;
      return Partition(
        treatment: map['treatment'] as String? ?? 'control',
        size: map['size'] as int? ?? 0,
      );
    }).toList();
  }

  List<Prerequisite> _parsePrerequisites(List? prerequisites) {
    if (prerequisites == null) return [];
    return prerequisites.map((p) {
      final map = p as Map<String, dynamic>;
      return Prerequisite(
        featureFlagName:
            map['n'] as String? ?? map['featureFlagName'] as String? ?? '',
        treatments: (map['ts'] as List? ?? map['treatments'] as List?)
                ?.cast<String>() ??
            [],
      );
    }).toList();
  }

  Map<String, String> _parseConfigs(Object? configs) {
    if (configs is Map<String, dynamic>) {
      return configs.map((k, v) => MapEntry(k, v.toString()));
    }
    return {};
  }

  ParsedSplit _unsupportedTemplate(Map<String, dynamic> dto) {
    return ParsedSplit(
      name: dto['name'] as String? ?? '',
      trafficTypeName: dto['trafficTypeName'] as String? ?? '',
      killed: false,
      defaultTreatment: 'control',
      conditions: [
        TargetingRule(
          conditionType: ConditionType.rollout,
          matcher: const CombiningMatcher(
            delegates: [AttributeMatcher(delegate: AllKeysMatcher())],
          ),
          partitions: [const Partition(treatment: 'control', size: 100)],
          label: Labels.unsupportedMatcher,
        ),
      ],
      trafficAllocation: 100,
      seed: dto['seed'] as int? ?? 0,
      algo: dto['algo'] as int? ?? 2,
      changeNumber: dto['changeNumber'] as int? ?? 0,
      sets: (dto['sets'] as List?)?.cast<String>() ?? [],
    );
  }
}
