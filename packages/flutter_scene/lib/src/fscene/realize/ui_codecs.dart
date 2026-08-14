/// Codecs for the UI-facing components: widget surfaces and semantics.
///
/// A widget subtree cannot travel through a document, so the format carries a
/// named slot instead; the app registers a builder for each slot name at
/// startup ([registerWidgetSlot]) and the codec binds the two at realize.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Size, TextDirection, Widget;

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/semantics_component.dart';
import 'package:flutter_scene/src/components/widget_component.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter_scene/src/fscene/realize/declarative_codec.dart';
import 'package:flutter_scene/src/widget_texture.dart';
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';

// --- Widget slot registry ---

/// Builds the widget subtree bound to a slot name.
typedef WidgetSlotBuilder = Widget Function();

final Map<String, WidgetSlotBuilder> _widgetSlots = {};

/// Registers [builder] under slot [name], replacing any existing entry.
///
/// A document's `widget` component names the subtree it shows by slot; the
/// app registers its builders at startup (`registerWidgetSlot('scoreboard',
/// () => const Scoreboard())`) so documents authored against them realize. A
/// scene loaded with an unregistered slot skips the component.
/// {@category Widgets}
void registerWidgetSlot(String name, WidgetSlotBuilder builder) {
  _widgetSlots[name] = builder;
}

/// The registered builder for slot [name], or null.
/// {@category Widgets}
WidgetSlotBuilder? widgetSlotBuilder(String name) => _widgetSlots[name];

/// Clears every registered slot. For tests that must not leak registrations
/// across cases.
@visibleForTesting
void debugResetWidgetSlots() => _widgetSlots.clear();

// --- Widget component ---

// The slot name the component was realized from, stamped at realize so
// serialize can recover it (the component holds the built widget, not the
// name).
// TODO(widget-hand-built): hand-built widget components carry no stamp, so
// they do not serialize; grow a public slot-tagging seam to lift that.
final Expando<String> _widgetSlot = Expando('widget component slot');

MapValue _encodeUpdatePolicy(WidgetUpdatePolicy policy) {
  final interval = policy.interval;
  if (interval != null) {
    final milliseconds = interval.inMilliseconds;
    return MapValue({
      'kind': const StringValue('interval'),
      'milliseconds': IntValue(milliseconds < 1 ? 1 : milliseconds),
    });
  }
  if (identical(policy, WidgetUpdatePolicy.manual)) {
    return MapValue({'kind': const StringValue('manual')});
  }
  return MapValue({'kind': const StringValue('everyFrame')});
}

WidgetUpdatePolicy _decodeUpdatePolicy(PropertyValue? value) {
  if (value is! MapValue) return WidgetUpdatePolicy.everyFrame;
  final kind = value.values['kind'];
  switch (kind is StringValue ? kind.value : '') {
    case 'manual':
      return WidgetUpdatePolicy.manual;
    case 'interval':
      final milliseconds = switch (value.values['milliseconds']) {
        IntValue(:final value) => value,
        DoubleValue(:final value) => value.round(),
        _ => 1,
      };
      return WidgetUpdatePolicy.interval(
        Duration(milliseconds: milliseconds < 1 ? 1 : milliseconds),
      );
  }
  return WidgetUpdatePolicy.everyFrame;
}

/// Codec for [WidgetComponent]. The widget subtree rides a named slot bound
/// through [registerWidgetSlot]; a spec naming an unregistered slot skips the
/// component so the scene still loads, without the surface. Custom geometry,
/// materials, and bind callbacks stay code-only.
// TODO(widget-slot-diagnostics): surface skipped slots to the editor (a
// per-load report) instead of only a debug print.
class WidgetCodec extends DeclarativeComponentCodec<WidgetComponent> {
  @override
  String get type => 'widget';

  @override
  List<ComponentField<WidgetComponent>> get fields => [
    // No default; every widget spec names its slot.
    ComponentField(
      const ComponentPropertyDef(
        'slot',
        ComponentPropertyKind.string,
        doc: 'Registered slot name of the widget subtree this surface shows.',
      ),
      read: (c, _) {
        final slot = _widgetSlot[c];
        return slot == null ? null : StringValue(slot);
      },
    ),
    ComponentField.vec2(
      'size',
      defaultValue: () => Vector2(256, 256),
      doc: 'The child\'s logical layout size.',
      get: (c) => Vector2(c.size.width, c.size.height),
    ),
    ComponentField.number(
      'pixelRatio',
      defaultValue: 1.0,
      doc: 'Texels per logical pixel.',
      constraints: const [Range.nonNegative(), SoftRange(0.25, 4)],
      get: (c) => c.pixelRatio,
    ),
    ComponentField.number(
      'worldHeight',
      defaultValue: 1.0,
      doc: 'Height of the owned quad in world units.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.worldHeight,
    ),
    ComponentField(
      ComponentPropertyDef(
        'updatePolicy',
        ComponentPropertyKind.union,
        defaultValue: MapValue({'kind': const StringValue('everyFrame')}),
        doc: 'When the widget subtree is re-captured.',
        unionVariants: const {
          'everyFrame': [],
          'interval': [
            ComponentPropertyDef(
              'milliseconds',
              ComponentPropertyKind.integer,
              defaultValue: IntValue(100),
              doc: 'Milliseconds between captures.',
              constraints: [IntRange(1, null)],
            ),
          ],
          'manual': [],
        },
      ),
      read: (c, _) => _encodeUpdatePolicy(c.updatePolicy),
    ),
    ComponentField.enumString(
      'input',
      values: WidgetInput.values,
      defaultValue: WidgetInput.automatic,
      doc: 'How the surface receives pointer input.',
      get: (c) => c.input,
    ),
    ComponentField.boolean(
      'occlusionHiding',
      defaultValue: false,
      doc: 'Drop the subtree\'s semantics while scene geometry occludes it.',
      get: (c) => c.occlusionHiding,
    ),
  ];

