/// Builds the skinned and morphed GLB the `morph_skinned` smoke scene draws.
///
/// Generated in code rather than committed, so the fixture costs no bytes and
/// every number that shapes the frame is visible here. The mesh is a
/// four-sided tube along +Y, bound to two joints (a bend at its waist) and
/// carrying three morph targets, which is the smallest shape that shows
/// morph-before-skin ordering, since a target's displacement is carried by
/// the joint rotation above it.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Rows of the tube along +Y, and the four corners of its cross section.
const int _rows = 5;
const double _rowSpacing = 0.5;
const double _radius = 0.22;
const List<(int, int)> _corners = [(1, 1), (-1, 1), (-1, -1), (1, -1)];

/// Per-corner vertex colors, so a twist or a flip shows as the wrong hue
/// facing the camera. Linear values (roughly sRGB red, green, blue, and
/// yellow), since the engine encodes for display at resolve.
const List<List<double>> _cornerColors = [
  [0.79, 0.05, 0.03, 1.0],
  [0.04, 0.57, 0.09, 1.0],
  [0.05, 0.16, 0.89, 1.0],
  [0.89, 0.60, 0.03, 1.0],
];

/// The morph weights the scene pins, one per target. Distinct and nonzero, so
/// a dropped or reordered target changes the silhouette.
const List<double> kMorphSkinnedWeights = [0.85, 0.55, 0.70];

/// Names the targets carry into [MorphTargetData.targetNames].
const List<String> _targetNames = ['bulge', 'hook', 'twist'];

int get _vertexCount => _rows * _corners.length;

/// Builds the GLB bytes. Every value is a literal or derived from one, with
/// no randomness and no wall-clock input, so the bytes never vary.
Uint8List buildMorphSkinnedGlb() {
  final positions = Float32List(_vertexCount * 3);
  final normals = Float32List(_vertexCount * 3);
  final colors = Float32List(_vertexCount * 4);
  final joints = Uint8List(_vertexCount * 4);
  final weights = Float32List(_vertexCount * 4);
  final targetPositions = [
    for (var t = 0; t < _targetNames.length; t++) Float32List(_vertexCount * 3),
  ];
  final targetNormals = [
    for (var t = 0; t < _targetNames.length; t++) Float32List(_vertexCount * 3),
  ];

  for (var r = 0; r < _rows; r++) {
    final t = r / (_rows - 1);
    for (var c = 0; c < _corners.length; c++) {
      final (cx, cz) = _corners[c];
      final v = r * _corners.length + c;
      positions[v * 3] = cx * _radius;
      positions[v * 3 + 1] = r * _rowSpacing;
      positions[v * 3 + 2] = cz * _radius;
      // Diagonally outward, the cross section's corner normal.
      final n = 1.0 / math.sqrt2;
      normals[v * 3] = cx * n;
      normals[v * 3 + 2] = cz * n;
      colors.setAll(v * 4, _cornerColors[c]);

      // Joint 0 holds the base, joint 1 the top, blended across the waist row.
      final upper = t > 0.5
          ? 1.0
          : t == 0.5
          ? 0.5
          : 0.0;
      joints[v * 4] = 0;
      joints[v * 4 + 1] = 1;
      weights[v * 4] = 1.0 - upper;
      weights[v * 4 + 1] = upper;

      // The bulge target, a radial swell peaking at the waist.
      final bulge = math.sin(math.pi * t) * 0.22;
      targetPositions[0][v * 3] = cx * bulge;
      targetPositions[0][v * 3 + 2] = cz * bulge;

      // The hook target lifts the top and leans it toward +Z, tilting its
      // normals with it.
      final hook = math.max(0.0, (t - 0.5) * 2.0);
      targetPositions[1][v * 3 + 1] = 0.28 * hook;
      targetPositions[1][v * 3 + 2] = 0.50 * hook;
      targetNormals[1][v * 3 + 1] = 0.35 * hook;
      targetNormals[1][v * 3 + 2] = -0.20 * hook;

      // The twist target shears the two z halves apart, growing upward.
      targetPositions[2][v * 3] = 0.34 * t * (cz > 0 ? 1.0 : -1.0);
    }
  }

  final indices = <int>[];
  for (var r = 0; r < _rows - 1; r++) {
    for (var c = 0; c < _corners.length; c++) {
      final a = r * _corners.length + c;
      final b = r * _corners.length + (c + 1) % _corners.length;
      indices.addAll([a, a + _corners.length, b]);
      indices.addAll([b, a + _corners.length, b + _corners.length]);
    }
  }
  // Caps, so the ends read solid instead of showing the inside wall.
  final top = (_rows - 1) * _corners.length;
  indices.addAll([0, 1, 2, 0, 2, 3]);
  indices.addAll([top, top + 2, top + 1, top, top + 3, top + 2]);

  // Joint 0 sits at the origin, joint 1 a unit up; the inverse binds undo
  // those rest positions.
  final inverseBinds = Float32List.fromList([
    1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, //
    1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, -1, 0, 1,
  ]);

  final builder = _GlbBuilder();
  final positionAccessor = builder.addFloats(positions, 'VEC3', minMax: true);
  final normalAccessor = builder.addFloats(normals, 'VEC3');
  final colorAccessor = builder.addFloats(colors, 'VEC4');
  final jointAccessor = builder.addJoints(joints);
  final weightAccessor = builder.addFloats(weights, 'VEC4');
  final indexAccessor = builder.addIndices(indices);
  final inverseBindAccessor = builder.addFloats(inverseBinds, 'MAT4');
  final targets = [
    for (var t = 0; t < _targetNames.length; t++)
      {
        'POSITION': builder.addFloats(targetPositions[t], 'VEC3', minMax: true),
        'NORMAL': builder.addFloats(targetNormals[t], 'VEC3'),
      },
  ];

  return builder.finish({
    'asset': {'version': '2.0'},
    'extensionsUsed': ['KHR_materials_unlit'],
    'scene': 0,
    'scenes': [
      {
        'nodes': [0, 1],
      },
    ],
    'nodes': [
      {'name': 'MorphSkinned', 'mesh': 0, 'skin': 0},
      {
        'name': 'Joint0',
        // 12 degrees about X, so the whole shape leans.
        'rotation': [math.sin(_deg(6)), 0, 0, math.cos(_deg(6))],
        'children': [2],
      },
      {
        'name': 'Joint1',
        'translation': [0, 1, 0],
        // 50 degrees about Z, the waist bend the top half rides.
        'rotation': [0, 0, math.sin(_deg(25)), math.cos(_deg(25))],
      },
    ],
    'skins': [
      {
        'inverseBindMatrices': inverseBindAccessor,
        'joints': [1, 2],
      },
    ],
    'meshes': [
      {
        'name': 'MorphSkinned',
        'primitives': [
          {
            'attributes': {
              'POSITION': positionAccessor,
              'NORMAL': normalAccessor,
              'COLOR_0': colorAccessor,
              'JOINTS_0': jointAccessor,
              'WEIGHTS_0': weightAccessor,
            },
            'indices': indexAccessor,
            'material': 0,
            'mode': 4,
            'targets': targets,
          },
        ],
        'extras': {'targetNames': _targetNames},
      },
    ],
    'materials': [
      {
        'name': 'MorphSkinned',
        'doubleSided': true,
        'pbrMetallicRoughness': {
          'baseColorFactor': [1, 1, 1, 1],
        },
        // Unlit keeps the draw inside the GLES minimum texture-unit budget.
        // A skinned morphed vertex stage spends two samplers, which the lit
        // fragment stage's fifteen would push one over.
        // TODO(morph-sampler-budget): switch this scene to a lit material once
        // the joint matrices and morph deltas share one vertex-stage texture.
        'extensions': {'KHR_materials_unlit': <String, Object?>{}},
      },
    ],
  });
}

