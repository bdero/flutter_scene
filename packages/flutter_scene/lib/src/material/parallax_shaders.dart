import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show
        ErrorDescription,
        FlutterError,
        FlutterErrorDetails,
        debugPrint,
        internal,
        visibleForTesting;
import 'package:flutter/services.dart' show AssetBundle;

import '../generated_assets/generated_asset_lookup.dart';
import '../generated_assets/generated_assets.dart';
import '../generated_assets/material_features.dart';
import '../gpu/gpu.dart' as gpu;
import '../render/frame_transients.dart';
import '../render/uniform_slots.dart';
import '../shaders.dart';
import 'parallax_silhouette.dart';
import 'shader_interface.dart' show markEngineShaderLibrary;

/// Whether [name] is an entry of the parallax bundle rather than the base one.
@internal
bool isParallaxEntryName(String name) =>
    name.startsWith('StandardParallax') || name.startsWith('Parallax');

/// A parallax-bundle entry every build contains, used to tell a bundle this
/// engine can read from one it cannot.
@visibleForTesting
const String parallaxBundleProbeName = 'StandardParallaxFragment';

Future<gpu.ShaderLibrary?>? _parallaxLoad;
gpu.ShaderLibrary? _parallaxLibrary;

// Set when a load a material asked for fails, so the materials that keep
// asking every frame do not reload and re-report it.
bool _parallaxLoadFailed = false;

/// Whether the build left [feature] out (the `material_features` hook
/// user-define), read from the base bundle's marker entries. False until the
/// base bundle loads.
@internal
bool materialFeatureCompiledOut(MaterialFeature feature) =>
    loadedBaseShaderLibrary?[feature.markerEntryName] != null;

/// The parallax shader bundle's key in the generated tree, or null when
/// nothing built it.
@visibleForTesting
Future<String?> resolveParallaxShaderBundleKey({AssetBundle? bundle}) async =>
    (await loadGeneratedAssetIndex(bundle)).resolveFirstKey(
      GeneratedAssetFamily.shaderBundle,
      'parallax',
      package: 'flutter_scene',
    );

// Completes with null when the build left parallax out.
Future<gpu.ShaderLibrary?> _loadParallaxShaderLibrary() =>
    _parallaxLoad ??= () async {
      try {
        // The base bundle's markers say whether the build left it out.
        await loadBaseShaderLibrary();
        if (materialFeatureCompiledOut(MaterialFeature.parallaxOcclusion)) {
          throw const _NotBuilt();
        }
        final key = await resolveParallaxShaderBundleKey();
        if (key == null) {
          throw StateError(
            'The parallax occlusion shaders are missing. flutter_scene\'s '
            'build hook compiles them unless material_features sets '
            'parallax_occlusion to false; rebuild the app.',
          );
        }
        final library = await gpu.loadShaderLibraryAsync(key);
        if (library == null || library[parallaxBundleProbeName] == null) {
          throw StateError(
            'Could not load the parallax shader bundle "$key". It is '
            'compiled for the engine and target that built the app, so '
            'rebuild after changing Flutter versions or platforms.',
          );
        }
        markEngineShaderLibrary(library);
        return _parallaxLibrary = library;
      } on _NotBuilt {
        _parallaxLoadSettled = true;
        return null;
      } catch (_) {
        _parallaxLoad = null;
        rethrow;
      }
    }();

/// The parallax shader library once loaded, else null.
@internal
gpu.ShaderLibrary? get loadedParallaxShaderLibrary => _parallaxLibrary;

/// Loads the parallax shaders, for `Scene.preload`. Retries after a failure
/// and throws it. Does nothing when the build left parallax out.
@internal
Future<void> initializeParallaxShaderLibrary() async {
  if (materialFeatureCompiledOut(MaterialFeature.parallaxOcclusion)) return;
  _parallaxLoadFailed = false;
  await _loadParallaxShaderLibrary();
}

