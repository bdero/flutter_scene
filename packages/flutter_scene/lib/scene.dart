/// 3D rendering for Flutter, built on Flutter GPU and Impeller.
///
/// The entry points most applications need are:
///
///  * [Scene] — the scene graph root and renderer. Construct one, attach
///    [Node]s, and call [Scene.render] from a `CustomPainter` (or any
///    `dart:ui` [Canvas]).
///  * [Node] — a transform in the scene graph that may carry a [Mesh] and
///    child nodes. Load 3D models with [Node.fromAsset] (preprocessed
///    `.model` files) or [Node.fromGlbBytes] / [Node.fromGlbAsset]
///    (runtime glTF binary).
///  * [Camera] / [PerspectiveCamera] — view configuration passed to
///    [Scene.render].
///  * [Material], [PhysicallyBasedMaterial], [UnlitMaterial],
///    [Environment] — shading.
///  * [Animation], [AnimationClip], [AnimationPlayer] — playback and
///    blending of imported animations.
///
/// Flutter Scene currently requires the Flutter master channel because it
/// depends on the Flutter GPU API.
library;

export 'src/animation.dart';

export 'src/geometry/geometry.dart';

export 'src/material/environment.dart';
export 'src/material/material.dart';
export 'src/material/physically_based_material.dart';
export 'src/material/unlit_material.dart';

export 'src/asset_helpers.dart';
export 'src/camera.dart';
export 'src/math_extensions.dart';
export 'src/mesh.dart';
export 'src/node.dart';
export 'src/scene_encoder.dart';
export 'src/scene.dart';
export 'src/shaders.dart';
export 'src/skin.dart';
export 'src/surface.dart';
