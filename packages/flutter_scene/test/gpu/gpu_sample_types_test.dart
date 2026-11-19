// ignore_for_file: implementation_imports
import 'package:flutter_scene/src/gpu/shared/gpu_sample_types.dart';
import 'package:flutter_scene/src/gpu/shared/wgsl_bindings.dart';
import 'package:test/test.dart';

const _color = (depth: false, float32: false);
const _float32 = (depth: false, float32: true);
const _depth = (depth: true, float32: false);

void main() {
  group('wgslTextureShape', () {
    test('reads dimension, scalar, depth, and multisampling', () {
      expect(wgslTextureShape('texture_2d<f32>'), (
        viewDimension: GpuTextureViewDimension.d2,
        scalar: WgslTextureScalar.f32,
        depth: false,
        multisampled: false,
      ));
      expect(
        wgslTextureShape('texture_cube<f32>')!.viewDimension,
        GpuTextureViewDimension.cube,
      );
      expect(
        wgslTextureShape('texture_2d_array<f32>')!.viewDimension,
        GpuTextureViewDimension.d2Array,
      );
      expect(
        wgslTextureShape('texture_2d<u32>')!.scalar,
        WgslTextureScalar.u32,
      );
      expect(wgslTextureShape('texture_depth_2d')!.depth, isTrue);
      expect(
        wgslTextureShape('texture_multisampled_2d<f32>')!.multisampled,
        isTrue,
      );
      expect(wgslTextureShape('texture_2d< f32 >'), isNotNull);
    });

    test('rejects samplers, storage textures, and unknown dimensions', () {
      expect(wgslTextureShape('sampler'), isNull);
      expect(wgslTextureShape('texture_storage_2d<rgba8unorm, write>'), isNull);
      expect(wgslTextureShape('texture_cube_array<f32>'), isNull);
    });

    test('works on declarations parsed out of Tint-shaped WGSL', () {
      const wgsl = '''
@group(0) @binding(65) var v_2 : texture_2d<f32>;
@group(0) @binding(66) var v_1 : sampler;
@group(0) @binding(67) var v_4 : texture_cube<f32>;
''';
      final textures = parseWgslDeclarations(wgsl)
          .where((d) => d.kind == WgslDeclarationKind.texture)
          .map((d) => wgslTextureShape(d.type)!.viewDimension)
          .toList();
      expect(textures, [
        GpuTextureViewDimension.d2,
        GpuTextureViewDimension.cube,
      ]);
    });
  });

  group('resolveSampleSlot', () {
    final plain2d = wgslTextureShape('texture_2d<f32>')!;

    GpuSampleSlot resolve(
      GpuFormatSampling format, {
      bool filters = true,
      bool float32Filterable = false,
      WgslTextureShape? shape,
    }) => resolveSampleSlot(
      shape: shape ?? plain2d,
      format: format,
      samplerFilters: filters,
      float32Filterable: float32Filterable,
    );

    test('ordinary color textures keep the sampler as bound', () {
      expect(resolve(_color), (
        sampleType: GpuTextureSampleType.float,
        samplerType: GpuSamplerBindingType.filtering,
        samplerDowngraded: false,
      ));
      expect(
        resolve(_color, filters: false).samplerType,
        GpuSamplerBindingType.nonFiltering,
      );
    });

    test('depth targets sampled as floats are unfilterable', () {
      final slot = resolve(_depth);
      expect(slot.sampleType, GpuTextureSampleType.unfilterableFloat);
      expect(slot.samplerType, GpuSamplerBindingType.nonFiltering);
      expect(slot.samplerDowngraded, isTrue);
      expect(resolve(_depth, filters: false).samplerDowngraded, isFalse);
    });

    test('32-bit float filtering follows the device feature', () {
      expect(
        resolve(_float32).sampleType,
        GpuTextureSampleType.unfilterableFloat,
      );
      expect(
        resolve(_float32, float32Filterable: true).sampleType,
        GpuTextureSampleType.float,
      );
      // The feature never makes depth filterable.
      expect(
        resolve(_depth, float32Filterable: true).sampleType,
        GpuTextureSampleType.unfilterableFloat,
      );
    });

    test('integer and multisampled textures never filter', () {
      final uint = resolve(_color, shape: wgslTextureShape('texture_2d<u32>'));
      expect(uint.sampleType, GpuTextureSampleType.uint);
      expect(uint.samplerDowngraded, isTrue);
      expect(
        resolve(
          _color,
          shape: wgslTextureShape('texture_multisampled_2d<f32>'),
        ).sampleType,
        GpuTextureSampleType.unfilterableFloat,
      );
    });

    test('shadow declarations resolve to a comparison sampler', () {
      final slot = resolve(_depth, shape: wgslTextureShape('texture_depth_2d'));
      expect(slot.sampleType, GpuTextureSampleType.depth);
      expect(slot.samplerType, GpuSamplerBindingType.comparison);
    });

    test('resolveSampleSlotCode and sampleSlotFromCode match exhaustively', () {
      for (final dimension in GpuTextureViewDimension.values) {
        for (final scalar in WgslTextureScalar.values) {
          for (final depthShape in const [false, true]) {
            for (final multisampled in const [false, true]) {
              final shape = (
                viewDimension: dimension,
                scalar: scalar,
                depth: depthShape,
                multisampled: multisampled,
              );
              for (final fmtDepth in const [false, true]) {
                for (final fmtFloat32 in const [false, true]) {
                  for (final filters in const [false, true]) {
                    for (final f32Feature in const [false, true]) {
                      final resolved = resolveSampleSlot(
                        shape: shape,
                        format: (depth: fmtDepth, float32: fmtFloat32),
                        samplerFilters: filters,
                        float32Filterable: f32Feature,
                      );
                      final code = resolveSampleSlotCode(
                        shape: shape,
                        formatDepth: fmtDepth,
                        formatFloat32: fmtFloat32,
                        samplerFilters: filters,
                        float32Filterable: f32Feature,
                      );
                      expect(code, sampleSlotCode(resolved));
                      final decoded = sampleSlotFromCode(code);
                      expect(decoded.sampleType, resolved.sampleType);
                      expect(decoded.samplerType, resolved.samplerType);
                    }
                  }
                }
              }
            }
          }
        }
      }
    });
  });

  group('GpuSampleSignature', () {
    final shape = wgslTextureShape('texture_2d<f32>')!;
    GpuSampleSlot slot(GpuFormatSampling f, {bool filters = true}) =>
        resolveSampleSlot(
          shape: shape,
          format: f,
          samplerFilters: filters,
          float32Filterable: false,
        );

    test('equal resolved slots give equal signatures', () {
      expect(
        GpuSampleSignature([slot(_color), slot(_depth)]),
        GpuSampleSignature([slot(_color), slot(_depth)]),
      );
    });

    test('a different bound texture class changes the signature', () {
      expect(
        GpuSampleSignature([slot(_color), slot(_color)]),
        isNot(GpuSampleSignature([slot(_color), slot(_depth)])),
      );
      expect(
        GpuSampleSignature([slot(_color)]),
        isNot(GpuSampleSignature([slot(_color, filters: false)])),
      );
    });

    test('order matters, and wide layouts spill past the first lane', () {
      expect(
        GpuSampleSignature([slot(_color), slot(_depth)]),
        isNot(GpuSampleSignature([slot(_depth), slot(_color)])),
      );
      final ten = GpuSampleSignature(List.filled(10, slot(_depth)));
      expect(ten.overflow, isEmpty);

      final eleven = GpuSampleSignature(List.filled(11, slot(_depth)));
      expect(eleven.overflow, hasLength(1));
      expect(eleven, isNot(ten));

      final twentyOne = GpuSampleSignature(List.filled(21, slot(_depth)));
      expect(twentyOne.overflow, hasLength(2));
      expect(twentyOne, isNot(eleven));
    });
    test('reused lanes match a fresh signature and decode per slot', () {
      final codes = [for (var i = 0; i < 23; i++) i % 6];
      final lanes = GpuSampleLanes();
      for (final code in codes) {
        lanes.add(code);
      }
      // Reuse after a wide layout must not leak its stale overflow lanes.
      lanes.reset();
      for (final code in codes.take(12)) {
        lanes.add(code);
      }
      final reused = lanes.toSignature();
      final fresh = GpuSampleLanes();
      for (final code in codes.take(12)) {
        fresh.add(code);
      }
      expect(reused, fresh.toSignature());
      expect(reused.hashCode, fresh.toSignature().hashCode);
      expect([for (var i = 0; i < 12; i++) reused.codeAt(i)], codes.take(12));
    });
  });
}
