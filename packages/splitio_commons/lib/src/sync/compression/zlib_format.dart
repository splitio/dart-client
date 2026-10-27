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

import 'adler32.dart';
import 'decompressor.dart';
import 'inflater.dart';

/// zlib container (RFC 1950): header validation, inflate, Adler-32 check.
class ZlibFormat {
  /// Output limit forwarded to the [Inflater].
  final int maxOutputBytes;

  const ZlibFormat({required this.maxOutputBytes});

  /// Decodes a complete zlib stream. Throws [DecompressionException] on any
  /// malformed, truncated or corrupt input.
  Uint8List decode(Uint8List d) {
    if (d.length < 6) {
      throw const DecompressionException('zlib data too short');
    }
    if ((d[0] & 15) != 8 || (d[0] >> 4) > 7 || ((d[0] << 8 | d[1]) % 31) != 0) {
      throw const DecompressionException('invalid zlib data');
    }
    if (d[1] & 32 != 0) {
      throw const DecompressionException(
          'invalid zlib data: preset dictionaries not supported');
    }
    final inflater = Inflater(d, 2, maxOutputBytes: maxOutputBytes);
    final out = inflater.inflate();
    final t = inflater.endOffset;
    if (t + 4 != d.length) {
      throw const DecompressionException('invalid zlib trailer');
    }
    final expected =
        d[t] * 16777216 + d[t + 1] * 65536 + d[t + 2] * 256 + d[t + 3];
    if (expected != Adler32.of(out)) {
      throw const DecompressionException('zlib Adler-32 mismatch');
    }
    return out;
  }
}
