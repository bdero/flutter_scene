import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/mesh_component.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:flutter_scene/src/node.dart';

/// One primitive's material choices under `KHR_materials_variants`.
///
/// Holds the primitive's default material and its per-variant alternates so
/// [MaterialsVariantsComponent.select] can swap them in place. [node] is the
/// node whose mesh owns [primitive], so the swap can refresh its registered
/// render items.
@internal
class MaterialsVariantBinding {
  MaterialsVariantBinding({
    required this.node,
    required this.primitive,
    required this.defaultMaterial,
    required this.materialsByVariant,
  });

  final Node node;
  final MeshPrimitive primitive;
  final Material defaultMaterial;

  /// Variant index (into [MaterialsVariantsComponent.variants]) to the
  /// material that variant assigns. A variant with no entry keeps
  /// [defaultMaterial].
  final Map<int, Material> materialsByVariant;
}

/// Switches an imported model between its named material variants
/// (`KHR_materials_variants`).
///
/// The importer attaches this to the root of a model whose source declares
/// variants. Read [variants] for the declared names and call [select] to
/// swap every affected primitive's material in place; `select(null)` restores
/// the source's default materials. Selection is cheap (material reassignment,
/// no reload), so it is suitable for interactive switching, for example a
/// product configurator.
///
/// ```dart
/// final variants = model.getComponent<MaterialsVariantsComponent>();
/// variants?.select('beach');
/// ```
/// {@category Materials}
class MaterialsVariantsComponent extends Component {
  // TODO(materials-variants): the offline document importer and the .fscene
  // format do not carry variants yet (runtime importer only), and Node.clone
  // does not clone components, so a cloned model loses variant switching.

  /// Used by the importer; not for application construction.
  @internal
  MaterialsVariantsComponent.internal(
    List<String> variants,
    List<MaterialsVariantBinding> bindings,
  ) : variants = List.unmodifiable(variants),
      _bindings = bindings;

  /// The variant names declared by the source, in declaration order.
  final List<String> variants;

  final List<MaterialsVariantBinding> _bindings;

  String? _selected;

  /// The currently selected variant name, or null when the defaults are
  /// active.
  String? get selected => _selected;

  /// Applies the named variant to every mapped primitive.
  ///
  /// Pass null to restore the default materials. Throws [ArgumentError] when
  /// [name] is not one of [variants]. Primitives the variant does not map
  /// keep their default material.
  void select(String? name) {
    if (name == null) {
      _selected = null;
      for (final binding in _bindings) {
        binding.primitive.material = binding.defaultMaterial;
      }
      _refreshRenderItems();
      return;
    }
    final index = variants.indexOf(name);
    if (index < 0) {
      throw ArgumentError.value(
        name,
        'name',
        'Unknown variant; declared variants are $variants',
      );
    }
    _selected = name;
    for (final binding in _bindings) {
      binding.primitive.material =
          binding.materialsByVariant[index] ?? binding.defaultMaterial;
    }
    _refreshRenderItems();
  }

  // Render items capture materials at registration, so mounted meshes must
  // re-register for a swap to take effect on screen.
  void _refreshRenderItems() {
    final seen = <Node>{};
    for (final binding in _bindings) {
      if (!seen.add(binding.node)) continue;
      for (final meshComponent in binding.node.getComponents<MeshComponent>()) {
        meshComponent.refreshMaterials();
      }
    }
  }
}
