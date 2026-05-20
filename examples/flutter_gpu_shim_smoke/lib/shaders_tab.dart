import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import 'src/shader_bundle_generated.dart' as fb;

const String _bundleAsset = 'assets/base.shaderbundle';

class ShadersTab extends StatefulWidget {
  const ShadersTab({super.key});

  @override
  State<ShadersTab> createState() => _ShadersTabState();
}

enum _ProcessingMode { raw, strip, transpile }

class _ShadersTabState extends State<ShadersTab> {
  bool _running = false;
  _ProcessingMode _mode = _ProcessingMode.transpile;
  String? _fatal;
  int? _formatVersion;
  final List<_CompileResult> _results = [];

  static final RegExp _strippableExtensions = RegExp(
    r'^(#extension\s+(?:GL_OES_standard_derivatives|GL_EXT_shader_texture_lod)\b[^\n]*)',
    multiLine: true,
  );

  /// Replace `#extension` directives for features that are core in WebGL2's
  /// GLSL ES 3.00 dialect with a comment. Preserves line numbers so info-log
  /// references stay aligned. NB: WebGL2 does not promote these extensions to
  /// builtins for `#version 100` shaders; this alone is not enough to make
  /// Impeller's GLSL ES 1.00 output compile when it uses derivatives or
  /// explicit LOD.
  static String _stripWebGL2CoreExtensions(String source) {
    return source.replaceAllMapped(
      _strippableExtensions,
      (m) => '// stripped by shim: ${m.group(1)}',
    );
  }

  /// Mechanically transpile Impeller's GLSL ES 1.00 output to GLSL ES 3.00
  /// so it can compile in a WebGL2 context where the derivatives and
  /// explicit-LOD features are core. Not a general-purpose GLSL transpiler;
  /// it covers the transformations Impeller's emitter exercises.
  static String _transpileToGlsl300Es(
    String source, {
    required bool isFragment,
  }) {
    var out = source;

    // Version directive.
    out = out.replaceFirst(
      RegExp(r'^#version\s+100\b[^\n]*', multiLine: true),
      '#version 300 es',
    );

    // Drop extensions whose features are core in 300 es.
    out = out.replaceAll(
      RegExp(
        r'^#extension\s+(?:GL_OES_standard_derivatives|GL_EXT_shader_texture_lod)\b[^\n]*\n',
        multiLine: true,
      ),
      '',
    );

    // Storage qualifiers. `varying` becomes `in` in fragment shaders and
    // `out` in vertex shaders; `attribute` always becomes `in`.
    out = out.replaceAll(RegExp(r'\battribute\b'), 'in');
    out = out.replaceAll(RegExp(r'\bvarying\b'), isFragment ? 'in' : 'out');

    // Texture builtins. GLSL ES 3.00's `texture` and `textureLod` overload
    // on sampler type, so the 1.00 family collapses cleanly.
    out = out.replaceAll(RegExp(r'\btexture2DLodEXT\b'), 'textureLod');
    out = out.replaceAll(RegExp(r'\btexture2DLod\b'), 'textureLod');
    out = out.replaceAll(RegExp(r'\btextureCubeLod\b'), 'textureLod');
    out = out.replaceAll(RegExp(r'\btexture2DProj\b'), 'textureProj');
    out = out.replaceAll(RegExp(r'\btexture2D\b'), 'texture');
    out = out.replaceAll(RegExp(r'\btextureCube\b'), 'texture');

    if (isFragment) {
      // `gl_FragColor` and `gl_FragData[0]` are both gone in 3.00; redirect
      // them to an explicit out variable. Anything beyond index 0 would need
      // explicit `layout(location=N) out ...` declarations (multi-render-target);
      // flutter_scene's shaders don't use MRT today.
      out = out.replaceAll(RegExp(r'\bgl_FragColor\b'), '_frag_color');
      out = out.replaceAll(
        RegExp(r'\bgl_FragData\s*\[\s*0\s*\]'),
        '_frag_color',
      );

      const injection = '\n\nout highp vec4 _frag_color;\n';
      final precisionMatches =
          RegExp(
            r'precision\s+\w+\s+\w+\s*;',
            multiLine: true,
          ).allMatches(out).toList();
      if (precisionMatches.isNotEmpty) {
        final last = precisionMatches.last;
        out = out.substring(0, last.end) + injection + out.substring(last.end);
      } else {
        final firstNewline = out.indexOf('\n');
        out =
            '${out.substring(0, firstNewline + 1)}'
            '$injection'
            '${out.substring(firstNewline + 1)}';
      }
    }

    return out;
  }

  @override
  void initState() {
    super.initState();
    _runExperiment();
  }

