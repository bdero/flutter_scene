/// The [FlowHost] a graph running inside a scene sees.
///
/// Everything a graph can reach outside its own values goes through here, so
/// the interpreter stays ignorant of what a scene is and the same graph runs
/// in a test against a stub.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:scene/flow.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter_scene/src/animation.dart' show AnimationClip;
import 'package:flutter_scene/src/kit/environment/lightning_component.dart'
    show sunDirectionForHour;
import 'package:flutter_scene/src/kit/environment/weather.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_scene/src/sky_sources.dart';
import 'package:flutter_scene/src/skybox.dart' show SunSky;

/// Runs a graph against a live node.
///
/// Paths are read and written against the owning node by default, and against
/// a named descendant when prefixed with it: `position`, `rotation.y`,
/// `turret/position`. That is deliberately the same spelling the animation
/// channels use, so someone who has bound one already knows how to bind the
/// other.
/// {@category Flow}
class SceneFlowHost implements FlowHost {
  SceneFlowHost(this.owner, {this.onAction, this.onLog});

  /// The node the graph is attached to, and what a bare path resolves
  /// against.
  final Node owner;

  /// Called for an action the built-in nodes do not handle, so an
  /// application can extend a graph's reach without a new node type.
  final Object? Function(String action, Map<String, Object?> arguments)?
  onAction;

  /// Where Print goes. Null prints through `debugPrint`, which is what an
  /// editor console shows.
  final void Function(String message)? onLog;

  @override
  double deltaSeconds = 0;

  @override
  double elapsedSeconds = 0;

  /// Signals raised since the last tick, consumed by the On Signal event.
  final Set<String> pendingSignals = {};

  /// Splits a path into the node it targets and the property on it.
  ///
  /// Returns null when the named node is not in the subtree, which is what
  /// lets a write report failure instead of silently doing nothing.
  (Node, String)? _resolve(String path) {
    final slash = path.lastIndexOf('/');
    if (slash < 0) return (owner, path);
    final name = path.substring(0, slash);
    final property = path.substring(slash + 1);
    final target = name == '.' ? owner : owner.getChildByName(name);
    return target == null ? null : (target, property);
  }

  @override
  Object? read(String path) {
    final resolved = _resolve(path);
    if (resolved == null) return null;
    final (node, property) = resolved;
    return switch (property) {
      'position' => node.position,
      'position.x' => node.position.x,
      'position.y' => node.position.y,
      'position.z' => node.position.z,
      'scale' => node.scale,
      'scale.x' => node.scale.x,
      'scale.y' => node.scale.y,
      'scale.z' => node.scale.z,
      'worldPosition' => node.globalTransform.getTranslation(),
      'visible' => node.visible,
      'name' => node.name,
      _ => null,
    };
  }

  @override
  bool write(String path, Object? value) {
    final resolved = _resolve(path);
    if (resolved == null) return false;
    final (node, property) = resolved;
    switch (property) {
      case 'position':
        node.position = flowVector(value);
      case 'position.x':
        node.position = node.position..x = flowNumber(value);
      case 'position.y':
        node.position = node.position..y = flowNumber(value);
      case 'position.z':
        node.position = node.position..z = flowNumber(value);
      case 'scale':
        node.scale = flowVector(value);
      case 'scale.x':
        node.scale = node.scale..x = flowNumber(value);
      case 'scale.y':
        node.scale = node.scale..y = flowNumber(value);
      case 'scale.z':
        node.scale = node.scale..z = flowNumber(value);
      case 'visible':
        node.visible = flowBool(value);
      default:
        return false;
    }
    return true;
  }

  @override
  Object? invoke(String action, Map<String, Object?> arguments) {
    switch (action) {
      case 'lookAt':
        final target = flowVector(arguments['target']);
        owner.lookAt(target);
        return null;
      case 'translate':
        final by = flowVector(arguments['by']);
        owner.position = owner.position + by;
        return null;
      case 'playAnimation':
        return _playAnimation(arguments);
      case 'stopAnimation':
        final stopped = _clips.remove('${arguments['name']}');
        if (stopped != null) owner.removeAnimationClip(stopped);
        return null;
      case 'destroy':
        owner.parent?.remove(owner);
        return null;
      case 'setWeather':
        return _setWeather(arguments);
      case 'setTimeOfDay':
        return _setTimeOfDay(arguments);
    }
    return onAction?.call(action, arguments);
  }

  final Map<String, AnimationClip> _clips = {};

  /// The scene this graph's node is mounted in, or null when it is not in
  /// one. Reached the same way [LightningComponent] reaches the sky it
  /// flashes, so a graph and a component see the same scene.
  Scene? get _scene {
    final root = owner.internalRenderScene?.owner;
    return root is Scene ? root : null;
  }

  /// The scene's sky, when it is one with clouds in it.
  WeatherSkySource? get _weatherSky {
    final source = _scene?.skybox?.source;
    return source is WeatherSkySource ? source : null;
  }

  bool _setWeather(Map<String, Object?> arguments) {
    final id = '${arguments['weather']}';
    final preset = weatherPresetById(id);
    if (preset == null) {
      log('No weather named "$id".');
      return false;
    }
    final sky = _weatherSky;
    if (sky == null) {
      log(
        'The scene\'s sky has no clouds to change; set it to a weather '
        'sky first.',
      );
      return false;
    }
    preset.applyTo(sky);
    return true;
  }

  bool _setTimeOfDay(Map<String, Object?> arguments) {
    final Object? source = _scene?.skybox?.source;
    if (source is SunSky) {
      // In place: SunSky exposes the direction as a getter, and every built-in
      // sky holds it as a plain mutable vector the shader reads at draw time.
      source.sunDirection.setFrom(
        sunDirectionForHour(
          flowNumber(arguments['hour'], 12),
          tilt: flowNumber(arguments['tilt'], 0.35),
        ),
      );
      return true;
    }
    log('The scene\'s sky has no sun to move.');
    return false;
  }

  Object? _playAnimation(Map<String, Object?> arguments) {
    final name = '${arguments['name']}';
    final animation = owner.findAnimationByName(name);
    if (animation == null) {
      log('No animation named "$name" on ${owner.name}.');
      return false;
    }
    final clip = _clips[name] ?? owner.createAnimationClip(animation);
    _clips[name] = clip
      ..loop = flowBool(arguments['loop'])
      ..playbackTimeScale = flowNumber(arguments['speed'], 1)
      ..play();
    return true;
  }

  @override
  void log(String message) {
    final sink = onLog;
    if (sink != null) {
      sink(message);
    } else {
      debugPrint('flow: $message');
    }
  }

  /// A vector as the engine's own type, for a caller reading a graph's output.
  static vm.Vector3 vector(Object? value) => flowVector(value);
}
