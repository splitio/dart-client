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
import 'dart:typed_data';

import 'bit_reader.dart';
import 'decompressor.dart';
import 'huffman_table.dart';

/// Reads the code-length header of a dynamic Huffman block (RFC 1951 §3.2.7)
/// and builds its literal/length and distance tables.
class DynamicTablesReader {
  // Order in which code-length code lengths are stored.
  static const List<int> _order = [
    16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 //
  ];

  /// Literal/length table of the block.
  late final HuffmanTable literal;

  /// Distance table of the block.
  late final HuffmanTable distance;

  /// Parses the header at the reader's current position.
  DynamicTablesReader(BitReader r) {
    final hLit = r.read(5) + 257;
    final hDist = r.read(5) + 1;
    final hcLen = r.read(4) + 4;
    if (hLit > 286 || hDist > 30) {
      throw const DecompressionException('invalid dynamic block header');
    }
    final clLengths = Uint8List(19);
    for (var i = 0; i < hcLen; i++) {
      clLengths[_order[i]] = r.read(3);
    }
    final clTable = HuffmanTable.fromLengths(clLengths);
    final total = hLit + hDist;
    final lengths = Uint8List(total);
    var i = 0;
    while (i < total) {
      final sym = clTable.decode(r);
      if (sym < 16) {
        lengths[i++] = sym;
        continue;
      }
      var value = 0;
      int repeat;
      if (sym == 16) {
        if (i == 0) {
          throw const DecompressionException('repeat with no previous length');
        }
        value = lengths[i - 1];
        repeat = 3 + r.read(2);
      } else if (sym == 17) {
        repeat = 3 + r.read(3);
      } else {
        repeat = 11 + r.read(7);
      }
      if (i + repeat > total) {
        throw const DecompressionException('code lengths overflow');
      }
      lengths.fillRange(i, i + repeat, value);
      i += repeat;
    }
    if (lengths[256] == 0) {
      throw const DecompressionException('missing end-of-block code');
    }
    literal = HuffmanTable.fromLengths(Uint8List.sublistView(lengths, 0, hLit));
    distance = HuffmanTable.fromLengths(Uint8List.sublistView(lengths, hLit));
  }
}
