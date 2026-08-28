import 'package:splitio_commons/src/input_validation/flag_name.dart';
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

  SplitManagerImpl({
    required InMemoryRuleStore ruleStore,
    required SplitLogger logger,
  })  : _ruleStore = ruleStore,
        _log = logger;

  @override
  SplitView? split(String flag) {
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
  List<SplitView> splits() => _ruleStore.getAll().map(_toView).toList();

  @override
  List<String> names() => _ruleStore.getAll().map((s) => s.name).toList();

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
