// Parser for the `.fmat` custom-material format.
//
// A `.fmat` file has two top-level blocks: a `material { ... }` metadata block
// in a small JSON-like dialect, and a `fragment { ... }` block of verbatim
// GLSL. This file extracts the two blocks (brace-matching while skipping
// comments), lexes and parses the metadata dialect into a generic value tree,
// then builds and validates an [FmatMaterial].

import 'package:flutter_scene/src/fmat/fmat_ast.dart';

/// Parses [source] into a validated [FmatMaterial]. Throws [FmatException] on
/// any syntax or validation error.
FmatMaterial parseFmat(String source, {String? fileName}) {
  final blocks = _extractBlocks(source, fileName);

  final material = blocks['material'];
  if (material == null) {
    throw FmatException(
      'Missing required `material { ... }` block.',
      fileName: fileName,
    );
  }
  final fragment = blocks['fragment'];
  if (fragment == null) {
    throw FmatException(
      'Missing required `fragment { ... }` block.',
      fileName: fileName,
    );
  }

  final tokens =
      _Lexer(material.content, fileName, material.startLine).tokenize();
  final tree = _ValueParser(tokens, fileName).parseObjectBody();

  return _build(tree, fragment, fileName);
}

// ---------------------------------------------------------------------------
// Block extraction.
// ---------------------------------------------------------------------------

class _Block {
  _Block(this.content, this.startLine);
  final String content;
  final int startLine;
}

/// Walks the top level of [source], returning each `keyword { ... }` block by
/// keyword. Brace matching skips `//` and `/* */` comments so braces inside
/// GLSL comments do not throw off the count.
Map<String, _Block> _extractBlocks(String source, String? fileName) {
  final blocks = <String, _Block>{};
  var i = 0;
  var line = 1;

  ({int i, int line}) skipTrivia(int i, int line) {
    while (i < source.length) {
      final c = source[i];
      if (c == '\n') {
        line++;
        i++;
      } else if (c == ' ' || c == '\t' || c == '\r') {
        i++;
      } else if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
        while (i < source.length && source[i] != '\n') {
          i++;
        }
      } else if (c == '/' && i + 1 < source.length && source[i + 1] == '*') {
        i += 2;
        while (i + 1 < source.length &&
            !(source[i] == '*' && source[i + 1] == '/')) {
          if (source[i] == '\n') line++;
          i++;
        }
        i += 2;
      } else {
        break;
      }
    }
    return (i: i, line: line);
  }

  while (true) {
    final t = skipTrivia(i, line);
    i = t.i;
    line = t.line;
    if (i >= source.length) break;

    // Read a keyword identifier.
    final keywordStart = i;
    while (i < source.length && _isIdentChar(source[i])) {
      i++;
    }
    if (i == keywordStart) {
      throw FmatException(
        'Expected a top-level block keyword (`material` or `fragment`).',
        fileName: fileName,
        line: line,
      );
    }
    final keyword = source.substring(keywordStart, i);

    final t2 = skipTrivia(i, line);
    i = t2.i;
    line = t2.line;
    if (i >= source.length || source[i] != '{') {
      throw FmatException(
        'Expected `{` after `$keyword`.',
        fileName: fileName,
        line: line,
      );
    }

    // Capture the brace-matched content.
    i++; // past '{'
    final contentStartLine = line;
    final contentStart = i;
    var depth = 1;
    while (i < source.length && depth > 0) {
      final c = source[i];
      if (c == '\n') {
        line++;
        i++;
      } else if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
        while (i < source.length && source[i] != '\n') {
          i++;
        }
      } else if (c == '/' && i + 1 < source.length && source[i + 1] == '*') {
        i += 2;
        while (i + 1 < source.length &&
            !(source[i] == '*' && source[i + 1] == '/')) {
          if (source[i] == '\n') line++;
          i++;
        }
        i += 2;
      } else {
        if (c == '{') depth++;
        if (c == '}') depth--;
        i++;
      }
    }
    if (depth != 0) {
      throw FmatException(
        'Unterminated `$keyword { ... }` block.',
        fileName: fileName,
        line: contentStartLine,
      );
    }
    final content = source.substring(contentStart, i - 1);
    if (blocks.containsKey(keyword)) {
      throw FmatException(
        'Duplicate `$keyword` block.',
        fileName: fileName,
        line: contentStartLine,
      );
    }
    blocks[keyword] = _Block(content, contentStartLine);
  }

  return blocks;
}