  @override
  Component? realize(ComponentSpec spec, RealizeContext context) {
    final slot = spec.properties['slot'];
    final name = slot is StringValue ? slot.value : '';
    if (widgetSlotBuilder(name) == null) {
      debugPrint(
        'fscene: widget component skipped (slot "$name" is not registered; '
        'call registerWidgetSlot at startup)',
      );
      return null;
    }
    return super.realize(spec, context);
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is! WidgetComponent) return null;
    if (_widgetSlot[component] == null) {
      debugPrint(
        'fscene: widget component not serialized; it was not realized from '
        'a named slot',
      );
      return null;
    }
    return super.serialize(component, context);
  }

  @override
  WidgetComponent create(PropertyReader props) {
    final slot = props.string('slot');
    // realize() guarded the lookup.
    final builder = widgetSlotBuilder(slot)!;
    final size = props.vec2('size');
    final pixelRatio = props.number('pixelRatio');
    final worldHeight = props.number('worldHeight');
    final component = WidgetComponent(
      child: builder(),
      size: Size(size.x > 0 ? size.x : 256, size.y > 0 ? size.y : 256),
      pixelRatio: pixelRatio > 0 ? pixelRatio : 1.0,
      worldHeight: worldHeight > 0 ? worldHeight : 1.0,
      update: _decodeUpdatePolicy(props.value('updatePolicy')),
      input: props.enumValue('input', WidgetInput.values),
      occlusionHiding: props.boolean('occlusionHiding'),
    );
    _widgetSlot[component] = slot;
    return component;
  }
}

// --- Semantics ---

ComponentField<SemanticsComponent> _optionalStringField(
  String name, {
  required String? Function(SemanticsComponent component) get,
  required void Function(SemanticsComponent component, String value) set,
  String? doc,
}) => ComponentField(
  ComponentPropertyDef(name, ComponentPropertyKind.string, doc: doc),
  read: (c, _) {
    final value = get(c);
    return value == null ? null : StringValue(value);
  },
  write: (c, v, _) {
    if (v is StringValue) set(c, v.value);
  },
);

/// Codec for [SemanticsComponent]. Only the data fields travel; action
/// callbacks and [SemanticsComponent.boundsOverride] are code-only. A
/// component driven by an explicit [SemanticsComponent.properties] object
/// owns its whole configuration in code, so it serializes as a bare spec
/// (type plus the universal `enabled` flag) that keeps the node marked as
/// semantic on reload.
// TODO(semantics-bounds): boundsOverride does not serialize; carry it once a
// bounds property kind exists.
class SemanticsCodec extends DeclarativeComponentCodec<SemanticsComponent> {
  @override
  String get type => 'semantics';

  @override
  List<ComponentField<SemanticsComponent>> get fields => [
    // The nullable fields have no default; absence round-trips as null.
    _optionalStringField(
      'label',
      doc: 'Short description read by the screen reader.',
      get: (c) => c.label,
      set: (c, v) => c.label = v,
    ),
    _optionalStringField(
      'value',
      doc: 'The current value the node represents.',
      get: (c) => c.value,
      set: (c, v) => c.value = v,
    ),
    _optionalStringField(
      'hint',
      doc: 'What interacting with the node does.',
      get: (c) => c.hint,
      set: (c, v) => c.hint = v,
    ),
    ComponentField.boolean(
      'button',
      defaultValue: false,
      doc: 'Whether the node behaves like a button.',
      get: (c) => c.button,
      set: (c, v) => c.button = v,
    ),
    ComponentField(
      const ComponentPropertyDef(
        'sortOrder',
        ComponentPropertyKind.number,
        doc: 'Traversal order, lower first; absent reads in scene order.',
      ),
      read: (c, _) {
        final sortOrder = c.sortOrder;
        return sortOrder == null ? null : DoubleValue(sortOrder);
      },
      write: (c, v, _) {
        c.sortOrder = switch (v) {
          DoubleValue(:final value) => value,
          IntValue(:final value) => value.toDouble(),
          _ => c.sortOrder,
        };
      },
    ),
    ComponentField(
      const ComponentPropertyDef(
        'textDirection',
        ComponentPropertyKind.string,
        doc:
            'Reading direction of the text fields; absent uses the ambient '
            'direction.',
        options: ['ltr', 'rtl'],
      ),
      read: (c, _) {
        final direction = c.textDirection;
        return direction == null ? null : StringValue(direction.name);
      },
      write: (c, v, _) {
        if (v is! StringValue) return;
        c.textDirection = TextDirection.values.asNameMap()[v.value];
      },
    ),
    ComponentField.boolean(
      'occlusionHiding',
      defaultValue: false,
      doc: 'Leave the semantics tree while scene geometry occludes the node.',
      get: (c) => c.occlusionHiding,
      set: (c, v) => c.occlusionHiding = v,
    ),
  ];

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is! SemanticsComponent) return null;
    // Properties mode: the SemanticsProperties object is code-owned, so the
    // spec carries only the type (the registry adds `enabled` on top).
    if (component.properties != null) return ComponentSpec(type);
    return super.serialize(component, context);
  }

  @override
  SemanticsComponent create(PropertyReader props) => SemanticsComponent();
}
