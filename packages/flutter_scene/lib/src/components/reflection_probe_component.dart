import 'dart:math' as math;

import 'package:flutter/foundation.dart' show internal;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/environment_settings.dart';
import 'package:flutter_scene/src/material/environment.dart';

/// A [Component] that captures the scene's lighting at its node into a local
/// [EnvironmentMap] and feeds it to nearby reflections with
/// parallax-corrected sampling.
///
/// The probe's box (half-size [extents], centered on the node's world
/// position) plays two roles: it is the influence volume the camera blends
/// the probe in over (full inside, fading across [blendDistance] outside),
/// and it is the parallax proxy reflections intersect so they track the
/// captured surfaces instead of floating at infinity. Size it to the room or
/// area the probe represents. The box is world-axis-aligned; the node's
/// rotation is ignored.
///
/// The capture renders the scene's linear HDR lighting from the box center
/// into a cubemap (six faces at [faceResolution]) and prefilters it through
/// the same machinery as any other environment. It happens once when the
/// probe first renders ([captureOnActivate]) and again on [requestCapture];
/// there is no automatic re-capture, so moving geometry is not tracked.
/// {@category Lighting and environment}
class ReflectionProbeComponent extends Component {
  /// Creates a reflection probe over a box of half-size [extents].
  ReflectionProbeComponent({
    Vector3? extents,
    this.blendDistance = 1.0,
    this.priority = 10.0,
    this.weight = 1.0,
    this.faceResolution = 128,
    this.captureOnActivate = true,
  }) : extents = extents ?? Vector3.all(5.0);

  /// World-space half-size of the probe's box (influence volume and
  /// parallax proxy).
  Vector3 extents;

  /// World-space fade band outside the box over which the probe's influence
  /// falls from full to zero. `0` is a hard edge.
  double blendDistance;

  /// Cross-fade order against environment volumes and other probes; higher
  /// applies later (on top). Defaults above the volume default so a probe
  /// wins inside its box.
  double priority;

  /// Master contribution scale, `0`..`1`.
  double weight;

  /// Resolution of each captured cube face, in pixels.
  int faceResolution;

  /// Whether the probe captures automatically before its first rendered
  /// frame. With this false, nothing renders from the probe until
  /// [requestCapture].
  bool captureOnActivate;

  /// The captured local environment, or null before the first capture
  /// completes. Carries the parallax box in
  /// [EnvironmentMap.parallaxBoxCenter]/[EnvironmentMap.parallaxBoxHalfExtents].
  EnvironmentMap? get environment => _environment;
  EnvironmentMap? _environment;

  bool _capturePending = false;

  /// Whether a capture will run before the next frame renders.
  bool get capturePending =>
      _capturePending || (captureOnActivate && _environment == null);

  /// Schedules a fresh capture before the next frame renders, replacing the
  /// previous one when it completes.
  void requestCapture() {
    _capturePending = true;
  }

  /// World-space center of the probe box (the owning node's position).
  Vector3 get worldCenter => node.globalTransform.getTranslation();

  /// The probe's coverage at [cameraPosition], `1` inside the box fading to
  /// `0` across [blendDistance] outside (before [weight]).
  double coverage(Vector3 cameraPosition) {
    final center = worldCenter;
    final dx = (cameraPosition.x - center.x).abs() - extents.x;
    final dy = (cameraPosition.y - center.y).abs() - extents.y;
    final dz = (cameraPosition.z - center.z).abs() - extents.z;
    final ox = dx > 0 ? dx : 0.0;
    final oy = dy > 0 ? dy : 0.0;
    final oz = dz > 0 ? dz : 0.0;
    final dist = math.sqrt(ox * ox + oy * oy + oz * oz);
    if (dist <= 0) return 1.0;
    if (blendDistance <= 0) return 0.0;
    return (1.0 - dist / blendDistance).clamp(0.0, 1.0);
  }

  /// Stores a completed [capture] (called by the renderer), stamping the
  /// parallax box from the probe's current placement.
  @internal
  void internalStoreCapture(EnvironmentMap capture) {
    capture
      ..parallaxBoxCenter = worldCenter
      ..parallaxBoxHalfExtents = Vector3.copy(extents);
    // Replacing a prior capture drops its GPU textures (six faces + equirect +
    // SH + prefiltered atlas) to native finalizers, since EnvironmentMap has no
    // dispose. Fine for the occasional recapture this targets; a tight
    // requestCapture() loop leans on GC and can spike memory before collection.
    // TODO(probe-recapture-churn): dispose the outgoing capture explicitly once
    // EnvironmentMap gains a dispose.
    _environment = capture;
    _crossfadeSettings = EnvironmentSettings(environment: capture);
    _capturePending = false;
  }

  /// The probe's contribution to the image-based-lighting cross-fade: a
  /// settings carrier holding only the captured environment (so the probe
  /// never drags the scene's look fields). Null before the first capture.
  @internal
  EnvironmentSettings? get internalCrossfadeSettings => _crossfadeSettings;
  EnvironmentSettings? _crossfadeSettings;

  @override
  void onMount() {
    node.internalRenderScene?.addReflectionProbeComponent(this);
  }

  @override
  void onUnmount() {
    if (isAttached) {
      node.internalRenderScene?.removeReflectionProbeComponent(this);
    }
  }
}
