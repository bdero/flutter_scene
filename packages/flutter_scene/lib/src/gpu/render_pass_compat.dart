import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

void bindVertexBufferCompat(
  gpu.RenderPass pass,
  gpu.BufferView bufferView,
  int vertexCount,
) {
  try {
    (pass as dynamic).bindVertexBuffer(bufferView);
  } on NoSuchMethodError {
    (pass as dynamic).bindVertexBuffer(bufferView, vertexCount);
  }
}

void bindIndexBufferCompat(
  gpu.RenderPass pass,
  gpu.BufferView bufferView,
  gpu.IndexType indexType,
  int indexCount,
) {
  try {
    (pass as dynamic).bindIndexBuffer(bufferView, indexType);
  } on NoSuchMethodError {
    (pass as dynamic).bindIndexBuffer(bufferView, indexType, indexCount);
  }
}

void drawCompat(gpu.RenderPass pass, int vertexCount) {
  try {
    (pass as dynamic).draw(vertexCount);
  } on NoSuchMethodError {
    (pass as dynamic).draw();
  }
}

void drawIndexedCompat(gpu.RenderPass pass, int indexCount) {
  try {
    (pass as dynamic).drawIndexed(indexCount);
  } on NoSuchMethodError {
    (pass as dynamic).draw();
  }
}
