import 'dart:convert';

import 'package:vector_math/vector_math.dart';

import 'package:scene/src/id.dart';
import 'package:scene/src/json/canonical.dart';
import 'package:scene/src/json/jsonc.dart';
import 'package:scene/src/json/property_json.dart';
import 'package:scene/src/property_value.dart';
import 'package:scene/src/scene_document.dart';
import 'package:scene/src/specs.dart';

/// The format feature flags this build understands. A document that lists a
/// feature outside this set in its `featuresRequired` is refused.
/// {@category Serialization}
const Set<String> supportedFeatures = {
  'skinning',
  'prefabInstances',
  'streaming',
  'renderTextures',
};

/// Upgrades a raw decoded document one version forward (version `N` to
/// `N + 1`). Indexed by source version in the migration list.
/// {@category Serialization}
typedef FsceneMigration =
    Map<String, dynamic> Function(Map<String, dynamic> json);

// Indexed by source version. Version 0 has no supported migration.
final List<FsceneMigration> _builtInMigrations = [
  (json) => throw const FsceneVersionException(
    'Document version 0 cannot be migrated',
  ),
  _migrateV1ToV2,
  // 2 -> 3 changed writer conventions only (delta-serialized component
  // properties, nested audio attenuation); version 2 documents read as-is.
  (json) => json,
  // 3 -> 4 added the additive geometry morphTargets spec; version 3
  // documents read as-is. The version exists so a version-3 reader refuses
  // a morph-bearing document instead of silently dropping the deltas.
  (json) => json,
  // 4 -> 5 standardized model-space front-face winding to Counter-Clockwise
  // (CCW). Version 4 documents flag geometry index buffers with legacyWinding
  // so index pairs are swapped during realization.
  _migrateV4ToV5,
];

Map<String, dynamic> _migrateV4ToV5(Map<String, dynamic> json) {
  final resources = json['resources'];
  if (resources is Map) {
    for (final res in resources.values) {
      if (res is Map && res['kind'] == 'geometry' && res['indices'] != null) {
        res['legacyWinding'] = true;
      }
    }
  }
  return json;
}

Map<String, dynamic> _migrateV1ToV2(Map<String, dynamic> json) {
  final stageValue = json['stage'];
  if (stageValue is! Map) {
    throw const FsceneFormatException('Document stage must be an object');
  }
  final stage = Map<String, dynamic>.from(stageValue);
  final handedness = stage['handedness'] as String? ?? 'right';
  if (handedness != 'left') {
    throw const FsceneVersionException(
      'Right-handed version 1 documents cannot be migrated. Re-import the '
      'source glTF.',
    );
  }
  final nodesValue = json['nodes'];
  if (nodesValue is Map &&
      nodesValue.values.any(
        (node) => node is Map && node['excludeWindingParity'] == true,
      )) {
    throw const FsceneVersionException(
      'Version 1 documents using excludeWindingParity cannot be migrated. '
      'Re-import the source glTF.',
    );
  }
  stage
    ..remove('upAxis')
    ..remove('unitsPerMeter')
    ..remove('handedness');
  return Map<String, dynamic>.from(json)..['stage'] = stage;
}

/// Thrown when a `.fscene` document is malformed.
/// {@category Serialization}
class FsceneFormatException implements Exception {
  /// Creates a format exception with the given [message].
  const FsceneFormatException(this.message);

  /// What is wrong with the document.
  final String message;

  @override
  String toString() => 'FsceneFormatException: $message';
}

/// Thrown when a document's version cannot be loaded (newer than supported,
/// or missing a migration step).
/// {@category Serialization}
class FsceneVersionException implements Exception {
  /// Creates a version exception with the given [message].
  const FsceneVersionException(this.message);

  /// What went wrong with the version.
  final String message;

  @override
  String toString() => 'FsceneVersionException: $message';
}

/// Thrown when a document requires a format feature this build does not
/// support.
/// {@category Serialization}
class FsceneUnsupportedFeatureException implements Exception {
  /// Creates an exception naming the unsupported [feature].
  const FsceneUnsupportedFeatureException(this.feature);

  /// The required feature this build does not support.
  final String feature;

  @override
  String toString() =>
      'FsceneUnsupportedFeatureException: required feature "$feature" '
      'is not supported';
}

/// Serializes [doc] to canonical `.fscene` JSON text.
/// {@category Serialization}
String writeFscene(SceneDocument doc) => canonicalJson(encodeDocument(doc));

/// Parses a `.fscene` document from [source].
///
/// Accepts a JSONC superset on read (`//` and `/* */` comments, trailing
/// commas), runs the version migration chain, then decodes. Pass [migrations]
/// to override the built-in chain (for tests). Unknown fields are ignored.
/// {@category Serialization}
SceneDocument readFscene(String source, {List<FsceneMigration>? migrations}) {
  final decoded = jsonDecode(stripJsonc(source));
  if (decoded is! Map) {
    throw const FsceneFormatException('Top-level value must be an object');
  }
  final migrated = migrateFscene(
    Map<String, dynamic>.from(decoded),
    migrations: migrations,
  );
  return decodeDocument(migrated);
}

/// Runs the version migration chain over a raw decoded [json] document,
/// upgrading it to [currentFsceneVersion]. Throws [FsceneVersionException]
/// for a newer-than-supported version or a missing migration step.
/// {@category Serialization}
Map<String, dynamic> migrateFscene(
  Map<String, dynamic> json, {
  List<FsceneMigration>? migrations,
}) {
  final steps = migrations ?? _builtInMigrations;
  final encodedVersion = json['fscene'];
  if (encodedVersion is! int) {
    throw const FsceneVersionException('Document has no format version');
  }
  var version = encodedVersion;
  if (version > currentFsceneVersion) {
    throw FsceneVersionException(
      'Document version $version is newer than supported $currentFsceneVersion',
    );
  }
  while (version < currentFsceneVersion) {
    if (version >= steps.length) {
      throw FsceneVersionException('No migration from version $version');
    }
    json = steps[version](json);
    version++;
    json['fscene'] = version;
  }
  return json;
}

//-----------------------------------------------------------------------------
// Encode
//-----------------------------------------------------------------------------

/// Encodes [doc] as a JSON tree (maps, lists, and primitives).
/// {@category Serialization}
Map<String, dynamic> encodeDocument(SceneDocument doc) {
  final prefixes = _buildPrefixMap(doc);
  String idKey(LocalId id) => '${prefixes[id] ?? 'id'}:${id.toToken()}';

  final json = <String, dynamic>{
    'fscene': doc.formatVersion,
    'documentId': doc.documentId.toToken(),
  };
  if (doc.featuresUsed.isNotEmpty) {
    json['featuresUsed'] = doc.featuresUsed.toList()..sort();
  }
  if (doc.featuresRequired.isNotEmpty) {
    json['featuresRequired'] = doc.featuresRequired.toList()..sort();
  }
  if (doc.generator != null) json['generator'] = doc.generator;
  if (doc.payloadSource != null) json['payloadSource'] = doc.payloadSource;
  json['stage'] = encodeStage(doc.stage, idKey);
  if (doc.resources.isNotEmpty) {
    json['resources'] = _encodeIdMap(
      doc.resources,
      idKey,
      (r) => _encodeResource(r, idKey),
    );
  }
  json['nodes'] = _encodeIdMap(doc.nodes, idKey, (n) => _encodeNode(n, idKey));
  json['roots'] = [for (final id in doc.roots) idKey(id)];
  if (doc.skins.isNotEmpty) {
    json['skins'] = _encodeIdMap(
      doc.skins,
      idKey,
      (s) => _encodeSkin(s, idKey),
    );
  }
  if (doc.animations.isNotEmpty) {
    json['animations'] = _encodeIdMap(
      doc.animations,
      idKey,
      (a) => _encodeAnimation(a, idKey),
    );
  }
  if (doc.payloads.isNotEmpty) {
    json['payloads'] = _encodeIdMap(doc.payloads, idKey, _encodePayload);
  }
  if (doc.views.isNotEmpty) {
    json['views'] = [for (final view in doc.views) _encodeView(view, idKey)];
  }
  return json;
}

Map<String, dynamic> _encodeView(
  RenderViewSpec view,
  String Function(LocalId) idKey,
) => {
  'camera': idKey(view.cameraNode),
  if (view.target != null) 'target': idKey(view.target!),
  if (view.layerMask != 0xFFFFFFFF) 'layerMask': view.layerMask,
  if (view.order != 0) 'order': view.order,
  if (view.antiAliasingMode != null) 'antiAliasing': view.antiAliasingMode,
  if (view.renderScale != null) 'renderScale': view.renderScale,
  if (view.filterQuality != null) 'filterQuality': view.filterQuality,
};

Map<LocalId, String> _buildPrefixMap(SceneDocument doc) {
  final prefixes = <LocalId, String>{};
  for (final id in doc.nodes.keys) {
    prefixes[id] = 'n';
  }
  for (final r in doc.resources.values) {
    prefixes[r.id] = switch (r) {
      GeometryResource() => 'geo',
      MaterialResource() => 'mat',
      TextureResource() => 'tex',
      RenderTextureResource() => 'rt',
      EnvironmentResource() => 'env',
    };
  }
  for (final id in doc.skins.keys) {
    prefixes[id] = 'skin';
  }
  for (final id in doc.animations.keys) {
    prefixes[id] = 'anim';
  }
  for (final id in doc.payloads.keys) {
    prefixes[id] = 'chunk';
  }
  return prefixes;
}

Map<String, dynamic> _encodeIdMap<V>(
  Map<LocalId, V> map,
  String Function(LocalId) idKey,
  Object Function(V) encode,
) {
  final entries = map.entries.toList()
    ..sort((a, b) => a.key.toToken().compareTo(b.key.toToken()));
  return {for (final e in entries) idKey(e.key): encode(e.value)};
}

