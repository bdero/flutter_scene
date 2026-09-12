import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';

import 'smoke_scenes.dart';

/// Which scene the manual host shows; `--dart-define=SMOKE_SCENE=<id>`.
/// Defaults to the first scene.
const _sceneId = String.fromEnvironment('SMOKE_SCENE');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final smoke = kSmokeScenes.firstWhere(
    (s) => s.id == _sceneId,
    orElse: () => kSmokeScenes.first,
  );
  // Geometry and material constructors touch the shader bundle, which must
  // be loaded first (the web backend has no synchronous load).
  await Scene.initializeStaticResources();
  await smoke.preload?.call();
  runApp(SmokeApp(smoke));
}

/// Minimal host for one smoke scene. Mostly here for manual inspection; the
/// integration test pumps [SmokeSceneView] directly.
class SmokeApp extends StatelessWidget {
  const SmokeApp(this.smoke, {super.key});

  final SmokeScene smoke;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: kSmokeClear,
        body: Center(child: SmokeSceneView(smoke)),
      ),
    );
  }
}
