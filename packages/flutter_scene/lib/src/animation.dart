/// Animation playback for `flutter_scene`.
///
/// Models loaded from `.model` or glTF files carry [Animation] objects
/// describing keyframed translation, rotation, and scale changes for
/// individual nodes. Instantiate one for playback by calling
/// [Node.createAnimationClip], which returns an [AnimationClip] bound to
/// the target subtree.
///
/// An internal [AnimationPlayer] on each animated node blends multiple
/// concurrent clips by their [AnimationClip.weight], normalizing weights
/// when their sum exceeds `1`. Each frame [AnimationPlayer.update]
/// recomputes node transforms from a stored bind pose.
library;

import 'dart:math';
import 'dart:ui';

import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/math_extensions.dart';
import 'package:flutter_scene_importer/flatbuffer.dart' as fb;
import 'package:vector_math/vector_math.dart';

part 'animation/animation.dart';
part 'animation/animation_clip.dart';
part 'animation/animation_player.dart';
part 'animation/animation_transform.dart';
part 'animation/property_resolver.dart';
