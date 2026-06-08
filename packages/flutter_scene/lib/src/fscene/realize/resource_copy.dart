/// Copies a resource (and the payload chunks it references) from one document
/// into another, preserving ids. Used by the scene serializer to rebuild a
/// document's resource pool from the resources a live graph was realized from.
///
/// This layer is GPU-free: it moves [ResourceSpec]s and [PayloadSpec]s (bytes
/// included), not live GPU objects.
library;

import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/json/fscene_json.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';

/// Copies resource [resourceId] from [source] into [dest], keeping its id, and
/// returns that id. Idempotent: a resource (or payload) already present in
/// [dest] is left as is, so a resource shared by several meshes copies once.
///
/// Referenced payload chunks are copied with their bytes, and a material's
/// referenced texture resources are copied recursively.
LocalId copyResourceInto(
  SceneDocument dest,
  SceneDocument source,
  LocalId resourceId,
) {
  if (dest.resource(resourceId) != null) return resourceId;
  final res = source.resource(resourceId);
  if (res == null) {
    throw FsceneFormatException('Source has no resource $resourceId to copy');
  }
  switch (res) {
    case GeometryResource(
      :final vertices,
      :final indices,
      :final procedural,
      :final bounds,
    ):
      if (vertices != null) _copyPayload(dest, source, vertices);
      if (indices != null) _copyPayload(dest, source, indices);
      dest.addResource(
        GeometryResource(
          resourceId,
          vertices: vertices,
          indices: indices,
          procedural: procedural,
          bounds: bounds,
        ),
      );
    case TextureResource(:final payload, :final asset):
      if (payload != null) _copyPayload(dest, source, payload);
      dest.addResource(
        TextureResource(resourceId, payload: payload, asset: asset),
      );
    case MaterialResource(:final type, :final properties, :final asset):
      for (final value in properties.values) {
        if (value is ResourceRefValue &&
            source.resource(value.id) is TextureResource) {
          copyResourceInto(dest, source, value.id);
        }
      }
      dest.addResource(
        MaterialResource(
          resourceId,
          type: type,
          properties: Map<String, PropertyValue>.of(properties),
          asset: asset,
        ),
      );
  }
  return resourceId;
}

void _copyPayload(SceneDocument dest, SceneDocument source, LocalId id) {
  if (dest.payload(id) != null) return;
  final p = source.payload(id);
  if (p == null) {
    throw FsceneFormatException('Source has no payload $id to copy');
  }
  dest.addPayload(
    PayloadSpec(
      id,
      encoding: p.encoding,
      layout: p.layout,
      format: p.format,
      width: p.width,
      height: p.height,
      length: p.length,
      bytes: p.bytes,
    ),
  );
}
