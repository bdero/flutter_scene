# Changelog

## 0.5.0

- `.fscene` format version 6 stores right-handed coordinates (`-Z` forward). Versions 2 through 5 migrate on read: node transforms, bounds, light, joint, particle, physics, and character-controller vectors, prefab overrides of those properties, and the editor camera azimuth reflect across Z.
- `GeometryResource`, `SkinSpec`, `AnimationSpec`, and convex-hull and triangle-mesh collider shapes carry `legacyLeftHanded` after migration so the realizer reflects their payloads.
- `EnvironmentResource.environmentMirrorZ` mirrors the environment across the XY plane before `environmentRotationY`. Migrated documents set it so image and procedural skies keep their place relative to the reflected content.
- `currentFsceneVersion` is 6; older readers refuse format 6 documents.

## 0.4.1

- `TriMeshShape` documents that a triangle collides from its front (counter-clockwise) face only.

## 0.4.0

- `GizmoOrthographicVolume` draws an orthographic camera's view volume, sized by a bound fit mode, extents, zoom, and offset.
- `NodeSpec.shadowCastingMode` carries a node's shadow casting mode (`off`, `on`, `doubleSided`, `shadowsOnly`), delta-serialized and overridable on prefab instances through the `shadowCasting` path.
- `EnvironmentEffectsSpec` carries SMAA quality (`smaaThreshold`, `smaaMaxSearchSteps`, `smaaMaxDiagonalSearchSteps`, `smaaCornerRounding`), delta-serialized like the other effects.
- The spec's temporal anti-aliasing defaults now match the renderer's.
- `SceneDocument.editor` (`EditorStateSpec`, `EditorCameraSpec`) carries the editor camera pose and selection.
- Added grid mesh splitting shared by editors and import pipelines: `splitTriangleMeshByGrid` bins whole triangles by world-space centroid into per-cell vertex/index buffers, and `applyMeshSplitHints` applies `-split<N>` node-name hints across a document (split children named `Ground_x0_z3`, hint stripped, orphaned source data removed).
- Added `documentWorldMatrix`, `countResourceReferences`, and `isPayloadReferenced` document utilities.
- Documents keep data this build does not read through a load and save. Unknown keys ride on the document, its specs, and their nested value objects (`unknown`), unknown `.fsceneb` chunks on `SceneDocument.unknownChunks` (`UnknownChunk`), and a property value with an unknown tag loads as an inert `UnknownValue` instead of failing the document.
- Added `encodeNode`, which encodes one node the way `encodeDocument` does.

## 0.3.0

- Standardized model-space front-face winding to Counter-Clockwise (CCW) in `.fscene` format version 5; version 4 documents migrate by swapping index pairs during realization.
- `.fsceneb` format version 2 compresses payload chunks with gzip; older readers reject version 2.
- `MorphTargetsSpec` and `GeometryResource.morphTargets` carry baked morph target deltas, names, and default weights.
- `AnimationProperty.weights` animates morph weights.
- `.fscene` version 4; a version-3 reader refuses a morph-bearing document instead of silently dropping the deltas. Version 3 documents read as-is.
- `EnvironmentEffectsSpec` carries global illumination and temporal anti-aliasing settings, delta-serialized through `.fscene` and `.fsceneb`.

## 0.2.0

- `package:scene/schema.dart`, the portable component schema model (`ComponentSchema`, `ComponentPropertyDef`, the tagged constraint taxonomy, `formerNames`/`formerTypes`).
- Component schemas carry declarative editor gizmos (`ComponentSchema.gizmo`, the `GizmoSpec` primitive model with property-bound scalars, colors, and axes).
- `.fscene` version 3, component properties delta-serialize and audio attenuation settings nest; version 2 documents migrate as-is.
- Sun lights carry `contactShadows`, `contactShadowDistance`, and `angularRadius`.
- Environment effects carry `colorGradingLut` (a `.cube` asset reference) and `colorGradingLutBlend`.
- Ambient-occlusion effects carry `indirectLight`, `method`, `sliceCount`, `stepsPerSlice`, `visibilityBitmask`, `thickness`, `thicknessHeuristic`, `bentNormals`, and `multiBounce`.
- Retuned effect defaults, ambient-occlusion intensity `1.0`, bloom intensity `0.15`, chromatic aberration `0.2`, auto-exposure clamps `-4`/`4` EV.
- `.fscene` version 2 fixes every document to the native coordinate system and migrates left-handed version 1 documents.
- Removed `Handedness`, `UpAxis`, `StageMetadata.unitsPerMeter`, `NodeSpec.excludeFromWindingParity`, and `SkyEnvironmentSpec.castShadows`.
- Documents must declare their `.fscene` version.
- `SunLightSpec` stores sky-driven analytic sun and cascaded-shadow settings.
- `payloadSource` links a text manifest to a binary payload sidecar.
- `TorusGeometrySpec` and `IcosphereGeometrySpec` procedural geometry, a torus around the Y axis and a geodesic sphere from a subdivided icosahedron.
- Prefab instances add components to individual member nodes (`MemberComponent`, `PrefabInstanceSpec.memberComponents`), and `PrefabOverrideAspect` addresses one aspect of an override without re-parsing paths.
- `ConstantEnvironment`, a reflection-free environment with uniform diffuse ambient radiance.
- `EnvironmentResource` carries `agxWhite`, `agxContrast`, `environmentRotationY`, and `overridesEffects`.
- `encodeComponentSchemas`/`decodeComponentSchemas` move a schema list through a manifest or cache payload, and `propertyValuesEqual` compares property values structurally.
- `copyWith` on `MaterialResource` and `PrefabInstanceSpec`.

## 0.1.1

- `PhysicsSimulation.snapshot`/`restore` (opt-in via `supportsSnapshot`), world serialization for rollback prediction and lag-compensation rewind.
- `PhysicsSimulation.setBodyPose`, immediate body teleport for rollback correction (default throws on backends without it).
- `TextureResource` carries a `content` role (`color`, `data`, `normal`) describing what its pixels represent.

## 0.1.0

- Initial release, extracted from `flutter_scene`. The `.fscene` document model (`SceneDocument`, node/resource/payload specs), stable ids (`DocumentId`, `LocalId`, `IdAllocator`), JSON and binary serialization (`.fscene`/`.fsceneb`), prefab composition, and structural diffing, as a pure Dart package.
