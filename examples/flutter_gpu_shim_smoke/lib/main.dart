import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_gpu_shim/gpu.dart' as gpu;

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
      home: const SmokePage(),
    );
  }
}

class SmokePage extends StatefulWidget {
  const SmokePage({super.key});

  @override
  State<SmokePage> createState() => _SmokePageState();
}

class _SmokePageState extends State<SmokePage> {
  static const int _size = 256;

  bool _transferOwnership = false;
  double _hue = 0.0;
  ui.Image? _image;
  String? _error;

  @override
  void initState() {
    super.initState();
    _render();
  }

  Future<void> _render() async {
    try {
      final surface = gpu.Surface(width: _size, height: _size);
      final color = HSVColor.fromAHSV(1.0, _hue, 0.85, 0.95).toColor();
      surface.clearToColor(color.r, color.g, color.b, 1.0);
      final image = await surface.snapshot(
        transferOwnership: _transferOwnership,
      );
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
        _error = null;
      });
      if (!_transferOwnership) {
        surface.dispose();
      }
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _error = '$e\n$st';
      });
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Scaffold(
      appBar: AppBar(title: const Text('flutter_gpu_shim smoke test')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (image != null)
              SizedBox(
                width: _size.toDouble(),
                height: _size.toDouble(),
                child: RawImage(image: image, fit: BoxFit.fill),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              )
            else
              const CircularProgressIndicator(),
            const SizedBox(height: 24),
            SizedBox(
              width: 320,
              child: Slider(
                value: _hue,
                min: 0.0,
                max: 360.0,
                onChanged: (v) {
                  setState(() {
                    _hue = v;
                  });
                  _render();
                },
              ),
            ),
            SwitchListTile(
              title: const Text('transferOwnership'),
              subtitle: const Text(
                'true: engine consumes the canvas; false: bitmap copy',
              ),
              value: _transferOwnership,
              onChanged: (v) {
                setState(() {
                  _transferOwnership = v;
                });
                _render();
              },
            ),
          ],
        ),
      ),
    );
  }
}