String _tokenIdKey(LocalId id) => id.toToken();

/// Encodes [s] to its canonical JSON map (also used to compare stages for
/// equality in the scene diff). [idKey] keys the environment-resource
/// reference; the diff uses the default raw-token form.
/// {@category Serialization}
Map<String, dynamic> encodeStage(
  StageMetadata s, [
  String Function(LocalId) idKey = _tokenIdKey,
]) => {
  if (s.environmentRef != null) 'environmentRef': idKey(s.environmentRef!),
  if (s.antiAliasingMode != 'auto') 'antiAliasing': s.antiAliasingMode,
  if (s.renderScale != 1.0) 'renderScale': s.renderScale,
  if (s.filterQuality != 'medium') 'filterQuality': s.filterQuality,
};

/// Encodes the look fields shared by the stage (the global base) and each
/// environment volume. They are the image-based-lighting environment, its
/// intensity and reflection size, exposure, tone mapping, the skybox, and sky
/// lighting.
Map<String, dynamic> _encodeLook({
  required String Function(LocalId) idKey,
  required EnvironmentSpec environment,
  required double environmentIntensity,
  required double exposure,
  required String toneMapping,
  required double agxWhite,
  required double agxContrast,
  required double environmentRotationY,
  required int? radianceCubeSize,
  required SkyboxSpec? skybox,
  required SkyEnvironmentSpec? skyEnvironment,
  required EnvironmentEffectsSpec effects,
  required bool overridesEffects,
}) => {
  'environment': switch (environment) {
    StudioEnvironment() => {'type': 'studio'},
    AssetEnvironment(:final asset) => {'type': 'asset', 'ref': asset.key},
    PayloadEnvironment(:final payload) => {
      'type': 'payload',
      'payload': idKey(payload),
    },
    ConstantEnvironment(:final color) => {
      'type': 'constant',
      'color': _vec3Json(color),
    },
    EmptyEnvironment() => {'type': 'empty'},
  },
  'environmentIntensity': environmentIntensity,
  'exposure': exposure,
  'toneMapping': toneMapping,
  if (agxWhite != 16.29) 'agxWhite': agxWhite,
  if (agxContrast != 1.25) 'agxContrast': agxContrast,
  if (environmentRotationY != 0.0) 'environmentRotationY': environmentRotationY,
  if (radianceCubeSize != null) 'radianceCubeSize': radianceCubeSize,
  if (overridesEffects) 'effects': _encodeEnvironmentEffects(effects),
  if (skybox != null)
    'skybox': {
      'source': encodeSkySource(skybox.source),
      'intensity': skybox.intensity,
    },
  if (skyEnvironment != null)
    'skyEnvironment': {
      'source': encodeSkySource(skyEnvironment.source),
      'refresh': skyEnvironment.refresh,
      'intervalSeconds': skyEnvironment.intervalSeconds,
      'faceResolution': skyEnvironment.faceResolution,
      'equirectWidth': skyEnvironment.equirectWidth,
      if (skyEnvironment.sunLight != null)
        'sunLight': _encodeSunLight(skyEnvironment.sunLight!),
    },
};

Map<String, dynamic> _encodeSunLight(SunLightSpec s) => {
  if (!s.castsShadow) 'castsShadow': false,
  if (s.intensityScale != 1.0) 'intensityScale': s.intensityScale,
  if (s.priority != 0) 'priority': s.priority,
  if (!s.cacheStaticShadows) 'cacheStaticShadows': false,
  if (s.shadowSoftness != 0.08) 'shadowSoftness': s.shadowSoftness,
  if (s.shadowMaxDistance != 150.0) 'shadowMaxDistance': s.shadowMaxDistance,
  if (s.shadowCascadeCount != 4) 'shadowCascadeCount': s.shadowCascadeCount,
  if (s.shadowMapResolution != 1024)
    'shadowMapResolution': s.shadowMapResolution,
  if (s.shadowDepthBias != 0.02) 'shadowDepthBias': s.shadowDepthBias,
  if (s.shadowNormalBias != 0.02) 'shadowNormalBias': s.shadowNormalBias,
  if (s.shadowFadeRange != 2.0) 'shadowFadeRange': s.shadowFadeRange,
  if (s.shadowCascadeSplitLambda != 0.6)
    'shadowCascadeSplitLambda': s.shadowCascadeSplitLambda,
  if (s.shadowAmbientStrength != 0.0)
    'shadowAmbientStrength': s.shadowAmbientStrength,
  if (s.shadowFilter != 'rotatedPoisson') 'shadowFilter': s.shadowFilter,
  if (s.contactShadows) 'contactShadows': true,
  if (s.contactShadowDistance != 0.3)
    'contactShadowDistance': s.contactShadowDistance,
  if (s.angularRadius != 0.005) 'angularRadius': s.angularRadius,
  if (s.shadowCasterFaces != 'front') 'shadowCasterFaces': s.shadowCasterFaces,
};

