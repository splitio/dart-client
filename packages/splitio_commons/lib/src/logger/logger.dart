import 'package:splitio_commons/src/models/log_level.dart';

export 'package:splitio_commons/src/models/log_level.dart';

class SplitLogger {
  final LogLevel _level;

  SplitLogger({LogLevel level = LogLevel.info}) : _level = level;

  bool get isVerboseEnabled => _level == LogLevel.verbose;
  bool get isDebugEnabled =>
      _level != LogLevel.none && _level.index <= LogLevel.debug.index;

  void verbose(String message) => _log(LogLevel.verbose, message);
  void debug(String message) => _log(LogLevel.debug, message);
  void info(String message) => _log(LogLevel.info, message);
  void warning(String message) => _log(LogLevel.warning, message);
  void error(String message, [Object? error]) =>
      _log(LogLevel.error, error != null ? '$message: $error' : message);

  void _log(LogLevel level, String message) {
    if (level.index >= _level.index && _level != LogLevel.none) {
      // ignore: avoid_print
      print('[Split][${level.name.toUpperCase()}] $message');
    }
  }
}
