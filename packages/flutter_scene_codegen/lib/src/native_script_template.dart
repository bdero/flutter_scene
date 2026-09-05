/// The starter files for a native component: the C++ that does the work and
/// the Dart component that owns it.
///
/// The split is the point. The C++ never learns about the scene graph — it
/// takes numbers and returns numbers — and the Dart wrapper is the component,
/// so it gets the inspector, the codec, the document form and MCP access the
/// same way a pure Dart one does. That is also what keeps the native side
/// testable on its own.
library;

import 'package:flutter_scene_codegen/src/script_template.dart';

/// The C++ source for [className].
///
/// Exported with C linkage and a name prefixed by the component, because the
/// whole project's native sources land in one library and C++ name mangling
/// would make these unfindable from `dart:ffi`.
String nativeComponentSource(String className) {
  final symbol = componentTypeTag(className);
  return '''
// The native half of the $className component.
//
// Keep this side free of scene-graph concepts: it takes numbers and returns
// numbers, which is what makes it callable from Dart, testable on its own,
// and portable to another host later.
//
// Every symbol Dart looks up must be extern "C". C++ mangles names, and a
// mangled name is not findable by DynamicLibrary.lookup.

#include <cmath>

extern "C" {

// Called once per frame with the elapsed time, returning this component's
// current value. Replace with whatever this component is actually for.
double ${symbol}_advance(double seconds, double speed) {
  return std::sin(seconds * speed);
}

}
''';
}

/// The Dart component wrapping [className]'s native half.
String nativeComponentBinding(String className) {
  final symbol = componentTypeTag(className);
  return '''
import 'dart:ffi';

import 'package:flutter_scene/annotations.dart';
import 'package:flutter_scene/scene.dart';

/// The native function this component calls each frame.
typedef _AdvanceNative = Double Function(Double, Double);
typedef _AdvanceDart = double Function(double, double);

/// Describe what $className does; this comment becomes the component's
/// description in the editor.
@SceneComponent('$symbol')
class $className extends Component {
  /// How fast the native side advances.
  @NumberProperty()
  double speed = 1.0;

  /// The value the native side last returned, for anything reading it.
  double get value => _value;
  double _value = 0.0;

  double _elapsed = 0.0;

  // Looked up once rather than per frame: a lookup is a string search through
  // the library's symbol table, which is not something to do sixty times a
  // second.
  static final _AdvanceDart _advance = () {
    // The library every native component in this project is compiled into.
    // DynamicLibrary.process() finds it because the build hook bundles it
    // with the app rather than shipping it as a separate file to open.
    final library = DynamicLibrary.process();
    return library
        .lookupFunction<_AdvanceNative, _AdvanceDart>('${symbol}_advance');
  }();

  @override
  void update(double deltaSeconds) {
    _elapsed += deltaSeconds;
    _value = _advance(_elapsed, speed);
  }
}
''';
}

/// The line a project's build hook needs so its native sources are compiled.
const String nativeComponentHookCall =
    '    await buildNativeComponents(buildInput: input, buildOutput: output);';

/// Whether [hookSource] already compiles native components.
bool hookBuildsNativeComponents(String hookSource) =>
    hookSource.contains('buildNativeComponents(');

/// [hookSource] with the native build step added, or null when it is already
/// there or the hook is not the shape `flutter_scene:init` writes.
///
/// Editing someone's build hook is worth doing carefully: a native component
/// that silently is not compiled fails at the symbol lookup, a long way from
/// the cause. When the hook does not match, the caller is told to add the one
/// line itself rather than having it guessed at.
String? hookWithNativeComponents(String hookSource) {
  if (hookBuildsNativeComponents(hookSource)) return null;
  const anchor = 'build(args, (input, output) async {';
  if (!hookSource.contains(anchor)) return null;

  const import = "import 'package:flutter_scene/build_hooks.dart';";
  var result = hookSource;
  if (!result.contains(import)) {
    result = '$import\n$result';
  }
  final at = result.indexOf(anchor) + anchor.length;
  return '${result.substring(0, at)}\n$nativeComponentHookCall'
      '${result.substring(at)}';
}