double _deg(double degrees) => degrees * math.pi / 180.0;

/// Accumulates accessors into one GLB binary chunk.
class _GlbBuilder {
  final BytesBuilder _binary = BytesBuilder();
  final List<Map<String, Object?>> _views = [];
  final List<Map<String, Object?>> _accessors = [];

  int _addView(TypedData data) {
    while (_binary.length % 4 != 0) {
      _binary.addByte(0);
    }
    final bytes = Uint8List.sublistView(data);
    _views.add({
      'buffer': 0,
      'byteOffset': _binary.length,
      'byteLength': bytes.length,
    });
    _binary.add(bytes);
    return _views.length - 1;
  }

  static const Map<String, int> _components = {
    'SCALAR': 1,
    'VEC3': 3,
    'VEC4': 4,
    'MAT4': 16,
  };

  int addFloats(Float32List values, String type, {bool minMax = false}) {
    final stride = _components[type]!;
    final count = values.length ~/ stride;
    final accessor = <String, Object?>{
      'bufferView': _addView(values),
      'componentType': 5126,
      'count': count,
      'type': type,
    };
    if (minMax) {
      final min = List<double>.filled(stride, double.infinity);
      final max = List<double>.filled(stride, double.negativeInfinity);
      for (var i = 0; i < count; i++) {
        for (var c = 0; c < stride; c++) {
          final value = values[i * stride + c];
          if (value < min[c]) min[c] = value;
          if (value > max[c]) max[c] = value;
        }
      }
      accessor['min'] = min;
      accessor['max'] = max;
    }
    _accessors.add(accessor);
    return _accessors.length - 1;
  }

  int addJoints(Uint8List values) {
    _accessors.add({
      'bufferView': _addView(values),
      'componentType': 5121,
      'count': values.length ~/ 4,
      'type': 'VEC4',
    });
    return _accessors.length - 1;
  }

  int addIndices(List<int> values) {
    _accessors.add({
      'bufferView': _addView(Uint16List.fromList(values)),
      'componentType': 5123,
      'count': values.length,
      'type': 'SCALAR',
    });
    return _accessors.length - 1;
  }

  Uint8List finish(Map<String, Object?> json) {
    final binary = _binary.toBytes();
    final document = <String, Object?>{
      ...json,
      'buffers': [
        {'byteLength': binary.length},
      ],
      'bufferViews': _views,
      'accessors': _accessors,
    };
    final jsonBytes = utf8.encode(jsonEncode(document));
    final jsonLength = (jsonBytes.length + 3) & ~3;
    final binaryLength = (binary.length + 3) & ~3;
    final output = BytesBuilder();
    void uint32(int value) => output.add(
      Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little),
    );
    output.add(ascii.encode('glTF'));
    uint32(2);
    uint32(12 + 8 + jsonLength + 8 + binaryLength);
    uint32(jsonLength);
    output.add(ascii.encode('JSON'));
    output.add(jsonBytes);
    final pad = jsonLength - jsonBytes.length;
    output.add(Uint8List(pad)..fillRange(0, pad, 0x20));
    uint32(binaryLength);
    output.add([0x42, 0x49, 0x4e, 0]);
    output.add(binary);
    output.add(Uint8List(binaryLength - binary.length));
    return output.takeBytes();
  }
}
