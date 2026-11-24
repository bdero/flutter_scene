import 'dart:async';
import 'dart:math' as math;

/// How long a rate-limited web `SceneView` stops its ticker after a frame,
/// waking a margin of `1.25 * vsync` (at least 6 ms, so a late timer still
/// lands before the target vsync) ahead of the next deadline ([remaining],
/// defaulting to [targetPeriod]). Null when waking that early would not skip
/// a vsync, no skipped vsync has confirmed a mismatch yet, or too little time
/// remains to sleep.
Duration? computePacedTickerSleep({
  required Duration targetPeriod,
  required Duration? measuredVsyncInterval,
  required bool sawSkippedVsync,
  Duration? remaining,
}) {
  if (measuredVsyncInterval == null) return null;
  final vsyncUs = measuredVsyncInterval.inMicroseconds;
  final periodUs = targetPeriod.inMicroseconds;
  if (vsyncUs < 1000 || vsyncUs > 25000) return null;
  final marginUs = math.max((vsyncUs * 1.25).round(), _kMinWakeMarginUs);
  // Sleeping only skips a vsync when the wakeup lands past the next edge.
  if (periodUs <= vsyncUs + marginUs) return null;
  // Low-rate pacing (25 fps or less) sleeps once vsync is measured; higher
  // rates wait for a skipped vsync to confirm the mismatch.
  if (!sawSkippedVsync && periodUs < 40000) return null;
  final sleepUs = (remaining ?? targetPeriod).inMicroseconds - marginUs;
  return sleepUs < 2000 ? null : Duration(microseconds: sleepUs);
}

const int _kMinWakeMarginUs = 6000;

/// Vsync cadence and timer sleep state for a rate-limited web `SceneView`.
// TODO(web-paced-sleep): track the vsync interval as a recent minimum rather
// than an average, so a dropped frame cannot inflate it, and re-probe on
// visibility and device pixel ratio changes.
final class PacedTickerSleep {
  // Re-probe the cadence periodically in case the window moves to a display
  // with another refresh rate.
  static const int _kReprobeIntervalFrames = 120;

  Timer? wakeTimer;
  Duration? sleepStartTimeStamp;
  Duration? lastVsyncElapsed;
  Duration? vsyncInterval;
  bool sawSkippedVsync = false;
  bool skippedSinceLastFrame = false;
  bool sleptBeforeFrame = false;
  int sleptSinceReprobe = 0;

  bool get isSleeping => wakeTimer != null;

  void cancelTimer() {
    wakeTimer?.cancel();
    wakeTimer = null;
  }

  void reset() {
    cancelTimer();
    sleepStartTimeStamp = null;
    lastVsyncElapsed = null;
    sawSkippedVsync = false;
    skippedSinceLastFrame = false;
    sleptBeforeFrame = false;
    sleptSinceReprobe = 0;
  }

  void recordVsync(Duration elapsed) {
    final prevElapsed = lastVsyncElapsed;
    lastVsyncElapsed = elapsed;
    if (prevElapsed == null) return;
    final deltaUs = (elapsed - prevElapsed).inMicroseconds;
    if (deltaUs < 1000 || deltaUs > 25000) return;
    final prev = vsyncInterval;
    vsyncInterval = prev == null
        ? Duration(microseconds: deltaUs)
        : Duration(microseconds: (prev.inMicroseconds * 3 + deltaUs) ~/ 4);
  }

  void noteSkip() {
    sawSkippedVsync = true;
    skippedSinceLastFrame = true;
  }

  void noteFrameStarted() {
    if (!sleptBeforeFrame && !skippedSinceLastFrame) {
      sawSkippedVsync = false;
    }
    sleptBeforeFrame = false;
    skippedSinceLastFrame = false;
  }

  bool consumeReprobeDue() {
    if (sleptSinceReprobe < _kReprobeIntervalFrames) return false;
    sleptSinceReprobe = 0;
    return true;
  }
}