Map<String, dynamic> _encodeEnvironmentEffects(EnvironmentEffectsSpec e) {
  final colorGrading = <String, dynamic>{
    if (e.colorGradingEnabled) 'enabled': true,
    if (e.brightness != 1.0) 'brightness': e.brightness,
    if (e.contrast != 1.0) 'contrast': e.contrast,
    if (e.saturation != 1.0) 'saturation': e.saturation,
    if (e.temperature != 0.0) 'temperature': e.temperature,
    if (e.tint != 0.0) 'tint': e.tint,
    if (e.lift != Vector3.zero()) 'lift': _vec3Json(e.lift),
    if (e.gamma != Vector3.all(1.0)) 'gamma': _vec3Json(e.gamma),
    if (e.gain != Vector3.all(1.0)) 'gain': _vec3Json(e.gain),
    if (e.colorGradingLut != null) 'lut': e.colorGradingLut!.key,
    if (e.colorGradingLutBlend != 1.0) 'lutBlend': e.colorGradingLutBlend,
  };
  final bloom = <String, dynamic>{
    if (e.bloomEnabled) 'enabled': true,
    if (e.bloomThreshold != 1.0) 'threshold': e.bloomThreshold,
    if (e.bloomIntensity != 0.15) 'intensity': e.bloomIntensity,
    if (e.bloomScatter != 0.7) 'scatter': e.bloomScatter,
  };
  final lensFlare = <String, dynamic>{
    if (e.lensFlareEnabled) 'enabled': true,
    if (e.lensFlareIntensity != 1.0) 'intensity': e.lensFlareIntensity,
    if (e.lensFlareGhostCount != 4) 'ghostCount': e.lensFlareGhostCount,
    if (e.lensFlareGhostSpacing != 0.3) 'ghostSpacing': e.lensFlareGhostSpacing,
    if (e.lensFlareHaloRadius != 0.35) 'haloRadius': e.lensFlareHaloRadius,
    if (e.lensFlareHaloIntensity != 1.0)
      'haloIntensity': e.lensFlareHaloIntensity,
    if (e.lensFlareChromaticAberration != 0.005)
      'chromaticAberration': e.lensFlareChromaticAberration,
  };
  final vignette = <String, dynamic>{
    if (e.vignetteEnabled) 'enabled': true,
    if (e.vignetteIntensity != 0.5) 'intensity': e.vignetteIntensity,
    if (e.vignetteRadius != 0.75) 'radius': e.vignetteRadius,
    if (e.vignetteSmoothness != 0.5) 'smoothness': e.vignetteSmoothness,
  };
  final chromaticAberration = <String, dynamic>{
    if (e.chromaticAberrationEnabled) 'enabled': true,
    if (e.chromaticAberrationIntensity != 0.2)
      'intensity': e.chromaticAberrationIntensity,
  };
  final filmGrain = <String, dynamic>{
    if (e.filmGrainEnabled) 'enabled': true,
    if (e.filmGrainIntensity != 0.3) 'intensity': e.filmGrainIntensity,
  };
  final ao = <String, dynamic>{
    if (e.ambientOcclusionEnabled) 'enabled': true,
    if (e.ambientOcclusionMethod != 'obscurance')
      'method': e.ambientOcclusionMethod,
    if (e.ambientOcclusionRadius != 0.33) 'radius': e.ambientOcclusionRadius,
    if (e.ambientOcclusionIntensity != 1.0)
      'intensity': e.ambientOcclusionIntensity,
    if (e.ambientOcclusionBias != 0.07) 'bias': e.ambientOcclusionBias,
    if (e.ambientOcclusionPower != 1.5) 'power': e.ambientOcclusionPower,
    if (e.ambientOcclusionDetail != 0.5) 'detail': e.ambientOcclusionDetail,
    if (e.ambientOcclusionHorizonAngle != 0.06)
      'horizonAngle': e.ambientOcclusionHorizonAngle,
    if (e.ambientOcclusionDirectLightAffect != 0.0)
      'directLightAffect': e.ambientOcclusionDirectLightAffect,
    if (e.ambientOcclusionMultiBounce != 0.0)
      'multiBounce': e.ambientOcclusionMultiBounce,
    if (e.ambientOcclusionSampleCount != 16)
      'sampleCount': e.ambientOcclusionSampleCount,
    if (e.ambientOcclusionSliceCount != 3)
      'sliceCount': e.ambientOcclusionSliceCount,
    if (e.ambientOcclusionStepsPerSlice != 3)
      'stepsPerSlice': e.ambientOcclusionStepsPerSlice,
    if (e.ambientOcclusionVisibilityBitmask) 'visibilityBitmask': true,
    if (e.ambientOcclusionThickness != 0.5)
      'thickness': e.ambientOcclusionThickness,
    if (e.ambientOcclusionThicknessHeuristic != 0.004)
      'thicknessHeuristic': e.ambientOcclusionThicknessHeuristic,
    if (e.ambientOcclusionBentNormals) 'bentNormals': true,
    if (e.ambientOcclusionIndirectLight != 0.0)
      'indirectLight': e.ambientOcclusionIndirectLight,
    if (!e.ambientOcclusionHalfResolution) 'halfResolution': false,
    if (e.ambientOcclusionDepthMipChain) 'depthMipChain': true,
    if (e.ambientOcclusionSpecularMode != 'none')
      'specularMode': e.ambientOcclusionSpecularMode,
  };
  final ssr = <String, dynamic>{
    if (e.screenSpaceReflectionsEnabled) 'enabled': true,
    if (e.screenSpaceReflectionsIntensity != 1.0)
      'intensity': e.screenSpaceReflectionsIntensity,
    if (e.screenSpaceReflectionsMaxDistance != 24.4)
      'maxDistance': e.screenSpaceReflectionsMaxDistance,
    if (e.screenSpaceReflectionsThickness != 0.46)
      'thickness': e.screenSpaceReflectionsThickness,
    if (e.screenSpaceReflectionsStride != 9.0)
      'stride': e.screenSpaceReflectionsStride,
    if (e.screenSpaceReflectionsMaxSteps != 90)
      'maxSteps': e.screenSpaceReflectionsMaxSteps,
    if (e.screenSpaceReflectionsBlur != 0.3)
      'blur': e.screenSpaceReflectionsBlur,
    if (e.screenSpaceReflectionsDistanceFadeStart != 0.0)
      'distanceFadeStart': e.screenSpaceReflectionsDistanceFadeStart,
    if (e.screenSpaceReflectionsResolutionScale != 1.0)
      'resolutionScale': e.screenSpaceReflectionsResolutionScale,
  };
  final gi = <String, dynamic>{
    if (e.globalIlluminationEnabled) 'enabled': true,
    if (e.globalIlluminationVolumeMode != 'followCamera')
      'volumeMode': e.globalIlluminationVolumeMode,
    if (e.globalIlluminationResolution != Vector3(16, 8, 16))
      'resolution': _vec3Json(e.globalIlluminationResolution),
    if (e.globalIlluminationExtents != Vector3(20, 10, 20))
      'extents': _vec3Json(e.globalIlluminationExtents),
    if (e.globalIlluminationIntensity != 1.0)
      'intensity': e.globalIlluminationIntensity,
    if (e.globalIlluminationHysteresis != 0.95)
      'hysteresis': e.globalIlluminationHysteresis,
    if (e.globalIlluminationShadowBias != 0.3)
      'shadowBias': e.globalIlluminationShadowBias,
    if (e.globalIlluminationVisibility != 0.7)
      'visibility': e.globalIlluminationVisibility,
    if (e.globalIlluminationVisibilityBias != 0.08)
      'visibilityBias': e.globalIlluminationVisibilityBias,
    if (e.globalIlluminationProbeUpdateBudget != 0)
      'probeUpdateBudget': e.globalIlluminationProbeUpdateBudget,
    if (e.globalIlluminationInjectionResolution != 'eighth')
      'injectionResolution': e.globalIlluminationInjectionResolution,
    if (e.globalIlluminationFireflyClamp != 8.0)
      'fireflyClamp': e.globalIlluminationFireflyClamp,
    if (e.globalIlluminationEmissiveBoost != 1.0)
      'emissiveBoost': e.globalIlluminationEmissiveBoost,
    if (e.globalIlluminationUpdateWhenIdleOnly) 'updateWhenIdleOnly': true,
    if (e.globalIlluminationBakeOnly) 'bakeOnly': true,
  };
  final fog = <String, dynamic>{
    if (e.fogEnabled) 'enabled': true,
    if (e.fogMode != 'exponential') 'mode': e.fogMode,
    if (e.fogColor != Vector3(0.6, 0.7, 0.8)) 'color': _vec3Json(e.fogColor),
    if (e.fogSkyColorInfluence != 0.0)
      'skyColorInfluence': e.fogSkyColorInfluence,
    if (e.fogDensity != 0.02) 'density': e.fogDensity,
    if (e.fogStart != 0.0) 'start': e.fogStart,
    if (e.fogEnd != 200.0) 'end': e.fogEnd,
    if (e.fogMaxOpacity != 1.0) 'maxOpacity': e.fogMaxOpacity,
    if (e.fogCutoffDistance != 0.0) 'cutoffDistance': e.fogCutoffDistance,
    if (e.fogHeight != 0.0) 'height': e.fogHeight,
    if (e.fogHeightFalloff != 0.0) 'heightFalloff': e.fogHeightFalloff,
    if (e.fogSunInScatter != 0.0) 'sunInScatter': e.fogSunInScatter,
    if (e.fogSunInScatterExponent != 8.0)
      'sunInScatterExponent': e.fogSunInScatterExponent,
  };
  final godRays = <String, dynamic>{
    if (e.godRaysEnabled) 'enabled': true,
    if (e.godRaysIntensity != 1.0) 'intensity': e.godRaysIntensity,
    if (e.godRaysDensity != 0.5) 'density': e.godRaysDensity,
    if (e.godRaysAnisotropy != 0.7) 'anisotropy': e.godRaysAnisotropy,
    if (e.godRaysStepCount != 24) 'stepCount': e.godRaysStepCount,
    if (e.godRaysMaxDistance != 200.0) 'maxDistance': e.godRaysMaxDistance,
    if (e.godRaysJitter != 1.0) 'jitter': e.godRaysJitter,
    if (e.godRaysColor != Vector3.all(1.0)) 'color': _vec3Json(e.godRaysColor),
  };
  final dof = <String, dynamic>{
    if (e.depthOfFieldEnabled) 'enabled': true,
    if (e.depthOfFieldFocusDistance != 10.0)
      'focusDistance': e.depthOfFieldFocusDistance,
    if (e.depthOfFieldFStop != 2.8) 'fStop': e.depthOfFieldFStop,
    if (e.depthOfFieldFocalLength != 0.0)
      'focalLength': e.depthOfFieldFocalLength,
    if (e.depthOfFieldSensorHeight != 0.024)
      'sensorHeight': e.depthOfFieldSensorHeight,
    if (e.depthOfFieldBlurScale != 1.0) 'blurScale': e.depthOfFieldBlurScale,
    if (e.depthOfFieldMaxForegroundBlur != 24.0)
      'maxForegroundBlur': e.depthOfFieldMaxForegroundBlur,
    if (e.depthOfFieldMaxBackgroundBlur != 32.0)
      'maxBackgroundBlur': e.depthOfFieldMaxBackgroundBlur,
    if (e.depthOfFieldBladeCount != 0) 'bladeCount': e.depthOfFieldBladeCount,
    if (e.depthOfFieldBladeRotation != 0.0)
      'bladeRotation': e.depthOfFieldBladeRotation,
    if (e.depthOfFieldBladeCurvature != 0.0)
      'bladeCurvature': e.depthOfFieldBladeCurvature,
    if (e.depthOfFieldQuality != 'medium') 'quality': e.depthOfFieldQuality,
  };
  final autoExposure = <String, dynamic>{
    if (e.autoExposureEnabled) 'enabled': true,
    if (e.autoExposureStrength != 0.55) 'strength': e.autoExposureStrength,
    if (e.autoExposureCompensation != 0.0)
      'compensation': e.autoExposureCompensation,
    if (e.autoExposureMinEv != -4.0) 'minEv': e.autoExposureMinEv,
    if (e.autoExposureMaxEv != 4.0) 'maxEv': e.autoExposureMaxEv,
    if (e.autoExposureSpeedUp != 3.0) 'speedUp': e.autoExposureSpeedUp,
    if (e.autoExposureSpeedDown != 1.0) 'speedDown': e.autoExposureSpeedDown,
  };
  final taa = <String, dynamic>{
    if (e.temporalAntiAliasingEnabled) 'enabled': true,
    if (e.temporalAntiAliasingMinimumCurrentWeight != 0.1)
      'minimumCurrentWeight': e.temporalAntiAliasingMinimumCurrentWeight,
    if (e.temporalAntiAliasingVarianceGamma != 1.0)
      'varianceGamma': e.temporalAntiAliasingVarianceGamma,
    if (e.temporalAntiAliasingSharpness != 0.0)
      'sharpness': e.temporalAntiAliasingSharpness,
    if (e.temporalAntiAliasingJitterSequenceLength != 16)
      'jitterSequenceLength': e.temporalAntiAliasingJitterSequenceLength,
    if (e.temporalAntiAliasingJitterScale != 1.0)
      'jitterScale': e.temporalAntiAliasingJitterScale,
    if (!e.temporalAntiAliasingObjectMotion) 'objectMotion': false,
    if (!e.temporalAntiAliasingSkinnedMotion) 'skinnedMotion': false,
  };
  return {
    if (colorGrading.isNotEmpty) 'colorGrading': colorGrading,
    if (bloom.isNotEmpty) 'bloom': bloom,
    if (lensFlare.isNotEmpty) 'lensFlare': lensFlare,
    if (vignette.isNotEmpty) 'vignette': vignette,
    if (chromaticAberration.isNotEmpty)
      'chromaticAberration': chromaticAberration,
    if (filmGrain.isNotEmpty) 'filmGrain': filmGrain,
    if (ao.isNotEmpty) 'ambientOcclusion': ao,
    if (ssr.isNotEmpty) 'screenSpaceReflections': ssr,
    if (gi.isNotEmpty) 'globalIllumination': gi,
    if (taa.isNotEmpty) 'temporalAntiAliasing': taa,
    if (fog.isNotEmpty) 'fog': fog,
    if (godRays.isNotEmpty) 'godRays': godRays,
    if (dof.isNotEmpty) 'depthOfField': dof,
    if (autoExposure.isNotEmpty) 'autoExposure': autoExposure,
  };
}

