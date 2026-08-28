class Change<T> {
  final int changeNumber;
  final Map<String, T?> updates;

  const Change({required this.changeNumber, required this.updates});
}

abstract class Store<T> {
  void applyChange(Change<T> change);
  T? get(String key);
  Iterable<T> getAll();
  int changeNumber();
  Future<void> loadLocal();
}

class InMemoryStore<T> implements Store<T> {
  final Map<String, T> _data = {};
  int _changeNumber = -1;

  @override
  void applyChange(Change<T> change) {
    for (final entry in change.updates.entries) {
      if (entry.value == null) {
        _data.remove(entry.key);
      } else {
        _data[entry.key] = entry.value!;
      }
    }
    _changeNumber = change.changeNumber;
  }

  @override
  T? get(String key) => _data[key];

  @override
  Iterable<T> getAll() => _data.values;

  @override
  int changeNumber() => _changeNumber;

  @override
  Future<void> loadLocal() async {}
}
