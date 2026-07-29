# Changelog

## Unreleased

- `PhysicsSimulation.snapshot`/`restore` (opt-in via `supportsSnapshot`), world serialization for rollback prediction and lag-compensation rewind.

## 0.1.1

- `TextureResource` carries a `content` role (`color`, `data`, `normal`) describing what its pixels represent.

## 0.1.0

- Initial release, extracted from `flutter_scene`. The `.fscene` document model (`SceneDocument`, node/resource/payload specs), stable ids (`DocumentId`, `LocalId`, `IdAllocator`), JSON and binary serialization (`.fscene`/`.fsceneb`), prefab composition, and structural diffing, as a pure Dart package.
