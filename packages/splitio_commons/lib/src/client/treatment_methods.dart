import 'package:splitio_commons/src/client/client_state.dart';
import 'package:splitio_commons/src/client/treatment_evaluator.dart';
import 'package:splitio_commons/src/input_validation/flag_names.dart';
import 'package:splitio_commons/src/input_validation/flag_set.dart';
import 'package:splitio_commons/src/input_validation/key.dart';
import 'package:splitio_commons/src/input_validation/operational.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/evaluation_options.dart';
import 'package:splitio_commons/src/models/evaluation_result.dart';
import 'package:splitio_commons/src/models/key.dart';
import 'package:splitio_commons/src/storage/rule_store.dart';

/// Shared `getTreatment*` pipelines for both flavors (key first, as in JS
/// `client.ts`). The string-returning public variants map `.treatment` over
/// these results in the adapter. [method] is the public method name and
/// drives every log message. Per call the order is: key guard (flag sets
/// only), list validation, validation warning, not-ready warning, READY
/// short-circuit (flag sets only), evaluation.
class TreatmentMethods {
  final TreatmentEvaluator _evaluator;
  final InMemoryRuleStore _ruleStore;
  final SplitLogger _log;

  TreatmentMethods({
    required TreatmentEvaluator evaluator,
    required InMemoryRuleStore ruleStore,
    required SplitLogger logger,
  })  : _evaluator = evaluator,
        _ruleStore = ruleStore,
        _log = logger;

  /// Single flag.
  EvaluationResult treatment(Key key, String flag, ClientState state,
      {Map<String, Object?>? attributes,
      EvaluationOptions? opts,
      required String method}) {
    _warnIfNotReady(state, method);
    return _evaluator.evaluate(key, flag, state,
        attributes: attributes, opts: opts, method: method);
  }

  /// List of flag names. An invalid list yields `{}`.
  Map<String, EvaluationResult> treatments(
      Key key, List<String> flags, ClientState state,
      {Map<String, Object?>? attributes,
      EvaluationOptions? opts,
      required String method}) {
    final validated = validateFlagNames(flags, method, onError: _log.error);
    if (!validated.isValid) {
      _log.error(validated.error!);
      return <String, EvaluationResult>{};
    }
    if (validated.warning != null) _log.warning(validated.warning!);
    _warnIfNotReady(state, method);
    return {
      for (final f in validated.value!)
        f: _evaluator.evaluate(key, f, state,
            attributes: attributes, opts: opts, method: method)
    };
  }

  /// Flag sets. Invalid key (SS only) or invalid sets yield `{}`; nothing
  /// resolves before READY, so nothing is evaluated or recorded (spec §8.2).
  Map<String, EvaluationResult> treatmentsByFlagSets(
      Key key, List<String> flagSets, ClientState state,
      {Map<String, Object?>? attributes,
      EvaluationOptions? opts,
      required String method}) {
    final keyGuard = validateKey(key, method);
    if (!keyGuard.isValid) {
      _log.error(keyGuard.error!);
      return <String, EvaluationResult>{};
    }
    final validated = validateFlagSets(flagSets, method);
    if (!validated.isValid) {
      _log.error(validated.error!);
      return <String, EvaluationResult>{};
    }
    if (validated.warning != null) _log.warning(validated.warning!);
    _warnIfNotReady(state, method);
    if (!state.isReady) return <String, EvaluationResult>{};
    return {
      for (final s in _ruleStore.getByFlagSets(validated.value!))
        s.name: _evaluator.evaluate(key, s.name, state,
            attributes: attributes, opts: opts, method: method)
    };
  }

  /// Logs the JS-parity "not ready" warning once per public call.
  void _warnIfNotReady(ClientState state, String method) {
    final r = validateIfReady(isReady: state.isReady, method: method);
    if (!r.isValid) _log.warning(r.error!);
  }
}
