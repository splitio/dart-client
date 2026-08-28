abstract class PersistentStore {
  Future<List<int>?> load(String key);
  Future<void> save(String key, List<int> data);
}

class NoOpPersistentStore implements PersistentStore {
  @override
  Future<List<int>?> load(String key) async => null;

  @override
  Future<void> save(String key, List<int> data) async {}
}
