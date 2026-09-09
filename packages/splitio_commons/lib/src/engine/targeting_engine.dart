import 'package:splitio_commons/src/core/core.dart';
import 'package:splitio_commons/src/models/models.dart';

import 'bucketer.dart';
import 'matcher_engine.dart';

class TargetingEngine {
  final Bucketer _bucketer = Bucketer();

  EngineEvaluationResult evaluate(
    String matchingKey,
    String? bucketingKey,
    ParsedSplit rule,
    Attributes attributes,
    EvaluationContext ctx,
  ) {
    if (rule.killed) {
      return EngineEvaluationResult(
          treatment: rule.defaultTreatment,
          label: Labels.killed,
          changeNumber: rule.changeNumber,
          impressionDisabled: rule.impressionsDisabled,
          config: rule.configurations[rule.defaultTreatment]);
    }

    final resolvedBk = bucketingKey ?? matchingKey;

    for (final prerequisite in rule.prerequisites) {
      final result = ctx.evaluate(
        matchingKey,
        resolvedBk,
        prerequisite.featureFlagName,
        attributes,
      );
      if (!prerequisite.treatments.contains(result.treatment)) {
        return EngineEvaluationResult(
            treatment: rule.defaultTreatment,
            label: Labels.prerequisitesNotMet,
            changeNumber: rule.changeNumber,
            impressionDisabled: rule.impressionsDisabled,
            config: rule.configurations[rule.defaultTreatment]);
      }
    }

    bool trafficAllocationChecked = false;

    for (final condition in rule.conditions) {
      if (!trafficAllocationChecked &&
          condition.conditionType == ConditionType.rollout) {
        trafficAllocationChecked = true;
        if (rule.trafficAllocation < 100) {
          final seed = rule.trafficAllocationSeed ?? rule.seed;
          final bucket = _bucketer.getBucket(resolvedBk, seed, rule.algo);
          if (bucket > rule.trafficAllocation) {
            return EngineEvaluationResult(
                treatment: rule.defaultTreatment,
                label: Labels.notInSplit,
                changeNumber: rule.changeNumber,
                impressionDisabled: rule.impressionsDisabled,
                config: rule.configurations[rule.defaultTreatment]);
          }
        }
      }

      final matched = matchCombining(
        condition.matcher,
        matchingKey,
        bucketingKey,
        attributes,
        ctx,
      );

      if (matched) {
        final treatment = _bucketer.getTreatment(
          resolvedBk,
          rule.seed,
          condition.partitions,
          rule.algo,
        );
        return EngineEvaluationResult(
            treatment: treatment,
            label: condition.label,
            impressionDisabled: rule.impressionsDisabled,
            changeNumber: rule.changeNumber,
            config: rule.configurations[treatment]);
      }
    }

    return EngineEvaluationResult(
        treatment: rule.defaultTreatment,
        label: Labels.defaultRule,
        impressionDisabled: rule.impressionsDisabled,
        changeNumber: rule.changeNumber,
        config: rule.configurations[rule.defaultTreatment]);
  }
}
