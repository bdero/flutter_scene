import 'dart:math' as math;

/// An ordered value transform on a binding.
///
/// Scalars pass through with `y` ignored; vectors transform both components.
/// {@category Bindings}
sealed class Processor {
  const Processor();
}

/// The shape of a [Deadzone].
/// {@category Bindings}
enum DeadzoneShape {
  /// On the vector's magnitude, remapped so output rises smoothly from zero
  /// at the threshold. The right default for sticks.
  scaledRadial,

  /// On each axis independently, remapped the same way.
  axial,
}

/// Zeroes values below [inner] and remaps `[inner, outer]` to `[0, 1]`, so
/// there is no step at the threshold.
/// {@category Bindings}
final class Deadzone extends Processor {
  /// A deadzone from [inner] to [outer].
  const Deadzone(
    this.inner, {
    this.outer = 1.0,
    this.shape = DeadzoneShape.scaledRadial,
  }) : tunable = null;

  /// A deadzone whose [inner] threshold is tunable [id], defaulting to
  /// [inner] until a profile sets it, for a player-facing deadzone setting.
  const Deadzone.tunable(
    String id,
    this.inner, {
    this.outer = 1.0,
    this.shape = DeadzoneShape.scaledRadial,
  }) : tunable = id;

  /// Magnitudes at or below this read as zero.
  final double inner;

  /// Magnitudes at or above this read as full.
  final double outer;

  /// Radial or per axis.
  final DeadzoneShape shape;

  /// The tunable that sets [inner], or null for a fixed threshold.
  final String? tunable;
}

/// Negates a value. A scalar uses [x] only.
/// {@category Bindings}
final class Invert extends Processor {
  /// Negates a scalar, or a vector's horizontal component.
  const Invert() : x = true, y = false, tunable = null;

  /// Negates a vector's vertical component, the usual inverted look.
  const Invert.y() : x = false, y = true, tunable = null;

  /// Negates both components.
  const Invert.both() : x = true, y = true, tunable = null;

  /// Negates the chosen components only while tunable [id] is nonzero, so an
  /// invert-look setting lives in a profile. Off until set.
  const Invert.tunable(String id, {this.x = false, this.y = true})
    : tunable = id;

  /// Whether to negate the horizontal component.
  final bool x;

  /// Whether to negate the vertical component.
  final bool y;

  /// The tunable that switches this inversion, or null when always on.
  final String? tunable;
}

/// Multiplies by [x] and [y], optionally times a tunable a profile can set.
/// {@category Bindings}
final class Scale extends Processor {
  /// Scales by [x] horizontally and [y] vertically (defaulting to [x]).
  const Scale(this.x, [double? y]) : y = y ?? x, tunable = null;

  /// Scales by the tunable value [id], which defaults to [defaultValue] until a
  /// profile sets it. Sensitivity settings use this.
  const Scale.tunable(String id, double defaultValue)
    : x = defaultValue,
      y = defaultValue,
      tunable = id;

  /// Horizontal factor, or the tunable's default.
  final double x;

  /// Vertical factor, or the tunable's default.
  final double y;

  /// The tunable id, or null for a fixed scale.
  final String? tunable;
}

/// Raises the magnitude to [exponent], keeping the sign or direction. Above
/// 1 gives finer control near center.
/// {@category Bindings}
final class ResponseCurve extends Processor {
  /// A power curve with [exponent].
  const ResponseCurve(this.exponent);

  /// The power applied to the magnitude.
  final double exponent;
}

/// Swaps the horizontal and vertical components, so a scalar binding can
/// feed the vertical axis of a vector or delta action.
/// {@category Bindings}
final class SwapAxes extends Processor {
  /// Swaps x and y.
  const SwapAxes();
}

/// Turns a level into a displacement of [rate] units per second over the read
/// window. Required when a stick, key, or axis binding feeds a `DeltaAction`.
/// {@category Bindings}
final class PerSecond extends Processor {
  /// [rate] units of displacement per second at full deflection.
  const PerSecond(this.rate);

  /// Units per second.
  final double rate;
}

/// Applies [processors] to `(x, y)`, reading tunables through [readTunable].
/// [PerSecond] is skipped; the delta evaluation applies it with the window's
/// elapsed time.
(double, double) applyProcessors(
  List<Processor> processors,
  double x,
  double y, {
  required bool isVector,
  required double Function(String id, double fallback) readTunable,
}) {
  for (final processor in processors) {
    switch (processor) {
      case Deadzone(:final outer, :final shape, :final tunable):
        final inner = tunable == null
            ? processor.inner
            : readTunable(tunable, processor.inner);
        final span = math.max(outer - inner, 1e-9);
        double remap(double magnitude) =>
            ((magnitude - inner) / span).clamp(0.0, 1.0);
        if (isVector && shape == DeadzoneShape.scaledRadial) {
          final magnitude = math.sqrt(x * x + y * y);
          if (magnitude <= inner) {
            x = 0;
            y = 0;
          } else {
            final scale = remap(magnitude) / magnitude;
            x *= scale;
            y *= scale;
          }
        } else {
          x = x.sign * remap(x.abs());
          y = y.sign * remap(y.abs());
        }
      case Invert(x: final invertX, y: final invertY, :final tunable):
        if (tunable != null && readTunable(tunable, 0) == 0) break;
        if (invertX) x = -x;
        if (invertY && isVector) y = -y;
      case Scale(x: final fallback, :final tunable?):
        final factor = readTunable(tunable, fallback);
        x *= factor;
        y *= factor;
      case Scale(x: final scaleX, y: final scaleY):
        x *= scaleX;
        y *= scaleY;
      case ResponseCurve(:final exponent):
        if (isVector) {
          final magnitude = math.sqrt(x * x + y * y);
          if (magnitude > 0) {
            final scale = math.pow(magnitude, exponent) / magnitude;
            x *= scale;
            y *= scale;
          }
        } else {
          x = x.sign * math.pow(x.abs(), exponent).toDouble();
        }
      case SwapAxes():
        if (isVector) (x, y) = (y, x);
      case PerSecond():
        break;
    }
  }
  return (x, y);
}
