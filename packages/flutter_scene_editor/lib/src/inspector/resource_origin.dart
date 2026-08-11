/// Shared "where does this resource live" vocabulary for the inspector and the
/// asset browser: a resource is either built into the `.fscene` document
/// (procedural geometry, parameter materials, embedded payloads) or an external
/// file on disk (anything referenced through an [AssetRef]). The [OriginBadge]
/// renders this consistently everywhere a resource reference is shown.
library;

import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:scene/scene.dart';

/// Whether a referenced resource is embedded in the document or a file on disk.
enum ResourceLocality {
  /// Stored inside the `.fscene` document (payload, procedural, or parameters).
  builtIn,

  /// An external file on the filesystem, referenced by path.
  external,
}

/// The locality of a material: `fmat` materials reference an external `.fmat`
/// source; parameter materials (physicallyBased, unlit) are built in.
ResourceLocality materialLocality(MaterialResource material) =>
    material.asset != null
    ? ResourceLocality.external
    : ResourceLocality.builtIn;

/// The locality of a texture: an [AssetRef] source is external; an embedded
/// payload chunk is built in.
ResourceLocality textureLocality(TextureResource texture) =>
    texture.asset != null
    ? ResourceLocality.external
    : ResourceLocality.builtIn;

/// The locality of any pool resource, plus the external path when it has one.
/// A resource's record always lives in the document; "external" means its
/// content comes from a file on disk (an `.fmat` source, an image asset, an
/// environment image).
(ResourceLocality, String?) resourceOriginOf(ResourceSpec spec) =>
    switch (spec) {
      MaterialResource() => (materialLocality(spec), spec.asset?.key),
      TextureResource() => (textureLocality(spec), spec.asset?.key),
      EnvironmentResource(:final environment) =>
        environment is AssetEnvironment
            ? (ResourceLocality.external, environment.asset.key)
            : (ResourceLocality.builtIn, null),
      _ => (ResourceLocality.builtIn, null),
    };

/// A compact pill marking a resource reference as built into the document or an
/// external file. External badges carry the file path in a tooltip so it is
/// always clear what is being referenced from where.
class OriginBadge extends StatelessWidget {
  const OriginBadge({
    super.key,
    required this.locality,
    this.path,
    this.dense = false,
  });

  final ResourceLocality locality;

  /// The external file path, shown in a tooltip. Ignored for built-in.
  final String? path;

  /// A tighter variant (icon + no label) for dense rows.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final external = locality == ResourceLocality.external;
    final bg = external
        ? scheme.tertiaryContainer
        : scheme.surfaceContainerHighest;
    final fg = external ? scheme.onTertiaryContainer : scheme.onSurfaceVariant;
    final icon = external ? Icons.folder_open_outlined : Icons.widgets_outlined;
    final label = external ? 'External' : 'Built-in';
    final pill = DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: dense ? 4 : 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: fg),
            if (!dense) ...[
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    final message = external
        ? (path == null ? 'External file' : 'External file\n$path')
        : 'Built into the scene document';
    return Tooltip(
      message: message,
      waitDuration: const Duration(milliseconds: 400),
      child: pill,
    );
  }
}
