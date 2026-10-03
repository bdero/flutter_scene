import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

const _instance = VertexBufferDescriptor(
  strideInBytes: 80,
  stepMode: gpu.VertexStepMode.instance,
  attributes: [
    VertexAttributeDescriptor(
      name: 'model_transform_0',
      format: gpu.VertexFormat.float32x4,
    ),
  ],
);

UnskinnedGeometry _declared(VertexBufferDescriptor first) =>
    UnskinnedGeometry()..setVertexLayout(
      VertexLayoutDescriptor(buffers: [first, _instance]),
    );

void main() {
  test('reads a declared float position stream', () {
    const first = VertexBufferDescriptor(
      strideInBytes: 12,
      attributes: [
        VertexAttributeDescriptor(
          name: 'position',
          format: gpu.VertexFormat.float32x3,
        ),
      ],
    );
    final layout = _declared(first).velocityPositionLayout;

    expect(layout, isNotNull);
    expect(layout!.buffers.first, first);
    expect(layout.buffers, hasLength(2));
  });

  test('skips a packed first stream', () {
    const first = VertexBufferDescriptor(
      strideInBytes: 8,
      attributes: [
        VertexAttributeDescriptor(
          name: 'packed',
          format: gpu.VertexFormat.uint32x2,
        ),
      ],
    );

    expect(_declared(first).velocityPositionLayout, isNull);
  });

  test('builds the layout once for an unchanged declaration', () {
    const first = VertexBufferDescriptor(
      strideInBytes: 12,
      attributes: [
        VertexAttributeDescriptor(
          name: 'position',
          format: gpu.VertexFormat.float32x3,
        ),
      ],
    );
    final geometry = _declared(first);

    expect(
      identical(
        geometry.velocityPositionLayout,
        geometry.velocityPositionLayout,
      ),
      isTrue,
    );
  });
}
