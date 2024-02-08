import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter_scene/camera.dart';
import 'package:flutter_scene/geometry/geometry.dart';
import 'package:flutter_scene/material/material.dart';
import 'package:flutter_scene/mesh.dart';
import 'package:flutter_scene/scene.dart';

import 'package:vector_math/vector_math.dart' as vm;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Scene scene = Scene();
  late Ticker ticker;
  double elapsedSeconds = 0;
  String selectedExample = 'Cuboid';

  @override
  void initState() {
    super.initState();
    ticker = Ticker((elapsed) {
      setState(() {
        elapsedSeconds = elapsed.inMilliseconds.toDouble() / 1000;
      });
    });
    ticker.start();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Scene Examples',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: Text('Example: $selectedExample'),
        ),
        body: Stack(
          children: [
            SizedBox.expand(
              child: CustomPaint(
                painter: ScenePainter(scene, elapsedSeconds),
              ),
            ),
            // Dropdown menu
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: DropdownButton<String>(
                  value: selectedExample,
                  items: const <String>['Cuboid', 'Sphere']
                      .map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      selectedExample = newValue!;
                    });
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScenePainter extends CustomPainter {
  ScenePainter(this.scene, this.elapsedTime);
  Scene scene;
  double elapsedTime;

  @override
  void paint(Canvas canvas, Size size) {
    scene = Scene();

    final mesh = Mesh(CuboidGeometry(vm.Vector3(1, 1, 1)), UnlitMaterial());
    scene.addMesh(mesh);

    final camera = Camera(
      position: vm.Vector3(sin(elapsedTime) * 5, 2, cos(elapsedTime) * 5),
      target: vm.Vector3(0, 0, 0),
    );

    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
