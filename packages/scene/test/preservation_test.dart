// Data this build does not understand must survive a load and a save, so an
// editor without an extension installed never destroys that extension's work.
import 'dart:convert';
import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:test/test.dart';

/// A document with one of everything the preservation contract covers.
SceneDocument _document() {
  final doc = SceneDocument(
    documentId: DocumentId(Uint8List(16)..fillRange(0, 16, 3)),
    allocator: IdAllocator(session: 9),
  );
  final payload = doc.allocator.mint();
  doc.payloads[payload] = PayloadSpec(
    payload,
    encoding: PayloadEncoding.vertexBuffer,
    layout: 'unskinned',
    length: 8,
    bytes: Uint8List.fromList(List.filled(8, 1)),
  );
  final geometry = doc.allocator.mint();
  doc.resources[geometry] = GeometryResource(geometry, vertices: payload);
  final node = doc.allocator.mint();
  doc.nodes[node] = NodeSpec(
    id: node,
    name: 'Crate',
    components: [ComponentSpec('mesh')],
  );
  doc.roots.add(node);
  return doc;
}

/// Injects [keys] into the JSON object at [path] of [text].
String _inject(String text, List<String> path, Map<String, Object?> keys) {
  final json = jsonDecode(text) as Map<String, Object?>;
  Object? cursor = json;
  for (final step in path) {
    cursor = switch (cursor) {
      Map<String, Object?> map when step.startsWith('*') =>
        map.values.elementAt(step == '*' ? 0 : int.parse(step.substring(1))),
      Map<String, Object?> map => map[step],
      List<Object?> list => list[int.parse(step)],
      _ => throw StateError('no $step'),
    };
  }
  (cursor! as Map<String, Object?>).addAll(keys);
  return const JsonEncoder.withIndent('  ').convert(json);
}

void main() {
  test('a clean document is unchanged by the preservation path', () {
    final text = writeFscene(_document());
    expect(writeFscene(readFscene(text)), text);
    final reread = readFscene(text);
    expect(reread.unknown, isEmpty);
    expect(reread.nodes.values.single.unknown, isEmpty);
    expect(reread.nodes.values.single.components.single.unknown, isEmpty);
    expect(reread.resources.values.single.unknown, isEmpty);
    expect(reread.payloads.values.single.unknown, isEmpty);
  });

  test('unknown keys survive a load and save at every level', () {
    var text = writeFscene(_document());
    text = _inject(text, [], {
      'dev.example.sdf': {'quality': 3},
    });
    text = _inject(text, ['stage'], {'dev.example.sdf': 'stage data'});
    text = _inject(
      text,
      ['nodes', '*'],
      {
        'dev.example.sdf': {'volume': 'vol1'},
      },
    );
    text = _inject(text, ['nodes', '*', 'components', '0'], {'extras': 7});
    text = _inject(text, ['resources', '*'], {'dev.example.sdf': true});
    text = _inject(text, ['payloads', '*'], {'dev.example.sdf': 'brick grid'});

    final doc = readFscene(text);
    expect(doc.unknown['dev.example.sdf'], {'quality': 3});
    expect(doc.stage.unknown['dev.example.sdf'], 'stage data');
    expect(doc.nodes.values.single.unknown['dev.example.sdf'], {
      'volume': 'vol1',
    });
    expect(doc.nodes.values.single.components.single.unknown['extras'], 7);
    expect(doc.resources.values.single.unknown['dev.example.sdf'], isTrue);
    expect(doc.payloads.values.single.unknown['dev.example.sdf'], 'brick grid');

    // Everything written back, and writing again changes nothing further.
    final written = writeFscene(doc);
    for (final needle in [
      '"dev.example.sdf"',
      '"quality": 3',
      '"brick grid"',
      '"extras": 7',
    ]) {
      expect(written, contains(needle), reason: needle);
    }
    expect(writeFscene(readFscene(written)), written);
  });

  test('an edit elsewhere leaves preserved data intact', () {
    var text = writeFscene(_document());
    text = _inject(text, ['nodes', '*'], {'dev.example.sdf': 'keep me'});
    final doc = readFscene(text);
    doc.nodes.values.single.name = 'Renamed';
    final written = writeFscene(doc);
    expect(written, contains('"keep me"'));
    expect(written, contains('"Renamed"'));
  });

  test('preserved keys never overwrite a key this build owns', () {
    final doc = readFscene(
      _inject(writeFscene(_document()), ['nodes', '*'], {'name': 'Crate'}),
    );
    expect(doc.nodes.values.single.unknown, isEmpty);
    expect(doc.nodes.values.single.name, 'Crate');
  });

  test('unknown keys survive inside nested value objects', () {
    var text = writeFscene(_nested());
    for (final path in [
      ['nodes', '*', 'transform'],
      ['resources', '*', 'bounds'],
      ['nodes', '*1', 'instance'],
      ['nodes', '*1', 'instance', 'overrides', '0'],
      ['nodes', '*1', 'instance', 'attachments', '0'],
    ]) {
      text = _inject(text, path, {'dev.example.sdf': 'deep'});
    }
    final written = writeFscene(readFscene(text));
    expect('deep'.allMatches(written).length, 5, reason: written);
    expect(writeFscene(readFscene(written)), written);
  });

  test('unknown effects keys survive, group by group', () {
    final doc = SceneDocument();
    final env = doc.allocator.mint();
    doc.resources[env] = EnvironmentResource(
      env,
      effects: EnvironmentEffectsSpec(),
    );
    var text = writeFscene(doc);
    text = _inject(
      text,
      ['resources', '*', 'effects'],
      {
        'bloom': {'dev.example.sdf': 'in a known group'},
        'dev.example.sdf': {'strength': 2},
      },
    );
    final reread = readFscene(text);
    final effects = (reread.resources[env]! as EnvironmentResource).effects;
    expect(effects.unknownInGroups['bloom'], {
      'dev.example.sdf': 'in a known group',
    });
    expect(effects.unknown['dev.example.sdf'], {'strength': 2});
    final written = writeFscene(reread);
    expect(written, contains('in a known group'));
    expect(writeFscene(readFscene(written)), written);
  });

  test('an unknown property value tag loads instead of failing', () {
    final doc = SceneDocument();
    final node = doc.allocator.mint();
    doc.nodes[node] = NodeSpec(id: node, components: [ComponentSpec('mesh')]);
    doc.roots.add(node);
    var text = writeFscene(doc);
    text = _inject(
      text,
      ['nodes', '*', 'components', '0'],
      {
        'properties': {
          'volume': {
            'sdfBrick': [1, 2, 3],
          },
        },
      },
    );
    final reread = readFscene(text);
    final value = reread.nodes[node]!.components.single.properties['volume'];
    expect(value, isA<UnknownValue>());
    expect((value! as UnknownValue).json, {
      'sdfBrick': [1, 2, 3],
    });
    final written = writeFscene(reread);
    expect(written, contains('sdfBrick'));
    expect(writeFscene(readFscene(written)), written);
  });

  group('binary container', () {
    test('a rewrite carries an unrecognized chunk through', () {
      final original = writeFsceneb(_document());
      final spliced = _withChunk(original, 'XTRA', ascii.encode('vendor'));
      expect(_chunkTypes(spliced), contains('XTRA'));

      final doc = readFsceneb(spliced);
      expect(doc.unknownChunks.single.type, 'XTRA');
      expect(ascii.decode(doc.unknownChunks.single.data), 'vendor');

      final rewritten = writeFsceneb(doc);
      expect(_chunkTypes(rewritten), _chunkTypes(spliced));
      expect(
        ascii.decode(readFsceneb(rewritten).unknownChunks.single.data),
        'vendor',
      );
      // A container this writer produced rewrites byte for byte.
      expect(writeFsceneb(readFsceneb(rewritten)), rewritten);
    });

    test('a clean container still rewrites byte for byte', () {
      final bytes = writeFsceneb(_document());
      expect(writeFsceneb(readFsceneb(bytes)), bytes);
    });
  });
}

