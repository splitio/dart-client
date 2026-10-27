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

import 'decompressor.dart';

/// LSB-first bit reader over a byte list (RFC 1951 bit order).
///
/// Web safe: reads at most 16 bits at a time from a 24-bit window, so every
/// intermediate value stays below 2^24. Reading past the end of the data
/// throws [DecompressionException]; [peek] zero-fills beyond the end, and the
/// following [skip] detects the overrun.
class BitReader {
  final Uint8List _data;
  final int _totalBits;
  int _pos;

  /// Starts reading at byte offset [startByte] of [data].
  BitReader(this._data, int startByte)
      : _totalBits = _data.length * 8,
        _pos = startByte * 8;

  /// Returns the next [n] bits (0..16) without consuming them.
  int peek(int n) {
    final o = _pos >> 3;
    final len = _data.length;
    final b0 = o < len ? _data[o] : 0;
    final b1 = o + 1 < len ? _data[o + 1] : 0;
    final b2 = o + 2 < len ? _data[o + 2] : 0;
    final window = b0 | (b1 << 8) | (b2 << 16);
    return (window >> (_pos & 7)) & ((1 << n) - 1);
  }

  /// Consumes [n] bits. Throws when that runs past the end of the data.
  void skip(int n) {
    _pos += n;
    if (_pos > _totalBits) {
      throw const DecompressionException('unexpected end of data');
    }
  }

  /// Reads and consumes [n] bits (0..16).
  int read(int n) {
    final v = peek(n);
    skip(n);
    return v;
  }

  /// Byte offset of the next whole byte (rounds the bit position up).
  int get alignedByteOffset => (_pos + 7) >> 3;

  /// Jumps to byte offset [byteOffset].
  void seekByte(int byteOffset) {
    if (byteOffset > _data.length) {
      throw const DecompressionException('unexpected end of data');
    }
    _pos = byteOffset * 8;
  }
}
