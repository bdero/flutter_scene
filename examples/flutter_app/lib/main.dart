import 'package:example_app/example_car.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:example_app/example_animation.dart';

import 'example_cuboid.dart';
import 'example_logo.dart';

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
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: Text('Example: $selectedExample'),
        ),
        body: Stack(
          children: [
            SizedBox.expand(child: examples[selectedExample]!(context)),
            // Dropdown menu
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: DropdownButton<String>(
                  value: selectedExample,
                  items:
                      examples.keys.map<DropdownMenuItem<String>>((
                        String value,
                      ) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      ticker.stop();
                      ticker.start();
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
