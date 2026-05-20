# flutter_gpu_shim

Web fallback for Flutter GPU.

On platforms where Impeller (and therefore Flutter GPU) is available, this
package re-exports `package:flutter_gpu`. On web, it provides a WebGL2-backed
implementation behind the same public API.

## Status

Day-zero scaffold. The only thing implemented is a `Surface` class on web,
which exists to answer one load-bearing question: can a WebGL2-rendered
texture be presented inside a Flutter widget on CanvasKit and Skwasm
without a CPU round-trip?

See `examples/flutter_gpu_shim_smoke` for the smoke test.

## Usage

```dart
import 'package:flutter_gpu_shim/gpu.dart';
```
