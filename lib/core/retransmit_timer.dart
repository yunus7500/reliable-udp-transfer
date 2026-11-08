import 'dart:async';

class RetransmitTimer {
  final Duration timeout;
  final int maxRetries;
  final void Function() onTimeout;
  final void Function() onFail;

  Timer? _timer;
  int _retryCount = 0;

  RetransmitTimer({
    required this.timeout,
    required this.maxRetries,
    required this.onTimeout,
    required this.onFail,
  });

  void start() {
    _retryCount = 0;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(timeout, () {
      _retryCount++;
      if (_retryCount > maxRetries) {
        onFail();
      } else {
        onTimeout();
        _schedule();
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
