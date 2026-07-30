# Changelog

## Unreleased

- `PhysicsSimulation.snapshot`/`restore` (opt-in via `supportsSnapshot`), world serialization for rollback prediction and lag-compensation rewind.
- `PhysicsSimulation.setBodyPose`, immediate body teleport for rollback correction (default throws on backends without it).

## 0.1.0

- Initial release, extracted from `flutter_scene`. The `.fscene` document model (`SceneDocument`, node/resource/payload specs), stable ids (`DocumentId`, `LocalId`, `IdAllocator`), JSON and binary serialization (`.fscene`/`.fsceneb`), prefab composition, and structural diffing, as a pure Dart package.
