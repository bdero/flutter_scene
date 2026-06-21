/// Realizes a document's stage render settings onto a live [Scene], and
/// serializes them back.
///
/// The stage carries the scene-wide, non-spatial settings: the image-based
/// lighting environment, environment intensity, exposure, tone mapping, the
/// skybox, and sky-driven lighting. `realizeScene` builds only the node
/// graph; apply the stage to the scene that hosts it with [realizeStage]
/// (`loadScene` does this when given a scene). [serializeStage] reads a
/// scene's settings back into a document, the editor-save direction.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle;

import 'package:flutter_scene/src/asset_helpers.dart';
import 'package:flutter_scene/src/fmat/material_registry.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/json/canonical.dart';
import 'package:flutter_scene/src/fscene/json/fscene_json.dart'
    show encodeSkySource;
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/realize/fmat_overrides.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/environment_settings.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/hdr_decoder.dart';
import 'package:flutter_scene/src/material/preprocessed_sky.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_scene/src/sky_environment.dart';
import 'package:flutter_scene/src/sky_sources.dart';
import 'package:flutter_scene/src/skybox.dart';
import 'package:flutter_scene/src/sun_light.dart';
import 'package:flutter_scene/src/tone_mapping.dart';

/// Builds the [EnvironmentMap] for an [AssetEnvironment] from outside the asset
/// bundle (the editor loads a user-picked file from disk and prefilters it).
/// Returns null to fall back to the asset bundle. Honors the current
/// [EnvironmentMap.radianceCubeSize], set around the build by the realizer.
typedef EnvironmentAssetLoader =
    Future<EnvironmentMap?> Function(AssetRef asset);

/// Resolves a [PayloadEnvironment]'s embedded image chunk to its descriptor (the
/// bytes plus `format`), so a self-contained build (which inlines an environment
/// image into a payload) realizes without an asset-bundle lookup. The realizer
/// passes the document's payload table.
typedef EnvironmentPayloadLookup = PayloadSpec? Function(LocalId payload);

/// The working width an inlined equirect environment is capped to on decode; a
/// realtime environment needs no more, and a very large panorama would
/// otherwise upload an enormous radiance source.
const int _maxEnvironmentWidth = 4096;

/// Tags applied environments with the spec they realized from, so
/// [serializeStage] can recover them. (Fmat skies recover through their
/// registry source-path stamp plus their assigned parameter values.)
final Expando<EnvironmentSpec> _environmentSpec = Expando(
  'fscene environment spec',
);