/// Encodes a sky source spec to its canonical JSON form (also used to key
/// realized sky sources for sharing).
/// {@category Serialization}
Object encodeSkySource(SkySourceSpec source) => switch (source) {
  EnvironmentSkySpec(:final blurriness) => {
    'type': 'environment',
    'blurriness': blurriness,
  },
  FmatSkySpec(:final asset, :final properties) => {
    'type': 'fmat',
    'ref': asset.key,
    if (properties.isNotEmpty)
      'properties': {
        for (final e in properties.entries)
          e.key: encodePropertyValue(e.value, (id) => id.toToken()),
      },
  },
  GradientSkySpec s => {
    'type': 'gradient',
    'zenithColor': _vec3Json(s.zenithColor),
    'horizonColor': _vec3Json(s.horizonColor),
    'groundColor': _vec3Json(s.groundColor),
    'sunDirection': _vec3Json(s.sunDirection),
    'sunColor': _vec3Json(s.sunColor),
    'sunSharpness': s.sunSharpness,
  },
  PhysicalSkySpec s => {
    'type': 'physical',
    'sunDirection': _vec3Json(s.sunDirection),
    'sunAngularRadius': s.sunAngularRadius,
    'rayleighCoefficient': s.rayleighCoefficient,
    'rayleighColor': _vec3Json(s.rayleighColor),
    'mieCoefficient': s.mieCoefficient,
    'mieEccentricity': s.mieEccentricity,
    'mieColor': _vec3Json(s.mieColor),
    'turbidity': s.turbidity,
    'groundColor': _vec3Json(s.groundColor),
    'energy': s.energy,
  },
  WeatherSkySpec s => {
    'type': 'weather',
    'sunDirection': _vec3Json(s.sunDirection),
    'sunAngularRadius': s.sunAngularRadius,
    'rayleighCoefficient': s.rayleighCoefficient,
    'rayleighColor': _vec3Json(s.rayleighColor),
    'mieCoefficient': s.mieCoefficient,
    'mieEccentricity': s.mieEccentricity,
    'mieColor': _vec3Json(s.mieColor),
    'turbidity': s.turbidity,
    'groundColor': _vec3Json(s.groundColor),
    'energy': s.energy,
    'coverage': s.coverage,
    'density': s.density,
    'altitude': s.altitude,
    'detail': s.detail,
    'softness': s.softness,
    'seed': s.seed,
    'wind': [s.wind.x, s.wind.y],
    'cloudColor': _vec3Json(s.cloudColor),
    'cloudShading': s.cloudShading,
    'stormDarkening': s.stormDarkening,
  },
};

List<double> _vec3Json(Vector3 v) => [v.x, v.y, v.z];

/// Encodes a single resource spec the same way [encodeScene] does, for
/// canonical-form comparison (the reload diff uses this to detect resource
/// content changes).
/// {@category Serialization}
Object encodeResource(ResourceSpec r, String Function(LocalId) idKey) =>
    _encodeResource(r, idKey);

Object _encodeResource(ResourceSpec r, String Function(LocalId) idKey) {
  switch (r) {
    case GeometryResource(
      :final vertices,
      :final indices,
      :final procedural,
      :final bounds,
      :final morphTargets,
      :final legacyWinding,
    ):
      return {
        'kind': 'geometry',
        if (vertices != null) 'vertices': idKey(vertices),
        if (indices != null) 'indices': idKey(indices),
        if (procedural != null) 'procedural': _encodeProcedural(procedural),
        if (bounds != null)
          'bounds': {
            'min': [bounds.min.x, bounds.min.y, bounds.min.z],
            'max': [bounds.max.x, bounds.max.y, bounds.max.z],
          },
        if (r.topology != 'triangle') 'topology': r.topology,
        if (morphTargets != null)
          'morphTargets': {
            'deltas': idKey(morphTargets.deltas),
            'targetCount': morphTargets.targetCount,
            if (morphTargets.hasNormalDeltas) 'normals': true,
            if (morphTargets.hasTangentDeltas) 'tangents': true,
            if (morphTargets.targetNames.isNotEmpty)
              'names': morphTargets.targetNames,
            if (morphTargets.defaultWeights.isNotEmpty)
              'weights': morphTargets.defaultWeights,
          },
        if (legacyWinding) 'legacyWinding': true,
      };
    case TextureResource(:final payload, :final asset, :final content):
      return {
        'kind': 'texture',
        if (payload != null) 'payload': idKey(payload),
        if (asset != null) 'ref': asset.key,
        if (content != 'color') 'content': content,
      };
    case RenderTextureResource(
      :final width,
      :final height,
      :final update,
      :final intervalMilliseconds,
      :final filter,
      :final wrap,
    ):
      return {
        'kind': 'renderTexture',
        'width': width,
        'height': height,
        if (update != 'everyFrame') 'update': update,
        if (intervalMilliseconds != null)
          'intervalMilliseconds': intervalMilliseconds,
        if (filter != 'linear') 'filter': filter,
        if (wrap != 'clampToEdge') 'wrap': wrap,
      };
    case MaterialResource(
      :final type,
      :final name,
      :final properties,
      :final asset,
    ):
      return {
        'kind': 'material',
        'type': type,
        if (name.isNotEmpty) 'name': name,
        if (asset != null) 'ref': asset.key,
        if (properties.isNotEmpty)
          'properties': {
            for (final e in properties.entries)
              e.key: encodePropertyValue(e.value, idKey),
          },
      };
    case EnvironmentResource():
      return {
        'kind': 'environment',
        if (r.name.isNotEmpty) 'name': r.name,
        ..._encodeLook(
          idKey: idKey,
          environment: r.environment,
          environmentIntensity: r.environmentIntensity,
          exposure: r.exposure,
          toneMapping: r.toneMapping,
          agxWhite: r.agxWhite,
          agxContrast: r.agxContrast,
          environmentRotationY: r.environmentRotationY,
          radianceCubeSize: r.radianceCubeSize,
          skybox: r.skybox,
          skyEnvironment: r.skyEnvironment,
          effects: r.effects,
          overridesEffects: r.overridesEffects,
        ),
      };
  }
}

Map<String, dynamic> _encodeNode(NodeSpec n, String Function(LocalId) idKey) {
  return {
    if (n.name.isNotEmpty) 'name': n.name,
    'transform': _encodeTransform(n.transform),
    if (n.children.isNotEmpty)
      'children': [for (final c in n.children) idKey(c)],
    if (n.components.isNotEmpty)
      'components': [for (final c in n.components) _encodeComponent(c, idKey)],
    if (n.layers != 1) 'layers': n.layers,
    if (n.lightChannelMask != 0xFF) 'lightChannelMask': n.lightChannelMask,
    if (n.skin != null) 'skin': idKey(n.skin!),
    if (n.instance != null) 'instance': _encodeInstance(n.instance!, idKey),
    if (!n.visible) 'visible': false,
    if (!n.raycastable) 'raycastable': false,
  };
}

Map<String, dynamic> _encodeTransform(TransformSpec t) => switch (t) {
  MatrixTransform(:final matrix) => {'matrix': matrix.storage.toList()},
  TrsTransform(:final translation, :final rotation, :final scale) => {
    'trs': {
      't': [translation.x, translation.y, translation.z],
      'r': [rotation.x, rotation.y, rotation.z, rotation.w],
      's': [scale.x, scale.y, scale.z],
    },
  },
};

Map<String, dynamic> _encodeComponent(
  ComponentSpec c,
  String Function(LocalId) idKey,
) => {
  'type': c.type,
  if (c.properties.isNotEmpty)
    'properties': {
      for (final e in c.properties.entries)
        e.key: encodePropertyValue(e.value, idKey),
    },
};

Map<String, dynamic> _encodeInstance(
  PrefabInstanceSpec p,
  String Function(LocalId) idKey,
) => {
  'source': p.source.key,
  if (p.load != LoadPolicy.eager) 'load': p.load.name,
  if (p.overrides.isNotEmpty)
    'overrides': [
      for (final o in p.overrides)
        {
          'target': idKey(o.target),
          'path': o.path,
          'value': encodePropertyValue(o.value, idKey),
        },
    ],
  if (p.attachments.isNotEmpty)
    'attachments': [
      for (final a in p.attachments)
        {
          'node': idKey(a.node),
          if (a.parent != null) 'parent': idKey(a.parent!),
        },
    ],
  if (p.removedNodes.isNotEmpty)
    'removedNodes': [for (final id in p.removedNodes) idKey(id)],
  if (p.addedComponents.isNotEmpty)
    'addedComponents': [
      for (final c in p.addedComponents) _encodeComponent(c, idKey),
    ],
  if (p.removedComponentTypes.isNotEmpty)
    'removedComponentTypes': p.removedComponentTypes,
  if (p.memberComponents.isNotEmpty)
    'memberComponents': [
      for (final mc in p.memberComponents)
        {
          'member': idKey(mc.member),
          'component': _encodeComponent(mc.component, idKey),
        },
    ],
};

Map<String, dynamic> _encodeSkin(SkinSpec s, String Function(LocalId) idKey) =>
    {
      'joints': [for (final j in s.joints) idKey(j)],
      'inverseBindMatrices': idKey(s.inverseBindMatrices),
      if (s.skeleton != null) 'skeleton': idKey(s.skeleton!),
    };

Map<String, dynamic> _encodeAnimation(
  AnimationSpec a,
  String Function(LocalId) idKey,
) => {
  if (a.name.isNotEmpty) 'name': a.name,
  'channels': [
    for (final ch in a.channels)
      {
        'target': idKey(ch.target),
        if (ch.targetName != null) 'targetName': ch.targetName,
        'property': ch.property.name,
        'timeline': idKey(ch.timeline),
        'keyframes': idKey(ch.keyframes),
      },
  ],
};

