part of '../animation.dart';

/// A node property an [AnimationProperty.path] channel drives, read and
/// written as [componentCount] floats.
///
/// [resolveAnimatedPath] binds one to a node; the path vocabulary is
/// documented on the scene format's `AnimationPathChannelSpec`.
final class AnimatedPath {
  AnimatedPath._(this.componentCount, this._read, this._write);

  /// Floats per value.
  final int componentCount;

  final void Function(Float32List out) _read;
  final void Function(Float32List values) _write;

  /// Copies the property's current value into [out].
  void read(Float32List out) => _read(out);

  /// Sets the property to [values].
  void write(Float32List values) => _write(values);
}

/// Binds [path] to the property it names on [node], or returns null when the
/// node has nothing at that path.
AnimatedPath? resolveAnimatedPath(Node node, String path) {
  final parts = path.split('/');
  switch (parts) {
    case ['visible']:
      return AnimatedPath._(
        1,
        (out) => out[0] = node.visible ? 1 : 0,
        (values) => node.visible = values[0] >= 0.5,
      );
    case ['light', final property]:
      return _lightPath(node, property);
    case ['primitives', final index, 'material', ...final rest]:
      final primitives = node.mesh?.primitives;
      final i = int.tryParse(index);
      if (primitives == null || i == null || i < 0 || i >= primitives.length) {
        return null;
      }
      return _materialPath(primitives[i], rest);
  }
  return null;
}

AnimatedPath? _lightPath(Node node, String property) {
  final point = node.getComponent<PointLightComponent>();
  if (point != null) {
    return switch (property) {
      'color' => _vector(
        () => point.light.color,
        (v) => point.light.color = v,
        Vector3.zero(),
      ),
      'intensity' => _scalar(
        () => point.light.intensity,
        (v) => point.light.intensity = v,
      ),
      'range' => _scalar(() => point.light.range, (v) => point.light.range = v),
      _ => null,
    };
  }
  final spot = node.getComponent<SpotLightComponent>();
  if (spot != null) {
    return switch (property) {
      'color' => _vector(
        () => spot.light.color,
        (v) => spot.light.color = v,
        Vector3.zero(),
      ),
      'intensity' => _scalar(
        () => spot.light.intensity,
        (v) => spot.light.intensity = v,
      ),
      'range' => _scalar(() => spot.light.range, (v) => spot.light.range = v),
      'innerConeAngle' => _scalar(
        () => spot.light.innerConeAngle,
        (v) => spot.light.innerConeAngle = v,
      ),
      'outerConeAngle' => _scalar(
        () => spot.light.outerConeAngle,
        (v) => spot.light.outerConeAngle = v,
      ),
      _ => null,
    };
  }
  final directional = node.getComponent<DirectionalLightComponent>();
  if (directional != null) {
    return switch (property) {
      'color' => _vector(
        () => directional.light.color,
        (v) => directional.light.color = v,
        Vector3.zero(),
      ),
      'intensity' => _scalar(
        () => directional.light.intensity,
        (v) => directional.light.intensity = v,
      ),
      _ => null,
    };
  }
  return null;
}