/// Applies [document]'s stage render settings to [scene]: environment,
/// environment intensity, exposure, tone mapping, skybox, and sky lighting.
///
/// When the stage binds sky lighting (`skyEnvironment`), the binding owns
/// `Scene.environment` and the stage's environment is not applied. A skybox
/// and a sky-lighting binding whose sources describe the same sky share one
/// live source, so mutating it (or hot reloading its `.fmat`) updates both.
///
/// GPU-bound and async (an asset environment decodes its image, an fmat sky
/// loads by source path from [bundle], default the root bundle).
///
/// [environmentLoader] builds an [AssetEnvironment]'s map from outside the asset
/// bundle (the editor resolves a user-picked file from disk and builds the
/// prefiltered cube), so a disk environment is owned by the environment's own
/// realization rather than patched in afterwards. It honors the current
/// [EnvironmentMap.radianceCubeSize].
Future<void> realizeStage(
  SceneDocument document,
  Scene scene, {
  AssetBundle? bundle,
  EnvironmentAssetLoader? environmentLoader,
}) async {
  final stage = document.stage;
  // A self-contained build inlines environment images into payload chunks; the
  // realize resolves them from this document's payload table.
  PayloadSpec? payloadLookup(LocalId id) => document.payload(id);
  scene.antiAliasingMode = _byName(
    AntiAliasingMode.values,
    stage.antiAliasingMode,
    AntiAliasingMode.auto,
  );
  scene.renderScale = stage.renderScale;
  scene.filterQuality = _byName(
    ui.FilterQuality.values,
    stage.filterQuality,
    ui.FilterQuality.medium,
  );

  // The stage's global look comes from a referenced environment resource when
  // set; otherwise from the stage's own inline look fields (legacy).
  final envRef = stage.environmentRef;
  final envResource = envRef == null ? null : document.resource(envRef);
  if (envResource is EnvironmentResource) {
    (await realizeEnvironmentSettings(
      environment: envResource.environment,
      environmentIntensity: envResource.environmentIntensity,
      exposure: envResource.exposure,
      toneMapping: envResource.toneMapping,
      radianceCubeSize: envResource.radianceCubeSize,
      skybox: envResource.skybox,
      skyEnvironment: envResource.skyEnvironment,
      bundle: bundle,
      environmentLoader: environmentLoader,
      payloadLookup: payloadLookup,
    )).applyTo(scene);
  } else {
    scene.environmentIntensity = stage.environmentIntensity;
    scene.exposure = stage.exposure;
    scene.toneMapping = _toneMapping(stage.toneMapping);

    // Realize each distinct sky source once so a skybox and sky lighting
    // describing the same sky share one live source.
    final realized = <String, SkySource?>{};
    Future<SkySource?> sourceFor(SkySourceSpec spec) async =>
        realized[canonicalJson(encodeSkySource(spec))] ??=
            await _realizeSkySource(spec, bundle);

    final skyEnvironmentSpec = stage.skyEnvironment;
    if (skyEnvironmentSpec == null) {
      scene.skyEnvironment = null;
      await _withRadianceCubeSize(
        stage.radianceCubeSize,
        () => _applyEnvironment(
          stage.environment,
          scene,
          bundle,
          environmentLoader,
          payloadLookup,
        ),
      );
    } else {
      final source = await sourceFor(skyEnvironmentSpec.source);
      if (source is ShaderSkySource) {
        scene.skyEnvironment = SkyEnvironment(
          source,
          refresh: _refresh(skyEnvironmentSpec.refresh),
          interval: Duration(
            microseconds: (skyEnvironmentSpec.intervalSeconds * 1e6).round(),
          ),
          faceResolution: skyEnvironmentSpec.faceResolution,
          equirectWidth: skyEnvironmentSpec.equirectWidth,
        );
      } else {
        if (source != null) {
          debugPrint(
            'fscene: skyEnvironment needs a shader sky (fmat, gradient, or '
            'physical); skipping the binding',
          );
        }
        scene.skyEnvironment = null;
        await _withRadianceCubeSize(
          stage.radianceCubeSize,
          () => _applyEnvironment(
            stage.environment,
            scene,
            bundle,
            environmentLoader,
            payloadLookup,
          ),
        );
      }
    }

    final skyboxSpec = stage.skybox;
    if (skyboxSpec == null) {
      scene.skybox = null;
    } else {
      final source = await sourceFor(skyboxSpec.source);
      scene.skybox = source == null
          ? null
          : Skybox(source, intensity: skyboxSpec.intensity);
    }

    // Drive a sun light from the sky-lighting source when shadows are enabled
    // and that source has a sun. It shares the bound sky source, so the visible
    // disk, the baked IBL, and the cast shadow all track one sun.
    final boundSkySource = scene.skyEnvironment?.source;
    if (skyEnvironmentSpec?.castShadows == true && boundSkySource is SunSky) {
      scene.sunLight = SunLight(boundSkySource as SunSky);
    } else {
      scene.sunLight = null;
    }
  }

  // Spatial environment-volume components blend over the stage as the global
  // base. Capture the just-applied stage look as that base so the components
  // have something to blend over; the per-frame blend is skipped when no volume
  // component is active, so the live fields are used directly in the common
  // case. The manual `Scene.environmentVolumes` list is code-driven, not carried
  // by the document, so a realize clears it.
  scene.baseEnvironment = EnvironmentSettings.fromScene(scene);
  scene.environmentVolumes.clear();
}