bool _isIdentChar(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 0x30 && u <= 0x39) || // 0-9
      (u >= 0x41 && u <= 0x5A) || // A-Z
      (u >= 0x61 && u <= 0x7A) || // a-z
      u == 0x5F; // _
}

bool _isIdentStart(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || u == 0x5F;
}

// ---------------------------------------------------------------------------
// Lexer for the metadata dialect.
// ---------------------------------------------------------------------------

enum _Tok {
  lbrace,
  rbrace,
  lbracket,
  rbracket,
  lparen,
  rparen,
  colon,
  comma,
  ident,
  number,
  string,
  eof,
}

class _Token {
  _Token(this.type, this.value, this.line);
  final _Tok type;
  final Object? value;
  final int line;
}

class _Lexer {
  _Lexer(this.source, this.fileName, this.baseLine);
  final String source;
  final String? fileName;
  final int baseLine;

  int _i = 0;
  int _line = 0; // newlines seen within the content

  int get _reportLine => baseLine + _line;

  List<_Token> tokenize() {
    final tokens = <_Token>[];
    while (true) {
      _skipTrivia();
      if (_i >= source.length) {
        tokens.add(_Token(_Tok.eof, null, _reportLine));
        return tokens;
      }
      final c = source[_i];
      final single = _singleCharToken(c);
      if (single != null) {
        tokens.add(_Token(single, c, _reportLine));
        _i++;
      } else if (c == '"') {
        tokens.add(_lexString());
      } else if (c == '-' || _isDigit(c)) {
        tokens.add(_lexNumber());
      } else if (_isIdentStart(c)) {
        tokens.add(_lexIdent());
      } else {
        throw FmatException(
          'Unexpected character `$c`.',
          fileName: fileName,
          line: _reportLine,
        );
      }
    }
  }

  _Tok? _singleCharToken(String c) => switch (c) {
    '{' => _Tok.lbrace,
    '}' => _Tok.rbrace,
    '[' => _Tok.lbracket,
    ']' => _Tok.rbracket,
    '(' => _Tok.lparen,
    ')' => _Tok.rparen,
    ':' => _Tok.colon,
    ',' => _Tok.comma,
    _ => null,
  };

  void _skipTrivia() {
    while (_i < source.length) {
      final c = source[_i];
      if (c == '\n') {
        _line++;
        _i++;
      } else if (c == ' ' || c == '\t' || c == '\r') {
        _i++;
      } else if (c == '/' && _i + 1 < source.length && source[_i + 1] == '/') {
        while (_i < source.length && source[_i] != '\n') {
          _i++;
        }
      } else if (c == '/' && _i + 1 < source.length && source[_i + 1] == '*') {
        _i += 2;
        while (_i + 1 < source.length &&
            !(source[_i] == '*' && source[_i + 1] == '/')) {
          if (source[_i] == '\n') _line++;
          _i++;
        }
        _i += 2;
      } else {
        break;
      }
    }
  }

  _Token _lexString() {
    final startLine = _reportLine;
    _i++; // opening quote
    final sb = StringBuffer();
    while (_i < source.length && source[_i] != '"') {
      if (source[_i] == '\n') {
        throw FmatException(
          'Unterminated string.',
          fileName: fileName,
          line: startLine,
        );
      }
      sb.write(source[_i]);
      _i++;
    }
    if (_i >= source.length) {
      throw FmatException(
        'Unterminated string.',
        fileName: fileName,
        line: startLine,
      );
    }
    _i++; // closing quote
    return _Token(_Tok.string, sb.toString(), startLine);
  }

  _Token _lexNumber() {
    final startLine = _reportLine;
    final start = _i;
    if (source[_i] == '-') _i++;
    while (_i < source.length && _isDigit(source[_i])) {
      _i++;
    }
    var isDouble = false;
    if (_i < source.length && source[_i] == '.') {
      isDouble = true;
      _i++;
      while (_i < source.length && _isDigit(source[_i])) {
        _i++;
      }
    }
    final text = source.substring(start, _i);
    final num value = isDouble ? double.parse(text) : int.parse(text);
    return _Token(_Tok.number, value, startLine);
  }

  _Token _lexIdent() {
    final startLine = _reportLine;
    final start = _i;
    while (_i < source.length && _isIdentChar(source[_i])) {
      _i++;
    }
    return _Token(_Tok.ident, source.substring(start, _i), startLine);
  }

