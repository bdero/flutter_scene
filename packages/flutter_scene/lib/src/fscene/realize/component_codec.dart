import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/fscene/realize/resource_realizer.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';

/// Context handed to a [ComponentCodec] when realizing a [ComponentSpec] into
/// a live [Component]. Carries the source [document] and a [resources]
/// realizer so a codec (for example a mesh) can resolve referenced geometry
/// and materials.
class RealizeContext {
  /// Creates a realize context over [document], optionally with a [resources]
  /// realizer.
  RealizeContext(this.document, {this.resources});

  /// The document being realized.
  final SceneDocument document;

  /// Realizes referenced geometry/material resources, or null when resource
  /// realization is unavailable (a codec needing it should return null).
  final ResourceRealizer? resources;
}

/// Context handed to a [ComponentCodec] when serializing a live [Component]
/// into a [ComponentSpec]. Carries the destination [document] so a codec can
/// register resources or mint ids.
class SerializeContext {
  /// Creates a serialize context over [document].
  SerializeContext(this.document);

  /// The document being written into.
  final SceneDocument document;
}

/// Translates between a serialized [ComponentSpec] and a live [Component] of
/// one type.
///
/// Codecs are registered in a [FsceneComponentRegistry]; the realizer and
/// serializer dispatch through it. This is the seam that lets the format
/// carry component types the core does not know about.
abstract class ComponentCodec {
  /// The serialized component type name this codec handles (for example
  /// `directionalLight`).
  String get type;

  /// Builds a live component from [spec], or returns null when it cannot be
  /// realized in the given context (for example a mesh with no resource
  /// realizer).
  Component? realize(ComponentSpec spec, RealizeContext context);

  /// Serializes [component] to a [ComponentSpec], or returns null if this
  /// codec does not handle that component instance.
  ComponentSpec? serialize(Component component, SerializeContext context);
}

/// A registry of [ComponentCodec]s, keyed by component type name.
///
/// Realization looks a codec up by [ComponentSpec.type]; serialization tries
/// each codec until one claims the component. Unknown components are skipped
/// (with the caller deciding how to report it) rather than failing the load.
class FsceneComponentRegistry {
  final Map<String, ComponentCodec> _byType = {};

  /// Registers [codec], replacing any existing codec for its type.
  void register(ComponentCodec codec) => _byType[codec.type] = codec;

  /// The codec for [type], or null when none is registered.
  ComponentCodec? codecFor(String type) => _byType[type];

  /// Realizes [spec] into a live component, or returns null when no codec is
  /// registered for its type.
  Component? realize(ComponentSpec spec, RealizeContext context) =>
      _byType[spec.type]?.realize(spec, context);

  /// Serializes [component] using the first codec that claims it, or returns
  /// null when none does.
  ComponentSpec? serialize(Component component, SerializeContext context) {
    for (final codec in _byType.values) {
      final spec = codec.serialize(component, context);
      if (spec != null) return spec;
    }
    return null;
  }
}