/// Realizes a look (the fields an [EnvironmentResource] or a volume carries)
/// into a runtime [EnvironmentSettings]: the image-based-lighting environment,
/// or a sky-lighting binding (with a sun light when it casts shadows), plus the
/// skybox and the scalar look. A skybox and sky lighting describing the same
/// sky share one live source. GPU-bound and async.
//
// TODO(env-realize-layer): this lives in stage.dart so the resource realizer
// can reuse its private build helpers; a leaf realize/environment file would be
// a cleaner home.
Future<EnvironmentSettings> realizeEnvironmentSettings({
  required EnvironmentSpec environment,
  required double environmentIntensity,
  required double exposure,
  required String toneMapping,
  int? radianceCubeSize,
  SkyboxSpec? skybox,
  SkyEnvironmentSpec? skyEnvironment,
  AssetBundle? bundle,
  EnvironmentAssetLoader? environmentLoader,
  EnvironmentPayloadLookup? payloadLookup,
}) async {
  final settings = EnvironmentSettings(
    environmentIntensity: environmentIntensity,
    exposure: exposure,
    toneMapping: _toneMapping(toneMapping),
  );

  final realized = <String, SkySource?>{};
  Future<SkySource?> sourceFor(SkySourceSpec s) async =>
      realized[canonicalJson(encodeSkySource(s))] ??= await _realizeSkySource(
        s,
        bundle,
      );

  Future<void> applyEnvironment() async {
    await _withRadianceCubeSize(radianceCubeSize, () async {
      settings.environment = await _buildEnvironment(
        environment,
        bundle,
        environmentLoader,
        payloadLookup,
      );
    });
  }

  if (skyEnvironment == null) {
    await applyEnvironment();
  } else {
    final source = await sourceFor(skyEnvironment.source);
    if (source is ShaderSkySource) {
      settings.skyEnvironment = SkyEnvironment(
        source,
        refresh: _refresh(skyEnvironment.refresh),
        interval: Duration(
          microseconds: (skyEnvironment.intervalSeconds * 1e6).round(),
        ),
        faceResolution: skyEnvironment.faceResolution,
        equirectWidth: skyEnvironment.equirectWidth,
      );
      if (skyEnvironment.castShadows && source is SunSky) {
        settings.sunLight = SunLight(source as SunSky);
      }
    } else {
      if (source != null) {
        debugPrint(
          'fscene: a skyEnvironment needs a shader sky (fmat, gradient, or '
          'physical); skipping the binding',
        );
      }
      await applyEnvironment();
    }
  }

  if (skybox != null) {
    final source = await sourceFor(skybox.source);
    settings.skybox = source == null
        ? null
        : Skybox(source, intensity: skybox.intensity);
  }
  return settings;
}

/// Re-applies a resource look onto live [target] settings in place, reusing the
/// live sky bindings and the static environment (so their baked image-based
/// lighting is kept and re-bakes smoothly instead of from zero) when the look's
/// structure is unchanged. Returns true when the look was applied in place, and
/// false when a structural change (a different sky source type or sky-binding
/// configuration, or a different environment kind) means the caller must
/// rebuild the settings from scratch with [realizeEnvironmentSettings].
///
/// A parameter-only edit (a dragged sun direction, a recolored sky, a scalar)
/// keeps the existing [SkyEnvironment] binding and only mutates its source and
/// invalidates it, so the time-sliced re-bake holds the current lighting until
/// the new one publishes. This mirrors what the editor's live preview does
/// during a drag, so committing the edit is then a near no-op.
bool reapplyEnvironmentSettingsInPlace({
  required EnvironmentSettings target,
  required EnvironmentSpec environment,
  required double environmentIntensity,
  required double exposure,
  required String toneMapping,
  SkyboxSpec? skybox,
  SkyEnvironmentSpec? skyEnvironment,
}) {
  if (!_skyEnvironmentReusable(target.skyEnvironment, skyEnvironment)) {
    return false;
  }
  if (!_skyboxReusable(target.skybox, skybox)) return false;
  // The static environment is only live when no sky binding owns it.
  if (skyEnvironment == null &&
      !_environmentReusable(target.environment, environment)) {
    return false;
  }

  target
    ..environmentIntensity = environmentIntensity
    ..exposure = exposure
    ..toneMapping = _toneMapping(toneMapping);

  final liveSkyEnvironment = target.skyEnvironment;
  if (liveSkyEnvironment != null && skyEnvironment != null) {
    _applySkySourceInPlace(liveSkyEnvironment.source, skyEnvironment.source);
    liveSkyEnvironment.invalidate();
    final source = liveSkyEnvironment.source;
    final wantsSun = skyEnvironment.castShadows && source is SunSky;
    final hasSun = identical(target.sunLight?.source, source);
    if (wantsSun && !hasSun) {
      target.sunLight = SunLight(source as SunSky);
    } else if (!wantsSun && target.sunLight != null) {
      target.sunLight = null;
    }
  }

  final liveSkybox = target.skybox;
  if (liveSkybox != null && skybox != null) {
    _applySkySourceInPlace(liveSkybox.source, skybox.source);
    liveSkybox.intensity = skybox.intensity;
  }
  return true;
}

