/// Placeholder realization for component types known only by schema.
///
/// An editor (or any tool) that learns a component type from a schema it
/// fetched, cached, or read from a package manifest has no codec code for it
/// in-process. Registering a [PlaceholderComponentCodec] makes documents
/// carrying that type realize into inert [ForeignComponent] data bags and
/// serialize back losslessly, so the incremental edit path works and no data
/// is ever dropped. Behavior never runs where only the schema traveled; the
/// real codec realizes the real component in the app that registered it.
library;

import 'package:scene/scene.dart';
import 'package:scene/schema.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';

/// An inert data-bag component standing in for a type whose real
/// implementation lives in another process (or an unregistered package).
/// Carries the spec it was realized from, untouched.
/// {@category Assets and loading}
class ForeignComponent extends Component {
  ForeignComponent(this.spec);

  /// The component data, preserved verbatim for serialization.
  ComponentSpec spec;
}

/// Realizes and serializes one schema-described type as [ForeignComponent]s.
/// {@category Assets and loading}
class PlaceholderComponentCodec extends ComponentCodec {
  PlaceholderComponentCodec(this._schema);

  final ComponentSchema _schema;

  @override
  String get type => _schema.type;

  @override
  ComponentSchema get schema => _schema;

  @override
  List<ComponentPropertyDef> get propertySchema => _schema.properties;

  @override
  bool claims(Component component) =>
      component is ForeignComponent && component.spec.type == type;

  @override
  Component realize(ComponentSpec spec, RealizeContext context) =>
      ForeignComponent(
        ComponentSpec(spec.type, properties: {...spec.properties}),
      );

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (!claims(component)) return null;
    final spec = (component as ForeignComponent).spec;
    return ComponentSpec(spec.type, properties: {...spec.properties});
  }
}
