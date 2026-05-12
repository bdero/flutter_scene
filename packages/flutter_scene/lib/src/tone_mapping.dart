/// Tone mapping operator applied when resolving the linear HDR scene color
/// to the display-referred image (see [Scene.toneMapping]).
///
/// The integer values are wire-compatible with the `tone_mapping_mode`
/// uniform in the tone-mapping fragment shader; don't reorder.
enum ToneMappingMode {
  /// Khronos PBR Neutral. Preserves base-color hue/saturation and only
  /// rolls off highlights. Good default for product/configurator
  /// rendering. This is the [Scene] default.
  pbrNeutral,

  /// ACES filmic (Stephen Hill fit). The classic games-y look; tends to
  /// desaturate and shift hue in the highlights.
  aces,

  /// Reinhard (`c / (1 + c)`). Cheap; flattens highlights.
  reinhard,

  /// No tone curve; the lighting result is just exposed and clamped to
  /// `[0, 1]`.
  linear,
}
