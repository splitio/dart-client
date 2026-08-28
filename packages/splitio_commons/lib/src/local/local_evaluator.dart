import 'package:splitio_commons/src/engine/engine.dart';
import 'package:splitio_commons/src/models/models.dart' hide EvaluationResult;
import 'package:splitio_commons/src/storage/storage.dart';

class LocalEvaluator {
  final TargetingEngine _engine;
  final InMemoryRuleStore _ruleStore;
  final InMemoryRuleBasedSegmentStore _rbsStore;
  final InMemoryMembershipStore _membershipStore;

  LocalEvaluator({
    required TargetingEngine engine,
    required InMemoryRuleStore ruleStore,
    required InMemoryRuleBasedSegmentStore rbsStore,
    required InMemoryMembershipStore membershipStore,
  })  : _engine = engine,
        _ruleStore = ruleStore,
        _rbsStore = rbsStore,
        _membershipStore = membershipStore;

  EngineEvaluationResult? evaluate(
    String matchingKey,
    String? bucketingKey,
    String flag,
    Attributes attributes,
  ) {
    try {
      final rule = _ruleStore.get(flag);
      if (rule == null) return null;

      final ctx = _LocalEvaluationContext(
        engine: _engine,
        ruleStore: _ruleStore,
        rbsStore: _rbsStore,
        membershipStore: _membershipStore,
        );

      return _engine.evaluate(matchingKey, bucketingKey, rule, attributes, ctx);
    } catch (e) {
      return const EngineEvaluationResult(
        treatment: 'control',
        label: Labels.exception,
        impressionDisabled: false,
        changeNumber: -1,
      );
    }
  }

  ParsedSplit? getRule(String flag) => _ruleStore.get(flag);
}

class _LocalEvaluationContext implements EvaluationContext {
  final TargetingEngine _engine;
  final InMemoryRuleStore _ruleStore;
  final InMemoryRuleBasedSegmentStore _rbsStore;
  final InMemoryMembershipStore _membershipStore;

  _LocalEvaluationContext({
    required TargetingEngine engine,
    required InMemoryRuleStore ruleStore,
    required InMemoryRuleBasedSegmentStore rbsStore,
    required InMemoryMembershipStore membershipStore,
  })  : _engine = engine,
        _ruleStore = ruleStore,
        _rbsStore = rbsStore,
        _membershipStore = membershipStore;

  @override
  EvaluationResult evaluate(
    String matchingKey,
    String bucketingKey,
    String ruleName,
    Map<String, Object?> attributes,
  ) {
    final rule = _ruleStore.get(ruleName);
    if (rule == null) {
      return (treatment: 'control', label: Labels.definitionNotFound);
    }
    final result =
        _engine.evaluate(matchingKey, bucketingKey, rule, attributes, this);
    return (treatment: result.treatment, label: result.label);
  }

  @override
  bool isInSegment(String segmentName, String key) {
    return _membershipStore.isInSegment(segmentName, key);
  }

  @override
  bool isInRuleBasedSegment(
    String segmentName,
    String key,
    String bucketingKey,
    Map<String, Object?> attributes,
  ) {
    final rbs = _rbsStore.get(segmentName);
    if (rbs == null) return false;

    if (rbs.excluded.keys.contains(key)) return false;

    for (final seg in rbs.excluded.segments) {
      if (seg.isStandard && isInSegment(seg.name, key)) {
        return false;
      }
      if (seg.isRuleBased &&
          isInRuleBasedSegment(seg.name, key, bucketingKey, attributes)) {
        return false;
      }
    }

    for (final condition in rbs.conditions) {
      final matched = matchCombining(
        condition.matcher,
        key,
        bucketingKey,
        attributes,
        this,
      );
      if (matched) return true;
    }
    return false;
  }
}
