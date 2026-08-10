# Changelog

## 0.2.0

- `.fscene` version 2 fixes every document to the native coordinate system and migrates left-handed version 1 documents.
- Removed `Handedness`, `UpAxis`, `StageMetadata.unitsPerMeter`, `NodeSpec.excludeFromWindingParity`, and `SkyEnvironmentSpec.castShadows`.
- Documents must declare their `.fscene` version.
- `SunLightSpec` stores sky-driven analytic sun and cascaded-shadow settings.
- `payloadSource` links a text manifest to a binary payload sidecar.

## 0.1.1

- `PhysicsSimulation.snapshot`/`restore` (opt-in via `supportsSnapshot`), world serialization for rollback prediction and lag-compensation rewind.
- `PhysicsSimulation.setBodyPose`, immediate body teleport for rollback correction (default throws on backends without it).
- `TextureResource` carries a `content` role (`color`, `data`, `normal`) describing what its pixels represent.

## 0.1.0

- Initial release, extracted from `flutter_scene`. The `.fscene` document model (`SceneDocument`, node/resource/payload specs), stable ids (`DocumentId`, `LocalId`, `IdAllocator`), JSON and binary serialization (`.fscene`/`.fsceneb`), prefab composition, and structural diffing, as a pure Dart package.
