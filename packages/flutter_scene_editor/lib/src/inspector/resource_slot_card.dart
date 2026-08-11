/// The shared "resource slot" card: a preview, the referenced resource's name,
/// an [OriginBadge] plus a kind label, and Replace/Remove actions. Every place
/// that binds a resource to a slot (environment image, material, texture) uses
/// this so the editor reads consistently. Mirrors the environment settings
/// layout that this pattern grew out of.
library;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'resource_origin.dart';

class ResourceSlotCard extends StatelessWidget {
  const ResourceSlotCard({
    super.key,
    required this.title,
    required this.kind,
    required this.locality,
    this.path,
    this.reference,
    this.preview,
    this.previewIcon = Icons.image_outlined,
    this.missing = false,
    this.missingLabel,
    this.onReplace,
    this.onRemove,
    this.removeTooltip = 'Remove',
    this.aspectRatio = 3.2,
  });

  /// The referenced resource's display name (a file name, or a resource name).
  final String title;

  /// A short kind label shown next to the origin badge (for example
  /// "Physically based", "PNG image", "Radiance HDR environment").
  final String kind;

  final ResourceLocality locality;

  /// The external file path, for the origin badge tooltip.
  final String? path;

  /// Full reference text for the card tooltip. Defaults to [path] or [title].
  final String? reference;

  final Widget? preview;

  /// Icon shown when there is no preview (or the source is missing).
  final IconData previewIcon;

  final bool missing;

  /// Subtitle shown in place of the kind label when [missing].
  final String? missingLabel;

  /// Tapping the card or the Replace button. Null hides the Replace action and
  /// makes the card non-interactive.
  final VoidCallback? onReplace;

  /// The clear/remove action. Null hides the Remove button (a required slot).
  final VoidCallback? onRemove;

  final String removeTooltip;

  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final editable = onReplace != null;
    return Tooltip(
      message: reference ?? path ?? title,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onReplace,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border.all(
              color: missing ? scheme.error : scheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: aspectRatio,
                child: ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: missing || preview == null
                      ? Center(
                          child: Icon(
                            missing ? Icons.broken_image_outlined : previewIcon,
                            size: 24,
                            color: missing
                                ? scheme.error
                                : scheme.onSurfaceVariant,
                          ),
                        )
                      : preview!,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              OriginBadge(locality: locality, path: path),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  missing
                                      ? (missingLabel ?? 'Source unavailable')
                                      : kind,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: missing
                                        ? scheme.error
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (editable) ...[
                      const SizedBox(width: 4),
                      FButton(
                        variant: .ghost,
                        size: .xs,
                        mainAxisSize: .min,
                        onPress: onReplace,
                        child: const Text('Replace'),
                      ),
                    ],
                    if (onRemove != null)
                      Tooltip(
                        message: removeTooltip,
                        child: FButton.icon(
                          variant: .ghost,
                          size: .xs,
                          onPress: onRemove,
                          child: const Icon(Icons.close, size: 14),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
