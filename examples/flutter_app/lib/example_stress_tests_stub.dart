import 'package:flutter/material.dart';

/// Web stub for [ExampleStressTests]. The real stress-test harness streams
/// glTF sample assets to disk via `dart:io` + `path_provider`, which aren't
/// available on web, so this placeholder stands in there.
class ExampleStressTests extends StatelessWidget {
  const ExampleStressTests({super.key, this.elapsedSeconds = 0});
  final double elapsedSeconds;

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'The stress-test harness downloads and caches glTF assets to disk '
          '(dart:io), so it is only available on native builds.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
