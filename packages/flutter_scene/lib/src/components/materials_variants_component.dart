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
  // Carried by both import paths: the runtime importer attaches it directly,
  // and the .fscene document serializes it as a materialsVariants component.
  // Clones get variant switching back through [rebindClone] (Node.clone
  // itself does not carry components).

  /// Used by the importer; not for application construction.
  @internal
  MaterialsVariantsComponent.internal(
    List<String> variants,
    List<MaterialsVariantBinding> bindings,
  ) : variants = List.unmodifiable(variants),
      _bindings = bindings;

  /// Finds the variants component for a loaded model.
  ///
  /// The runtime importer attaches the component to the model's root; the
  /// `.fscene` realizer attaches it to the document root node it was
  /// serialized on, which sits below the synthesized scene root. This
  /// searches [root] and then its subtree (breadth-first), so callers work
  /// with either import path.
  static MaterialsVariantsComponent? of(Node root) {
    final direct = root.getComponent<MaterialsVariantsComponent>();
    if (direct != null) return direct;
    final queue = <Node>[...root.children];
    for (var i = 0; i < queue.length; i++) {
      final component = queue[i].getComponent<MaterialsVariantsComponent>();
      if (component != null) return component;
      queue.addAll(queue[i].children);
    }
    return null;
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

  /// Rebuilds this component for a [Node.clone] of the tree it was built
  /// against, rebinding every binding to the clone's corresponding node and
  /// primitive, and attaches the result to [cloneRoot].
  ///
  /// [Node.clone] does not carry components, so cloned models would lose
  /// variant switching without this. Bindings whose node or primitive cannot
  /// be resolved in the clone are dropped. Returns null (attaching nothing)
  /// when [templateRoot] has no variants component.
  @internal
  static MaterialsVariantsComponent? rebindClone(
    Node templateRoot,
    Node cloneRoot,
  ) {
    final source = MaterialsVariantsComponent.of(templateRoot);
    if (source == null) return null;
    final bindings = <MaterialsVariantBinding>[];
    for (final binding in source._bindings) {
      final path = Node.getIndexPath(templateRoot, binding.node);
      final cloneNode = path == null
          ? null
          : cloneRoot.getChildByIndexPath(path);
      final templateMesh = binding.node.mesh;
      final cloneMesh = cloneNode?.mesh;
      if (cloneNode == null || templateMesh == null || cloneMesh == null) {
        continue;
      }
      // Mesh.clone preserves primitive order, so positions correspond.
      final index = templateMesh.primitives.indexOf(binding.primitive);
      if (index < 0 || index >= cloneMesh.primitives.length) continue;
      bindings.add(
        MaterialsVariantBinding(
          node: cloneNode,
          primitive: cloneMesh.primitives[index],
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
    return clone;
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