Map<String, dynamic> _encodePayload(PayloadSpec p) => {
  'encoding': p.encoding.name,
  if (p.layout != null) 'layout': p.layout,
  if (p.format != null) 'format': p.format,
  if (p.width != null) 'width': p.width,
  if (p.height != null) 'height': p.height,
  if (p.length != null) 'length': p.length,
};

//-----------------------------------------------------------------------------
// Decode
//-----------------------------------------------------------------------------

/// Decodes a [SceneDocument] from a raw JSON tree (already migrated to the
/// current version). Throws on an unsupported required feature.
/// {@category Serialization}
SceneDocument decodeDocument(Map<String, dynamic> json) {
  final version = json['fscene'] as int? ?? currentFsceneVersion;
  if (version != currentFsceneVersion) {
    throw FsceneVersionException(
      'Document is version $version; expected $currentFsceneVersion '
      '(run migrateFscene first)',
    );
  }

  final required =
      (json['featuresRequired'] as List?)?.cast<String>() ?? const <String>[];
  for (final feature in required) {
    if (!supportedFeatures.contains(feature)) {
      throw FsceneUnsupportedFeatureException(feature);
    }
  }

  final documentId = DocumentId.parse(json['documentId'] as String);

  final nodes = _decodeIdMap(json['nodes'], _decodeNode);
  final resources = _decodeIdMap(json['resources'], _decodeResource);
  final skins = _decodeIdMap(json['skins'], _decodeSkin);
  final animations = _decodeIdMap(json['animations'], _decodeAnimation);
  final payloads = _decodeIdMap(json['payloads'], _decodePayload);
  final roots = [
    for (final id in (json['roots'] as List? ?? const []))
      LocalId.parse(id as String),
  ];

  // Mint future ids with a fresh session that avoids every session already
  // present in the document, so new edits cannot collide with loaded ids.
  final views = [
    for (final view in (json['views'] as List? ?? const []))
      _decodeView(Map<String, dynamic>.from(view as Map)),
  ];

  final usedSessions = <int>{};
  void collect(LocalId id) => usedSessions.add(id.session);
  nodes.keys.forEach(collect);
  resources.keys.forEach(collect);
  skins.keys.forEach(collect);
  animations.keys.forEach(collect);
  payloads.keys.forEach(collect);
  for (final view in views) {
    collect(view.cameraNode);
    if (view.target != null) collect(view.target!);
  }

  final doc = SceneDocument(
    documentId: documentId,
    allocator: IdAllocator(excludedSessions: usedSessions),
    stage: _decodeStage(json['stage'] as Map<String, dynamic>),
  );
  doc.formatVersion = version;
  doc.generator = json['generator'] as String?;
  doc.payloadSource = json['payloadSource'] as String?;
  doc.featuresUsed.addAll(
    (json['featuresUsed'] as List?)?.cast<String>() ?? const [],
  );
  doc.featuresRequired.addAll(required);
  doc.nodes.addAll(nodes);
  doc.roots.addAll(roots);
  doc.resources.addAll(resources);
  doc.skins.addAll(skins);
  doc.animations.addAll(animations);
  doc.payloads.addAll(payloads);
  doc.views.addAll(views);
  return doc;
}

RenderViewSpec _decodeView(Map<String, dynamic> json) => RenderViewSpec(
  cameraNode: LocalId.parse(json['camera'] as String),
  target: json['target'] != null
      ? LocalId.parse(json['target'] as String)
      : null,
  layerMask: json['layerMask'] as int? ?? 0xFFFFFFFF,
  order: json['order'] as int? ?? 0,
  antiAliasingMode: json['antiAliasing'] as String?,
  renderScale: json['renderScale'] != null ? _d(json['renderScale']) : null,
  filterQuality: json['filterQuality'] as String?,
);

Map<LocalId, V> _decodeIdMap<V>(
  Object? json,
  V Function(LocalId id, Map<String, dynamic> value) decode,
) {
  if (json == null) return {};
  final out = <LocalId, V>{};
  for (final e in (json as Map).entries) {
    final id = LocalId.parse(e.key as String);
    out[id] = decode(id, Map<String, dynamic>.from(e.value as Map));
  }
  return out;
}

NodeSpec _decodeNode(LocalId id, Map<String, dynamic> json) => NodeSpec(
  id: id,
  name: json['name'] as String? ?? '',
  transform: _decodeTransform(json['transform'] as Map<String, dynamic>),
  children: [
    for (final c in (json['children'] as List? ?? const []))
      LocalId.parse(c as String),
  ],
  components: [
    for (final c in (json['components'] as List? ?? const []))
      _decodeComponent(Map<String, dynamic>.from(c as Map)),
  ],
  layers: json['layers'] as int? ?? 1,
  lightChannelMask: json['lightChannelMask'] as int? ?? 0xFF,
  skin: json['skin'] != null ? LocalId.parse(json['skin'] as String) : null,
  instance: json['instance'] != null
      ? _decodeInstance(Map<String, dynamic>.from(json['instance'] as Map))
      : null,
  visible: json['visible'] as bool? ?? true,
  raycastable: json['raycastable'] as bool? ?? true,
);

TransformSpec _decodeTransform(Map<String, dynamic> json) {
  final matrix = json['matrix'];
  if (matrix != null) {
    return MatrixTransform(
      Matrix4.fromList([for (final e in matrix as List) _d(e)]),
    );
  }
  final trs = json['trs'] as Map<String, dynamic>;
  final t = trs['t'] as List;
  final r = trs['r'] as List;
  final s = trs['s'] as List;
  return TrsTransform(
    translation: Vector3(_d(t[0]), _d(t[1]), _d(t[2])),
    rotation: Quaternion(_d(r[0]), _d(r[1]), _d(r[2]), _d(r[3])),
    scale: Vector3(_d(s[0]), _d(s[1]), _d(s[2])),
  );
}

ComponentSpec _decodeComponent(Map<String, dynamic> json) => ComponentSpec(
  json['type'] as String,
  properties: _decodeProperties(json['properties']),
);

Map<String, PropertyValue> _decodeProperties(Object? json) => {
  if (json != null)
    for (final e in (json as Map).entries)
      e.key as String: decodePropertyValue(e.value),
};

PrefabInstanceSpec _decodeInstance(Map<String, dynamic> json) =>
    PrefabInstanceSpec(
      source: AssetRef(json['source'] as String),
      load: json['load'] == 'lazy' ? LoadPolicy.lazy : LoadPolicy.eager,
      overrides: [
        for (final o in (json['overrides'] as List? ?? const []))
          _decodeOverride(Map<String, dynamic>.from(o as Map)),
      ],
      attachments: [
        for (final e in (json['attachments'] as List? ?? const []))
          _decodeAttachment(Map<String, dynamic>.from(e as Map)),
      ],
      removedNodes: [
        for (final id in (json['removedNodes'] as List? ?? const []))
          LocalId.parse(id as String),
      ],
      addedComponents: [
        for (final c in (json['addedComponents'] as List? ?? const []))
          _decodeComponent(Map<String, dynamic>.from(c as Map)),
      ],
      removedComponentTypes:
          (json['removedComponentTypes'] as List?)?.cast<String>() ?? const [],
      memberComponents: [
        for (final mc in (json['memberComponents'] as List? ?? const []))
          MemberComponent(
            member: LocalId.parse((mc as Map)['member'] as String),
            component: _decodeComponent(
              Map<String, dynamic>.from(mc['component'] as Map),
            ),
          ),
      ],
    );

Attachment _decodeAttachment(Map<String, dynamic> json) => Attachment(
  LocalId.parse(json['node'] as String),
  parent: json['parent'] == null
      ? null
      : LocalId.parse(json['parent'] as String),
);

PropertyOverride _decodeOverride(Map<String, dynamic> json) => PropertyOverride(
  target: LocalId.parse(json['target'] as String),
  path: json['path'] as String,
  value: decodePropertyValue(json['value']),
);

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

Vector3 _effectVec(Object? value, Vector3 fallback) {
  if (value is! List || value.length < 3) return fallback;
  return Vector3(_d(value[0]), _d(value[1]), _d(value[2]));
}

