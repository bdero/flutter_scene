/// The starter source for a hand-written component script.
///
/// The editor writes one of these when you ask for a new component. It lives
/// here rather than in the editor
/// so it can be checked against the extractor that has to parse it: a
/// template the extractor cannot read is worse than no template at all.
library;

/// The Dart identifier rules this template needs: an upper-camel class name
/// that is not a reserved word.
const _reservedWords = <String>{
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

/// Why [componentClassNameError] rejected a name, or null when it is usable.
///
/// Checked before a file is written, so the failure is a message rather than
/// a source file that will not parse.
String? componentClassNameError(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Give the component a name.';
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(trimmed)) {
    return 'Use letters, digits and underscores, starting with a letter.';
  }
  if (_reservedWords.contains(trimmed.toLowerCase())) {
    return '"$trimmed" is a Dart keyword.';
  }
  return null;
}

/// The class name [name] becomes: upper camel case, punctuation dropped.
String componentClassName(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((part) => part.isNotEmpty);
  return parts.map((part) => part[0].toUpperCase() + part.substring(1)).join();
}

/// The document type tag for [className]: its lower-camel form, which is what
/// every built-in component uses (`pointLight`, `cameraDirector`).
String componentTypeTag(String className) => className.isEmpty
    ? className
    : className[0].toLowerCase() + className.substring(1);

/// The file [className] is written to, relative to `lib/components/`.
String componentFileName(String className) {
  final buffer = StringBuffer();
  for (var i = 0; i < className.length; i++) {
    final char = className[i];
    final upper = char.toUpperCase() == char && char.toLowerCase() != char;
    if (upper && i > 0) buffer.write('_');
    buffer.write(char.toLowerCase());
  }
  return '${buffer.toString()}.dart';
}

/// The starter source for [className].
///
/// It compiles as written and carries one property of each shape a beginner
/// reaches for first, so the generated inspector has something in it the
/// moment the file is saved.
String componentScriptSource(String className) {
  final tag = componentTypeTag(className);
  return '''
import 'package:flutter_scene/annotations.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// Describe what $className does; this comment becomes the component's
/// description in the editor.
@SceneComponent('$tag')
class $className extends Component {
  /// Turns per second.
  @NumberProperty()
  double speed = 1.0;

  /// The axis to turn about.
  @Vec3Property()
  Vector3 axis = Vector3(0.0, 1.0, 0.0);

  /// Whether the motion runs at all.
  @BoolProperty()
  bool enabled = true;

  @override
  void update(double deltaSeconds) {
    if (!enabled || !isAttached) return;
    final turn = Quaternion.axisAngle(
      axis.normalized(),
      speed * deltaSeconds * 2 * 3.1415926535897932,
    );
    node.rotation = node.rotation * turn;
  }
}
''';
}