  bool _isDigit(String c) {
    final u = c.codeUnitAt(0);
    return u >= 0x30 && u <= 0x39;
  }
}

// ---------------------------------------------------------------------------
// Generic value tree.
// ---------------------------------------------------------------------------

/// A bare identifier in the metadata dialect (an enum value or a type name).
class _Ident {
  _Ident(this.name, this.line);
  final String name;
  final int line;
}

/// A function-call value, e.g. `range(0, 1, 0.01)`.
class _Call {
  _Call(this.name, this.args, this.line);
  final String name;
  final List<Object?> args;
  final int line;
}

class _ValueParser {
  _ValueParser(this.tokens, this.fileName);
  final List<_Token> tokens;
  final String? fileName;
  int _p = 0;

  _Token get _cur => tokens[_p];
  _Token _advance() => tokens[_p++];

  _Token _expect(_Tok type, String what) {
    if (_cur.type != type) {
      throw FmatException(
        'Expected $what.',
        fileName: fileName,
        line: _cur.line,
      );
    }
    return _advance();
  }

  /// Parses the body of an object (no surrounding braces): `key : value`
  /// pairs separated by commas, with an optional trailing comma. Used for the
  /// top-level material block content.
  Map<String, Object?> parseObjectBody() {
    final map = _parsePairsUntil(_Tok.eof);
    _expect(_Tok.eof, 'end of the material block');
    return map;
  }

  Map<String, Object?> _parsePairsUntil(_Tok terminator) {
    final map = <String, Object?>{};
    while (_cur.type != terminator) {
      if (_cur.type != _Tok.ident && _cur.type != _Tok.string) {
        throw FmatException(
          'Expected a key.',
          fileName: fileName,
          line: _cur.line,
        );
      }
      final key = _advance().value as String;
      if (map.containsKey(key)) {
        throw FmatException(
          'Duplicate key `$key`.',
          fileName: fileName,
          line: _cur.line,
        );
      }
      _expect(_Tok.colon, '`:` after `$key`');
      map[key] = _parseValue();
      if (_cur.type == _Tok.comma) {
        _advance();
      } else {
        break;
      }
    }
    return map;
  }

  Object? _parseValue() {
    final t = _cur;
    switch (t.type) {
      case _Tok.string:
        _advance();
        return t.value;
      case _Tok.number:
        _advance();
        return t.value;
      case _Tok.lbrace:
        _advance();
        final map = _parsePairsUntil(_Tok.rbrace);
        _expect(_Tok.rbrace, '`}`');
        return map;
      case _Tok.lbracket:
        return _parseArray();
      case _Tok.ident:
        _advance();
        if (_cur.type == _Tok.lparen) {
          return _parseCall(t.value as String, t.line);
        }
        return _Ident(t.value as String, t.line);
      default:
        throw FmatException(
          'Expected a value.',
          fileName: fileName,
          line: t.line,
        );
    }
  }

  List<Object?> _parseArray() {
    _expect(_Tok.lbracket, '`[`');
    final list = <Object?>[];
    while (_cur.type != _Tok.rbracket) {
      list.add(_parseValue());
      if (_cur.type == _Tok.comma) {
        _advance();
      } else {
        break;
      }
    }
    _expect(_Tok.rbracket, '`]`');
    return list;
  }

  _Call _parseCall(String name, int line) {
    _expect(_Tok.lparen, '`(`');
    final args = <Object?>[];
    while (_cur.type != _Tok.rparen) {
      args.add(_parseValue());
      if (_cur.type == _Tok.comma) {
        _advance();
      } else {
        break;
      }
    }
    _expect(_Tok.rparen, '`)`');
    return _Call(name, args, line);
  }
}

// ---------------------------------------------------------------------------
// AST builder + validation.
// ---------------------------------------------------------------------------

const _reservedNames = <String>{
  'frag_info',
  'FragInfo',
  'frag_color',
  'v_position',
  'v_normal',
  'v_viewvector',
  'v_texture_coords',
  'v_color',
  'prefiltered_radiance',
  'brdf_lut',
  'shadow_map',
  'MaterialInputs',
  'material',
  'material_params',
  'MaterialParams',
  'Surface',
  'EvaluateLighting',
  'InitMaterialInputs',
  'PrepareMaterial',
  'GetWorldPosition',
  'GetWorldNormal',
  'GetViewDirection',
  'GetUV0',
  'GetVertexColor',
  'main',
};