AnimatedPath? _materialPath(MeshPrimitive primitive, List<String> path) {
  final material = primitive.material;
  if (material is UnlitMaterial) {
    return switch (path) {
      ['baseColorFactor'] => _vector(
        () => material.baseColorFactor,
        (v) => material.baseColorFactor = v,
        Vector4.zero(),
      ),
      ['baseColorTexture', final property] => _textureTransformPath(
        () => material.baseColorTextureTransform,
        (t) => material.baseColorTextureTransform = t,
        property,
      ),
      _ => null,
    };
  }
  if (material is! PhysicallyBasedMaterial) return null;
  final m = material;
  if (path case [final slot, final property]) {
    final (get, set) = switch (slot) {
      'baseColorTexture' => (
        () => m.baseColorTextureTransform,
        (TextureTransform t) => m.baseColorTextureTransform = t,
      ),
      'metallicRoughnessTexture' => (
        () => m.metallicRoughnessTextureTransform,
        (TextureTransform t) => m.metallicRoughnessTextureTransform = t,
      ),
      'normalTexture' => (
        () => m.normalTextureTransform,
        (TextureTransform t) => m.normalTextureTransform = t,
      ),
      'occlusionTexture' => (
        () => m.occlusionTextureTransform,
        (TextureTransform t) => m.occlusionTextureTransform = t,
      ),
      'emissiveTexture' => (
        () => m.emissiveTextureTransform,
        (TextureTransform t) => m.emissiveTextureTransform = t,
      ),
      'specularTexture' => (
        () => m.specularTextureTransform,
        (TextureTransform t) => m.specularTextureTransform = t,
      ),
      'specularColorTexture' => (
        () => m.specularColorTextureTransform,
        (TextureTransform t) => m.specularColorTextureTransform = t,
      ),
      'clearcoatTexture' => (
        () => m.clearcoatTextureTransform,
        (TextureTransform t) => m.clearcoatTextureTransform = t,
      ),
      'clearcoatRoughnessTexture' => (
        () => m.clearcoatRoughnessTextureTransform,
        (TextureTransform t) => m.clearcoatRoughnessTextureTransform = t,
      ),
      'clearcoatNormalTexture' => (
        () => m.clearcoatNormalTextureTransform,
        (TextureTransform t) => m.clearcoatNormalTextureTransform = t,
      ),
      'sheenColorTexture' => (
        () => m.sheenColorTextureTransform,
        (TextureTransform t) => m.sheenColorTextureTransform = t,
      ),
      'sheenRoughnessTexture' => (
        () => m.sheenRoughnessTextureTransform,
        (TextureTransform t) => m.sheenRoughnessTextureTransform = t,
      ),
      'transmissionTexture' => (
        () => m.transmissionTextureTransform,
        (TextureTransform t) => m.transmissionTextureTransform = t,
      ),
      'diffuseTransmissionTexture' => (
        () => m.diffuseTransmissionTextureTransform,
        (TextureTransform t) => m.diffuseTransmissionTextureTransform = t,
      ),
      'diffuseTransmissionColorTexture' => (
        () => m.diffuseTransmissionColorTextureTransform,
        (TextureTransform t) => m.diffuseTransmissionColorTextureTransform = t,
      ),
      'thicknessTexture' => (
        () => m.thicknessTextureTransform,
        (TextureTransform t) => m.thicknessTextureTransform = t,
      ),
      'iridescenceTexture' => (
        () => m.iridescenceTextureTransform,
        (TextureTransform t) => m.iridescenceTextureTransform = t,
      ),
      'iridescenceThicknessTexture' => (
        () => m.iridescenceThicknessTextureTransform,
        (TextureTransform t) => m.iridescenceThicknessTextureTransform = t,
      ),
      'anisotropyTexture' => (
        () => m.anisotropyTextureTransform,
        (TextureTransform t) => m.anisotropyTextureTransform = t,
      ),
      _ => (null, null),
    };
    if (get == null || set == null) return null;
    return _textureTransformPath(get, set, property);
  }
  if (path case [final property]) {
    return switch (property) {
      'baseColorFactor' => _vector(
        () => m.baseColorFactor,
        (v) => m.baseColorFactor = v,
        Vector4.zero(),
      ),
      'emissiveFactor' => _vector(
        () => m.emissiveFactor,
        (v) => m.emissiveFactor = v,
        Vector4.zero(),
        count: 3,
      ),
      'emissiveStrength' => _scalar(
        () => m.emissiveStrength,
        (v) => m.emissiveStrength = v,
      ),
      'metallicFactor' => _scalar(
        () => m.metallicFactor,
        (v) => m.metallicFactor = v,
      ),
      'roughnessFactor' => _scalar(
        () => m.roughnessFactor,
        (v) => m.roughnessFactor = v,
      ),
      'normalScale' => _scalar(() => m.normalScale, (v) => m.normalScale = v),
      'occlusionStrength' => _scalar(
        () => m.occlusionStrength,
        (v) => m.occlusionStrength = v,
      ),
      'alphaCutoff' => _scalar(() => m.alphaCutoff, (v) => m.alphaCutoff = v),
      'ior' => _scalar(() => m.ior, (v) => m.ior = v),
      'specular' => _scalar(() => m.specular, (v) => m.specular = v),
      'specularColor' => _vector(
        () => m.specularColor,
        (v) => m.specularColor = v,
        Vector4.zero(),
        count: 3,
      ),
      'clearcoat' => _scalar(() => m.clearcoat, (v) => m.clearcoat = v),
      'clearcoatRoughness' => _scalar(
        () => m.clearcoatRoughness,
        (v) => m.clearcoatRoughness = v,
      ),
      'sheenColor' => _vector(
        () => m.sheenColor,
        (v) => m.sheenColor = v,
        Vector4.zero(),
        count: 3,
      ),
      'sheenRoughness' => _scalar(
        () => m.sheenRoughness,
        (v) => m.sheenRoughness = v,
      ),
      'transmission' => _scalar(
        () => m.transmission,
        (v) => m.transmission = v,
      ),
      'diffuseTransmission' => _scalar(
        () => m.diffuseTransmission,
        (v) => m.diffuseTransmission = v,
      ),
      'diffuseTransmissionColor' => _vector(
        () => m.diffuseTransmissionColor,
        (v) => m.diffuseTransmissionColor = v,
        Vector4.zero(),
        count: 3,
      ),
      'thickness' => _scalar(() => m.thickness, (v) => m.thickness = v),
      'attenuationDistance' => _scalar(
        () => m.attenuationDistance,
        (v) => m.attenuationDistance = v,
      ),
      'attenuationColor' => _vector(
        () => m.attenuationColor,
        (v) => m.attenuationColor = v,
        Vector4.zero(),
        count: 3,
      ),
      'dispersion' => _scalar(() => m.dispersion, (v) => m.dispersion = v),
      'iridescence' => _scalar(() => m.iridescence, (v) => m.iridescence = v),
      'iridescenceIor' => _scalar(
        () => m.iridescenceIor,
        (v) => m.iridescenceIor = v,
      ),
      'iridescenceThicknessMinimum' => _scalar(
        () => m.iridescenceThicknessMinimum,
        (v) => m.iridescenceThicknessMinimum = v,
      ),
      'iridescenceThicknessMaximum' => _scalar(
        () => m.iridescenceThicknessMaximum,
        (v) => m.iridescenceThicknessMaximum = v,
      ),
      'anisotropy' => _scalar(() => m.anisotropy, (v) => m.anisotropy = v),
      'anisotropyRotation' => _scalar(
        () => m.anisotropyRotation,
        (v) => m.anisotropyRotation = v,
      ),
      _ => null,
    };
  }
  return null;
}

