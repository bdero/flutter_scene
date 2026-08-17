/// Curated public GPU surface for the custom-shader ([ShaderMaterial])
/// workflow.
///
/// flutter_scene ships an internal `flutter_gpu` shim (a WebGL2 backend on
/// web; a zero-cost re-export of `package:flutter_gpu` on native). Most of it
/// is implementation detail. This library exposes only the handful of types a
/// caller needs to author a custom material: load a compiled shader bundle and
/// hand its fragment shader to a [ShaderMaterial].
///
/// ```dart
/// import 'package:flutter_scene/gpu.dart' as gpu;
///
/// final library = await gpu.loadShaderLibraryAsync(
///   await gpu.resolveShaderBundleKey('my'),
/// );
/// final material = ShaderMaterial(fragmentShader: library!['MyFragment']!);
/// ```
library;

export 'src/generated_assets/generated_asset_lookup.dart'
    show resolveShaderBundleKey;

export 'src/gpu/gpu.dart'
    show
        Shader,
        ShaderLibrary,
        loadShaderLibraryAsync,
        Texture,
        SamplerOptions,
        MinMagFilter,
        MipFilter,
        SamplerAddressMode,
        // Value types a caller-declared vertex layout and index buffer need.
        IndexType,
        VertexFormat,
        VertexStepMode;
