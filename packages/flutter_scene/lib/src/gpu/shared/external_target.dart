/// What kind of platform object an external color target wraps.
///
/// Which kinds a backend accepts depends on the backend; see
/// `GpuCapabilities.externalColorTargets` and `wrapExternalColorTarget`.
enum ExternalTargetHandleKind {
  /// A complete framebuffer the backend binds and draws into but cannot
  /// sample (a WebXR `XRWebGLLayer.framebuffer` on the web).
  framebuffer,

  /// A color texture the backend attaches to its own framebuffer (a WebXR
  /// projection layer's `colorTexture` on the web).
  texture,
}
