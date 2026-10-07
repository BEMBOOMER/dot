import 'dart:collection';

/// Sliding one-second window, measured on arrival using a monotonic clock.
class InputRateLimiter {
  static const limit = 240;
  final Duration Function() _now;
  final Queue<int> _arrivals = Queue();

  InputRateLimiter({Duration Function()? clock}) : _now = clock ?? _clock();

  static Duration Function() _clock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  bool allow() {
    final now = _now().inMicroseconds;
    while (_arrivals.isNotEmpty && now - _arrivals.first >= 1000000) {
      _arrivals.removeFirst();
    }
    if (_arrivals.length >= limit) return false;
    _arrivals.addLast(now);
    return true;
  }
}