FmatMaterial _build(
  Map<String, Object?> tree,
  _Block fragment,
  String? fileName,
) {
  const knownKeys = {
    'name',
    'shading_model',
    'blending',
    'culling',
    'parameters',
    'requires',
  };
  for (final key in tree.keys) {
    if (!knownKeys.contains(key)) {
      throw FmatException('Unknown material key `$key`.', fileName: fileName);
    }
  }

  final name = tree['name'];
  if (name is! String || name.isEmpty) {
    throw FmatException(
      '`name` is required and must be a non-empty string.',
      fileName: fileName,
    );
  }

  final shadingModel = _enum<FmatShadingModel>(
    tree['shading_model'],
    FmatShadingModel.values,
    'shading_model',
    defaultValue: FmatShadingModel.lit,
    fileName: fileName,
  );
  final blending = _enum<FmatBlending>(
    tree['blending'],
    FmatBlending.values,
    'blending',
    defaultValue: FmatBlending.opaque,
    fileName: fileName,
  );
  final culling = _enum<FmatCulling>(
    tree['culling'],
    FmatCulling.values,
    'culling',
    defaultValue: FmatCulling.back,
    fileName: fileName,
  );

  final parameters = _buildParameters(tree['parameters'], fileName);

  // Loose check: the fragment block must define a Surface function. We do not
  // fully parse GLSL; this catches the common omission with a clear message.
  if (!RegExp(r'\bvoid\s+Surface\s*\(').hasMatch(fragment.content)) {
    throw FmatException(
      'The `fragment` block must define '
      '`void Surface(inout MaterialInputs material)`.',
      fileName: fileName,
      line: fragment.startLine,
    );
  }

  return FmatMaterial(
    name: name,
    shadingModel: shadingModel,
    blending: blending,
    culling: culling,
    parameters: parameters,
    fragmentSource: fragment.content,
    fragmentSourceLine: fragment.startLine,
  );
}

T _enum<T extends Enum>(
  Object? value,
  List<T> values,
  String key, {
  required T defaultValue,
  String? fileName,
}) {
  if (value == null) return defaultValue;
  if (value is! _Ident) {
    throw FmatException(
      '`$key` must be one of ${values.map((v) => v.name)}.',
      fileName: fileName,
    );
  }
  for (final v in values) {
    if (v.name == value.name) return v;
  }
  throw FmatException(
    '`$key` is `${value.name}`, expected one of ${values.map((v) => v.name)}.',
    fileName: fileName,
    line: value.line,
  );
}

List<FmatParameter> _buildParameters(Object? raw, String? fileName) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw FmatException('`parameters` must be a list.', fileName: fileName);
  }
  final params = <FmatParameter>[];
  final seen = <String>{};
  for (final entry in raw) {
    if (entry is! Map<String, Object?>) {
      throw FmatException(
        'Each parameter must be an object.',
        fileName: fileName,
      );
    }
    for (final key in entry.keys) {
      if (!{'type', 'name', 'hint', 'default'}.contains(key)) {
        throw FmatException(
          'Unknown parameter key `$key`.',
          fileName: fileName,
        );
      }
    }

    final typeTok = entry['type'];
    if (typeTok is! _Ident) {
      throw FmatException('Parameter `type` is required.', fileName: fileName);
    }
    if (typeTok.name == 'mat3') {
      throw FmatException(
        '`mat3` parameters are not supported because of a GLES std140 '
        'layout bug; use `mat4`.',
        fileName: fileName,
        line: typeTok.line,
      );
    }
    final type = FmatType.fromToken(typeTok.name);
    if (type == null) {
      throw FmatException(
        'Unknown parameter type `${typeTok.name}`.',
        fileName: fileName,
        line: typeTok.line,
      );
    }

    final nameVal = entry['name'];
    final pname = switch (nameVal) {
      String s => s,
      _Ident id => id.name,
      _ =>
        throw FmatException(
          'Parameter `name` is required.',
          fileName: fileName,
        ),
    };
    _validateParamName(pname, fileName);
    if (!seen.add(pname)) {
      throw FmatException(
        'Duplicate parameter name `$pname`.',
        fileName: fileName,
      );
    }

    final hint = _buildHint(entry['hint'], type, pname, fileName);
    final defaultValue = _buildDefault(entry['default'], type, pname, fileName);

    params.add(
      FmatParameter(
        type: type,
        name: pname,
        hint: hint,
        defaultValue: defaultValue,
      ),
    );
  }
  return params;
}

