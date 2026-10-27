# Third-party notices

## fflate

The pure-Dart gzip/zlib decompressor in `packages/splitio_commons` is a port of
the inflate logic of [fflate](https://github.com/101arrowz/fflate) (via the
trimmed copy in Split's `javascript-commons`, `src/utils/decompress/index.ts`).

Ported files (each carries the notice below in its header):

- `packages/splitio_commons/lib/src/sync/compression/bit_reader.dart`
- `packages/splitio_commons/lib/src/sync/compression/huffman_table.dart`
- `packages/splitio_commons/lib/src/sync/compression/dynamic_tables_reader.dart`
- `packages/splitio_commons/lib/src/sync/compression/inflater.dart`
- `packages/splitio_commons/lib/src/sync/compression/gzip_format.dart`
- `packages/splitio_commons/lib/src/sync/compression/zlib_format.dart`
- `packages/splitio_commons/lib/src/sync/compression/inflate_decompressor.dart`

```
MIT License

Copyright (c) 2020 Arjun Barrett

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
