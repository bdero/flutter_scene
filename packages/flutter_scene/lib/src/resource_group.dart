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
///   EnvironmentMap.fromEquirectImageAsset(assetPath: 'sky.hdr'),
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
  final List<Future<void> Function()> _releases = <Future<void> Function()>[];
  bool _disposed = false;
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

  /// Releases this group's claim on everything loaded through [track], then
  /// releases the [progress] notifier.
  ///
  /// Call when the scope this group represents ends, typically a level or a
  /// screen. Each tracked load took a claim on the engine's shared cache, and
  /// this gives them all back, so a resource nothing else claims leaves the
  /// cache. After disposal the group must not be added to or listened on.
  ///
  /// This releases the engine's references, not the memory. A resource a live
  /// scene still points at stays resident until that reference goes too, and
  /// the GPU allocation is reclaimed after that on the engine's schedule
  /// rather than at this call. Use [takeMemoryReport] to see what is actually
  /// pinned.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    release();
    _progress.dispose();
  }

  /// Releases this group's claims without disposing [progress], so the group
  /// can be refilled and reused. [dispose] calls this for you.
  void release() {
    for (final release in _releases) {
      release();
    }
    _releases.clear();
  }

  /// Tracks [load] like [add], and additionally takes ownership of it, so
  /// [dispose] gives the claim back.
  ///
  /// Use this for the source-path loaders whose results live in a shared
  /// cache ([loadScene], [loadTexture]). [add] only waits for a load; this
  /// also scopes it to the group's lifetime.
  ///
  /// ```dart
  /// final level = ResourceGroup();
  /// final terrain = level.track(loadScene('levels/ice.fsceneb'),
  ///     release: () => releaseScene('levels/ice.fsceneb'));
  /// // ...
  /// level.dispose(); // gives the template's claim back
  /// ```
  Future<T> track<T>(
    Future<T> load, {
    required Future<void> Function() release,
  }) {
    _releases.add(release);
    return add(load);
  }

  void _markSettled() {
    _completed++;
    _updateProgress();
  }

  void _updateProgress() {
    // A group is routinely disposed while loads are still in flight (a level
    // torn down mid-load), and those loads still settle afterwards. Reporting
    // progress into a disposed notifier would throw from a future nobody is
    // awaiting.
    if (_disposed) return;
    _progress.value = _total == 0 ? 1.0 : _completed / _total;
  }
}
