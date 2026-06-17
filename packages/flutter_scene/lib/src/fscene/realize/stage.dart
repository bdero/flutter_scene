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
import 'package:flutter_scene/src/fscene/json/canonical.dart';
import 'package:flutter_scene/src/fscene/json/fscene_json.dart'
    show encodeSkySource;
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/realize/fmat_overrides.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/preprocessed_sky.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_scene/src/sky_environment.dart';
import 'package:flutter_scene/src/sky_sources.dart';
import 'package:flutter_scene/src/skybox.dart';
import 'package:flutter_scene/src/sun_light.dart';
import 'package:flutter_scene/src/tone_mapping.dart';

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
Future<void> realizeStage(
  SceneDocument document,
  Scene scene, {
  AssetBundle? bundle,
}) async {
  final stage = document.stage;
  scene.environmentIntensity = stage.environmentIntensity;
  scene.exposure = stage.exposure;
  scene.toneMapping = _toneMapping(stage.toneMapping);
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

  // Realize each distinct sky source once so a skybox and sky lighting
  // describing the same sky share one live source.
  final realized = <String, SkySource?>{};
  Future<SkySource?> sourceFor(SkySourceSpec spec) async =>
      realized[canonicalJson(encodeSkySource(spec))] ??=
          await _realizeSkySource(spec, bundle);

  final skyEnvironmentSpec = stage.skyEnvironment;
  if (skyEnvironmentSpec == null) {
    scene.skyEnvironment = null;
    await _applyEnvironment(stage.environment, scene, bundle);
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
      await _applyEnvironment(stage.environment, scene, bundle);
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
  final EnvironmentMap environment;
  switch (spec) {
    case StudioEnvironment():
      environment = EnvironmentMap.studio();
    case EmptyEnvironment():
      environment = EnvironmentMap.empty();
    case AssetEnvironment(:final asset):
      try {
        environment = await EnvironmentMap.fromUIImages(
          radianceImage: await imageFromAsset(asset.key, bundle: bundle),
        );
      } catch (e) {
        debugPrint(
          'fscene: failed to load environment asset "${asset.key}": $e',
        );
        return;
      }
  }
  _environmentSpec[environment] = spec;
  scene.environment = environment;
}

// EnvironmentSpec has no public encoder; mirror the stage codec's shape just
// for equality checks.
Map<String, Object> _encodeEnvironment(EnvironmentSpec spec) => switch (spec) {
  StudioEnvironment() => {'type': 'studio'},
  AssetEnvironment(:final asset) => {'type': 'asset', 'ref': asset.key},
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
