import 'package:example_app/example_car.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:example_app/example_animation.dart';

import 'example_cuboid.dart';
import 'example_logo.dart';
import 'example_stress_tests.dart';
import 'example_toon.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Ticker ticker;
  double elapsedSeconds = 0;
  String selectedExample = '';
  Map<String, WidgetBuilder> examples = {};

  @override
  void initState() {
    ticker = Ticker((elapsed) {
      setState(() {
        elapsedSeconds = elapsed.inMilliseconds.toDouble() / 1000;
      });
    });
    ticker.start();

    examples = {
      'Car': (context) => ExampleCar(elapsedSeconds: elapsedSeconds),
      'Animation':
          (context) => ExampleAnimation(elapsedSeconds: elapsedSeconds),
      'Imported Model':
          (context) => ExampleLogo(elapsedSeconds: elapsedSeconds),
      'Cuboid': (context) => ExampleCuboid(elapsedSeconds: elapsedSeconds),
      'Toon': (context) => ExampleToon(elapsedSeconds: elapsedSeconds),
      'Stress Tests':
          (context) => ExampleStressTests(elapsedSeconds: elapsedSeconds),
    };
    selectedExample = examples.keys.first;

    super.initState();
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
        body: Stack(
          children: [
            SizedBox.expand(child: examples[selectedExample]!(context)),
            // Example picker (top-left, overlaid on the scene).
            Positioned(
              top: 8,
              left: 8,
              child: _ExamplePicker(
                examples: examples.keys.toList(growable: false),
                selected: selectedExample,
                onSelected: (next) {
                  setState(() {
                    ticker.stop();
                    ticker.start();
                    selectedExample = next;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Top-left example selector. Uses [PopupMenuButton] so the menu opens
/// as an overlay above any of the example screens — a plain
/// [DropdownButton] tries to draw in-line and ended up clipped behind
/// list content on the stress-tests screen.
class _ExamplePicker extends StatelessWidget {
  const _ExamplePicker({
    required this.examples,
    required this.selected,
    required this.onSelected,
  });

  final List<String> examples;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: PopupMenuButton<String>(
        initialValue: selected,
        onSelected: onSelected,
        tooltip: 'Switch example',
        itemBuilder:
            (context) => [
              for (final name in examples)
                PopupMenuItem<String>(value: name, child: Text(name)),
            ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(selected, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
