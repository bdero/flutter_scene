// The native component scaffold. The Dart half has to be something the
// extractor can read, and the build-hook edit has to be something that
// compiles.
import 'package:flutter_scene_codegen/flutter_scene_codegen.dart';
import 'package:test/test.dart';

const _hook = '''
import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) {
  build(args, (input, output) async {
    buildScenes(buildInput: input, buildOutput: output);
  });
}
''';

void main() {
  group('the generated Dart half', () {
    test('is a component the extractor can read', () {
      final result = extractComponents(nativeComponentBinding('Wobble'));
      expect(result.diagnostics, isEmpty);
      final component = result.components.single;
      expect(component.className, 'Wobble');
      expect(component.schema.type, 'wobble');
    });

    test('declares an editable property, so the inspector is not empty', () {
      final component = extractComponents(
        nativeComponentBinding('Wobble'),
      ).components.single;
      expect(component.schema.properties.map((p) => p.name), contains('speed'));
    });

    test('looks up the symbol the C++ half exports', () {
      // The two files are generated together and only agree by construction;
      // a mismatch here fails at runtime with an unhelpful lookup error.
      expect(nativeComponentSource('Wobble'), contains('wobble_advance'));
      expect(nativeComponentBinding('Wobble'), contains('wobble_advance'));
    });

    test('the native half exports with C linkage', () {
      // C++ mangles names; a mangled name cannot be looked up by string.
      expect(nativeComponentSource('Wobble'), contains('extern "C"'));
    });
  });

  group('the build hook', () {
    test('gains the native build step', () {
      final updated = hookWithNativeComponents(_hook)!;
      expect(updated, contains('buildNativeComponents('));
      expect(hookBuildsNativeComponents(updated), isTrue);
      // Still inside the build callback, not after it.
      expect(
        updated.indexOf('buildNativeComponents('),
        greaterThan(updated.indexOf('build(args,')),
      );
    });

    test('a hook that already builds them is left alone', () {
      final updated = hookWithNativeComponents(_hook)!;
      expect(hookWithNativeComponents(updated), isNull);
    });

    test('the import is added when it is missing', () {
      const bare = '''
import 'package:hooks/hooks.dart';

void main(List<String> args) {
  build(args, (input, output) async {});
}
''';
      final updated = hookWithNativeComponents(bare)!;
      expect(
        updated,
        contains("import 'package:flutter_scene/build_hooks.dart'"),
      );
    });

    test('an unrecognised hook is refused rather than guessed at', () {
      // A native component that silently is not compiled fails at the symbol
      // lookup, a long way from the cause.
      expect(hookWithNativeComponents('void main() {}'), isNull);
    });
  });
}
