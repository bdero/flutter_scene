# scene

The engine-agnostic scene document core, extracted from [flutter_scene](https://pub.dev/packages/flutter_scene).

A `.fscene` scene is a document, a tree of node specs with stable ids, typed component properties, resources, and payloads. This package holds that document model and everything that operates on it without touching a renderer, parsing and writing the JSON (`.fscene`) and binary (`.fsceneb`) forms, coordinator-free id allocation, prefab composition with overrides, and structural diffing by stable id.

Pure Dart, no Flutter dependency. `flutter_scene` builds its renderer on this package and re-exports it; editors, asset pipelines, and servers can depend on it directly and run under `dart run`.

```dart
import 'package:scene/scene.dart';

final document = SceneDocument();
final id = document.allocator.mint();
// ... build specs, then:
final text = writeFscene(document);
final reread = readFscene(text);
```

Realization (turning a document into live renderable nodes) lives in `flutter_scene`; this package deliberately stops at the document boundary.
