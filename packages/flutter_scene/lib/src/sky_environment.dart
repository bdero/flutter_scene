/// Binds a sky to a scene's image-based lighting with a refresh policy.
library;

import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/render/sky_bake.dart';
import 'package:flutter_scene/src/skybox.dart';

/// When a [SkyEnvironment] re-bakes the sky into the scene's lighting.
enum SkyEnvironmentRefresh {
  /// Bake once when the binding is set, then only when [SkyEnvironment.invalidate]
  /// is called. The right choice for a static sky.
  manual,

  /// Re-bake when [SkyEnvironment.interval] has elapsed since the last bake
  /// began. The visible sky still draws every frame, so a slowly changing sky
  /// (a moving sun) stays smooth on screen while the lighting catches up
  /// periodically at a fraction of the cost.
  interval,

  /// Re-bake continuously: as soon as one bake cycle publishes, the next
  /// starts. With the time-sliced bake this costs one bounded pass per frame
  /// and the lighting refreshes every cycle (`6 + 1 + band count + 1`
  /// frames); lower [SkyEnvironment.faceResolution] /
  /// [SkyEnvironment.equirectWidth] to cheapen the slices further.
  everyFrame,
}

/// Drives `Scene.environment` from a sky on a refresh policy.
///
/// Assign one to `Scene.skyEnvironment` to have the scene bake [source] into
/// its image-based lighting (specular reflections plus diffuse irradiance)
/// and keep it fresh per [refresh]. While set, the binding owns
/// `Scene.environment`: each due bake replaces it. The visible background
/// (`Scene.skybox`) is independent and cheap; the same source can drive both
/// so the lit scene always matches what is on screen:
///
/// ```dart
/// final sky = await loadFmatSky('assets/gradient_sky.fmat');
/// scene.skybox = Skybox(sky);
/// scene.skyEnvironment = SkyEnvironment(sky);
/// // ... later, after changing the sky's parameters:
/// scene.skyEnvironment!.invalidate();
/// ```
class SkyEnvironment {
  SkyEnvironment(
    this.source, {
    this.refresh = SkyEnvironmentRefresh.manual,
    this.interval = const Duration(seconds: 1),
    this.faceResolution = 128,
    this.equirectWidth = 512,
  });

  /// The sky baked into the lighting.
  ShaderSkySource source;

  /// When the bake re-runs. See [SkyEnvironmentRefresh].
  SkyEnvironmentRefresh refresh;

  /// Minimum time between bakes for [SkyEnvironmentRefresh.interval].
  Duration interval;

  /// Cube-face capture resolution for the bake. Lower values make frequent
  /// re-bakes cheaper at the cost of lighting detail.
  int faceResolution;

  /// Width of the assembled equirect the prefilter and SH projection read.
  int equirectWidth;

  bool _dirty = true;
  bool _everBaked = false;
  DateTime? _lastBake;
  final SkyBakeJob _job = SkyBakeJob();

  // The empty environment handed to the sky fragment's bind during a bake (a
  // sky baked into the environment cannot sample the environment it is
  // producing). Cached so per-frame bake steps allocate nothing.
  static EnvironmentMap? _noEnvironmentCache;
  static EnvironmentMap get _noEnvironment =>
      _noEnvironmentCache ??= EnvironmentMap.empty();

  /// Requests a re-bake on the next frame regardless of [refresh]. Call after
  /// changing the sky's parameters under [SkyEnvironmentRefresh.manual].
  void invalidate() => _dirty = true;

  /// Advances the bake and returns a fresh environment when one completes,
  /// or null to keep the current one. Called by the engine once per frame
  /// before the render graph is built; not part of the app-facing API.
  ///
  /// The very first bake of a binding runs in one call so the scene is lit by
  /// the sky immediately. Every later bake is time-sliced through a
  /// [SkyBakeJob]: one GPU pass per frame, published only when the cycle
  /// completes, so a re-bake never spikes a frame and a partial result is
  /// never visible.
  EnvironmentMap? bakeIfDue(DateTime now) {
    if (!_everBaked) {
      _everBaked = true;
      _dirty = false;
      _lastBake = now;
      return EnvironmentMap.fromSky(
        source,
        faceResolution: faceResolution,
        equirectWidth: equirectWidth,
      );
    }
    if (!_job.inFlight) {
      if (!_isDue(now)) return null;
      _dirty = false;
      _lastBake = now;
      _job.start(faceResolution: faceResolution, equirectWidth: equirectWidth);
    }
    final done = _job.advance(source, _noEnvironment);
    if (done == null) return null;
    return EnvironmentMap.fromGpuTextures(
      prefilteredRadiance: done.atlas,
      diffuseShTexture: done.sh,
    );
  }

  bool _isDue(DateTime now) {
    if (_dirty) return true;
    return switch (refresh) {
      SkyEnvironmentRefresh.manual => false,
      SkyEnvironmentRefresh.everyFrame => true,
      SkyEnvironmentRefresh.interval =>
        _lastBake == null || now.difference(_lastBake!) >= interval,
    };
  }
}