// Whether the [live] sky binding can be reused for [spec] without a rebuild,
// needing the same presence, source type, and bake configuration (the binding
// config is fixed at construction, so a change there needs a fresh binding).
bool _skyEnvironmentReusable(SkyEnvironment? live, SkyEnvironmentSpec? spec) {
  if (live == null || spec == null) return live == null && spec == null;
  if (!_skySourceTypeMatches(live.source, spec.source)) return false;
  return live.refresh == _refresh(spec.refresh) &&
      live.interval.inMicroseconds == (spec.intervalSeconds * 1e6).round() &&
      live.faceResolution == spec.faceResolution &&
      live.equirectWidth == spec.equirectWidth;
}

// Whether the [live] skybox can be reused for [spec], needing the same presence
// and source type. The intensity and source parameters are mutated in place.
bool _skyboxReusable(Skybox? live, SkyboxSpec? spec) {
  if (live == null || spec == null) return live == null && spec == null;
  return _skySourceTypeMatches(live.source, spec.source);
}

// Whether [live] is a static environment this realizer built from a spec equal
// to [spec], so it can be kept rather than rebuilt. A null or externally built
// environment (no spec stamp, such as a disk-loaded HDR) is not reusable here,
// so the caller falls back to a rebuild.
//
// TODO(radiance-size-reapply): a radianceCubeSize-only change is not detected
// (the live map does not expose its built size), so it is ignored on reuse,
// matching _applyEnvironment.
bool _environmentReusable(EnvironmentMap? live, EnvironmentSpec spec) {
  if (live == null) return false;
  final current = _environmentSpec[live];
  if (current == null) return false;
  return canonicalJson(_encodeEnvironment(current)) ==
      canonicalJson(_encodeEnvironment(spec));
}

bool _skySourceTypeMatches(SkySource live, SkySourceSpec spec) =>
    switch (spec) {
      EnvironmentSkySpec() => live is EnvironmentSkySource,
      GradientSkySpec() => live is GradientSkySource,
      PhysicalSkySpec() => live is PhysicalSkySource,
      FmatSkySpec(:final asset) =>
        live is PreprocessedSky && fmatSourcePathOf(live) == asset.key,
    };

// Mutates [live]'s parameters from [spec] without replacing the source object,
// so a bound SkyEnvironment keeps its baked state and only needs invalidation.
// A type mismatch is a no-op (the reusability checks above gate this).
void _applySkySourceInPlace(SkySource live, SkySourceSpec spec) {
  switch (spec) {
    case EnvironmentSkySpec(:final blurriness):
      if (live is EnvironmentSkySource) live.blurriness = blurriness;
    case GradientSkySpec s:
      if (live is GradientSkySource) {
        live.zenithColor.setFrom(s.zenithColor);
        live.horizonColor.setFrom(s.horizonColor);
        live.groundColor.setFrom(s.groundColor);
        live.sunDirection.setFrom(s.sunDirection);
        live.sunColor.setFrom(s.sunColor);
        live.sunSharpness = s.sunSharpness;
      }
    case PhysicalSkySpec s:
      if (live is PhysicalSkySource) {
        live.sunDirection.setFrom(s.sunDirection);
        live.sunAngularRadius = s.sunAngularRadius;
        live.rayleighCoefficient = s.rayleighCoefficient;
        live.rayleighColor.setFrom(s.rayleighColor);
        live.mieCoefficient = s.mieCoefficient;
        live.mieEccentricity = s.mieEccentricity;
        live.mieColor.setFrom(s.mieColor);
        live.turbidity = s.turbidity;
        live.groundColor.setFrom(s.groundColor);
        live.energy = s.energy;
      }
    case FmatSkySpec s:
      if (live is PreprocessedSky) {
        applyFmatParameterOverrides(live.parameters, s.properties);
      }
  }
}

