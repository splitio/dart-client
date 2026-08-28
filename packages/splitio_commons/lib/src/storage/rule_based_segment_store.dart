import 'package:splitio_commons/src/models/models.dart';

import 'store.dart';

final class ExcludedSegment {
  final String type;
  final String name;

  const ExcludedSegment({required this.type, required this.name});

  bool get isStandard => type == 'standard';
  bool get isRuleBased => type == 'rule-based';
}

final class RbsExcluded {
  final Set<String> keys;
  final List<ExcludedSegment> segments;

  const RbsExcluded({this.keys = const {}, this.segments = const []});
}

final class RuleBasedSegment {
  final String name;
  final List<TargetingRule> conditions;
  final int changeNumber;
  final RbsExcluded excluded;

  const RuleBasedSegment({
    required this.name,
    required this.conditions,
    required this.changeNumber,
    this.excluded = const RbsExcluded(),
  });
}

class InMemoryRuleBasedSegmentStore extends InMemoryStore<RuleBasedSegment> {}
