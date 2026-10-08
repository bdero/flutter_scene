@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the velocity frame block matches across stages', () {
    // WebGL2 refuses to link a program whose shared block differs between
    // stages, which silently dropped object motion on the web.
    List<String> members(String path) {
      final source = File(path).readAsStringSync();
      final block = RegExp(
        r'uniform VelocityFrameInfo \{([^}]*)\}',
      ).firstMatch(source)!.group(1)!;
      return [
        for (final line in block.split('\n'))
          if (line.contains(';'))
            line.split(';').first.trim().replaceFirst('highp ', ''),
      ];
    }

    final fragment = members('shaders/flutter_scene_velocity.frag');
    for (final vertex in [
      'shaders/flutter_scene_velocity_unskinned.vert',
      'shaders/flutter_scene_velocity_skinned.vert',
    ]) {
      expect(fragment, members(vertex), reason: vertex);
    }
  });
}