void _validateParamName(String name, String? fileName) {
  if (name.isEmpty ||
      !_isIdentStart(name[0]) ||
      !name.split('').every(_isIdentChar)) {
    throw FmatException(
      '`$name` is not a valid identifier.',
      fileName: fileName,
    );
  }
  if (name.startsWith('gl_')) {
    throw FmatException(
      'Parameter names may not start with `gl_`.',
      fileName: fileName,
    );
  }
  if (_reservedNames.contains(name)) {
    throw FmatException(
      '`$name` collides with an engine-reserved identifier.',
      fileName: fileName,
    );
  }
}

FmatHint? _buildHint(
  Object? raw,
  FmatType type,
  String pname,
  String? fileName,
) {
  if (raw == null) return null;

  FmatHint colorHint(int line) {
    if (type != FmatType.vec3 && type != FmatType.vec4) {
      throw FmatException(
        '`source_color` on `$pname` requires a vec3 or vec4.',
        fileName: fileName,
        line: line,
      );
    }
    return const FmatHint(FmatHintKind.sourceColor);
  }

  FmatHint samplerDefault(FmatHintKind kind, int line) {
    if (!type.isSampler) {
      throw FmatException(
        'A sampler-default hint on `$pname` requires a sampler type.',
        fileName: fileName,
        line: line,
      );
    }
    return FmatHint(kind);
  }

  if (raw is _Ident) {
    return switch (raw.name) {
      'source_color' => colorHint(raw.line),
      'default_white' => samplerDefault(FmatHintKind.defaultWhite, raw.line),
      'default_black' => samplerDefault(FmatHintKind.defaultBlack, raw.line),
      'default_normal' => samplerDefault(FmatHintKind.defaultNormal, raw.line),
      'default_transparent' => samplerDefault(
        FmatHintKind.defaultTransparent,
        raw.line,
      ),
      _ =>
        throw FmatException(
          'Unknown hint `${raw.name}` on `$pname`.',
          fileName: fileName,
          line: raw.line,
        ),
    };
  }
  if (raw is _Call && raw.name == 'range') {
    if (type != FmatType.float_ && type != FmatType.int_) {
      throw FmatException(
        '`range` on `$pname` requires a float or int.',
        fileName: fileName,
        line: raw.line,
      );
    }
    if (raw.args.length != 3 || raw.args.any((a) => a is! num)) {
      throw FmatException(
        '`range` takes three numbers: range(min, max, step).',
        fileName: fileName,
        line: raw.line,
      );
    }
    return FmatHint(
      FmatHintKind.range,
      rangeMin: (raw.args[0] as num).toDouble(),
      rangeMax: (raw.args[1] as num).toDouble(),
      rangeStep: (raw.args[2] as num).toDouble(),
    );
  }
  throw FmatException('Invalid hint on `$pname`.', fileName: fileName);
}

Object? _buildDefault(
  Object? raw,
  FmatType type,
  String pname,
  String? fileName,
) {
  if (raw == null) return null;
  if (type.isSampler) {
    throw FmatException(
      'Samplers take a placeholder via `hint`, not `default` (`$pname`).',
      fileName: fileName,
    );
  }
  if (type == FmatType.float_) {
    if (raw is! num) {
      throw FmatException(
        '`default` for `$pname` must be a number.',
        fileName: fileName,
      );
    }
    return raw.toDouble();
  }
  if (type == FmatType.int_) {
    if (raw is! num || raw != raw.toInt()) {
      throw FmatException(
        '`default` for `$pname` must be an integer.',
        fileName: fileName,
      );
    }
    return raw.toInt();
  }
  // Vector / matrix.
  if (raw is! List || raw.any((e) => e is! num)) {
    throw FmatException(
      '`default` for `$pname` must be a list of ${type.componentCount} '
      'numbers.',
      fileName: fileName,
    );
  }
  if (raw.length != type.componentCount) {
    throw FmatException(
      '`default` for `$pname` has ${raw.length} components, '
      'expected ${type.componentCount}.',
      fileName: fileName,
    );
  }
  return raw.map((e) => (e as num).toDouble()).toList();
}