/// Runs [build] with [EnvironmentMap.radianceCubeSize] set to [size],
/// restoring it afterward. A null [size] keeps the current default.
//
// TODO(radiance-size-instance): radianceCubeSize is a static, so per-environment
// sizing relies on setting it around each (sequential) build. Promote it to a
// constructor argument on EnvironmentMap so it is genuinely per-instance.
Future<void> _withRadianceCubeSize(
  int? size,
  Future<void> Function() build,
) async {
  if (size == null) {
    await build();
    return;
  }
  final previous = EnvironmentMap.radianceCubeSize;
  EnvironmentMap.radianceCubeSize = size;
  try {
    await build();
  } finally {
    EnvironmentMap.radianceCubeSize = previous;
  }
}

/// Reads [scene]'s stage render settings back into [document]'s stage.
///
/// The reverse of [realizeStage]. An environment the realizer produced
/// recovers its source spec, and an fmat sky loaded through `loadFmatSky`
/// recovers its source path plus every parameter assigned through its typed
/// setters; a hand-built [EnvironmentMap] serializes as the studio default
/// and a custom [ShaderSkySource] is dropped, each with a warning.
void serializeStage(Scene scene, SceneDocument document) {
  final stage = document.stage;
  stage.environmentIntensity = scene.environmentIntensity;
  stage.exposure = scene.exposure;
  stage.toneMapping = scene.toneMapping.name;
  stage.antiAliasingMode = scene.antiAliasingMode.name;
  stage.renderScale = scene.renderScale;
  stage.filterQuality = scene.filterQuality.name;

  final skyEnvironment = scene.skyEnvironment;
  if (skyEnvironment == null) {
    stage.skyEnvironment = null;
    final environment = scene.environment;
    var spec = environment == null ? null : _environmentSpec[environment];
    if (spec == null && environment != null) {
      // An environment the app loaded itself still recovers when it carries
      // its asset-path stamp (EnvironmentMap.fromAssets).
      final assetPath = environmentAssetPathOf(environment);
      if (assetPath != null) spec = AssetEnvironment(AssetRef(assetPath));
    }
    if (spec != null) {
      stage.environment = spec;
    } else {
      if (environment != null) {
        debugPrint(
          'fscene: the scene environment was not produced by realizeStage '
          'or EnvironmentMap.fromAssets and cannot be recovered; serializing '
          'the studio default',
        );
      }
      stage.environment = const StudioEnvironment();
    }
  } else {
    final source = _serializeSkySource(skyEnvironment.source);
    // A sun light counts as "the sky casts shadows" only when it is driven by
    // the same sky source the lighting is, the binding this realizer produces.
    final castsSkyShadows = identical(
      scene.sunLight?.source,
      skyEnvironment.source,
    );
    stage.skyEnvironment = source == null
        ? null
        : SkyEnvironmentSpec(
            source,
            refresh: skyEnvironment.refresh.name,
            intervalSeconds: skyEnvironment.interval.inMicroseconds / 1e6,
            faceResolution: skyEnvironment.faceResolution,
            equirectWidth: skyEnvironment.equirectWidth,
            castShadows: castsSkyShadows,
          );
  }

  final skybox = scene.skybox;
  if (skybox == null) {
    stage.skybox = null;
  } else {
    final source = _serializeSkySource(skybox.source);
    stage.skybox = source == null
        ? null
        : SkyboxSpec(source, intensity: skybox.intensity);
  }
}

