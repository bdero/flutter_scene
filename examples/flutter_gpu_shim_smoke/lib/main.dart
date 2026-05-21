import 'package:flutter/material.dart';

import 'bridge_tab.dart';
import 'hdr_tab.dart';
import 'mesh_tab.dart';
import 'shaders_tab.dart';
import 'triangle_tab.dart';

void main() {
  runApp(const SmokeApp());
}

class SmokeApp extends StatelessWidget {
  const SmokeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_gpu_shim smoke test',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const SmokeHome(),
    );
  }
}

class SmokeHome extends StatelessWidget {
  const SmokeHome({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('flutter_gpu_shim smoke test'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Bridge'),
              Tab(text: 'Shaders'),
              Tab(text: 'Triangle'),
              Tab(text: 'Mesh'),
              Tab(text: 'HDR'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            BridgeTab(),
            ShadersTab(),
            TriangleTab(),
            MeshTab(),
            HdrTab(),
          ],
        ),
      ),
    );
  }
}
