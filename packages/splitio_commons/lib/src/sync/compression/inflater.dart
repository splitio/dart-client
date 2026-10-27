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
import 'dynamic_tables_reader.dart';
import 'huffman_table.dart';

/// Raw DEFLATE (RFC 1951) decoder: stored, fixed and dynamic Huffman blocks.
///
/// Output is capped at `maxOutputBytes`; exceeding it throws
/// [DecompressionException] (decompression-bomb guard).
class Inflater {
  static const List<int> _lenBase = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, //
    67, 83, 99, 115, 131, 163, 195, 227, 258
  ];
  static const List<int> _lenExtra = [
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, //
    5, 5, 5, 5, 0
  ];
  static const List<int> _distBase = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, //
    769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577
  ];
  static const List<int> _distExtra = [
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, //
    11, 11, 12, 12, 13, 13
  ];

  final Uint8List _data;
  final BitReader _reader;
  final int _maxOutputBytes;
  Uint8List _out;
  int _len = 0;

  /// Prepares to inflate [data] starting at byte offset [start].
  Inflater(Uint8List data, int start, {required int maxOutputBytes})
      : _data = data,
        _reader = BitReader(data, start),
        _maxOutputBytes = maxOutputBytes,
        _out = Uint8List(_initialSize(data.length, maxOutputBytes));

  static int _initialSize(int inputLength, int max) {
    final guess = inputLength * 3 < 256 ? 256 : inputLength * 3;
    return guess < max ? guess : max;
  }

  /// Byte offset just past the last consumed block (valid after [inflate]).
  int get endOffset => _reader.alignedByteOffset;

  /// Inflates all blocks and returns the decompressed bytes.
  Uint8List inflate() {
    var last = false;
    while (!last) {
      last = _reader.read(1) == 1;
      switch (_reader.read(2)) {
        case 0:
          _stored();
        case 1:
          _huffman(HuffmanTable.fixedLiteral, HuffmanTable.fixedDistance);
        case 2:
          final t = DynamicTablesReader(_reader);
          _huffman(t.literal, t.distance);
        default:
          throw const DecompressionException('invalid block type');
      }
    }
    return _out.sublist(0, _len);
  }

  void _stored() {
    final s = _reader.alignedByteOffset;
    if (s + 4 > _data.length) {
      throw const DecompressionException('unexpected end of data');
    }
    final len = _data[s] | (_data[s + 1] << 8);
    final nlen = _data[s + 2] | (_data[s + 3] << 8);
    if (len != (~nlen & 0xFFFF)) {
      throw const DecompressionException('stored block length mismatch');
    }
    final end = s + 4 + len;
    if (end > _data.length) {
      throw const DecompressionException('unexpected end of data');
    }
    _reserve(len);
    _out.setRange(_len, _len + len, _data, s + 4);
    _len += len;
    _reader.seekByte(end);
  }

  void _huffman(HuffmanTable lit, HuffmanTable dist) {
    while (true) {
      final sym = lit.decode(_reader);
      if (sym < 256) {
        _reserve(1);
        _out[_len++] = sym;
      } else if (sym == 256) {
        return;
      } else {
        if (sym > 285) {
          throw const DecompressionException('invalid length symbol');
        }
        final li = sym - 257;
        final length = _lenBase[li] + _reader.read(_lenExtra[li]);
        final ds = dist.decode(_reader);
        if (ds > 29) {
          throw const DecompressionException('invalid distance symbol');
        }
        final distance = _distBase[ds] + _reader.read(_distExtra[ds]);
        _copy(length, distance);
      }
    }
  }

  void _copy(int length, int distance) {
    if (distance > _len) {
      throw const DecompressionException('distance too far back');
    }
    _reserve(length);
    for (var i = 0; i < length; i++) {
      _out[_len] = _out[_len - distance];
      _len++;
    }
  }

  void _reserve(int extra) {
    final needed = _len + extra;
    if (needed > _maxOutputBytes) {
      throw const DecompressionException('output size limit exceeded');
    }
    if (needed > _out.length) {
      var size = _out.length * 2;
      if (size < needed) size = needed;
      if (size > _maxOutputBytes) size = _maxOutputBytes;
      final bigger = Uint8List(size)..setRange(0, _len, _out);
      _out = bigger;
    }
  }
}
