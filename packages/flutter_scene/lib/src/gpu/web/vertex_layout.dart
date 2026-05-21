part of '_gpu.dart';

/// Explicit per-pipeline vertex layout override. Not used by the inline
/// pipeline path; the WebGL2 backend derives its vertex layout from the
/// shader's reflected inputs by default.
///
/// Stub for Phase 1; `RenderPipeline` ignores this argument today.
class VertexLayout {
  const VertexLayout({this.strideInBytes = 0});

  final int strideInBytes;
}
