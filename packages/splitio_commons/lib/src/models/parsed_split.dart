import 'condition.dart';

final class Prerequisite {
  final String featureFlagName;
  final List<String> treatments;

  const Prerequisite({
    required this.featureFlagName,
    required this.treatments,
  });
}

final class ParsedSplit {
  final String name;
  final String trafficTypeName;
  final bool killed;
  final String defaultTreatment;
  final List<TargetingRule> conditions;
  final int trafficAllocation;
  final int? trafficAllocationSeed;
  final int seed;
  final int algo;
  final int changeNumber;
  final Map<String, String> configurations;
  final List<Prerequisite> prerequisites;
  final List<String> sets;
  final bool impressionsDisabled;

  const ParsedSplit({
    required this.name,
    required this.trafficTypeName,
    required this.killed,
    required this.defaultTreatment,
    required this.conditions,
    required this.trafficAllocation,
    this.trafficAllocationSeed,
    required this.seed,
    required this.algo,
    required this.changeNumber,
    this.configurations = const {},
    this.prerequisites = const [],
    this.sets = const [],
    this.impressionsDisabled = false,
  });
}
