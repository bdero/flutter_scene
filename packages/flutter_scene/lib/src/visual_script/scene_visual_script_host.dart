/// The [VisualScriptHost] a graph running inside a scene sees.
///
/// Everything a graph can reach outside its own values goes through here, so
/// the interpreter stays ignorant of what a scene is and the same graph runs
/// in a test against a stub.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:scene/visual_script.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter_scene/src/animation.dart' show AnimationClip;
import 'package:flutter_scene/src/kit/environment/lightning_component.dart'
    show sunDirectionForHour;
import 'package:flutter_scene/src/kit/environment/weather.dart';
import 'package:flutter_scene/src/animation/animator_component.dart';
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
/// {@category Visual scripting}
class SceneVisualScriptHost implements VisualScriptHost {
  SceneVisualScriptHost(this.owner, {this.onAction, this.onLog});

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
        node.position = scriptVector(value);
      case 'position.x':
        node.position = node.position..x = scriptNumber(value);
      case 'position.y':
        node.position = node.position..y = scriptNumber(value);
      case 'position.z':
        node.position = node.position..z = scriptNumber(value);
      case 'scale':
        node.scale = scriptVector(value);
      case 'scale.x':
        node.scale = node.scale..x = scriptNumber(value);
      case 'scale.y':
        node.scale = node.scale..y = scriptNumber(value);
      case 'scale.z':
        node.scale = node.scale..z = scriptNumber(value);
      case 'visible':
        node.visible = scriptBool(value);
      default:
        return false;
    }
    return true;
  }

  @override
  Object? invoke(String action, Map<String, Object?> arguments) {
    switch (action) {
      case 'lookAt':
        final target = scriptVector(arguments['target']);
        owner.lookAt(target);
        return null;
      case 'translate':
        final by = scriptVector(arguments['by']);
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
      case 'spawn':
        return _spawn(arguments);
      case 'setAnimatorNumber':
        return _withAnimator(
          (a) => a.animator.parameters.setNumber(
            '${arguments['name']}',
            scriptNumber(arguments['value'], 0),
          ),
        );
      case 'setAnimatorFlag':
        return _withAnimator(
          (a) => a.animator.parameters.setFlag(
            '${arguments['name']}',
            value: scriptBool(arguments['value']),
          ),
        );
      case 'animatorTrigger':
        return _withAnimator(
          (a) => a.animator.parameters.trigger('${arguments['name']}'),
        );
      case 'animatorState':
        final animator = _animator;
        if (animator == null) {
          log('This node has no animator.');
          return '';
        }
        final layer = '${arguments['layer'] ?? ''}';
        if (layer.isEmpty) return animator.animator.base.current;
        final found = animator.animator.layer(layer);
        if (found == null) {
          log('No animator layer named "$layer".');
          return '';
        }
        return found.current;
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
          scriptNumber(arguments['hour'], 12),
          tilt: scriptNumber(arguments['tilt'], 0.35),
        ),
      );
      return true;
    }
    log('The scene\'s sky has no sun to move.');
    return false;
  }

  /// Clones a template already in the scene and puts the copy in it.
  ///
  /// A template rather than an asset path because a node's evaluate is
  /// synchronous and loading a document is not: a graph cannot wait for a file
  /// mid-tick. So a blueprint spawns a copy of something the scene already
  /// holds -- the usual arrangement being a hidden template parked off to one
  /// side -- which is the same shape as handing any spawn call a loaded
  /// prefab rather than a path.
  ///
  /// Returns the spawned node's name, or an empty string when there was no
  /// such template.
  String _spawn(Map<String, Object?> arguments) {
    final templateName = '${arguments['template'] ?? ''}';
    if (templateName.isEmpty) {
      log('Spawn was given no template to copy.');
      return '';
    }
    final template = _find(templateName);
    if (template == null) {
      log('No node named "$templateName" to spawn a copy of.');
      return '';
    }

    // The scene root by preference: a spawned thing outliving the node that
    // spawned it is the usual case, and parenting it to the spawner would take
    // it away when that node goes.
    final parentName = '${arguments['parent'] ?? ''}';
    final parent = parentName.isEmpty
        ? (_scene?.root ?? owner)
        : _find(parentName);
    if (parent == null) {
      log('No node named "$parentName" to spawn into.');
      return '';
    }
    if (identical(parent, template)) {
      log('A template cannot be spawned into itself.');
      return '';
    }

    final spawned = template.clone();
    spawned
      ..name = templateName
      // Visible whatever the template was: a template is usually parked
      // hidden, and a spawn nobody can see reads as a spawn that failed.
      ..visible = true
      ..position = scriptVector(arguments['at']);
    parent.add(spawned);
    return spawned.name;
  }

  /// The node called [name], searched from the scene root and then from the
  /// node the graph is on, so a template parked anywhere is reachable.
  Node? _find(String name) {
    final root = _scene?.root;
    if (root != null) {
      if (root.name == name) return root;
      final found = root.getChildByName(name);
      if (found != null) return found;
    }
    if (owner.name == name) return owner;
    return owner.getChildByName(name);
  }

  /// The animator on the node the graph runs on, or null.
  ///
  /// A graph drives a character by setting parameters and letting the machine
  /// decide what plays, which is the whole point of having a machine: the
  /// script says "speed is 4" and never says "play the run".
  AnimatorComponent? get _animator => owner.getComponent<AnimatorComponent>();

  /// Runs [edit] against this node's animator, reporting whether there was
  /// one to run it against.
  bool _withAnimator(void Function(AnimatorComponent animator) edit) {
    final animator = _animator;
    if (animator == null) {
      log('This node has no animator to set a parameter on.');
      return false;
    }
    edit(animator);
    return true;
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
      ..loop = scriptBool(arguments['loop'])
      ..playbackTimeScale = scriptNumber(arguments['speed'], 1)
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
  static vm.Vector3 vector(Object? value) => scriptVector(value);
}
