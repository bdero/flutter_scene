// Covers the described vertex-layout type: the canonical unskinned layout's
// structure and byte parity with the interleaved packer, value equality and
// interning (so two layouts on one shader cannot share a pipeline-cache
// identity), and the lowering-time validation. Pure logic, so these run
// without a Flutter GPU context.

import 'package:flutter_scene/src/geometry/geometry.dart'
    show
        kUnskinnedInstancedLayout,
        kUnskinnedPositionOnlyLayout,
        kUnskinnedSoAColorLayout,
        kUnskinnedSoADepthLayout;
import 'package:flutter_scene/src/geometry/interleaved_layout.dart';
import 'package:flutter_scene/src/geometry/vertex_layout.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/importer/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canonical unskinned layout', () {
    test('lowers to the expected two-buffer gpu layout', () {
      final layout = kUnskinnedInstancedLayout.toGpuLayout();
      expect(layout.buffers, hasLength(2));

      // Slot 0: the interleaved 48-byte vertex stream.
      final vertex = layout.buffers[0];
      expect(vertex.strideInBytes, kUnskinnedPerVertexSize);
      expect(vertex.stepMode, gpu.VertexStepMode.vertex);
      expect(
        vertex.attributes.map((a) => (a.name, a.format, a.offsetInBytes)),
        [
          ('position', gpu.VertexFormat.float32x3, 0),
          ('normal', gpu.VertexFormat.float32x3, 12),
          ('texture_coords', gpu.VertexFormat.float32x2, 24),
          ('color', gpu.VertexFormat.float32x4, 32),
        ],
      );

      // Slot 1: the instance-rate model matrix, four vec4 columns.
      final instance = layout.buffers[1];
      expect(instance.strideInBytes, 64);
      expect(instance.stepMode, gpu.VertexStepMode.instance);
      expect(
        instance.attributes.map((a) => (a.name, a.format, a.offsetInBytes)),
        [
          ('model_transform_0', gpu.VertexFormat.float32x4, 0),
          ('model_transform_1', gpu.VertexFormat.float32x4, 16),
          ('model_transform_2', gpu.VertexFormat.float32x4, 32),
          ('model_transform_3', gpu.VertexFormat.float32x4, 48),
        ],
      );
    });

    test('vertex attributes match the interleaved packer byte for byte', () {
      // The packer writes position at floats 0-2, normal 3-5, texcoord 6-7,
      // and color 8-11 of each 12-float vertex; the canonical layout's slot-0
      // attribute byte offsets and formats must describe exactly that, or the
      // declared layout and the packed bytes would disagree.
      final vertex = kUnskinnedInstancedLayout.toGpuLayout().buffers[0];
      var cursor = 0;
      for (final attribute in vertex.attributes) {
        expect(
          attribute.offsetInBytes,
          cursor,
          reason: '${attribute.name} is not tightly packed',
        );
        cursor += attribute.format.bytesPerElement;
      }
      expect(cursor, kUnskinnedPerVertexSize);
      // Sanity-check that the packer agrees on the per-vertex size.
      expect(InterleavedLayoutAdapter.floatsPerVertex * 4, cursor);
    });
  });

  group('position-only depth layout', () {
    test('reads only position from slot 0, plus the instance slot', () {
      final layout = kUnskinnedPositionOnlyLayout.toGpuLayout();
      expect(layout.buffers, hasLength(2));

      // Slot 0: still the 48-byte interleaved stride, but only position is
      // declared, so the input assembler fetches only position per vertex.
      final vertex = layout.buffers[0];
      expect(vertex.strideInBytes, kUnskinnedPerVertexSize);
      expect(vertex.stepMode, gpu.VertexStepMode.vertex);
      expect(
        vertex.attributes.map((a) => (a.name, a.format, a.offsetInBytes)),
        [('position', gpu.VertexFormat.float32x3, 0)],
      );

      // Slot 1: the same instance-rate model matrix as the color layout, so
      // the bound instance buffer is identical across the two passes.
      final instance = layout.buffers[1];
      expect(instance.strideInBytes, 64);
      expect(instance.stepMode, gpu.VertexStepMode.instance);
      expect(instance.attributes.map((a) => a.name), [
        'model_transform_0',
        'model_transform_1',
        'model_transform_2',
        'model_transform_3',
      ]);
    });

    test('is a distinct layout from the color layout', () {
      // The two layouts drive the same vertex buffer but different pipelines,
      // so they must not share a pipeline-cache identity.
      expect(
        kUnskinnedPositionOnlyLayout,
        isNot(equals(kUnskinnedInstancedLayout)),
      );
      expect(
        vertexLayoutId(kUnskinnedPositionOnlyLayout),
        isNot(vertexLayoutId(kUnskinnedInstancedLayout)),
      );
    });
  });

  group('structure-of-arrays layouts', () {
    test('color layout is one tight buffer per attribute plus instance', () {
      final layout = kUnskinnedSoAColorLayout.toGpuLayout();
      expect(layout.buffers, hasLength(5));
      expect(
        layout.buffers.map((b) => (b.strideInBytes, b.attributes.first.name)),
        [
          (12, 'position'),
          (12, 'normal'),
          (8, 'texture_coords'),
          (16, 'color'),
          (64, 'model_transform_0'),
        ],
      );
      expect(layout.buffers.last.stepMode, gpu.VertexStepMode.instance);
    });

    test('depth layout binds only tight position plus the instance slot', () {
      final layout = kUnskinnedSoADepthLayout.toGpuLayout();
      expect(layout.buffers, hasLength(2));
      expect(layout.buffers[0].strideInBytes, 12);
      expect(layout.buffers[0].attributes.map((a) => a.name), ['position']);
      expect(layout.buffers[1].stepMode, gpu.VertexStepMode.instance);
    });

    test('the four unskinned layouts are all distinct identities', () {
      final ids = {
        vertexLayoutId(kUnskinnedInstancedLayout),
        vertexLayoutId(kUnskinnedPositionOnlyLayout),
        vertexLayoutId(kUnskinnedSoAColorLayout),
        vertexLayoutId(kUnskinnedSoADepthLayout),
      };
      expect(ids, hasLength(4));
    });
  });

  group('value equality and interning', () {
    VertexLayoutDescriptor singleBuffer(int stride) => VertexLayoutDescriptor(
      buffers: [
        VertexBufferDescriptor(
          strideInBytes: stride,
          attributes: const [
            VertexAttributeDescriptor(
              name: 'position',
              format: gpu.VertexFormat.float32x3,
            ),
          ],
        ),
      ],
    );

    test('structurally identical layouts are equal and share an id', () {
      final a = singleBuffer(12);
      final b = singleBuffer(12);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(vertexLayoutId(a), vertexLayoutId(b));
    });

    test('different layouts get different non-zero ids', () {
      // The pipeline-cache key carries this id, so two layouts on one shader
      // must not collapse to the same id (the latent cache bug this fixes).
      final a = singleBuffer(12);
      final c = singleBuffer(16);
      expect(a, isNot(equals(c)));
      expect(vertexLayoutId(a), isNot(vertexLayoutId(c)));
      expect(vertexLayoutId(a), isNot(0));
      expect(vertexLayoutId(c), isNot(0));
    });

    test('the default reflected layout (null) is id 0', () {
      expect(vertexLayoutId(null), 0);
    });

    test('an id is stable across repeated lookups', () {
      final a = singleBuffer(24);
      expect(vertexLayoutId(a), vertexLayoutId(singleBuffer(24)));
    });
  });

  group('lowering-time validation', () {
    test('rejects an attribute that overruns its buffer stride', () {
      final layout = VertexLayoutDescriptor(
        buffers: const [
          VertexBufferDescriptor(
            strideInBytes: 8,
            attributes: [
              VertexAttributeDescriptor(
                name: 'position',
                format: gpu.VertexFormat.float32x3, // 12 bytes > 8 stride
              ),
            ],
          ),
        ],
      );
      expect(layout.toGpuLayout, throwsArgumentError);
    });

    test('rejects a duplicated attribute name', () {
      final layout = VertexLayoutDescriptor(
        buffers: const [
          VertexBufferDescriptor(
            strideInBytes: 24,
            attributes: [
              VertexAttributeDescriptor(
                name: 'position',
                format: gpu.VertexFormat.float32x3,
              ),
              VertexAttributeDescriptor(
                name: 'position',
                format: gpu.VertexFormat.float32x3,
                offsetInBytes: 12,
              ),
            ],
          ),
        ],
      );
      expect(layout.toGpuLayout, throwsArgumentError);
    });

    test('accepts the canonical layout', () {
      expect(kUnskinnedInstancedLayout.toGpuLayout, returnsNormally);
    });
  });
}
