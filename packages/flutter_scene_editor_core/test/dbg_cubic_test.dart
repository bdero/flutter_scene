// Temporary probe: cubic->linear collapse.
import 'package:scene/scene.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';

Future<void> main() async {
  final doc = SceneDocument(allocator: IdAllocator(session: 1));
  final registry = CommandRegistry();
  registerBuiltinCommands(registry);
  final history = EditHistory(DocumentMutator(doc));
  void run(String c, Map<String, Object?> p) {
    final entry = registry.lookup(c)!;
    history.commit(entry.execute(CommandContext(doc), p));
  }

  run('createNode', {'name': 'N'});
  final node = doc.roots.last;
  run('createAnimation', {'name': 'Clip'});
  final animId = doc.animations.keys.last;
  run('setAnimationKeyframes', {
    'animationId': animId.toToken(),
    'nodeId': node.toToken(),
    'property': 'translation',
    'keys': [
      {'time': 0.0},
      {'time': 1.0},
    ],
  });
  int len() => doc
      .payload(doc.animations[animId]!.channels.first.keyframes)!
      .bytes!
      .length;
  print('linear len=${len()}');
  run('setChannelInterpolation', {
    'animationId': animId.toToken(),
    'nodeId': node.toToken(),
    'property': 'translation',
    'interpolation': 'cubic',
  });
  print('cubic len=${len()}');
  run('setNodeTransform', {
    'nodeId': node.toToken(),
    'translation': {'x': 7.0, 'y': 8.0, 'z': 9.0},
  });
  run('keyPose', {
    'animationId': animId.toToken(),
    'time': 0.0,
    'nodeIds': [node.toToken()],
  });
  print('after keyPose len=${len()}');
  run('setChannelInterpolation', {
    'animationId': animId.toToken(),
    'nodeId': node.toToken(),
    'property': 'translation',
    'interpolation': 'linear',
  });
  print('back-to-linear len=${len()}');
}
