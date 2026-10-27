import 'package:splitio_commons/src/client/split_manager.dart' as cs;
import 'package:splitio_commons/src/models/split_view.dart';

/// SS-side public manager contract. Mirrors CS's `SplitManager` shape so
/// public API callers see a stable type from `splitio_server_side`.
abstract class SplitManager {
  SplitView? split(String flag);
  List<SplitView> splits();
  List<String> names();
}

class SplitManagerImpl implements SplitManager {
  final cs.SplitManager _delegate;
  SplitManagerImpl(this._delegate);

  @override
  SplitView? split(String flag) => _delegate.split(flag);

  @override
  List<SplitView> splits() => _delegate.splits();

  @override
  List<String> names() => _delegate.names();
}

class _NoOpSplitManager implements SplitManager {
  @override
  SplitView? split(String flag) => null;

  @override
  List<SplitView> splits() => const <SplitView>[];

  @override
  List<String> names() => const <String>[];
}

/// Public accessor for the NoOp manager returned by `_NoOpSplitFactory`.
/// Kept as a top-level function so the private class stays private.
SplitManager noOpSplitManager() => _NoOpSplitManager();
