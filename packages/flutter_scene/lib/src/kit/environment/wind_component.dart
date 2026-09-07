/// The thing that drives the scene's wind, and points the sky at it.
library;

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/kit/environment/wind.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_scene/src/sky_sources.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Advances a [Wind] each frame, and scrolls the scene's weather sky by it.
///
/// Put one on the scene root. Everything downwind of it -- the clouds, the
/// rain, the snow -- moves together, because they are all reading the same
/// vector rather than each carrying a constant of its own.
/// {@category Gameplay kit}
class WindComponent extends Component {
  /// Drives [wind], or the scene's ambient wind when none is given.
  WindComponent({Wind? wind, this.driveSky = true})
    : wind = wind ?? Wind.ambient;

  /// The wind this advances.
  final Wind wind;

  /// Whether the scene's weather sky is scrolled by this wind.
  ///
  /// On by default, because clouds that ignore the wind are the most visible
  /// way for weather to look wrong. Off when the sky is being driven by
  /// something else -- a cutscene scrubbing its own cloud offset.
  bool driveSky;

  /// How fast the cloud layer scrolls per unit of wind speed.
  ///
  /// Clouds are far away, so they move across the sky far more slowly than
  /// the wind moves a leaf; this is the ratio between the two, and it is a
  /// look rather than a physical quantity.
  double skyScale = 0.02;

  @override
  void update(double deltaSeconds) {
    wind.advance(deltaSeconds);
    if (!driveSky) return;
    final sky = _weatherSky();
    if (sky == null) return;
    final velocity = wind.velocity;
    sky.wind.setValues(velocity.x * skyScale, velocity.z * skyScale);
  }

  /// The scene's skybox, when it is a weather sky. Read each tick rather
  /// than cached, so a sky swapped under a live scene is picked up on the
  /// next frame rather than never.
  WeatherSkySource? _weatherSky() {
    if (!isAttached) return null;
    final owner = node.internalRenderScene?.owner;
    if (owner is! Scene) return null;
    final source = owner.skybox?.source;
    return source is WeatherSkySource ? source : null;
  }

  @override
  Component? cloneFor(Node cloneOwner) =>
      WindComponent(wind: wind, driveSky: driveSky)..skyScale = skyScale;
}

/// Reads the scene's wind into a direction and speed, for a caller that wants
/// the number rather than the object: a shader uniform, a debug readout.
/// {@category Gameplay kit}
vm.Vector3 windVelocity([Wind? wind]) => (wind ?? Wind.ambient).velocity;