  Future<void> _runExperiment() async {
    setState(() {
      _running = true;
      _fatal = null;
      _results.clear();
    });

    try {
      final data = await rootBundle.load(_bundleAsset);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final bundle = fb.ShaderBundle(bytes);
      _formatVersion = bundle.formatVersion;

      // Independent 1x1 GL context for the shader compile test. We bypass the
      // shim here because Surface.gl is web-only and isn't visible through
      // the unified package entry under static analysis.
      final canvas = web.OffscreenCanvas(1, 1);
      final gl = canvas.getContext('webgl2') as web.WebGL2RenderingContext?;
      if (gl == null) {
        throw StateError('WebGL2 unavailable; cannot run shader experiment.');
      }

      for (final shader in bundle.shaders ?? const <fb.Shader>[]) {
        final name = shader.name ?? '<unnamed>';
        final backend = shader.openglEs;
        if (backend == null) {
          _results.add(
            _CompileResult.skipped(name, 'no opengl_es variant in bundle'),
          );
          continue;
        }
        final sourceBytes = backend.shader;
        if (sourceBytes == null || sourceBytes.isEmpty) {
          _results.add(_CompileResult.skipped(name, 'empty shader source'));
          continue;
        }
        var source = utf8.decode(sourceBytes);
        final isFragment = backend.stage == fb.ShaderStage.kFragment;
        switch (_mode) {
          case _ProcessingMode.raw:
            break;
          case _ProcessingMode.strip:
            source = _stripWebGL2CoreExtensions(source);
          case _ProcessingMode.transpile:
            source = _transpileToGlsl300Es(source, isFragment: isFragment);
        }
        final stage =
            isFragment
                ? web.WebGL2RenderingContext.FRAGMENT_SHADER
                : web.WebGL2RenderingContext.VERTEX_SHADER;

        final compiled = _tryCompile(gl, stage, source);
        _results.add(
          _CompileResult(
            name: name,
            stage:
                backend.stage == fb.ShaderStage.kFragment
                    ? 'fragment'
                    : (backend.stage == fb.ShaderStage.kVertex
                        ? 'vertex'
                        : 'compute'),
            ok: compiled.ok,
            log: compiled.log,
            source: source,
          ),
        );
      }
    } catch (e, st) {
      _fatal = '$e\n$st';
    }

    if (mounted) {
      setState(() => _running = false);
    }
  }

  ({bool ok, String log}) _tryCompile(
    web.WebGL2RenderingContext gl,
    int stage,
    String source,
  ) {
    final shaderObj = gl.createShader(stage);
    if (shaderObj == null) {
      return (ok: false, log: 'gl.createShader returned null');
    }
    try {
      gl.shaderSource(shaderObj, source);
      gl.compileShader(shaderObj);
      final statusJs = gl.getShaderParameter(
        shaderObj,
        web.WebGL2RenderingContext.COMPILE_STATUS,
      );
      final ok = (statusJs as JSBoolean?)?.toDart ?? false;
      final log = gl.getShaderInfoLog(shaderObj) ?? '';
      return (ok: ok, log: log);
    } finally {
      gl.deleteShader(shaderObj);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_fatal != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(
            _fatal!,
            style: const TextStyle(color: Colors.red, fontFamily: 'monospace'),
          ),
        ),
      );
    }
    final passed = _results.where((r) => r.ok).length;
    final skipped = _results.where((r) => r.skipped).length;
    final failed = _results.length - passed - skipped;

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bundle: $_bundleAsset',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            'format version: ${_formatVersion ?? "?"}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            '$passed pass / $failed fail / $skipped skipped of ${_results.length}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (_running)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      OutlinedButton(
                        onPressed: _runExperiment,
                        child: const Text('Re-run'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('mode: ', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    SegmentedButton<_ProcessingMode>(
                      segments: const [
                        ButtonSegment(
                          value: _ProcessingMode.raw,
                          label: Text('Raw'),
                        ),
                        ButtonSegment(
                          value: _ProcessingMode.strip,
                          label: Text('Strip ext.'),
                        ),
                        ButtonSegment(
                          value: _ProcessingMode.transpile,
                          label: Text('Transpile → 300 es'),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged:
                          _running
                              ? null
                              : (s) {
                                setState(() => _mode = s.first);
                                _runExperiment();
                              },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _results.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (ctx, i) => _ShaderResultTile(result: _results[i]),
          ),
        ),
      ],
    );
  }
}

class _CompileResult {
  _CompileResult({
    required this.name,
    required this.stage,
    required this.ok,
    required this.log,
    required this.source,
  }) : skipped = false,
       skipReason = '';

  _CompileResult.skipped(this.name, this.skipReason)
    : stage = '?',
      ok = false,
      log = '',
      source = '',
      skipped = true;

  final String name;
  final String stage;
  final bool ok;
  final String log;
  final String source;
  final bool skipped;
  final String skipReason;
}

class _ShaderResultTile extends StatelessWidget {
  const _ShaderResultTile({required this.result});
  final _CompileResult result;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    if (result.skipped) {
      color = Colors.orange;
      icon = Icons.remove_circle_outline;
    } else if (result.ok) {
      color = Colors.green;
      icon = Icons.check_circle;
    } else {
      color = Colors.red;
      icon = Icons.error;
    }
    return ExpansionTile(
      leading: Icon(icon, color: color),
      title: Text(result.name),
      subtitle: Text(result.stage),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        if (result.skipped)
          _MonoBlock(label: 'reason', body: result.skipReason)
        else ...[
          if (result.log.isNotEmpty)
            _MonoBlock(label: 'info log', body: result.log)
          else
            const _MonoBlock(label: 'info log', body: '(empty)'),
          const SizedBox(height: 8),
          _MonoBlock(label: 'source', body: result.source, maxLines: 40),
        ],
      ],
    );
  }
}

class _MonoBlock extends StatelessWidget {
  const _MonoBlock({required this.label, required this.body, this.maxLines});
  final String label;
  final String body;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          color: Colors.black.withValues(alpha: 0.04),
          child: Text(
            body,
            maxLines: maxLines,
            overflow:
                maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
      ],
    );
  }
}