Future<void> _applyEnvironment(
  EnvironmentSpec spec,
  Scene scene,
  AssetBundle? bundle,
  EnvironmentAssetLoader? environmentLoader,
  EnvironmentPayloadLookup? payloadLookup,
) async {
  // Skip rebuilding (and re-decoding an asset panorama) when the current
  // environment already realized from an identical spec, the common case on
  // a stage hot reload that only tweaked a scalar.
  final currentEnvironment = scene.environment;
  final current = currentEnvironment == null
      ? null
      : _environmentSpec[currentEnvironment];
  if (current != null &&
      canonicalJson(_encodeEnvironment(current)) ==
          canonicalJson(_encodeEnvironment(spec))) {
    return;
  }
  final environment = await _buildEnvironment(
    spec,
    bundle,
    environmentLoader,
    payloadLookup,
  );
  if (environment != null) scene.environment = environment;
}

/// Builds the [EnvironmentMap] for [spec], stamping it so [serializeStage] can
/// recover the spec, or null when an asset fails to load. Honors the current
/// [EnvironmentMap.radianceCubeSize].
///
/// An [AssetEnvironment] is built through [environmentLoader] first (the editor
/// loads a user-picked file from disk and prefilters it), falling back to the
/// asset bundle when there is no loader or it declines. This keeps the disk
/// environment's whole lifecycle (decode plus prefilter cube) inside the
/// environment's own realization.
Future<EnvironmentMap?> _buildEnvironment(
  EnvironmentSpec spec,
  AssetBundle? bundle,
  EnvironmentAssetLoader? environmentLoader,
  EnvironmentPayloadLookup? payloadLookup,
) async {
  final EnvironmentMap environment;
  switch (spec) {
    case StudioEnvironment():
      environment = EnvironmentMap.studio();
    case EmptyEnvironment():
      environment = EnvironmentMap.empty();
    case PayloadEnvironment(:final payload):
      final chunk = payloadLookup?.call(payload);
      final bytes = chunk?.bytes;
      if (bytes == null) {
        debugPrint(
          'fscene: environment payload $payload has no bytes; load the '
          'document from a .fsceneb container so its chunks are attached',
        );
        return null;
      }
      try {
        environment = await _environmentFromImageBytes(bytes, chunk!.format);
      } catch (e) {
        debugPrint('fscene: failed to decode environment payload $payload: $e');
        return null;
      }
    case AssetEnvironment(:final asset):
      final loaded = environmentLoader == null
          ? null
          : await environmentLoader(asset);
      if (loaded != null) {
        environment = loaded;
      } else {
        try {
          environment = await EnvironmentMap.fromUIImages(
            radianceImage: await imageFromAsset(asset.key, bundle: bundle),
          );
        } catch (e) {
          debugPrint(
            'fscene: failed to load environment asset "${asset.key}": $e',
          );
          return null;
        }
      }
  }
  _environmentSpec[environment] = spec;
  return environment;
}

// Builds an environment map from an inlined equirect image chunk, choosing the
// decoder by the payload's format (`hdr` for Radiance HDR, an image codec
// otherwise). Mirrors the editor's disk loader, sourced from embedded bytes.
Future<EnvironmentMap> _environmentFromImageBytes(
  Uint8List bytes,
  String? format,
) async {
  if (format == 'hdr') {
    final hdr = decodeRadianceHdr(bytes, maxWidth: _maxEnvironmentWidth);
    return EnvironmentMap.fromEquirectHdr(
      linearPixels: hdr.pixels,
      width: hdr.width,
      height: hdr.height,
    );
  }
  return EnvironmentMap.fromUIImages(
    radianceImage: await imageFromBytes(bytes),
  );
}

// EnvironmentSpec has no public encoder; mirror the stage codec's shape just
// for equality checks.
Map<String, Object> _encodeEnvironment(EnvironmentSpec spec) => switch (spec) {
  StudioEnvironment() => {'type': 'studio'},
  AssetEnvironment(:final asset) => {'type': 'asset', 'ref': asset.key},
  PayloadEnvironment(:final payload) => {
    'type': 'payload',
    'payload': payload.toToken(),
  },
  EmptyEnvironment() => {'type': 'empty'},
};

