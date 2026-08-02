const bool profileRendering = bool.fromEnvironment('FLUTTER_SCENE_PROFILE');

/// Shared profile samples intentionally combine all active render views.
class RenderProfileAccumulator {
  RenderProfileAccumulator({this.sampleWindow = 120});

  final int sampleWindow;
  final Map<String, int> _totals = {};
  final Map<String, int> _counts = {};
  final Map<String, int> _maxima = {};
  int _samples = 0;

  void add(String name, int value, {bool trackMax = false}) {
    _totals[name] = (_totals[name] ?? 0) + value;
    _counts[name] = (_counts[name] ?? 0) + 1;
    if (trackMax && value > (_maxima[name] ?? 0)) {
      _maxima[name] = value;
    }
  }

  RenderProfileSnapshot? endSample() {
    if (++_samples < sampleWindow) return null;
    final snapshot = RenderProfileSnapshot(
      Map<String, int>.of(_totals),
      Map<String, int>.of(_counts),
      Map<String, int>.of(_maxima),
    );
    _samples = 0;
    _totals.clear();
    _counts.clear();
    _maxima.clear();
    return snapshot;
  }
}

class RenderProfileSnapshot {
  const RenderProfileSnapshot(this.totals, this.counts, this.maxima);

  final Map<String, int> totals;
  final Map<String, int> counts;
  final Map<String, int> maxima;

  int mean(String name) => totals[name]! ~/ counts[name]!;
  int max(String name) => maxima[name] ?? 0;
}
