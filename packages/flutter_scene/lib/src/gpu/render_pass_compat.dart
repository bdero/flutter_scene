import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

void bindVertexBufferCompat(
  gpu.RenderPass pass,
  gpu.BufferView bufferView,
  int vertexCount, {
  int slot = 0,
}) {
  try {
    (pass as dynamic).bindVertexBuffer(bufferView, slot: slot);
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

void drawCompat(gpu.RenderPass pass, int vertexCount, {int instanceCount = 1}) {
  if (instanceCount != 1) {
    (pass as dynamic).draw(vertexCount, instanceCount: instanceCount);
    return;
  }
  try {
    (pass as dynamic).draw(vertexCount);
  } on NoSuchMethodError {
    (pass as dynamic).draw();
  }
}

void drawIndexedCompat(
  gpu.RenderPass pass,
  int indexCount, {
  int instanceCount = 1,
}) {
  if (instanceCount != 1) {
    (pass as dynamic).drawIndexed(indexCount, instanceCount: instanceCount);
    return;
  }
  try {
    (pass as dynamic).drawIndexed(indexCount);
  } on NoSuchMethodError {
    (pass as dynamic).draw();
  }
}
