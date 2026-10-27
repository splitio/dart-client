import 'package:splitio_server_side/splitio_server_side.dart';
import 'package:test/test.dart';

void main() {
  test('barrel re-exports BasicSplitClient from commons', () {
    // Compile-time reference — proves the barrel wires through.
    expect(BasicSplitClient, isNotNull);
  });
}
