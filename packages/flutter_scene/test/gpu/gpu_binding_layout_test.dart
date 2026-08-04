// ignore_for_file: implementation_imports
import 'package:flutter_scene/src/gpu/shared/gpu_binding_layout.dart';
import 'package:flutter_test/flutter_test.dart';

GpuBindingSlot _ubo(String name) =>
    (name: name, kind: GpuBindingKind.uniformBuffer);
GpuBindingSlot _tex(String name) => (name: name, kind: GpuBindingKind.texture);

void main() {
  group('GpuBindingLayout ordering', () {
    // Declaration order is an accident of how a material happens to be
    // written, so it must not split the cache.
    test('two layouts differing only in declaration order are equal', () {
      final a = GpuBindingLayout([_ubo('FragInfo'), _tex('albedo')]);
      final b = GpuBindingLayout([_tex('albedo'), _ubo('FragInfo')]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('slots are exposed in a stable canonical order', () {
      final layout = GpuBindingLayout([
        _tex('z_tex'),
        _ubo('a_ubo'),
        _tex('m_tex'),
      ]);
      expect(layout.slots.map((s) => s.name), ['a_ubo', 'm_tex', 'z_tex']);
    });
  });

  group('GpuBindingLayout equality', () {
    test('differs when a name differs', () {
      expect(
        GpuBindingLayout([_tex('albedo')]),
        isNot(GpuBindingLayout([_tex('normal')])),
      );
    });

    test('differs when a kind differs for the same name', () {
      expect(
        GpuBindingLayout([_tex('thing')]),
        isNot(GpuBindingLayout([_ubo('thing')])),
      );
    });

    test('differs when one has an extra slot', () {
      expect(
        GpuBindingLayout([_tex('albedo')]),
        isNot(GpuBindingLayout([_tex('albedo'), _tex('normal')])),
      );
    });

    test('an empty layout equals another empty layout', () {
      expect(GpuBindingLayout(const []), GpuBindingLayout(const []));
    });

    test('works as a map key', () {
      final cache = <GpuBindingLayout, int>{};
      cache[GpuBindingLayout([_ubo('FragInfo'), _tex('albedo')])] = 1;
      cache[GpuBindingLayout([_tex('albedo'), _ubo('FragInfo')])] = 2;
      expect(cache.length, 1);
      expect(cache.values.single, 2);
    });
  });

  group('GpuBindingLayout queries', () {
    final layout = GpuBindingLayout([
      _ubo('FragInfo'),
      _ubo('FrameInfo'),
      _tex('albedo'),
    ]);

    test('separates the per-draw uniforms from the stable textures', () {
      expect(layout.uniformNames, ['FragInfo', 'FrameInfo']);
      expect(layout.textureNames, ['albedo']);
    });

    test('reports the kind of a known slot', () {
      expect(layout.kindOf('albedo'), GpuBindingKind.texture);
      expect(layout.kindOf('FragInfo'), GpuBindingKind.uniformBuffer);
    });

    test('reports null for an unknown slot', () {
      expect(layout.kindOf('missing'), isNull);
      expect(layout.contains('missing'), isFalse);
      expect(layout.contains('albedo'), isTrue);
    });
  });

  group('GpuBindingLayout validation', () {
    // A duplicate name is ambiguous: the reflected slot it resolves to would
    // depend on iteration order.
    test('rejects a duplicate binding name', () {
      expect(
        () => GpuBindingLayout([_tex('albedo'), _ubo('albedo')]),
        throwsArgumentError,
      );
    });

    test('slots cannot be mutated after construction', () {
      final layout = GpuBindingLayout([_tex('albedo')]);
      expect(() => layout.slots.add(_tex('normal')), throwsUnsupportedError);
    });
  });

  group('GpuBindingLayout.toString', () {
    test('names each slot and its kind', () {
      final text = GpuBindingLayout([
        _ubo('FragInfo'),
        _tex('albedo'),
      ]).toString();
      expect(text, contains('FragInfo:uniformBuffer'));
      expect(text, contains('albedo:texture'));
    });
  });
}