/// Appends a chunk of [type] holding [data] to [container].
Uint8List _withChunk(Uint8List container, String type, List<int> data) {
  final preamble = ByteData(8)..setUint32(0, data.length, Endian.little);
  for (var i = 0; i < 4; i++) {
    preamble.setUint8(4 + i, ascii.encode(type)[i]);
  }
  final padding = (-data.length) & 7;
  final out = BytesBuilder()
    ..add(container)
    ..add(preamble.buffer.asUint8List())
    ..add(Uint8List.fromList(data))
    ..add(Uint8List(padding));
  final bytes = out.toBytes();
  ByteData.sublistView(bytes).setUint32(8, bytes.length, Endian.little);
  return bytes;
}

/// The chunk types in [container], in order.
List<String> _chunkTypes(Uint8List container) {
  final view = ByteData.sublistView(container);
  final types = <String>[];
  var offset = 16;
  while (offset + 8 <= container.length) {
    final length = view.getUint32(offset, Endian.little);
    types.add(
      ascii.decode(Uint8List.sublistView(container, offset + 4, offset + 8)),
    );
    offset += 8 + length + ((-length) & 7);
  }
  return types;
}

/// A document with a prefab instance, so the nested objects have somewhere to
/// hang foreign keys.
SceneDocument _nested() {
  final doc = _document();
  final node = doc.nodes.keys.first;
  final child = doc.allocator.mint();
  doc.nodes[child] = NodeSpec(
    id: child,
    name: 'Instance',
    instance: PrefabInstanceSpec(
      source: const AssetRef('prefabs/crate.fscene'),
      overrides: [
        PropertyOverride(
          target: node,
          path: 'name',
          value: const StringValue('override'),
        ),
      ],
      attachments: [Attachment(node)],
    ),
  );
  doc.roots.add(child);
  final geometry = doc.resources.values.whereType<GeometryResource>().single;
  doc.resources[geometry.id] = GeometryResource(
    geometry.id,
    vertices: geometry.vertices,
    bounds: BoundsSpec(min: Vector3.zero(), max: Vector3.all(1)),
  );
  return doc;
}
