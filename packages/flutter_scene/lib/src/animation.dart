/// Animation playback for `flutter_scene`.
///
/// Imported scenes and glTF files carry [Animation] objects
/// describing keyframed translation, rotation, and scale changes for
/// individual nodes, plus other node properties addressed by path
/// (visibility, lights, material factors). Instantiate one for playback by calling
/// [Node.createAnimationClip], which returns an [AnimationClip] bound to
/// the target subtree.
///
/// An internal [AnimationPlayer] on each animated node blends multiple
/// concurrent clips by their [AnimationClip.weight], normalizing weights
/// when their sum exceeds `1`. Each frame [AnimationPlayer.update]
/// recomputes node transforms from a stored bind pose.
library;

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/components/point_light_component.dart';
import 'package:flutter_scene/src/components/spot_light_component.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/math_extensions.dart';
import 'package:vector_math/vector_math.dart';

part 'animation/animated_path.dart';
part 'animation/animation.dart';
part 'animation/animation_clip.dart';
part 'animation/animation_player.dart';
part 'animation/animation_transform.dart';
part 'animation/property_resolver.dart';