/// Starts the parallax bundle loading without awaiting it, for a material
/// that has just started needing it. A failure is reported once and not
/// retried from here; the materials then draw without parallax.
@internal
void requestParallaxShaderLibrary() {
  if (_parallaxLibrary != null ||
      _parallaxLoad != null ||
      _parallaxLoadFailed) {
    return;
  }
  _loadParallaxShaderLibrary().then<void>(
    (_) {},
    onError: (Object error, StackTrace stack) {
      _parallaxLoadFailed = true;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'flutter_scene',
          context: ErrorDescription(
            'while loading the parallax occlusion shaders. Materials that '
            'need them draw without parallax',
          ),
        ),
      );
    },
  );
}

/// Loads the parallax bundle again if a load failed, for a view retrying.
@internal
void retryFailedParallaxShaderLibrary() {
  if (!_parallaxLoadFailed) return;
  _parallaxLoadFailed = false;
  requestParallaxShaderLibrary();
}

/// Whether the parallax bundle is loading and has not arrived yet.
@internal
bool get parallaxShaderLibraryPending =>
    _parallaxLoad != null && _parallaxLibrary == null && !_parallaxLoadSettled;

// Set once a load completes without a library (the build left it out).
bool _parallaxLoadSettled = false;

/// Whether a material that needs parallax can draw with it now.
@internal
bool get parallaxShaderLibraryReady =>
    debugParallaxShaderLibraryReadyOverride ?? _parallaxLibrary != null;

/// Overrides [parallaxShaderLibraryReady] for tests with no GPU.
@visibleForTesting
bool? debugParallaxShaderLibraryReadyOverride;

/// Completes when an in-flight parallax load settles, successfully or not, or
/// null when none is in flight. Never completes with an error.
@internal
Future<void>? get parallaxShaderLibraryLoad {
  if (!parallaxShaderLibraryPending) return null;
  final load = _parallaxLoad!;
  if (!identical(load, _settledSource)) {
    _settledSource = load;
    _settled = load.then<void>((_) {}, onError: (Object _) {});
  }
  return _settled;
}

Future<gpu.ShaderLibrary?>? _settledSource;
Future<void>? _settled;

/// Forgets the loaded bundle and any recorded failure, for tests.
@visibleForTesting
void resetParallaxShaderLibraryForTesting() {
  debugParallaxShaderLibraryReadyOverride = null;
  _parallaxLoad = null;
  _parallaxLibrary = null;
  _parallaxLoadFailed = false;
  _parallaxLoadSettled = false;
  _warnedCompiledOut.clear();
}

final class _NotBuilt {
  const _NotBuilt();
}

final Set<MaterialFeature> _warnedCompiledOut = {};

/// Prints, once per feature, that a material asked for [feature] in a build
/// that left it out.
@internal
void warnMaterialFeatureCompiledOut(MaterialFeature feature) {
  if (!_warnedCompiledOut.add(feature)) return;
  debugPrint(
    'flutter_scene: a material uses ${feature.key}, but this build left it '
    'out (material_features: ${feature.key}: false), so it draws without it.',
  );
}

final Float32List _parallaxInfoScratch = Float32List(8);
final ByteData _parallaxInfoBytes = ByteData.sublistView(_parallaxInfoScratch);

/// Packs and binds the `ParallaxInfo` block (see `shaders/parallax.glsl`) on
/// [shader], when it declares one.
@internal
void bindParallaxInfo(
  gpu.RenderPass pass,
  gpu.Shader shader,
  TransientWriter transientsBuffer, {
  required double scale,
  required int maxSteps,
  required double shadowStrength,
  required ParallaxSilhouette? silhouette,
}) {
  final slot = shader.cachedUniformSlot('ParallaxInfo');
  if (slot.sizeInBytes == null) return;
  final info = _parallaxInfoScratch
    ..[0] = scale
    ..[1] = maxSteps.toDouble()
    ..[2] = shadowStrength
    ..[3] = (silhouette?.shaderMode ?? 0).toDouble();
  final lo = silhouette?.min;
  final hi = silhouette?.max;
  info
    ..[4] = lo?.x ?? 0.0
    ..[5] = lo?.y ?? 0.0
    ..[6] = hi?.x ?? 0.0
    ..[7] = hi?.y ?? 0.0;
  pass.bindUniform(slot, transientsBuffer.emplace(_parallaxInfoBytes));
}
