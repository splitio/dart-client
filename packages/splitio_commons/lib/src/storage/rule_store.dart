import 'package:splitio_commons/src/models/models.dart';

import 'store.dart';

class InMemoryRuleStore extends InMemoryStore<ParsedSplit> {
  List<ParsedSplit> getByFlagSets(List<String> flagSets) {
    final setFilter = flagSets.toSet();
    return getAll()
        .where((split) => split.sets.any((s) => setFilter.contains(s)))
        .toList();
  }

  bool trafficTypeExists(String trafficType) {
    for (final split in getAll()) {
      if (split.trafficTypeName == trafficType) return true;
    }
    return false;
  }
}
