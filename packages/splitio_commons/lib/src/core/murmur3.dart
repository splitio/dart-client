import 'dart:convert';

int murmurhash3X8632(String key, int seed) {
  final data = utf8.encode(key);
  final len = data.length;
  final nblocks = len ~/ 4;

  int h1 = seed;
  const c1 = 0xcc9e2d51;
  const c2 = 0x1b873593;

  for (int i = 0; i < nblocks; i++) {
    int k1 = (data[i * 4]) |
        (data[i * 4 + 1] << 8) |
        (data[i * 4 + 2] << 16) |
        (data[i * 4 + 3] << 24);

    k1 = _multiply(k1, c1);
    k1 = _rotl32(k1, 15);
    k1 = _multiply(k1, c2);

    h1 ^= k1;
    h1 = _rotl32(h1, 13);
    h1 = _multiply(h1, 5) + 0xe6546b64;
  }

  int k1 = 0;
  final tail = nblocks * 4;
  switch (len & 3) {
    case 3:
      k1 ^= data[tail + 2] << 16;
      k1 ^= data[tail + 1] << 8;
      k1 ^= data[tail];
      k1 = _multiply(k1, c1);
      k1 = _rotl32(k1, 15);
      k1 = _multiply(k1, c2);
      h1 ^= k1;
    case 2:
      k1 ^= data[tail + 1] << 8;
      k1 ^= data[tail];
      k1 = _multiply(k1, c1);
      k1 = _rotl32(k1, 15);
      k1 = _multiply(k1, c2);
      h1 ^= k1;
    case 1:
      k1 ^= data[tail];
      k1 = _multiply(k1, c1);
      k1 = _rotl32(k1, 15);
      k1 = _multiply(k1, c2);
      h1 ^= k1;
  }

  h1 ^= len;
  h1 = _fmix32(h1);

  return h1 & 0xFFFFFFFF;
}

int _rotl32(int x, int r) {
  x &= 0xFFFFFFFF;
  return ((x << r) | (x >>> (32 - r))) & 0xFFFFFFFF;
}

int _multiply(int a, int b) {
  // 32-bit multiplication
  a &= 0xFFFFFFFF;
  b &= 0xFFFFFFFF;
  final ah = (a >>> 16) & 0xFFFF;
  final al = a & 0xFFFF;
  final bh = (b >>> 16) & 0xFFFF;
  final bl = b & 0xFFFF;
  return ((al * bl) + (((ah * bl + al * bh) & 0xFFFF) << 16)) & 0xFFFFFFFF;
}

int _fmix32(int h) {
  h &= 0xFFFFFFFF;
  h ^= h >>> 16;
  h = _multiply(h, 0x85ebca6b);
  h ^= h >>> 13;
  h = _multiply(h, 0xc2b2ae35);
  h ^= h >>> 16;
  return h & 0xFFFFFFFF;
}
