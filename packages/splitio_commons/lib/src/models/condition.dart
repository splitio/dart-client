import 'enums.dart';
import 'matchers/combining_matcher.dart';
import 'partition.dart';

final class TargetingRule {
  final ConditionType conditionType;
  final CombiningMatcher matcher;
  final List<Partition> partitions;
  final String label;

  const TargetingRule({
    required this.conditionType,
    required this.matcher,
    required this.partitions,
    required this.label,
  });
}
