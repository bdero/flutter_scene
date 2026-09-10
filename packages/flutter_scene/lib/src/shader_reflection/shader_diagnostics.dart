/// Structured shader compile errors: the diagnostics parsed out of a
/// compiler log, and a marked source window around each.
library;

/// One message from a shader compiler.
/// {@category Debugging and profiling}
final class ShaderCompileDiagnostic {
  const ShaderCompileDiagnostic({
    required this.message,
    this.line,
    this.file,
    this.isError = true,
  });

  final String message;

  /// The 1-based source line, when the compiler reported one.
  final int? line;

  /// The file the compiler named, when it named one.
  final String? file;
  final bool isError;

  Map<String, Object?> toJson() => {
    'message': message,
    if (line != null) 'line': line,
    if (file != null) 'file': file,
    'error': isError,
  };

  @override
  String toString() =>
      '${isError ? 'error' : 'warning'}'
      '${file != null ? ' in $file' : ''}'
      '${line != null ? ' at line $line' : ''}: $message';
}

// glslang: `ERROR: 0:12: 'x' : undeclared identifier` and
// `ERROR: path/file.glsl:12: ...`. Some drivers print `WARNING:` the same way.
final RegExp _glslangLine = RegExp(
  r'^(ERROR|WARNING):\s*([^:\n]*?):(\d+):\s*(.*)$',
  multiLine: true,
);

// impellerc and clang-style: `path/file.glsl:12:5: error: message` or
// `file.glsl:12: error: message`.
final RegExp _clangLine = RegExp(
  r'^([^\s:]+\.\w+):(\d+)(?::\d+)?:\s*(error|warning):\s*(.*)$',
  multiLine: true,
);

/// Parses the diagnostics a shader compiler wrote to [log]. Lines that match
/// no known format are dropped, so a log with only prose yields nothing.
/// {@category Debugging and profiling}
List<ShaderCompileDiagnostic> parseShaderCompileErrors(String log) {
  final result = <ShaderCompileDiagnostic>[];
  for (final match in _glslangLine.allMatches(log)) {
    final file = match.group(2)!.trim();
    result.add(
      ShaderCompileDiagnostic(
        message: match.group(4)!.trim(),
        line: int.tryParse(match.group(3)!),
        // glslang names the source string index when it has no file.
        file: file.isEmpty || int.tryParse(file) != null ? null : file,
        isError: match.group(1) == 'ERROR',
      ),
    );
  }
  for (final match in _clangLine.allMatches(log)) {
    result.add(
      ShaderCompileDiagnostic(
        message: match.group(4)!.trim(),
        line: int.tryParse(match.group(2)!),
        file: match.group(1),
        isError: match.group(3) == 'error',
      ),
    );
  }
  return result;
}

/// [source] lines around 1-based [line], numbered, with the offending line
/// marked by `>`. [context] lines are shown on each side.
/// {@category Debugging and profiling}
String shaderSourceWindow(String source, int line, {int context = 3}) {
  final lines = source.split('\n');
  final first = (line - 1 - context).clamp(0, lines.length);
  final last = (line - 1 + context + 1).clamp(0, lines.length);
  final width = '$last'.length;
  final buffer = StringBuffer();
  for (var i = first; i < last; i++) {
    final number = '${i + 1}'.padLeft(width);
    buffer.writeln('${i + 1 == line ? '>' : ' '} $number | ${lines[i]}');
  }
  return buffer.toString();
}
