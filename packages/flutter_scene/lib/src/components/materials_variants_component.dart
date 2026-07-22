import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/mesh_component.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:flutter_scene/src/node.dart';

/// One primitive's material choices under `KHR_materials_variants`.
///
/// Identifies the primitive as [node] plus [primitiveIndex] and resolves it
/// at selection time, so a mesh whose primitives are rebuilt (a scene hot
/// reload replacing the mesh component) stays bound instead of orphaning
/// direct primitive references.
@internal
class MaterialsVariantBinding {
  MaterialsVariantBinding({
    required this.node,
    required this.primitiveIndex,
    required this.defaultMaterial,
    required this.materialsByVariant,
  });

  final Node node;
  final int primitiveIndex;
  final Material defaultMaterial;

  /// Variant index (into [MaterialsVariantsComponent.variants]) to the
  /// material that variant assigns. A variant with no entry keeps
  /// [defaultMaterial].
  final Map<int, Material> materialsByVariant;

  /// The primitive this binding currently targets, or null when the mesh no
  /// longer has one at [primitiveIndex].
  MeshPrimitive? resolvePrimitive() {
    final primitives = node.mesh?.primitives;
    if (primitives == null ||
        primitiveIndex < 0 ||
        primitiveIndex >= primitives.length) {
      return null;
    }
    return primitives[primitiveIndex];
  }
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
/// final variants = MaterialsVariantsComponent.of(model);
/// variants?.select('beach');
/// ```
/// {@category Materials}
class MaterialsVariantsComponent extends Component {
  // Carried by both import paths: the runtime importer attaches it directly,
  // and the .fscene document serializes it as a materialsVariants component.
  // Clones get variant switching back through [rebindClone]; the component
  // cannot use [Component.cloneFor] because its bindings reference other
  // nodes, which only the caller holding both roots can remap.

  /// Used by the importer; not for application construction.
  @internal
  MaterialsVariantsComponent.internal(
    List<String> variants,
    List<MaterialsVariantBinding> bindings,
  ) : variants = List.unmodifiable(variants),
      _bindings = bindings;

  /// Finds the first variants component for a loaded model.
  ///
  /// The runtime importer attaches one component to the model's root; the
  /// `.fscene` realizer attaches one per document root (below the
  /// synthesized scene root). This searches [root] and then its subtree
  /// breadth-first, so callers work with either import path. A multi-root
  /// document can carry several components; use [allOf] to reach every one.
  static MaterialsVariantsComponent? of(Node root) {
    final all = allOf(root);
    return all.isEmpty ? null : all.first;
  }

  /// Every variants component on [root] and its subtree, in breadth-first
  /// order. Select on each to switch a multi-root model completely.
  static List<MaterialsVariantsComponent> allOf(Node root) {
    final found = <MaterialsVariantsComponent>[
      ...root.getComponents<MaterialsVariantsComponent>(),
    ];
    final queue = <Node>[...root.children];
    for (var i = 0; i < queue.length; i++) {
      found.addAll(queue[i].getComponents<MaterialsVariantsComponent>());
      queue.addAll(queue[i].children);
    }
    return found;
  }

  /// The variant names declared by the source, in declaration order.
  final List<String> variants;

  final List<MaterialsVariantBinding> _bindings;

  /// The per-primitive bindings, for the fscene codec.
  @internal
  List<MaterialsVariantBinding> get internalBindings => _bindings;

  String? _selected;

  /// The currently selected variant name, or null when the defaults are
  /// active.
  String? get selected => _selected;

  /// Applies the named variant to every mapped primitive.
  ///
  /// Pass null to restore the default materials. Throws [ArgumentError] when
  /// [name] is not one of [variants]. Primitives the variant does not map
  /// keep their default material. Re-selecting the current variant is free.
  void select(String? name) {
    if (name != null && !variants.contains(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'Unknown variant; declared variants are $variants',
      );
    }
    if (name == _selected) return;
    _selected = name;
    _apply();
  }

  /// Re-applies the current selection to the bindings, for callers that
  /// changed the binding list or the bound meshes after selection.
  @internal
  void reapply() => _apply();

  void _apply() {
    final index = _selected == null ? -1 : variants.indexOf(_selected!);
    for (final binding in _bindings) {
      final primitive = binding.resolvePrimitive();
      if (primitive == null) continue;
      primitive.material =
          binding.materialsByVariant[index] ?? binding.defaultMaterial;
    }
    _refreshRenderItems();
  }

  /// Rebuilds this component for a [Node.clone] of the tree it was built
  /// against, rebinding every binding to the clone's corresponding node, and
  /// attaches the result to [cloneRoot].
  ///
  /// Bindings whose node cannot be resolved in the clone are dropped.
  /// Returns null (attaching nothing) when [templateRoot] has no variants
  /// component. A template with several components (multi-root documents)
  /// has each rebound onto [cloneRoot].
  @internal
  static MaterialsVariantsComponent? rebindClone(
    Node templateRoot,
    Node cloneRoot,
  ) {
    MaterialsVariantsComponent? first;
    for (final source in allOf(templateRoot)) {
      final bindings = <MaterialsVariantBinding>[];
      for (final binding in source._bindings) {
        final path = Node.getIndexPath(templateRoot, binding.node);
        final cloneNode = path == null
            ? null
            : cloneRoot.getChildByIndexPath(path);
        if (cloneNode == null) continue;
        // Mesh.clone preserves primitive order, so the index carries over.
        bindings.add(
          MaterialsVariantBinding(
            node: cloneNode,
            primitiveIndex: binding.primitiveIndex,
            defaultMaterial: binding.defaultMaterial,
            materialsByVariant: binding.materialsByVariant,
          ),
        );
      }
      final clone = MaterialsVariantsComponent.internal(
        source.variants,
        bindings,
      );
      cloneRoot.addComponent(clone);
      first ??= clone;
    }
    return first;
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
