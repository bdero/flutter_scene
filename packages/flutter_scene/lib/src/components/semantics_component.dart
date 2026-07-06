import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter_scene/src/components/component.dart';

/// Exposes the owning `Node` to assistive technology (screen readers,
/// switch access) as one element of the enclosing `SceneView`'s semantics.
///
/// Scene content is opaque to accessibility by default. Attaching a
/// [SemanticsComponent] to a node publishes it as a semantics element whose
/// focus rectangle is the node's bounds projected through the view's camera,
/// recomputed as the camera and the node move. Actions ([onTap],
/// [onIncrease], [onDecrease], and anything else set through [properties])
/// are invoked directly by the platform's accessibility system; they do not
/// pass through scene raycasting.
///
/// ```dart
/// node.addComponent(SemanticsComponent(
///   label: 'Power switch',
///   button: true,
///   onTap: togglePower,
/// ));
/// ```
///
/// The focus rectangle covers the node's [`combinedLocalBounds`] (the node's
/// mesh and all descendants). Set [boundsOverride] when that is wrong for
/// focus, and for subtrees with no computable bounds (skinned content),
/// which otherwise project as a nominal-size rectangle at the node origin.
///
/// Elements read in scene-graph order; set [sortOrder] to control traversal
/// explicitly. While the node is invisible (or, with [occlusionHiding], is
/// occluded) it is removed from the semantics tree.
///
/// The convenience parameters cover common cases; pass a full
/// [SemanticsProperties] as [properties] for anything else (sliders, live
/// regions, custom actions). The two forms are mutually exclusive.
/// {@category Accessibility}
class SemanticsComponent extends Component {
  /// Creates semantics for the owning node.
  ///
  /// Pass either the convenience parameters or a full [properties] object,
  /// not both.
  SemanticsComponent({
    String? label,
    String? value,
    String? hint,
    bool button = false,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    VoidCallback? onIncrease,
    VoidCallback? onDecrease,
    VoidCallback? onDidGainAccessibilityFocus,
    VoidCallback? onDidLoseAccessibilityFocus,
    double? sortOrder,
    TextDirection? textDirection,
    bool occlusionHiding = false,
    vm.Aabb3? boundsOverride,
    SemanticsProperties? properties,
  }) : assert(
         properties == null ||
             (label == null &&
                 value == null &&
                 hint == null &&
                 !button &&
                 onTap == null &&
                 onLongPress == null &&
                 onIncrease == null &&
                 onDecrease == null &&
                 onDidGainAccessibilityFocus == null &&
                 onDidLoseAccessibilityFocus == null &&
                 sortOrder == null &&
                 textDirection == null),
         'Pass either the convenience parameters or a full properties '
         'object, not both.',
       ),
       _label = label,
       _value = value,
       _hint = hint,
       _button = button,
       _onTap = onTap,
       _onLongPress = onLongPress,
       _onIncrease = onIncrease,
       _onDecrease = onDecrease,
       _onDidGainAccessibilityFocus = onDidGainAccessibilityFocus,
       _onDidLoseAccessibilityFocus = onDidLoseAccessibilityFocus,
       _sortOrder = sortOrder,
       _textDirection = textDirection,
       _occlusionHiding = occlusionHiding,
       _boundsOverride = boundsOverride,
       _properties = properties;

  String? _label;
  String? _value;
  String? _hint;
  bool _button;
  VoidCallback? _onTap;
  VoidCallback? _onLongPress;
  VoidCallback? _onIncrease;
  VoidCallback? _onDecrease;
  VoidCallback? _onDidGainAccessibilityFocus;
  VoidCallback? _onDidLoseAccessibilityFocus;
  double? _sortOrder;
  TextDirection? _textDirection;
  bool _occlusionHiding;
  vm.Aabb3? _boundsOverride;
  SemanticsProperties? _properties;

  // Bumped by every property setter so the per-frame snapshot can detect
  // changes without comparing assembled SemanticsProperties objects.
  int _version = 0;

  void _bump() => _version++;

  // Guards the convenience setters: a component constructed with (or later
  // given) an explicit [properties] object owns its whole configuration
  // there.
  void _assertConvenience() {
    assert(
      _properties == null,
      'This SemanticsComponent uses an explicit SemanticsProperties object; '
      'set `properties` instead of the convenience fields.',
    );
  }

  /// A short description of the node, read by the screen reader.
  String? get label => _label;
  set label(String? value) {
    _assertConvenience();
    if (value == _label) return;
    _label = value;
    _bump();
  }

  /// The current value the node represents (for example a reading on a
  /// gauge), read after [label].
  String? get value => _value;
  set value(String? newValue) {
    _assertConvenience();
    if (newValue == _value) return;
    _value = newValue;
    _bump();
  }

  /// A brief description of what interacting with the node does.
  String? get hint => _hint;
  set hint(String? value) {
    _assertConvenience();
    if (value == _hint) return;
    _hint = value;
    _bump();
  }

  /// Whether the node behaves like a button.
  bool get button => _button;
  set button(bool value) {
    _assertConvenience();
    if (value == _button) return;
    _button = value;
    _bump();
  }

  /// Called when assistive technology activates the node (for example a
  /// VoiceOver double tap).
  VoidCallback? get onTap => _onTap;
  set onTap(VoidCallback? value) {
    _assertConvenience();
    if (value == _onTap) return;
    _onTap = value;
    _bump();
  }

  /// Called when assistive technology long-presses the node.
  VoidCallback? get onLongPress => _onLongPress;
  set onLongPress(VoidCallback? value) {
    _assertConvenience();
    if (value == _onLongPress) return;
    _onLongPress = value;
    _bump();
  }

