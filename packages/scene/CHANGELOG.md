# Changelog

## 0.4.0

- `NodeSpec.shadowCastingMode` carries a node's shadow casting mode (`off`, `on`, `doubleSided`, `shadowsOnly`), delta-serialized and overridable on prefab instances through the `shadowCasting` path.
- `EnvironmentEffectsSpec` carries SMAA quality (`smaaThreshold`, `smaaMaxSearchSteps`, `smaaMaxDiagonalSearchSteps`, `smaaCornerRounding`), delta-serialized like the other effects.
- The spec's temporal anti-aliasing defaults now match the renderer's.

- Added grid mesh splitting shared by editors and import pipelines: `splitTriangleMeshByGrid` bins whole triangles by world-space centroid into per-cell vertex/index buffers, and `applyMeshSplitHints` applies `-split<N>` node-name hints across a document (split children named `Ground_x0_z3`, hint stripped, orphaned source data removed).
- Added `documentWorldMatrix`, `countResourceReferences`, and `isPayloadReferenced` document utilities.

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