EnvironmentEffectsSpec _decodeEnvironmentEffects(Object? value) {
  final effects = _map(value);
  final cg = _map(effects['colorGrading']);
  final bloom = _map(effects['bloom']);
  final lensFlare = _map(effects['lensFlare']);
  final vignette = _map(effects['vignette']);
  final ca = _map(effects['chromaticAberration']);
  final grain = _map(effects['filmGrain']);
  final ao = _map(effects['ambientOcclusion']);
  final ssr = _map(effects['screenSpaceReflections']);
  final gi = _map(effects['globalIllumination']);
  final taa = _map(effects['temporalAntiAliasing']);
  final fog = _map(effects['fog']);
  final rays = _map(effects['godRays']);
  final dof = _map(effects['depthOfField']);
  final auto = _map(effects['autoExposure']);
  return EnvironmentEffectsSpec(
    colorGradingEnabled: cg['enabled'] as bool? ?? false,
    brightness: _d(cg['brightness'] ?? 1.0),
    contrast: _d(cg['contrast'] ?? 1.0),
    saturation: _d(cg['saturation'] ?? 1.0),
    temperature: _d(cg['temperature'] ?? 0.0),
    tint: _d(cg['tint'] ?? 0.0),
    lift: _effectVec(cg['lift'], Vector3.zero()),
    gamma: _effectVec(cg['gamma'], Vector3.all(1.0)),
    gain: _effectVec(cg['gain'], Vector3.all(1.0)),
    colorGradingLut: cg['lut'] is String ? AssetRef(cg['lut'] as String) : null,
    colorGradingLutBlend: _d(cg['lutBlend'] ?? 1.0),
    bloomEnabled: bloom['enabled'] as bool? ?? false,
    bloomThreshold: _d(bloom['threshold'] ?? 1.0),
    bloomIntensity: _d(bloom['intensity'] ?? 0.15),
    bloomScatter: _d(bloom['scatter'] ?? 0.7),
    lensFlareEnabled: lensFlare['enabled'] as bool? ?? false,
    lensFlareIntensity: _d(lensFlare['intensity'] ?? 1.0),
    lensFlareGhostCount: (lensFlare['ghostCount'] as num? ?? 4).toInt(),
    lensFlareGhostSpacing: _d(lensFlare['ghostSpacing'] ?? 0.3),
    lensFlareHaloRadius: _d(lensFlare['haloRadius'] ?? 0.35),
    lensFlareHaloIntensity: _d(lensFlare['haloIntensity'] ?? 1.0),
    lensFlareChromaticAberration: _d(lensFlare['chromaticAberration'] ?? 0.005),
    vignetteEnabled: vignette['enabled'] as bool? ?? false,
    vignetteIntensity: _d(vignette['intensity'] ?? 0.5),
    vignetteRadius: _d(vignette['radius'] ?? 0.75),
    vignetteSmoothness: _d(vignette['smoothness'] ?? 0.5),
    chromaticAberrationEnabled: ca['enabled'] as bool? ?? false,
    chromaticAberrationIntensity: _d(ca['intensity'] ?? 0.2),
    filmGrainEnabled: grain['enabled'] as bool? ?? false,
    filmGrainIntensity: _d(grain['intensity'] ?? 0.3),
    ambientOcclusionEnabled: ao['enabled'] as bool? ?? false,
    ambientOcclusionMethod: ao['method'] as String? ?? 'obscurance',
    ambientOcclusionRadius: _d(ao['radius'] ?? 0.33),
    ambientOcclusionIntensity: _d(ao['intensity'] ?? 1.0),
    ambientOcclusionBias: _d(ao['bias'] ?? 0.07),
    ambientOcclusionPower: _d(ao['power'] ?? 1.5),
    ambientOcclusionDetail: _d(ao['detail'] ?? 0.5),
    ambientOcclusionHorizonAngle: _d(ao['horizonAngle'] ?? 0.06),
    ambientOcclusionDirectLightAffect: _d(ao['directLightAffect'] ?? 0.0),
    ambientOcclusionMultiBounce: _d(ao['multiBounce'] ?? 0.0),
    ambientOcclusionSampleCount: (ao['sampleCount'] as num?)?.toInt() ?? 16,
    ambientOcclusionSliceCount: (ao['sliceCount'] as num?)?.toInt() ?? 3,
    ambientOcclusionStepsPerSlice: (ao['stepsPerSlice'] as num?)?.toInt() ?? 3,
    ambientOcclusionVisibilityBitmask:
        ao['visibilityBitmask'] as bool? ?? false,
    ambientOcclusionThickness: _d(ao['thickness'] ?? 0.5),
    ambientOcclusionThicknessHeuristic: _d(ao['thicknessHeuristic'] ?? 0.004),
    ambientOcclusionBentNormals: ao['bentNormals'] as bool? ?? false,
    ambientOcclusionIndirectLight: _d(ao['indirectLight'] ?? 0.0),
    ambientOcclusionHalfResolution: ao['halfResolution'] as bool? ?? true,
    ambientOcclusionDepthMipChain: ao['depthMipChain'] as bool? ?? false,
    ambientOcclusionSpecularMode: ao['specularMode'] as String? ?? 'none',
    globalIlluminationEnabled: gi['enabled'] as bool? ?? false,
    globalIlluminationVolumeMode: gi['volumeMode'] as String? ?? 'followCamera',
    globalIlluminationResolution: _effectVec(
      gi['resolution'],
      Vector3(16, 8, 16),
    ),
    globalIlluminationExtents: _effectVec(gi['extents'], Vector3(20, 10, 20)),
    globalIlluminationIntensity: _d(gi['intensity'] ?? 1.0),
    globalIlluminationHysteresis: _d(gi['hysteresis'] ?? 0.95),
    globalIlluminationShadowBias: _d(gi['shadowBias'] ?? 0.3),
    globalIlluminationVisibility: _d(gi['visibility'] ?? 0.7),
    globalIlluminationVisibilityBias: _d(gi['visibilityBias'] ?? 0.08),
    globalIlluminationProbeUpdateBudget:
        (gi['probeUpdateBudget'] as num?)?.toInt() ?? 0,
    globalIlluminationInjectionResolution:
        gi['injectionResolution'] as String? ?? 'eighth',
    globalIlluminationFireflyClamp: _d(gi['fireflyClamp'] ?? 8.0),
    globalIlluminationEmissiveBoost: _d(gi['emissiveBoost'] ?? 1.0),
    globalIlluminationUpdateWhenIdleOnly:
        gi['updateWhenIdleOnly'] as bool? ?? false,
    globalIlluminationBakeOnly: gi['bakeOnly'] as bool? ?? false,
    temporalAntiAliasingEnabled: taa['enabled'] as bool? ?? false,
    temporalAntiAliasingMinimumCurrentWeight: _d(
      taa['minimumCurrentWeight'] ?? 0.1,
    ),
    temporalAntiAliasingVarianceGamma: _d(taa['varianceGamma'] ?? 1.0),
    temporalAntiAliasingSharpness: _d(taa['sharpness'] ?? 0.0),
    temporalAntiAliasingJitterSequenceLength:
        (taa['jitterSequenceLength'] as num?)?.toInt() ?? 16,
    temporalAntiAliasingJitterScale: _d(taa['jitterScale'] ?? 1.0),
    temporalAntiAliasingObjectMotion: taa['objectMotion'] as bool? ?? true,
    temporalAntiAliasingSkinnedMotion: taa['skinnedMotion'] as bool? ?? true,
    screenSpaceReflectionsEnabled: ssr['enabled'] as bool? ?? false,
    screenSpaceReflectionsIntensity: _d(ssr['intensity'] ?? 1.0),
    screenSpaceReflectionsMaxDistance: _d(ssr['maxDistance'] ?? 24.4),
    screenSpaceReflectionsThickness: _d(ssr['thickness'] ?? 0.46),
    screenSpaceReflectionsStride: _d(ssr['stride'] ?? 9.0),
    screenSpaceReflectionsMaxSteps: (ssr['maxSteps'] as num?)?.toInt() ?? 90,
    screenSpaceReflectionsBlur: _d(ssr['blur'] ?? 0.3),
    screenSpaceReflectionsDistanceFadeStart: _d(
      ssr['distanceFadeStart'] ?? 0.0,
    ),
    screenSpaceReflectionsResolutionScale: _d(ssr['resolutionScale'] ?? 1.0),
    fogEnabled: fog['enabled'] as bool? ?? false,
    fogMode: fog['mode'] as String? ?? 'exponential',
    fogColor: _effectVec(fog['color'], Vector3(0.6, 0.7, 0.8)),
    fogSkyColorInfluence: _d(fog['skyColorInfluence'] ?? 0.0),
    fogDensity: _d(fog['density'] ?? 0.02),
    fogStart: _d(fog['start'] ?? 0.0),
    fogEnd: _d(fog['end'] ?? 200.0),
    fogMaxOpacity: _d(fog['maxOpacity'] ?? 1.0),
    fogCutoffDistance: _d(fog['cutoffDistance'] ?? 0.0),
    fogHeight: _d(fog['height'] ?? 0.0),
    fogHeightFalloff: _d(fog['heightFalloff'] ?? 0.0),
    fogSunInScatter: _d(fog['sunInScatter'] ?? 0.0),
    fogSunInScatterExponent: _d(fog['sunInScatterExponent'] ?? 8.0),
    godRaysEnabled: rays['enabled'] as bool? ?? false,
    godRaysIntensity: _d(rays['intensity'] ?? 1.0),
    godRaysDensity: _d(rays['density'] ?? 0.5),
    godRaysAnisotropy: _d(rays['anisotropy'] ?? 0.7),
    godRaysStepCount: (rays['stepCount'] as num?)?.toInt() ?? 24,
    godRaysMaxDistance: _d(rays['maxDistance'] ?? 200.0),
    godRaysJitter: _d(rays['jitter'] ?? 1.0),
    godRaysColor: _effectVec(rays['color'], Vector3.all(1.0)),
    depthOfFieldEnabled: dof['enabled'] as bool? ?? false,
    depthOfFieldFocusDistance: _d(dof['focusDistance'] ?? 10.0),
    depthOfFieldFStop: _d(dof['fStop'] ?? 2.8),
    depthOfFieldFocalLength: _d(dof['focalLength'] ?? 0.0),
    depthOfFieldSensorHeight: _d(dof['sensorHeight'] ?? 0.024),
    depthOfFieldBlurScale: _d(dof['blurScale'] ?? 1.0),
    depthOfFieldMaxForegroundBlur: _d(dof['maxForegroundBlur'] ?? 24.0),
    depthOfFieldMaxBackgroundBlur: _d(dof['maxBackgroundBlur'] ?? 32.0),
    depthOfFieldBladeCount: (dof['bladeCount'] as num?)?.toInt() ?? 0,
    depthOfFieldBladeRotation: _d(dof['bladeRotation'] ?? 0.0),
    depthOfFieldBladeCurvature: _d(dof['bladeCurvature'] ?? 0.0),
    depthOfFieldQuality: dof['quality'] as String? ?? 'medium',
    autoExposureEnabled: auto['enabled'] as bool? ?? false,
    autoExposureStrength: _d(auto['strength'] ?? 0.55),
    autoExposureCompensation: _d(auto['compensation'] ?? 0.0),
    autoExposureMinEv: _d(auto['minEv'] ?? -4.0),
    autoExposureMaxEv: _d(auto['maxEv'] ?? 4.0),
    autoExposureSpeedUp: _d(auto['speedUp'] ?? 3.0),
    autoExposureSpeedDown: _d(auto['speedDown'] ?? 1.0),
  );
}