  /// Called when assistive technology increases the node's [value].
  VoidCallback? get onIncrease => _onIncrease;
  set onIncrease(VoidCallback? value) {
    _assertConvenience();
    if (value == _onIncrease) return;
    _onIncrease = value;
    _bump();
  }

  /// Called when assistive technology decreases the node's [value].
  VoidCallback? get onDecrease => _onDecrease;
  set onDecrease(VoidCallback? value) {
    _assertConvenience();
    if (value == _onDecrease) return;
    _onDecrease = value;
    _bump();
  }

  /// Called when the node gains accessibility focus (the screen-reader
  /// cursor lands on it). A natural place to draw an in-scene focus
  /// indicator (a `Node.highlightColor` outline) or steer the camera.
  VoidCallback? get onDidGainAccessibilityFocus => _onDidGainAccessibilityFocus;
  set onDidGainAccessibilityFocus(VoidCallback? value) {
    _assertConvenience();
    if (value == _onDidGainAccessibilityFocus) return;
    _onDidGainAccessibilityFocus = value;
    _bump();
  }

  /// Called when the node loses accessibility focus.
  VoidCallback? get onDidLoseAccessibilityFocus => _onDidLoseAccessibilityFocus;
  set onDidLoseAccessibilityFocus(VoidCallback? value) {
    _assertConvenience();
    if (value == _onDidLoseAccessibilityFocus) return;
    _onDidLoseAccessibilityFocus = value;
    _bump();
  }

  /// The node's position in the accessibility traversal order, lower values
  /// first. Elements without a sort order read in scene-graph order.
  double? get sortOrder => _sortOrder;
  set sortOrder(double? value) {
    _assertConvenience();
    if (value == _sortOrder) return;
    _sortOrder = value;
    _bump();
  }

  /// The reading direction of [label], [value], and [hint]. When null (the
  /// default) the enclosing `SceneView`'s ambient [Directionality] is used.
  TextDirection? get textDirection => _textDirection;
  set textDirection(TextDirection? value) {
    _assertConvenience();
    if (value == _textDirection) return;
    _textDirection = value;
    _bump();
  }

  /// Whether the node leaves the semantics tree while scene geometry
  /// occludes it from the camera. Defaults to false (an occluded node stays
  /// focusable), matching how a partially obscured widget behaves.
  ///
  /// Checked with a single raycast toward the node's bounds center each
  /// semantics update, so enable it only where occlusion genuinely changes
  /// meaning (a gauge behind a hatch).
  bool get occlusionHiding => _occlusionHiding;
  set occlusionHiding(bool value) {
    if (value == _occlusionHiding) return;
    _occlusionHiding = value;
    _bump();
  }

  /// Local-space bounds to project as the focus rectangle, replacing the
  /// node's own combined bounds.
  vm.Aabb3? get boundsOverride => _boundsOverride;
  set boundsOverride(vm.Aabb3? value) {
    if (value == _boundsOverride) return;
    _boundsOverride = value;
    _bump();
  }

  /// The full semantics configuration, for anything beyond the convenience
  /// parameters. Mutually exclusive with them.
  ///
  /// Used verbatim, so set [SemanticsProperties.textDirection] whenever the
  /// object carries text (the platform requires a direction on any node
  /// with a label, value, or hint); the ambient direction only fills in for
  /// the convenience parameters.
  SemanticsProperties? get properties => _properties;
  set properties(SemanticsProperties? value) {
    assert(
      value == null ||
          (_label == null &&
              _value == null &&
              _hint == null &&
              !_button &&
              _onTap == null &&
              _onLongPress == null &&
              _onIncrease == null &&
              _onDecrease == null &&
              _onDidGainAccessibilityFocus == null &&
              _onDidLoseAccessibilityFocus == null &&
              _sortOrder == null &&
              _textDirection == null),
      'Pass either the convenience parameters or a full properties object, '
      'not both.',
    );
    if (identical(value, _properties)) return;
    _properties = value;
    _bump();
  }

  /// Monotonic change counter over every semantics-affecting property, used
  /// by `SceneView` to detect stale snapshots.
  @internal
  int get version => _version;

  SemanticsProperties? _builtProperties;
  int _builtVersion = -1;
  TextDirection? _builtAmbient;

  /// The assembled [SemanticsProperties] for the current configuration,
  /// cached per [version]. [ambientTextDirection] fills in [textDirection]
  /// when unset (the platform requires a direction on any node with text);
  /// an explicit [properties] object is returned as-is and owns its own
  /// direction.
  @internal
  SemanticsProperties effectiveProperties(TextDirection? ambientTextDirection) {
    if (_builtProperties == null ||
        _builtVersion != _version ||
        _builtAmbient != ambientTextDirection) {
      _builtProperties =
          _properties ??
          SemanticsProperties(
            label: _label,
            value: _value,
            hint: _hint,
            button: _button ? true : null,
            onTap: _onTap,
            onLongPress: _onLongPress,
            onIncrease: _onIncrease,
            onDecrease: _onDecrease,
            onDidGainAccessibilityFocus: _onDidGainAccessibilityFocus,
            onDidLoseAccessibilityFocus: _onDidLoseAccessibilityFocus,
            sortKey: _sortOrder == null ? null : OrdinalSortKey(_sortOrder!),
            textDirection: _textDirection ?? ambientTextDirection,
          );
      _builtVersion = _version;
      _builtAmbient = ambientTextDirection;
    }
    return _builtProperties!;
  }

  @override
  void onMount() {
    node.internalRenderScene?.addSemanticsComponent(this);
  }

  @override
  void onUnmount() {
    node.internalRenderScene?.removeSemanticsComponent(this);
  }
}
