import 'package:splitio_commons/src/core/core.dart';
import 'package:splitio_commons/src/models/models.dart';

class Bucketer {
  int getBucket(String key, int seed, int algo) {
    final hash = algo == 2 ? _murmurHash(key, seed) : _legacyHash(key, seed);
    return (hash % 100) + 1;
  }

  String getTreatment(
    String key,
    int seed,
    List<Partition> partitions,
    int algo,
  ) {
    if (partitions.isEmpty) return 'control';
    if (partitions.length == 1 && partitions[0].size == 100) {
      return partitions[0].treatment;
    }

    final bucket = getBucket(key, seed, algo);
    int covered = 0;
    for (final partition in partitions) {
      covered += partition.size;
      if (covered >= bucket) {
        return partition.treatment;
      }
    }
    return 'control';
  }

  int _murmurHash(String key, int seed) => murmurhash3X8632(key, seed);

  int _legacyHash(String key, int seed) {
    int h = 0;
    for (int i = 0; i < key.length; i++) {
      h = ((31 * h) + key.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return (h ^ (seed & 0xFFFFFFFF)) & 0xFFFFFFFF;
  }
}