Future<SkySource?> _realizeSkySource(
  SkySourceSpec spec,
  AssetBundle? bundle,
) async {
  switch (spec) {
    case EnvironmentSkySpec(:final blurriness):
      return EnvironmentSkySource(blurriness: blurriness);
    case GradientSkySpec s:
      return GradientSkySource(
        zenithColor: s.zenithColor.clone(),
        horizonColor: s.horizonColor.clone(),
        groundColor: s.groundColor.clone(),
        sunDirection: s.sunDirection.clone(),
        sunColor: s.sunColor.clone(),
        sunSharpness: s.sunSharpness,
      );
    case PhysicalSkySpec s:
      return PhysicalSkySource(
        sunDirection: s.sunDirection.clone(),
        sunAngularRadius: s.sunAngularRadius,
        rayleighCoefficient: s.rayleighCoefficient,
        rayleighColor: s.rayleighColor.clone(),
        mieCoefficient: s.mieCoefficient,
        mieEccentricity: s.mieEccentricity,
        mieColor: s.mieColor.clone(),
        turbidity: s.turbidity,
        groundColor: s.groundColor.clone(),
        energy: s.energy,
      );
    case FmatSkySpec s:
      try {
        final sky = await loadFmatSky(s.asset.key, bundle: bundle);
        applyFmatParameterOverrides(sky.parameters, s.properties);
        return sky;
      } catch (e) {
        debugPrint('fscene: failed to load sky fmat "${s.asset.key}": $e');
        return null;
      }
  }
}

SkySourceSpec? _serializeSkySource(SkySource source) {
  // PreprocessedSky and the built-in sources all extend ShaderSkySource;
  // match the concrete types before the generic fallthrough.
  if (source is PreprocessedSky) {
    final sourcePath = fmatSourcePathOf(source);
    if (sourcePath == null) {
      debugPrint(
        'fscene: a sky fmat with no known source path cannot be serialized; '
        'load skies with loadFmatSky',
      );
      return null;
    }
    // Assigned parameter values (overrides applied at realization plus any
    // the app set since) round-trip; texture parameters have no stage-level
    // resource pool to reference and are skipped with a warning.
    return FmatSkySpec(
      AssetRef(sourcePath),
      properties: serializeFmatParameterOverrides(
        source.parameters.assignedValues,
      ),
    );
  }
  if (source is GradientSkySource) {
    return GradientSkySpec(
      zenithColor: source.zenithColor.clone(),
      horizonColor: source.horizonColor.clone(),
      groundColor: source.groundColor.clone(),
      sunDirection: source.sunDirection.clone(),
      sunColor: source.sunColor.clone(),
      sunSharpness: source.sunSharpness,
    );
  }
  if (source is PhysicalSkySource) {
    return PhysicalSkySpec(
      sunDirection: source.sunDirection.clone(),
      sunAngularRadius: source.sunAngularRadius,
      rayleighCoefficient: source.rayleighCoefficient,
      rayleighColor: source.rayleighColor.clone(),
      mieCoefficient: source.mieCoefficient,
      mieEccentricity: source.mieEccentricity,
      mieColor: source.mieColor.clone(),
      turbidity: source.turbidity,
      groundColor: source.groundColor.clone(),
      energy: source.energy,
    );
  }
  if (source is EnvironmentSkySource) {
    return EnvironmentSkySpec(blurriness: source.blurriness);
  }
  debugPrint(
    'fscene: a custom ShaderSkySource is not serializable; use a .fmat sky '
    '(loadFmatSky) or a built-in source',
  );
  return null;
}

ToneMappingMode _toneMapping(String name) {
  try {
    return ToneMappingMode.values.byName(name);
  } catch (_) {
    debugPrint('fscene: unknown tone mapping "$name"; using pbrNeutral');
    return ToneMappingMode.pbrNeutral;
  }
}

T _byName<T extends Enum>(List<T> values, String name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  debugPrint('fscene: unknown $T "$name"; using ${fallback.name}');
  return fallback;
}

SkyEnvironmentRefresh _refresh(String name) {
  try {
    return SkyEnvironmentRefresh.values.byName(name);
  } catch (_) {
    debugPrint('fscene: unknown sky refresh policy "$name"; using manual');
    return SkyEnvironmentRefresh.manual;
  }
}
