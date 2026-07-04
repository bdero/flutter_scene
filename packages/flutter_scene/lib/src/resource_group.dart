import 'package:flutter/foundation.dart';

/// Tracks a set of in-flight resource loads so a scene can wait for all of
/// them before it is shown, and report aggregate progress while they run.
///
/// Every loader in Flutter Scene returns a [Future] that completes only once
/// the resource and its dependencies are decoded and resident on the GPU, so
/// a completed future means "ready to render this frame". A [ResourceGroup]
/// collects those futures, exposes a [progress] value for a loading bar, and
/// completes [ready] once they have all settled. Pass one to a `SceneView`
/// (via its `loading` argument) to hold the scene off-screen behind a loading
/// widget until it is fully assembled, instead of drawing it half-built.
///
/// ```dart
/// final loading = ResourceGroup();
/// final terrain = loading.add(loadScene('terrain.fscene'));
/// final env = loading.add(
///   EnvironmentMap.fromAssets(radianceImagePath: 'sky.png'),
/// );
/// loading.addAll([
///   Node.fromGlbAsset('player.glb'),
///   Texture2D.fromAsset('coin.png'),
/// ]);
///
/// // Drive a progress bar from loading.progress, or just await:
/// await loading.ready;
/// scene.add(await terrain);
/// ```
///
/// [progress] counts completed loads over the total tracked, so it can jump
/// backward if you [add] more loads after it has advanced. Track every load
/// up front (before reading [progress]) to avoid that.
/// {@category Assets and loading}
class ResourceGroup {
  /// Creates an empty group. A group with nothing tracked is immediately
  /// [isReady], and its [ready] future is already complete.
  ResourceGroup();

  int _total = 0;
  int _completed = 0;
  final List<Object> _failures = <Object>[];
  final List<Future<void>> _tracked = <Future<void>>[];
  final ValueNotifier<double> _progress = ValueNotifier<double>(1.0);

  /// Tracks [load] and returns it unchanged, so the call reads inline:
  ///
  /// ```dart
  /// final node = await loading.add(Node.fromGlbAsset('player.glb'));
  /// ```
  ///
  /// A failed load counts toward completion (so [ready] still resolves) and
  /// its error is recorded in [failures]; it does not abort the group.
  Future<T> add<T>(Future<T> load) {
    _total++;
    _updateProgress();
    _tracked.add(
      load.then(
        (_) => _markSettled(),
        onError: (Object error, StackTrace stack) {
          _failures.add(error);
          _markSettled();
        },
      ),
    );
    return load;
  }

  /// Tracks each of [loads]. Convenience for calling [add] in a loop when you
  /// do not need the individual futures back.
  void addAll(Iterable<Future<Object?>> loads) {
    for (final load in loads) {
      add(load);
    }
  }

  /// Fraction of tracked loads that have settled, in the range 0 to 1.
  ///
  /// A [ValueListenable] so a loading widget can rebuild as it changes without
  /// polling. It is 1 while the group is empty (nothing to wait for).
  ValueListenable<double> get progress => _progress;

  /// Completes once every load tracked so far has settled (succeeded or
  /// failed). Never throws; inspect [failures] for any errors.
  ///
  /// Loads added after this getter is awaited are not included in that wait,
  /// so add every load before awaiting.
  Future<void> get ready => Future.wait(_tracked);

  /// The number of loads tracked so far.
  int get total => _total;

  /// The number of tracked loads that have settled.
  int get completed => _completed;

  /// Whether every tracked load has settled.
  bool get isReady => _completed >= _total;

  /// Whether any tracked load failed.
  bool get hasFailures => _failures.isNotEmpty;

  /// The errors from any tracked loads that failed, in completion order.
  List<Object> get failures => List<Object>.unmodifiable(_failures);

  /// Releases the [progress] notifier. Call when the group is no longer used;
  /// after disposal the group must not be added to or listened on.
  void dispose() => _progress.dispose();

  void _markSettled() {
    _completed++;
    _updateProgress();
  }

  void _updateProgress() {
    _progress.value = _total == 0 ? 1.0 : _completed / _total;
  }
}