AnimatedPath _scalar(double Function() get, void Function(double) set) =>
    AnimatedPath._(1, (out) => out[0] = get(), (values) => set(values[0]));

// Writes go through [scratch], which the path owns, rather than mutating the
// current vector in place, since a default may be a shared constant. The
// first [count] components animate; the rest keep the current value.
AnimatedPath _vector<V extends Vector>(
  V Function() get,
  void Function(V) set,
  V scratch, {
  int? count,
}) {
  final n = count ?? scratch.storage.length;
  return AnimatedPath._(n, (out) => out.setRange(0, n, get().storage), (
    values,
  ) {
    final current = get();
    if (!identical(current, scratch)) {
      scratch.storage.setAll(0, current.storage);
    }
    scratch.storage.setRange(0, n, values);
    set(scratch);
  });
}

// Same ownership rule as [_vector]. A sibling path animating another field
// of the same transform writes its own scratch, so each copies the fields
// it doesn't drive from whichever transform is current.
AnimatedPath? _textureTransformPath(
  TextureTransform Function() get,
  void Function(TextureTransform) set,
  String property,
) {
  final scratch = TextureTransform();
  void write(void Function(TextureTransform t) apply) {
    final current = get();
    if (!identical(current, scratch)) {
      scratch.offset.setFrom(current.offset);
      scratch.scale.setFrom(current.scale);
      scratch.rotation = current.rotation;
    }
    apply(scratch);
    set(scratch);
  }

  return switch (property) {
    'offset' => AnimatedPath._(
      2,
      (out) => out.setRange(0, 2, get().offset.storage),
      (values) => write((t) => t.offset.setValues(values[0], values[1])),
    ),
    'scale' => AnimatedPath._(
      2,
      (out) => out.setRange(0, 2, get().scale.storage),
      (values) => write((t) => t.scale.setValues(values[0], values[1])),
    ),
    'rotation' => AnimatedPath._(
      1,
      (out) => out[0] = get().rotation,
      (values) => write((t) => t.rotation = values[0]),
    ),
    _ => null,
  };
}