ResourceSpec _decodeResource(LocalId id, Map<String, dynamic> json) {
  final kind = json['kind'] as String;
  switch (kind) {
    case 'geometry':
      return GeometryResource(
        id,
        vertices: json['vertices'] != null
            ? LocalId.parse(json['vertices'] as String)
            : null,
        indices: json['indices'] != null
            ? LocalId.parse(json['indices'] as String)
            : null,
        procedural: json['procedural'] != null
            ? _decodeProcedural(
                Map<String, dynamic>.from(json['procedural'] as Map),
              )
            : null,
        bounds: _decodeBounds(json['bounds']),
        topology: json['topology'] as String? ?? 'triangle',
        morphTargets: _decodeMorphTargets(json['morphTargets']),
        legacyWinding: json['legacyWinding'] == true,
      );
    case 'texture':
      return TextureResource(
        id,
        payload: json['payload'] != null
            ? LocalId.parse(json['payload'] as String)
            : null,
        asset: json['ref'] != null ? AssetRef(json['ref'] as String) : null,
        content: json['content'] as String? ?? 'color',
      );
    case 'renderTexture':
      return RenderTextureResource(
        id,
        width: json['width'] as int,
        height: json['height'] as int,
        update: json['update'] as String? ?? 'everyFrame',
        intervalMilliseconds: json['intervalMilliseconds'] as int?,
        filter: json['filter'] as String? ?? 'linear',
        wrap: json['wrap'] as String? ?? 'clampToEdge',
      );
    case 'material':
      return MaterialResource(
        id,
        type: json['type'] as String,
        name: json['name'] as String? ?? '',
        asset: json['ref'] != null ? AssetRef(json['ref'] as String) : null,
        properties: _decodeProperties(json['properties']),
      );
    case 'environment':
      return EnvironmentResource(
        id,
        name: json['name'] as String? ?? '',
        environment: _decodeEnvironment(json['environment']),
        environmentIntensity: _d(json['environmentIntensity'] ?? 1.0),
        exposure: _d(json['exposure'] ?? 1.0),
        toneMapping: json['toneMapping'] as String? ?? 'pbrNeutral',
        agxWhite: _d(json['agxWhite'] ?? 16.29),
        agxContrast: _d(json['agxContrast'] ?? 1.25),
        environmentRotationY: _d(json['environmentRotationY'] ?? 0.0),
        radianceCubeSize: (json['radianceCubeSize'] as num?)?.toInt(),
        skybox: _decodeSkybox(json['skybox']),
        skyEnvironment: _decodeSkyEnvironment(json['skyEnvironment']),
        effects: _decodeEnvironmentEffects(json['effects']),
        overridesEffects: json.containsKey('effects'),
      );
    default:
      throw FsceneFormatException('Unknown resource kind: $kind');
  }
}

Map<String, dynamic> _encodeProcedural(ProceduralGeometry p) => switch (p) {
  CuboidGeometrySpec(:final extents, :final debugColors) => {
    'shape': 'cuboid',
    'extents': [extents.x, extents.y, extents.z],
    if (debugColors) 'debugColors': true,
  },
  PlaneGeometrySpec(
    :final width,
    :final depth,
    :final segmentsX,
    :final segmentsZ,
  ) =>
    {
      'shape': 'plane',
      'width': width,
      'depth': depth,
      'segmentsX': segmentsX,
      'segmentsZ': segmentsZ,
    },
  SphereGeometrySpec(:final radius, :final segments, :final rings) => {
    'shape': 'sphere',
    'radius': radius,
    'segments': segments,
    'rings': rings,
  },
  TorusGeometrySpec(
    :final radius,
    :final tubeRadius,
    :final radialSegments,
    :final tubularSegments,
  ) =>
    {
      'shape': 'torus',
      'radius': radius,
      'tubeRadius': tubeRadius,
      'radialSegments': radialSegments,
      'tubularSegments': tubularSegments,
    },
  CylinderGeometrySpec(
    :final bottomRadius,
    :final topRadius,
    :final height,
    :final radialSegments,
    :final heightSegments,
    :final bottomCap,
    :final topCap,
  ) =>
    {
      'shape': 'cylinder',
      'bottomRadius': bottomRadius,
      'topRadius': topRadius,
      'height': height,
      'radialSegments': radialSegments,
      'heightSegments': heightSegments,
      'bottomCap': bottomCap,
      'topCap': topCap,
    },
  CapsuleGeometrySpec(
    :final radius,
    :final height,
    :final radialSegments,
    :final capRings,
  ) =>
    {
      'shape': 'capsule',
      'radius': radius,
      'height': height,
      'radialSegments': radialSegments,
      'capRings': capRings,
    },
  DiscGeometrySpec(:final radius, :final segments) => {
    'shape': 'disc',
    'radius': radius,
    'segments': segments,
  },
  WedgeGeometrySpec(:final size) => {
    'shape': 'wedge',
    'size': [size.x, size.y, size.z],
  },
  TerrainGeometrySpec(
    :final width,
    :final depth,
    :final columns,
    :final rows,
    :final amplitude,
    :final frequency,
    :final octaves,
    :final seed,
    :final heights,
  ) =>
    {
      'shape': 'terrain',
      if (heights != null) 'heights': heights.toToken(),
      'width': width,
      'depth': depth,
      'columns': columns,
      'rows': rows,
      'amplitude': amplitude,
      'frequency': frequency,
      'octaves': octaves,
      'seed': seed,
    },
  IcosphereGeometrySpec(:final radius, :final subdivisions) => {
    'shape': 'icosphere',
    'radius': radius,
    'subdivisions': subdivisions,
  },
};

ProceduralGeometry _decodeProcedural(Map<String, dynamic> json) {
  final shape = json['shape'] as String;
  switch (shape) {
    case 'cuboid':
      final e = json['extents'] as List;
      return CuboidGeometrySpec(
        extents: Vector3(_d(e[0]), _d(e[1]), _d(e[2])),
        debugColors: json['debugColors'] as bool? ?? false,
      );
    case 'plane':
      return PlaneGeometrySpec(
        width: _d(json['width'] ?? 1.0),
        depth: _d(json['depth'] ?? 1.0),
        segmentsX: json['segmentsX'] as int? ?? 1,
        segmentsZ: json['segmentsZ'] as int? ?? 1,
      );
    case 'sphere':
      return SphereGeometrySpec(
        radius: _d(json['radius'] ?? 0.5),
        segments: json['segments'] as int? ?? 32,
        rings: json['rings'] as int? ?? 16,
      );
    case 'torus':
      return TorusGeometrySpec(
        radius: _d(json['radius'] ?? 0.5),
        tubeRadius: _d(json['tubeRadius'] ?? 0.15),
        radialSegments: json['radialSegments'] as int? ?? 32,
        tubularSegments: json['tubularSegments'] as int? ?? 16,
      );
    case 'cylinder':
      return CylinderGeometrySpec(
        bottomRadius: _d(json['bottomRadius'] ?? 0.5),
        topRadius: _d(json['topRadius'] ?? 0.5),
        height: _d(json['height'] ?? 1.0),
        radialSegments: json['radialSegments'] as int? ?? 32,
        heightSegments: json['heightSegments'] as int? ?? 1,
        bottomCap: json['bottomCap'] as bool? ?? true,
        topCap: json['topCap'] as bool? ?? true,
      );
    case 'capsule':
      return CapsuleGeometrySpec(
        radius: _d(json['radius'] ?? 0.5),
        height: _d(json['height'] ?? 1.0),
        radialSegments: json['radialSegments'] as int? ?? 32,
        capRings: json['capRings'] as int? ?? 8,
      );
    case 'disc':
      return DiscGeometrySpec(
        radius: _d(json['radius'] ?? 0.5),
        segments: json['segments'] as int? ?? 32,
      );
    case 'wedge':
      final size = json['size'];
      return WedgeGeometrySpec(
        size: size is List && size.length == 3
            ? Vector3(_d(size[0]), _d(size[1]), _d(size[2]))
            : Vector3(1, 1, 1),
      );
    case 'terrain':
      return TerrainGeometrySpec(
        width: _d(json['width'] ?? 64.0),
        depth: _d(json['depth'] ?? 64.0),
        columns: json['columns'] as int? ?? 65,
        rows: json['rows'] as int? ?? 65,
        amplitude: _d(json['amplitude'] ?? 8.0),
        frequency: _d(json['frequency'] ?? 0.02),
        octaves: json['octaves'] as int? ?? 4,
        seed: json['seed'] as int? ?? 1337,
        heights: json['heights'] is String
            ? LocalId.parse(json['heights'] as String)
            : null,
      );
    case 'icosphere':
      return IcosphereGeometrySpec(
        radius: _d(json['radius'] ?? 0.5),
        subdivisions: json['subdivisions'] as int? ?? 2,
      );
    default:
      throw FsceneFormatException('Unknown procedural geometry shape: $shape');
  }
}

BoundsSpec? _decodeBounds(Object? json) {
  if (json == null) return null;
  final m = json as Map;
  final min = m['min'] as List;
  final max = m['max'] as List;
  return BoundsSpec(
    min: Vector3(_d(min[0]), _d(min[1]), _d(min[2])),
    max: Vector3(_d(max[0]), _d(max[1]), _d(max[2])),
  );
}

