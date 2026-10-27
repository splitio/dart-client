// Ported from "fflate" (https://github.com/101arrowz/fflate), via the trimmed
// copy in javascript-commons (src/utils/decompress/index.ts).
//
// MIT License
//
// Copyright (c) 2020 Arjun Barrett
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import 'dart:typed_data';

import 'bit_reader.dart';
import 'decompressor.dart';

/// Canonical Huffman decode table built from code lengths (RFC 1951 §3.2.2).
///
/// A single lookup table of `1 << maxBits` entries is indexed by the next
/// [maxBits] bits; each entry is `(symbol << 4) | codeLength`, and `0` marks
/// an unused code.
class HuffmanTable {
  /// Longest code length in the table (0 when no code is defined).
  final int maxBits;
  final Uint16List _table;

  HuffmanTable._(this.maxBits, this._table);

  /// Builds a table from [lengths] (index = symbol, value = code length,
  /// 0 = unused). Throws when the lengths over-subscribe the code space.
  factory HuffmanTable.fromLengths(Uint8List lengths) {
    var maxBits = 0;
    final counts = Uint16List(16);
    for (final l in lengths) {
      counts[l]++;
      if (l > maxBits) maxBits = l;
    }
    counts[0] = 0;
    final next = Uint16List(16);
    var code = 0;
    for (var bits = 1; bits <= 15; bits++) {
      code = (code + counts[bits - 1]) << 1;
      next[bits] = code;
      if (code + counts[bits] > (1 << bits)) {
        throw const DecompressionException('over-subscribed Huffman code');
      }
    }
    final table = Uint16List(1 << maxBits);
    for (var sym = 0; sym < lengths.length; sym++) {
      final len = lengths[sym];
      if (len == 0) continue;
      final reversed = _reverse(next[len]++, len);
      final entry = (sym << 4) | len;
      for (var i = reversed; i < table.length; i += 1 << len) {
        table[i] = entry;
      }
    }
    return HuffmanTable._(maxBits, table);
  }

  static HuffmanTable? _fixedLiteral;
  static HuffmanTable? _fixedDistance;

  /// The fixed literal/length table of block type 1.
  static HuffmanTable get fixedLiteral =>
      _fixedLiteral ??= HuffmanTable.fromLengths(Uint8List(288)
        ..fillRange(0, 144, 8)
        ..fillRange(144, 256, 9)
        ..fillRange(256, 280, 7)
        ..fillRange(280, 288, 8));

  /// The fixed distance table of block type 1.
  static HuffmanTable get fixedDistance => _fixedDistance ??=
      HuffmanTable.fromLengths(Uint8List(32)..fillRange(0, 32, 5));

  /// Decodes and consumes the next symbol from [reader]. Throws on an
  /// unused code or when the data ends mid-code.
  int decode(BitReader reader) {
    final entry = _table[reader.peek(maxBits)];
    if (entry == 0) {
      throw const DecompressionException('invalid Huffman code');
    }
    reader.skip(entry & 15);
    return entry >> 4;
  }

  static int _reverse(int code, int len) {
    var r = 0;
    for (var i = 0; i < len; i++) {
      r = (r << 1) | (code & 1);
      code >>= 1;
    }
    return r;
  }
}
