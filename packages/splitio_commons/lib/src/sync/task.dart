import 'dart:async';

abstract class Task {
  final int pushRateSeconds;
  Timer? _timer;

  Task({
    required this.pushRateSeconds,
  });

  Future<bool> execute();

  void start() {
    _timer = Timer.periodic(
      Duration(seconds: pushRateSeconds),
      (_) => execute(),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
