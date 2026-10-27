import 'package:splitio_commons/src/client/client_state.dart';
import 'package:splitio_commons/src/impressions/impressions_manager.dart';
import 'package:splitio_commons/src/input_validation/attributes.dart';
import 'package:splitio_commons/src/input_validation/event_properties.dart';
import 'package:splitio_commons/src/input_validation/flag_name.dart';
import 'package:splitio_commons/src/input_validation/key.dart';
import 'package:splitio_commons/src/input_validation/operational.dart';
import 'package:splitio_commons/src/local/local_evaluator.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/evaluation_options.dart';
import 'package:splitio_commons/src/models/evaluation_result.dart';
import 'package:splitio_commons/src/models/impression.dart';
import 'package:splitio_commons/src/models/key.dart';
import 'package:splitio_commons/src/models/labels.dart';

/// Single-flag evaluation + impression recording shared by both flavors.
/// Holds no per-call state — the owning client's lifecycle is read from the
/// [ClientState] passed in per call.
class TreatmentEvaluator {
  final LocalEvaluator _evaluator;
  final ImpressionsManager _impressions;
  final SplitLogger _log;

  TreatmentEvaluator({
    required LocalEvaluator evaluator,
    required ImpressionsManager impressions,
    required SplitLogger logger,
  })  : _evaluator = evaluator,
        _impressions = impressions,
        _log = logger;

  /// Single-flag pipeline (spec §5, §8.2, §16). Synchronous and MUST NOT throw.
  EvaluationResult evaluate(Key key, String flag, ClientState state,
      {Map<String, Object?>? attributes,
      EvaluationOptions? opts,
      required String method}) {
    try {
      if (state.isClientDestroyed) {
        _log.error(
            '$method: Client has already been destroyed - no calls possible');
        return const EvaluationResult(treatment: 'control');
      }
      final destroyedGuard = validateIfNotDestroyed(
          isDestroyed: state.isEventsDestroyed, method: method);
      if (!destroyedGuard.isValid) {
        _log.error(destroyedGuard.error!);
        return const EvaluationResult(treatment: 'control');
      }
      final keyResult = validateKey(key, method);
      if (!keyResult.isValid) {
        _log.error(keyResult.error!);
        return const EvaluationResult(treatment: 'control');
      }
      // The trimmed key from validateKey MUST be used for evaluation,
      // bucketing, impressions and events (spec §16) — not the raw
      // (possibly untrimmed) `key` passed in.
      final trimmedKey = keyResult.value!.matchingKey;
      final trimmedBucketingKey = keyResult.value!.bucketingKey;

      final flagResult = validateFlagName(flag, method);
      if (!flagResult.isValid) {
        _log.error(flagResult.error!);
        return const EvaluationResult(treatment: 'control');
      }
      if (flagResult.warning != null) _log.warning(flagResult.warning!);
      final flagName = flagResult.value!;

      final attrsResult = validateAttributes(attributes, method);
      if (attrsResult.warning != null) _log.warning(attrsResult.warning!);
      final cleanAttributes = attrsResult.value;

      // Before READY the result is control + `not ready` and still produces
      // an impression (spec §8.2, javascript-commons sdkClient/client.ts).
      if (!state.isReady) {
        _recordImpression(
          flag: flagName,
          treatment: 'control',
          label: Labels.notReady,
          changeNumber: null,
          matchingKey: trimmedKey,
          bucketingKey: trimmedBucketingKey,
          attributes: cleanAttributes,
          opts: opts,
          method: method,
          impressionsDisabled: false,
        );
        return const EvaluationResult(treatment: 'control');
      }

      final engineResult = _evaluator.evaluate(
        trimmedKey,
        trimmedBucketingKey,
        flagName,
        cleanAttributes ?? const {},
      );

      if (engineResult == null) {
        _log.warning(
            '$method: "$flagName" does not exist in this environment.');
        return const EvaluationResult(treatment: 'control');
      }

      _recordImpression(
        flag: flagName,
        treatment: engineResult.treatment,
        label: engineResult.label,
        changeNumber: engineResult.changeNumber,
        matchingKey: trimmedKey,
        bucketingKey: trimmedBucketingKey,
        attributes: cleanAttributes,
        opts: opts,
        method: method,
        impressionsDisabled: engineResult.impressionDisabled,
      );

      return EvaluationResult(
        treatment: engineResult.treatment,
        config: engineResult.config,
      );
    } catch (e, s) {
      _log.error('$method: error evaluating flag "$flag"', '$e\n$s');
      return const EvaluationResult(treatment: 'control');
    }
  }

  void _recordImpression({
    required String flag,
    required String treatment,
    required String label,
    required int? changeNumber,
    required String matchingKey,
    required String? bucketingKey,
    required Map<String, Object?>? attributes,
    required EvaluationOptions? opts,
    required String method,
    required bool impressionsDisabled,
  }) {
    final keyImpression = KeyImpression(
      feature: flag,
      keyName: matchingKey,
      bucketingKey: bucketingKey,
      treatment: treatment,
      label: label,
      changeNumber: changeNumber,
      time: DateTime.now().millisecondsSinceEpoch,
      properties: validateEvaluationProperties(opts?.properties,
          method: method, onWarning: _log.warning, onError: _log.error),
    );
    _impressions.record(
        keyImpression, impressionsDisabled, attributes ?? const {});
  }
}
