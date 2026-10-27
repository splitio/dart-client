import 'package:splitio_commons/src/input_validation/flag_name.dart';
import 'package:splitio_commons/src/input_validation/operational.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/split_view.dart';
import 'package:splitio_commons/src/models/parsed_split.dart';
import 'package:splitio_commons/src/storage/rule_store.dart';

abstract class SplitManager {
  SplitView? split(String flag);
  List<SplitView> splits();
  List<String> names();
}

class SplitManagerImpl implements SplitManager {
  final InMemoryRuleStore _ruleStore;
  final SplitLogger _log;
  final bool Function() _isDestroyed;

  /// [isDestroyed] reports whether the owning factory has been destroyed.
  /// After that, the manager returns null/empty and logs an ERROR (spec
  /// §7.1); destroying an individual client does not affect it.
  SplitManagerImpl({
    required InMemoryRuleStore ruleStore,
    required SplitLogger logger,
    bool Function()? isDestroyed,
  })  : _ruleStore = ruleStore,
        _log = logger,
        _isDestroyed = isDestroyed ?? _never;

  static bool _never() => false;

  bool _destroyedFor(String method) {
    final r =
        validateIfNotDestroyed(isDestroyed: _isDestroyed(), method: method);
    if (r.isValid) return false;
    _log.error(r.error!);
    return true;
  }

  @override
  SplitView? split(String flag) {
    if (_destroyedFor('split')) return null;
    final r = validateFlagName(flag, 'split');
    if (!r.isValid) {
      _log.error(r.error!);
      return null;
    }
    if (r.warning != null) _log.warning(r.warning!);
    final parsed = _ruleStore.get(r.value!);
    if (parsed == null) {
      _log.warning('split: "${r.value!}" does not exist in this environment.');
      return null;
    }
    return _toView(parsed);
  }

  @override
  List<SplitView> splits() {
    if (_destroyedFor('splits')) return <SplitView>[];
    return _ruleStore.getAll().map(_toView).toList();
  }

  @override
  List<String> names() {
    if (_destroyedFor('names')) return <String>[];
    return _ruleStore.getAll().map((s) => s.name).toList();
  }

  SplitView _toView(ParsedSplit parsed) {
    final treatments = <String>{};
    for (final condition in parsed.conditions) {
      for (final partition in condition.partitions) {
        treatments.add(partition.treatment);
      }
    }
    treatments.add(parsed.defaultTreatment);

    return SplitView(
      name: parsed.name,
      trafficType: parsed.trafficTypeName,
      killed: parsed.killed,
      treatments: treatments.toList(),
      changeNumber: parsed.changeNumber,
      configs: parsed.configurations,
      defaultTreatment: parsed.defaultTreatment,
      sets: parsed.sets,
      impressionsDisabled: parsed.impressionsDisabled,
    );
  }
}
