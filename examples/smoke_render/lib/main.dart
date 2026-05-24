import 'package:flutter/material.dart';

import 'smoke_scenes.dart';

void main() {
  runApp(const SmokeApp());
}

/// Minimal host for the smoke scene. Mostly here for manual inspection; the
/// integration test pumps [SmokeSceneView] directly.
class SmokeApp extends StatelessWidget {
  const SmokeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: kSmokeClear,
        body: Center(child: SmokeSceneView(kSmokeScenes.first)),
      ),
    );
  }
}
