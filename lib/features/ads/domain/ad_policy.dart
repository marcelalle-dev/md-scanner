/// Decides when an interstitial may be shown. Pure logic, no SDK.
///
/// Rules:
/// - never for Premium users;
/// - only at a natural break, after a task the user completed (an export, a
///   PDF tool) — never before or during one, never during capture;
/// - none in the first minute of a session;
/// - at least [minInterval] and [tasksBetween] completed tasks between two;
/// - at most [maxPerSession] per session.
class AdPolicy {
  AdPolicy({DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    _sessionStart = _clock();
  }

  final DateTime Function() _clock;
  late final DateTime _sessionStart;
  DateTime? _lastShown;
  int _tasksSinceLast = 0;
  int _shown = 0;

  static const Duration warmUp = Duration(minutes: 1);
  static const Duration minInterval = Duration(minutes: 3);
  static const int tasksBetween = 3;
  static const int maxPerSession = 4;

  /// Call when the user finished a task (document saved, tool completed).
  void taskCompleted() => _tasksSinceLast++;

  bool canShowInterstitial({required bool isPremium}) {
    if (isPremium || _shown >= maxPerSession) return false;
    final now = _clock();
    if (now.difference(_sessionStart) < warmUp) return false;
    if (_tasksSinceLast < tasksBetween) return false;
    final last = _lastShown;
    return last == null || now.difference(last) >= minInterval;
  }

  void interstitialShown() {
    _lastShown = _clock();
    _tasksSinceLast = 0;
    _shown++;
  }
}
