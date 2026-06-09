/// Binds a sky to a scene's image-based lighting with a refresh policy.
library;

import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/skybox.dart';

/// When a [SkyEnvironment] re-bakes the sky into the scene's lighting.
enum SkyEnvironmentRefresh {
  /// Bake once when the binding is set, then only when [SkyEnvironment.invalidate]
  /// is called. The right choice for a static sky.
  manual,

  /// Re-bake when [SkyEnvironment.interval] has elapsed since the last bake.
  /// The visible sky still draws every frame, so a slowly changing sky (a
  /// moving sun) stays smooth on screen while the lighting catches up
  /// periodically at a fraction of the cost.
  interval,

  /// Re-bake every frame. The most responsive and by far the most expensive;
  /// lower [SkyEnvironment.faceResolution] / [SkyEnvironment.equirectWidth]
  /// to keep it affordable.
  // TODO(skybox-amortize): time-slice the bake (faces, prefilter, SH spread
  // across frames) so interval/everyFrame refreshes cost a bounded slice per
  // frame instead of a spike.
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
  DateTime? _lastBake;

  /// Requests a re-bake on the next frame regardless of [refresh]. Call after
  /// changing the sky's parameters under [SkyEnvironmentRefresh.manual].
  void invalidate() => _dirty = true;

  /// Bakes and returns a fresh environment when the policy says one is due,
  /// or null to keep the current one. Called by the engine once per frame
  /// before the render graph is built; not part of the app-facing API.
  EnvironmentMap? bakeIfDue(DateTime now) {
    if (!_isDue(now)) return null;
    _dirty = false;
    _lastBake = now;
    return EnvironmentMap.fromSky(
      source,
      faceResolution: faceResolution,
      equirectWidth: equirectWidth,
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
