// Custom vertex attributes resolved against what a draw's vertex shader
// declares. No GPU context is needed: the slot resolution and the layouts are
// pure, and the geometry here carries no custom streams of its own.

// ignore_for_file: implementation_imports

import 'package:flutter_scene/src/fmat/fmat.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/vertex_layout.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/vertex_attributes.dart';
import 'package:flutter_test/flutter_test.dart';

const _phase = VertexAttributeSchema([(name: 'phase', components: 1)]);

List<String> _names(Iterable<VertexBufferDescriptor> buffers) => [
  for (final buffer in buffers)
    for (final attribute in buffer.attributes) attribute.name,
];

void main() {
  group('sidecar', () {
    test('records declared attributes', () {
      final m = parseFmat('''
material {
  name: "Waves",
  attributes: [ { type: vec2, name: wind }, { type: float, name: phase } ],
}
vertex { void Vertex(inout VertexInputs vertex) {} }
fragment { void Surface(inout MaterialInputs material) {} }
''');
      final schema = VertexAttributeSchema.fromMetadata(buildSidecar(m))!;
      expect(schema.attributes, [
        (name: 'wind', components: 2),
        (name: 'phase', components: 1),
      ]);
    });

    test('always writes the entry, so an older sidecar reads as unknown', () {
      final m = parseFmat('''
material { name: "Plain" }
fragment { void Surface(inout MaterialInputs material) {} }
''');
      expect(
        VertexAttributeSchema.fromMetadata(buildSidecar(m)),
        same(VertexAttributeSchema.none),
      );
      expect(VertexAttributeSchema.fromMetadata({}), isNull);
    });
  });

  group('slot resolution', () {
    test('a declared attribute the geometry lacks reads zero', () {
      final slots = resolveVertexAttributeSlots(_phase, {});
      expect(slots, hasLength(1));
      expect(slots.single.name, 'phase');
      expect(slots.single.provided, isFalse);
      expect(slots.single.format, gpu.VertexFormat.float32);
    });

    test('a stream nobody declared is left out', () {
      final slots = resolveVertexAttributeSlots(VertexAttributeSchema.none, {
        'phase': gpu.VertexFormat.float32,
      });
      expect(slots, isEmpty);
    });

    test('declared streams bind in declaration order', () {
      const schema = VertexAttributeSchema([
        (name: 'b', components: 2),
        (name: 'a', components: 1),
      ]);
      final slots = resolveVertexAttributeSlots(schema, {
        'a': gpu.VertexFormat.float32,
        'extra': gpu.VertexFormat.float32x4,
        'b': gpu.VertexFormat.float32x2,
      });
      expect([for (final s in slots) s.name], ['b', 'a']);
      expect(slots.every((s) => s.provided), isTrue);
    });
  });

  group('layouts', () {
    test('unskinned splices declared slots before the instance buffer', () {
      final geometry = UnskinnedGeometry();
      final none = geometry.debugLayoutForAttributes(
        VertexAttributeSchema.none,
      )!;
      final withPhase = geometry.debugLayoutForAttributes(_phase)!;
      expect(withPhase.buffers, hasLength(none.buffers.length + 1));
      expect(
        _names(
          withPhase.buffers.sublist(
            none.buffers.length - 1,
            none.buffers.length,
          ),
        ),
        ['phase'],
      );
      expect(_names([withPhase.buffers.last]), _names([none.buffers.last]));
    });

    test('skinned keeps the reflected layout until an attribute is read', () {
      final geometry = SkinnedGeometry();
      expect(
        geometry.debugLayoutForAttributes(VertexAttributeSchema.none),
        isNull,
      );
      final withPhase = geometry.debugLayoutForAttributes(_phase)!;
      expect(withPhase.buffers.first, same(kSkinnedVertexBuffer));
      expect(_names(withPhase.buffers.skip(1)), ['phase']);
    });
  });
}
