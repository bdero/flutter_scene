import 'dart:io';
import 'dart:typed_data';

// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/geometry/geometry.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/debug_view.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/resolve_info.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const _litFmat = '''
material {
  name: "Probe",
  shading_model: lit,
}

fragment {
  void Surface(inout MaterialInputs material) {
    material.roughness = 0.25;
    material.debug = vec3(GetUV0(), 0.0);
    PrepareMaterial(material);
  }
}
''';

const _unlitFmat = '''
material {
  name: "Flat",
  shading_model: unlit,
}

fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(1.0, 0.5, 0.0, 1.0);
  }
}
''';

void main() {
  group('SurfaceDebugChannel', () {
    test('ids and shader ids are unique', () {
      final ids = SurfaceDebugChannel.values.map((c) => c.id).toSet();
      final shaderIds = SurfaceDebugChannel.values.map((c) => c.shaderId);
      expect(ids.length, SurfaceDebugChannel.values.length);
      expect(shaderIds.toSet().length, SurfaceDebugChannel.values.length);
      expect(
        SurfaceDebugChannel.byId('roughness'),
        SurfaceDebugChannel.roughness,
      );
      expect(SurfaceDebugChannel.byId('nope'), isNull);
    });

    test('shader ids match the GLSL defines', () {
      // The include is the source of truth for the shader; the enum must
      // agree with every DEBUG_CHANNEL_* it declares.
      final glsl = _readShader('material_debug.glsl');
      final defines = RegExp(r'#define DEBUG_CHANNEL_([A-Z0-9_]+) (\d+)\.0');
      final declared = <String, int>{
        for (final m in defines.allMatches(glsl))
          m.group(1)!: int.parse(m.group(2)!),
      };
      expect(declared, isNotEmpty);
      for (final channel in SurfaceDebugChannel.values) {
        if (channel == SurfaceDebugChannel.none) continue;
        final key = channel.id.toUpperCase();
        expect(
          declared[key],
          channel.shaderId,
          reason: '${channel.id} disagrees with material_debug.glsl',
        );
      }
      expect(declared.length, SurfaceDebugChannel.values.length - 1);
    });
  });

  group('DebugView', () {
    test('defaults the range to the channel and compares by value', () {
      const view = DebugView(channel: SurfaceDebugChannel.worldPosition);
      expect(view.rangeMin, -10.0);
      expect(view.rangeMax, 10.0);
      expect(view.isActive, isTrue);
      expect(DebugView.none.isActive, isFalse);
      expect(
        view.copyWith(gain: 2.0),
        const DebugView(channel: SurfaceDebugChannel.worldPosition, gain: 2.0),
      );
      expect(view.copyWith(rangeMax: 1.0).rangeMax, 1.0);
    });

    test('the registry lists every channel and accepts custom entries', () {
      final ids = DebugViewRegistry.entries.map((e) => e.id).toList();
      for (final channel in SurfaceDebugChannel.values) {
        expect(ids, contains(channel.id));
      }
      DebugViewRegistry.register(
        const DebugViewEntry(
          id: 'roughness_x4',
          label: 'Roughness x4',
          group: SurfaceDebugGroup.surface,
          view: DebugView(channel: SurfaceDebugChannel.roughness, gain: 4.0),
        ),
      );
      expect(DebugViewRegistry.byId('roughness_x4')?.view.gain, 4.0);
      expect(DebugViewRegistry.unregister('roughness_x4'), isTrue);
      expect(DebugViewRegistry.unregister('roughness'), isFalse);
      expect(DebugViewRegistry.byId('roughness_x4'), isNull);
    });
  });

  group('DebugViewFrame', () {
    test('packs the block the shader reads', () {
      final frame = DebugViewFrame(
        sceneView: const DebugView(
          channel: SurfaceDebugChannel.metallic,
          gain: 1.5,
          rangeMin: 0.2,
          rangeMax: 0.8,
          rangePolicy: DebugRangePolicy.cycle,
        ),
        splitPixels: 256.0,
        hasNodeOverrides: false,
        overlays: const {},
        wireframeColor: Vector4(1, 1, 1, 1),
      );
      final out = Float32List(DebugViewFrame.floatCount);
      frame.pack(out, frame.sceneView, objectSeed: 0x1234A, materialSeed: 7);
      expect(out[0], SurfaceDebugChannel.metallic.shaderId.toDouble());
      expect(out[1], 256.0);
      expect(out[2], 1.5);
      expect(out[3], DebugRangePolicy.cycle.index.toDouble());
      expect(out[4], closeTo(0.2, 1e-6));
      expect(out[5], closeTo(0.8, 1e-6));
      expect(out[6], (0x1234A & 0xFFFF).toDouble());
      expect(out[7], 7.0);
      expect(DebugViewFrame.inactive[0], 0.0);
    });

    test('a node override wins over the scene view', () {
      final frame = DebugViewFrame(
        sceneView: const DebugView(channel: SurfaceDebugChannel.uv0),
        splitPixels: -1.0,
        hasNodeOverrides: true,
        overlays: const {},
        wireframeColor: Vector4(1, 1, 1, 1),
      );
      expect(frame.effectiveView(null).channel, SurfaceDebugChannel.uv0);
      expect(frame.effectiveView(DebugView.none).isActive, isFalse);
      expect(
        frame
            .effectiveView(
              const DebugView(channel: SurfaceDebugChannel.roughness),
            )
            .channel,
        SurfaceDebugChannel.roughness,
      );
    });
  });

  group('Node.debugView', () {
    test('counts overrides and resolves up the ancestry', () {
      final before = Node.debugViewOverrideCount;
      final root = Node();
      final middle = Node();
      final leaf = Node();
      root.add(middle);
      middle.add(leaf);
      expect(leaf.effectiveDebugView, isNull);

      root.debugView = const DebugView(channel: SurfaceDebugChannel.uv1);
      expect(Node.debugViewOverrideCount, before + 1);
      expect(leaf.effectiveDebugView?.channel, SurfaceDebugChannel.uv1);

      middle.debugView = DebugView.none;
      expect(Node.debugViewOverrideCount, before + 2);
      expect(leaf.effectiveDebugView, DebugView.none);

      // Replacing a set view keeps the count; clearing it drops it.
      middle.debugView = const DebugView(channel: SurfaceDebugChannel.tangent);
      expect(Node.debugViewOverrideCount, before + 2);
      middle.debugView = null;
      root.debugView = null;
      expect(Node.debugViewOverrideCount, before);
      expect(leaf.effectiveDebugView, isNull);
    });
  });

  group('debugEdgeIndices', () {
    test('deduplicates shared edges and skips degenerate triangles', () {
      // Two triangles sharing the edge 1-2, plus a degenerate one.
      final indices = Uint16List.fromList([0, 1, 2, 2, 1, 3, 3, 3, 0]);
      final edges = debugEdgeIndices(
        ByteData.sublistView(indices),
        gpu.IndexType.int16,
        indices.length,
        4,
      );
      expect(edges.type, gpu.IndexType.int16);
      expect(edges.count, 10);
      final pairs = <String>{};
      final view = Uint16List.sublistView(edges.bytes);
      for (var i = 0; i < view.length; i += 2) {
        pairs.add('${view[i]}-${view[i + 1]}');
      }
      expect(pairs, {'0-1', '1-2', '0-2', '2-3', '1-3'});
    });

    test('non-indexed lists and wide meshes', () {
      final edges = debugEdgeIndices(null, gpu.IndexType.int16, 0, 6);
      expect(edges.count, 12);
      final wide = debugEdgeIndices(
        ByteData.sublistView(Uint32List.fromList([0, 70000, 70001])),
        gpu.IndexType.int32,
        3,
        70002,
      );
      expect(wide.type, gpu.IndexType.int32);
      expect(wide.count, 6);
      expect(Uint32List.sublistView(wide.bytes), [
        0,
        70000,
        70000,
        70001,
        0,
        70001,
      ]);
    });
  });

  group('resolve info', () {
    test('carries the debug bypass and split', () {
      final info = packResolveInfo(
        exposure: 1.0,
        toneMappingMode: ToneMappingMode.pbrNeutral,
        flipY: false,
        time: 0.0,
        settings: PostProcessSettings()..bloom.enabled = true,
        debugViewActive: true,
        debugViewSplit: 0.5,
        bloomEnabled: false,
      );
      expect(info[36], 0.0);
      expect(info[38], 1.0);
      expect(info[39], 0.5);
    });
  });

  group('fmat emitter', () {
    test('every material selects between the view and its shaded output', () {
      for (final source in [_litFmat, _unlitFmat]) {
        final glsl = compileFmat(source, fileName: 'probe.fmat').glsl;
        expect(glsl, contains('#include <material_debug.glsl>'));
        expect(glsl, contains('vec4 MaterialOutput(MaterialInputs material)'));
        expect(glsl, contains('float debug_mode = DebugViewMode();'));
        expect(glsl, contains('DebugViewSplit(DebugSurfaceOutput(material)'));
        expect(glsl, contains('frag_color = MaterialOutput(material);'));
      }
    });

    test('a material can write the custom channel', () {
      final glsl = compileFmat(_litFmat, fileName: 'probe.fmat').glsl;
      expect(glsl, contains('material.debug = vec3(GetUV0(), 0.0);'));
    });
  });
}

// Tests run with the package as the working directory.
String _readShader(String name) => File('shaders/$name').readAsStringSync();