MorphTargetsSpec? _decodeMorphTargets(Object? json) {
  if (json == null) return null;
  final m = json as Map;
  return MorphTargetsSpec(
    deltas: LocalId.parse(m['deltas'] as String),
    targetCount: m['targetCount'] as int,
    hasNormalDeltas: m['normals'] as bool? ?? false,
    hasTangentDeltas: m['tangents'] as bool? ?? false,
    targetNames: [
      for (final name in (m['names'] as List? ?? const [])) name as String,
    ],
    defaultWeights: [
      for (final weight in (m['weights'] as List? ?? const []))
        _d(weight as num),
    ],
  );
}

SkinSpec _decodeSkin(LocalId id, Map<String, dynamic> json) => SkinSpec(
  id,
  joints: [
    for (final j in (json['joints'] as List? ?? const []))
      LocalId.parse(j as String),
  ],
  inverseBindMatrices: LocalId.parse(json['inverseBindMatrices'] as String),
  skeleton: json['skeleton'] != null
      ? LocalId.parse(json['skeleton'] as String)
      : null,
);

AnimationSpec _decodeAnimation(LocalId id, Map<String, dynamic> json) =>
    AnimationSpec(
      id,
      name: json['name'] as String? ?? '',
      channels: [
        for (final ch in (json['channels'] as List? ?? const []))
          _decodeChannel(Map<String, dynamic>.from(ch as Map)),
      ],
    );

AnimationChannelSpec _decodeChannel(Map<String, dynamic> json) =>
    AnimationChannelSpec(
      target: LocalId.parse(json['target'] as String),
      targetName: json['targetName'] as String?,
      property: AnimationProperty.values.byName(json['property'] as String),
      timeline: LocalId.parse(json['timeline'] as String),
      keyframes: LocalId.parse(json['keyframes'] as String),
    );

PayloadSpec _decodePayload(LocalId id, Map<String, dynamic> json) =>
    PayloadSpec(
      id,
      encoding: PayloadEncoding.values.byName(json['encoding'] as String),
      layout: json['layout'] as String?,
      format: json['format'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      length: json['length'] as int?,
    );

StageMetadata _decodeStage(Map<String, dynamic> json) => StageMetadata(
  antiAliasingMode: json['antiAliasing'] as String? ?? 'auto',
  renderScale: _d(json['renderScale'] ?? 1.0),
  filterQuality: json['filterQuality'] as String? ?? 'medium',
  environmentRef: json['environmentRef'] != null
      ? LocalId.parse(json['environmentRef'] as String)
      : null,
);

SkyboxSpec? _decodeSkybox(Object? json) {
  if (json == null) return null;
  final m = json as Map;
  final source = _decodeSkySource(m['source']);
  if (source == null) return null;
  return SkyboxSpec(source, intensity: _d(m['intensity'] ?? 1.0));
}

SkyEnvironmentSpec? _decodeSkyEnvironment(Object? json) {
  if (json == null) return null;
  final m = json as Map;
  final source = _decodeSkySource(m['source']);
  if (source == null) return null;
  return SkyEnvironmentSpec(
    source,
    refresh: m['refresh'] as String? ?? 'manual',
    intervalSeconds: _d(m['intervalSeconds'] ?? 1.0),
    faceResolution: (m['faceResolution'] as num?)?.toInt() ?? 128,
    equirectWidth: (m['equirectWidth'] as num?)?.toInt() ?? 512,
    sunLight: m['sunLight'] != null
        ? _decodeSunLight(m['sunLight'] as Map)
        : (m['castShadows'] == true ? SunLightSpec() : null),
  );
}

SunLightSpec _decodeSunLight(Map<dynamic, dynamic> m) => SunLightSpec(
  castsShadow: m['castsShadow'] as bool? ?? true,
  intensityScale: _d(m['intensityScale'] ?? 1.0),
  priority: (m['priority'] as num?)?.toInt() ?? 0,
  cacheStaticShadows: m['cacheStaticShadows'] as bool? ?? true,
  shadowSoftness: _d(m['shadowSoftness'] ?? 0.08),
  shadowMaxDistance: _d(m['shadowMaxDistance'] ?? 150.0),
  shadowCascadeCount: (m['shadowCascadeCount'] as num?)?.toInt() ?? 4,
  shadowMapResolution: (m['shadowMapResolution'] as num?)?.toInt() ?? 1024,
  shadowDepthBias: _d(m['shadowDepthBias'] ?? 0.02),
  shadowNormalBias: _d(m['shadowNormalBias'] ?? 0.02),
  shadowFadeRange: _d(m['shadowFadeRange'] ?? 2.0),
  shadowCascadeSplitLambda: _d(m['shadowCascadeSplitLambda'] ?? 0.6),
  shadowAmbientStrength: _d(m['shadowAmbientStrength'] ?? 0.0),
  shadowFilter: m['shadowFilter'] as String? ?? 'rotatedPoisson',
  contactShadows: m['contactShadows'] as bool? ?? false,
  contactShadowDistance: _d(m['contactShadowDistance'] ?? 0.3),
  angularRadius: _d(m['angularRadius'] ?? 0.005),
  shadowCasterFaces: m['shadowCasterFaces'] as String? ?? 'front',
);

SkySourceSpec? _decodeSkySource(Object? json) {
  if (json == null) return null;
  final m = json as Map;
  switch (m['type']) {
    case 'environment':
      return EnvironmentSkySpec(blurriness: _d(m['blurriness'] ?? 0.0));
    case 'fmat':
      return FmatSkySpec(
        AssetRef(m['ref'] as String),
        properties: {
          for (final e in ((m['properties'] as Map?) ?? const {}).entries)
            e.key as String: decodePropertyValue(e.value),
        },
      );
    case 'gradient':
      final s = GradientSkySpec();
      _setVec3(m['zenithColor'], (v) => s.zenithColor = v);
      _setVec3(m['horizonColor'], (v) => s.horizonColor = v);
      _setVec3(m['groundColor'], (v) => s.groundColor = v);
      _setVec3(m['sunDirection'], (v) => s.sunDirection = v);
      _setVec3(m['sunColor'], (v) => s.sunColor = v);
      if (m['sunSharpness'] != null) s.sunSharpness = _d(m['sunSharpness']);
      return s;
    case 'physical':
      final s = PhysicalSkySpec();
      _setVec3(m['sunDirection'], (v) => s.sunDirection = v);
      if (m['sunAngularRadius'] != null) {
        s.sunAngularRadius = _d(m['sunAngularRadius']);
      }
      if (m['rayleighCoefficient'] != null) {
        s.rayleighCoefficient = _d(m['rayleighCoefficient']);
      }
      _setVec3(m['rayleighColor'], (v) => s.rayleighColor = v);
      if (m['mieCoefficient'] != null) {
        s.mieCoefficient = _d(m['mieCoefficient']);
      }
      if (m['mieEccentricity'] != null) {
        s.mieEccentricity = _d(m['mieEccentricity']);
      }
      _setVec3(m['mieColor'], (v) => s.mieColor = v);
      if (m['turbidity'] != null) s.turbidity = _d(m['turbidity']);
      _setVec3(m['groundColor'], (v) => s.groundColor = v);
      if (m['energy'] != null) s.energy = _d(m['energy']);
      return s;
    case 'weather':
      final s = WeatherSkySpec();
      _setVec3(m['sunDirection'], (v) => s.sunDirection = v);
      if (m['sunAngularRadius'] != null) {
        s.sunAngularRadius = _d(m['sunAngularRadius']);
      }
      if (m['rayleighCoefficient'] != null) {
        s.rayleighCoefficient = _d(m['rayleighCoefficient']);
      }
      _setVec3(m['rayleighColor'], (v) => s.rayleighColor = v);
      if (m['mieCoefficient'] != null) {
        s.mieCoefficient = _d(m['mieCoefficient']);
      }
      if (m['mieEccentricity'] != null) {
        s.mieEccentricity = _d(m['mieEccentricity']);
      }
      _setVec3(m['mieColor'], (v) => s.mieColor = v);
      if (m['turbidity'] != null) s.turbidity = _d(m['turbidity']);
      _setVec3(m['groundColor'], (v) => s.groundColor = v);
      if (m['energy'] != null) s.energy = _d(m['energy']);
      if (m['coverage'] != null) s.coverage = _d(m['coverage']);
      if (m['density'] != null) s.density = _d(m['density']);
      if (m['altitude'] != null) s.altitude = _d(m['altitude']);
      if (m['detail'] != null) s.detail = _d(m['detail']);
      if (m['softness'] != null) s.softness = _d(m['softness']);
      if (m['seed'] is num) s.seed = (m['seed'] as num).toInt();
      final wind = m['wind'];
      if (wind is List && wind.length >= 2) {
        s.wind = Vector2(_d(wind[0]), _d(wind[1]));
      }
      _setVec3(m['cloudColor'], (v) => s.cloudColor = v);
      if (m['cloudShading'] != null) {
        s.cloudShading = _d(m['cloudShading']);
      }
      if (m['stormDarkening'] != null) {
        s.stormDarkening = _d(m['stormDarkening']);
      }
      return s;
    default:
      return null;
  }
}

void _setVec3(Object? json, void Function(Vector3) assign) {
  if (json is! List || json.length < 3) return;
  assign(Vector3(_d(json[0]), _d(json[1]), _d(json[2])));
}

EnvironmentSpec _decodeEnvironment(Object? json) {
  if (json == null) return const StudioEnvironment();
  final m = json as Map;
  switch (m['type']) {
    case 'asset':
      return AssetEnvironment(AssetRef(m['ref'] as String));
    case 'payload':
      return PayloadEnvironment(LocalId.parse(m['payload'] as String));
    case 'empty':
      return const EmptyEnvironment();
    case 'constant':
      final color = m['color'] as List;
      return ConstantEnvironment(
        Vector3(_d(color[0]), _d(color[1]), _d(color[2])),
      );
    case 'studio':
    default:
      return const StudioEnvironment();
  }
}

double _d(Object? v) => (v as num).toDouble();
