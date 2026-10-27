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

import 'crc32.dart';
import 'decompressor.dart';
import 'inflater.dart';

/// gzip container (RFC 1952): header parsing, inflate, CRC-32 + ISIZE check.
class GzipFormat {
  /// Output limit forwarded to the [Inflater].
  final int maxOutputBytes;

  const GzipFormat({required this.maxOutputBytes});

  /// Decodes a complete single-member gzip stream. Throws
  /// [DecompressionException] on any malformed, truncated or corrupt input.
  Uint8List decode(Uint8List d) {
    final start = _headerLength(d);
    final inflater = Inflater(d, start, maxOutputBytes: maxOutputBytes);
    final out = inflater.inflate();
    final t = inflater.endOffset;
    if (t + 8 != d.length) {
      throw const DecompressionException('invalid gzip trailer');
    }
    if (_u32(d, t) != Crc32.of(out)) {
      throw const DecompressionException('gzip CRC-32 mismatch');
    }
    if (_u32(d, t + 4) != out.length & 0xFFFFFFFF) {
      throw const DecompressionException('gzip ISIZE mismatch');
    }
    return out;
  }

  static int _u32(Uint8List d, int o) =>
      d[o] + d[o + 1] * 256 + d[o + 2] * 65536 + d[o + 3] * 16777216;

  static int _headerLength(Uint8List d) {
    if (d.length < 18) {
      throw const DecompressionException('gzip data too short');
    }
    if (d[0] != 0x1F || d[1] != 0x8B || d[2] != 8) {
      throw const DecompressionException('invalid gzip data');
    }
    final flg = d[3];
    if (flg & 0xE0 != 0) {
      throw const DecompressionException('invalid gzip flags');
    }
    var p = 10;
    if (flg & 4 != 0) {
      if (p + 2 > d.length) {
        throw const DecompressionException('unexpected end of data');
      }
      p += 2 + (d[p] | (d[p + 1] << 8));
    }
    for (final bit in const [8, 16]) {
      if (flg & bit == 0) continue;
      while (p < d.length && d[p] != 0) {
        p++;
      }
      p++;
    }
    if (flg & 2 != 0) p += 2;
    if (p > d.length) {
      throw const DecompressionException('unexpected end of data');
    }
    return p;
  }
}
