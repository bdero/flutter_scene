import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/generated/scene_impeller.fb_flatbuffers.dart'
    as fb;
import 'package:vector_math/vector_math.dart';

extension FlatbufferMatrixConversions on fb.Matrix {
  Matrix4 toMatrix4() {
    return Matrix4.fromList(<double>[
      m0, m4, m8, m12, //
      m1, m5, m9, m13, //
      m2, m6, m10, m14, //
      m3, m7, m11, m15, //
    ]);
  }
}

extension FlatbufferIndexTypeConversions on fb.IndexType {
  gpu.IndexType toIndexType() {
    switch (this) {
      case fb.IndexType.k16Bit:
        return gpu.IndexType.int16;
      case fb.IndexType.k32Bit:
        return gpu.IndexType.int32;
    }
    throw Exception('Unknown index type');
  }
}
