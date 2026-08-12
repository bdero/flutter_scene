import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/texture/compressed_texture.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/texture/ktx2_image.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Side length of the captured render, in logical pixels. Fixed for
/// determinism (independent of window size).
const int kSmokeSize = 512;

/// Distinctive background behind the scene so the sanity assertions can tell
/// rendered geometry from empty space.
const Color kSmokeClear = Color(0xFFFF00FF); // magenta

/// Key on the [RepaintBoundary] wrapping the scene, used by the integration
/// test to capture the rendered frame.
final GlobalKey smokeSceneKey = GlobalKey();

/// A deterministic smoke scene: a builder that produces a [Scene] and the
/// camera to view it from. No animation, no wall-clock input.
class SmokeScene {
  const SmokeScene(this.id, this.setup, {this.preload});

  final String id;
  final ({Scene scene, PerspectiveCamera camera}) Function() setup;
  final Future<void> Function()? preload;
}

/// The fixed three-quarter view shared by the scenes.
PerspectiveCamera _camera() => PerspectiveCamera(
  position: vm.Vector3(3, 2, 4),
  target: vm.Vector3(0, 0, 0),
);

/// A slightly elevated view for the shadow scene, framed so the small
/// ground plane stays central and the corners remain the magenta clear.
PerspectiveCamera _shadowCamera() => PerspectiveCamera(
  position: vm.Vector3(2.6, 2.4, 3.0),
  target: vm.Vector3(0, 0.25, 0),
);

Node _cuboid(vm.Vector4 baseColor, double metallic, double roughness) {
  final material = PhysicallyBasedMaterial()
    ..baseColorFactor = baseColor
    ..metallicFactor = metallic
    ..roughnessFactor = roughness
    ..vertexColorWeight = 0.0;
  return Node(mesh: Mesh(CuboidGeometry(vm.Vector3(1, 1, 1)), material))
    ..localTransform = vm.Matrix4.rotationY(0.6) * vm.Matrix4.rotationX(0.3);
}

Node _directionalLightNode(vm.Vector3 direction, DirectionalLight light) =>
    Node()..addComponent(DirectionalLightComponent.aimed(light, direction));

void _configureAmbientOcclusion(Scene scene) {
  scene.ambientOcclusion
    ..enabled = true
    ..radius = 1.0
    ..bias = 0.0
    ..horizonAngle = 0.06
    ..intensity = 1.5
    ..power = 1.5
    ..detail = 0.5
    ..directLightAffect = 0.59
    ..sampleCount = 24
    ..halfResolution = false
    ..depthMipChain = true;
}

/// A deterministic anisotropic Gaussian splat cloud (degree-1 SH) for the
/// splat smoke scene. Built from a fixed seed, so the packed data and the
/// resulting depth sort are identical across runs and backends. Splats form
/// a fuzzy spherical shell so the corners stay the magenta clear.
GaussianSplats _splatCloud() {
  const count = 2500;
  final rng = math.Random(20260705);
  final data = SplatData.zeroed(count, shDegree: 1);
  for (var i = 0; i < count; i++) {
    // A point on a fuzzy spherical shell around the origin.
    final theta = rng.nextDouble() * 2 * math.pi;
    final phi = math.acos(2 * rng.nextDouble() - 1);
    final r = 0.45 + rng.nextDouble() * 0.65;
    final sinPhi = math.sin(phi);
    final p = i * 3, q = i * 4;
    data.positions[p] = r * sinPhi * math.cos(theta);
    data.positions[p + 1] = r * math.cos(phi);
    data.positions[p + 2] = r * sinPhi * math.sin(theta);
    // Anisotropic scales plus a yaw, so the covariance projection and the
    // 2D eigendecomposition see non-circular footprints at varied angles.
    final len = 0.05 + rng.nextDouble() * 0.055;
    data.scales[p] = len * 2.4;
    data.scales[p + 1] = len * 0.8;
    data.scales[p + 2] = len;
    final yaw = rng.nextDouble() * math.pi;
    data.rotations[q + 1] = math.sin(yaw / 2);
    data.rotations[q + 3] = math.cos(yaw / 2);
    // Hue rotation by height for many distinct colors (linear space).
    final h = (data.positions[p + 1] + 1.2) / 2.4;
    data.colors[p] = 0.5 + 0.5 * math.cos(6.28318 * h);
    data.colors[p + 1] = 0.5 + 0.5 * math.cos(6.28318 * (h + 0.33));
    data.colors[p + 2] = 0.5 + 0.5 * math.cos(6.28318 * (h + 0.66));
    data.opacities[i] = 0.55 + rng.nextDouble() * 0.4;
    // A gentle view-dependent tint (degree-1 SH), small so the base color
    // leads. Exercises the SH texture fetch and evaluation branch.
    for (var c = 0; c < 3; c++) {
      for (var ch = 0; ch < 3; ch++) {
        data.sh![(i * 3 + c) * 3 + ch] = (rng.nextDouble() - 0.5) * 0.3;
      }
    }
  }
  return GaussianSplats.fromData(data);
}

/// Custom-material assets pre-loaded by [loadSmokeMaterials], so the
/// synchronous [SmokeScene] setup closures can build a [PreprocessedMaterial].
gpu.ShaderLibrary? _materialsLibrary;
Map<String, Object?>? _materialsMetadata;
PhysicallyBasedMaterial? _layeredPhysicalMaterial;
PhysicallyBasedMaterial? _transmissionPhysicalMaterial;

/// Loads the `buildMaterials` output (bundle plus parameter sidecar) once. Call
/// before pumping a scene that uses a custom material.
Future<void> loadSmokeMaterials() async {
  if (_materialsLibrary != null) return;
  _materialsLibrary = await gpu.loadShaderLibraryAsync(
    'packages/smoke_render/flutter_scene/fmat/materials/'
    'materials.shaderbundle',
  );
  final sidecar = await rootBundle.loadString(
    'packages/smoke_render/flutter_scene/fmat/materials/'
    'materials.fmat.json',
  );
  _materialsMetadata = (jsonDecode(sidecar) as Map).cast<String, Object?>();
  _rawPairLibrary = await gpu.loadShaderLibraryAsync(
    'packages/smoke_render/flutter_gpu_shaders/shaderbundles/'
    'smoke.shaderbundle',
  );
  _layeredPhysicalMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.45, 0.08, 0.03, 1.0)
    ..metallicFactor = 0.1
    ..roughnessFactor = 0.45
    ..clearcoat = 0.9
    ..clearcoatRoughness = 0.12
    ..sheenColor = vm.Vector4(0.35, 0.08, 0.03, 1.0)
    ..sheenRoughness = 0.35
    ..anisotropy = 0.55
    ..anisotropyRotation = 0.4
    ..iridescence = 0.35
    ..iridescenceThicknessMinimum = 180.0
    ..iridescenceThicknessMaximum = 360.0;
  _transmissionPhysicalMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.72, 0.92, 1.0, 1.0)
    ..metallicFactor = 0.0
    ..roughnessFactor = 0.08
    ..transmission = 0.78
    ..ior = 1.45
    ..thickness = 0.7
    ..attenuationColor = vm.Vector4(0.55, 0.85, 1.0, 1.0)
    ..attenuationDistance = 2.5
    ..dispersion = 0.25;
}

/// The hand-written shader pair pre-loaded by [loadSmokeMaterials], so the
/// synchronous scene setup can build a [ShaderMaterial] from both stages.
gpu.ShaderLibrary? _rawPairLibrary;

/// Builds a `PreprocessedMaterial` for the named `.fmat`, resolving its
/// generated vertex variants from the sidecar's variant map (as the DataAssets
/// loader does), since these scenes build the material by hand.
PreprocessedMaterial _fmatMaterial(String name) {
  final metadata = (_materialsMetadata![name] as Map).cast<String, Object?>();
  final vertexMeta = (metadata['vertex'] as Map?)?.cast<String, Object?>();
  final vertexShaders = vertexMeta == null
      ? null
      : <String, gpu.Shader>{
          for (final e in vertexMeta.entries)
            e.key: _materialsLibrary![e.value as String]!,
        };
  return PreprocessedMaterial(
    fragmentShader: _materialsLibrary![name]!,
    metadata: metadata,
    vertexShaders: vertexShaders,
  );
}

/// The skinned animated model preloaded by [loadSmokeModels], so the
/// synchronous [SmokeScene] setup closures can pose and add it.
Node? _skinnedModel;

/// Loads the skinned test model once. Call before pumping the
/// skinned_animation scene.
Future<void> loadSmokeModels() async {
  _skinnedModel ??= await Node.fromGlbAsset('assets_src/two_triangles.glb');
}

/// A flat NxN grid in the XZ plane carrying a per-vertex `phase` custom
/// attribute, for the custom-material scene.
MeshGeometry _phaseGrid() {
  const n = 24; // cells per side; (n + 1)^2 vertices
  const size = 2.2;
  final vertexCount = (n + 1) * (n + 1);
  final positions = Float32List(vertexCount * 3);
  final phase = Float32List(vertexCount);
  var v = 0;
  for (var r = 0; r <= n; r++) {
    for (var c = 0; c <= n; c++) {
      positions[v * 3] = (c / n - 0.5) * size;
      positions[v * 3 + 2] = (r / n - 0.5) * size;
      phase[v] = (r + c) * 0.6;
      v++;
    }
  }
  final indices = <int>[];
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      final i0 = r * (n + 1) + c;
      final i2 = i0 + (n + 1);
      indices.addAll([i0, i2, i0 + 1, i0 + 1, i2, i2 + 1]);
    }
  }
  // TODO(gles-swiftshader): the x86_64 SwiftShader GLES stack the Android
  // emulator uses (the CI android_gles job) mis-reads this custom vertex
  // attribute, so the material renders colorless (depth-only) there. It is
  // correct on every other backend: Metal, Vulkan, llvmpipe and ANGLE GLES,
  // WebGL2, and arm64 SwiftShader. Widening the attribute to a vec4 did not
  // help. Investigate the Impeller GLES custom-attribute path and file upstream
  // against SwiftShader if the fault is there.
  return MeshGeometry.fromArrays(positions: positions, indices: indices)
    ..setCustomAttribute('phase', phase, components: 1);
}

class _NormalsProbePass extends CustomRenderPass {
  @override
  String get name => 'normals_probe';

  @override
  RenderStage get stage => RenderStage.afterScene;

  @override
  Set<RenderInput> get inputs => const {RenderInput.normals};

  @override
  void execute(RenderPassContext context) {}
}

/// The smoke scene set. Mostly procedural for determinism; the final scenes
/// exercise a custom `.fmat` material compiled by the build hook.
final List<SmokeScene> kSmokeScenes = <SmokeScene>[
  // Diffuse-ish PBR under the default studio IBL.
  SmokeScene('pbr_cuboid', () {
    final scene = Scene();
    scene.add(_cuboid(vm.Vector4(0.85, 0.30, 0.20, 1.0), 0.1, 0.5));
    return (scene: scene, camera: _camera());
  }),
  // Exercises the full-layout camera depth prepass requested by a custom
  // normals consumer. The matching plain meshes collapse into one synthetic
  // instanced draw.
  SmokeScene('depth_post', () {
    final scene = Scene();
    scene.depthOfField
      ..enabled = true
      ..focusDistance = 5.0
      ..fStop = 5.6
      ..quality = DepthOfFieldQuality.low;
    scene.addRenderPass(_NormalsProbePass());
    final geometry = CuboidGeometry(vm.Vector3(0.65, 0.65, 0.65));
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.25, 0.65, 0.90, 1.0)
      ..metallicFactor = 0.1
      ..roughnessFactor = 0.5
      ..vertexColorWeight = 0.0;
    for (var i = -1; i <= 1; i++) {
      scene.add(
        Node(mesh: Mesh(geometry, material))
          ..localTransform = vm.Matrix4.translation(
            vm.Vector3(i * 0.85, i.abs() * -0.25, i * -0.2),
          ),
      );
    }
    return (scene: scene, camera: _camera());
  }),
  // AO over broad surfaces with contact continuing through both horizontal
  // edges. This catches screen-axis bands and viewport-edge discontinuities.
  SmokeScene('ambient_occlusion_edge', () {
    final scene = Scene();
    _configureAmbientOcclusion(scene);
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.78, 0.76, 0.72, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.9
      ..vertexColorWeight = 0.0;
    scene.add(
      Node(mesh: Mesh(PlaneGeometry(width: 8.0, depth: 2.4), material))
        ..localTransform =
            vm.Matrix4.translation(vm.Vector3(0, 0, -1.0)) *
            vm.Matrix4.rotationX(math.pi * 0.5),
    );
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(8.0, 0.35, 0.35)), material))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, -0.72, -0.82)),
    );
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0, 0, 4.0),
        target: vm.Vector3(0, 0, -1.0),
      ),
    );
  }),
  // The ground-truth occlusion method with the visibility bitmask and
  // multi-bounce enabled. Exercises the horizon-slice shader, the uint
  // bitfield path (including the manual popcount on GLES/WebGL2), and the
  // albedo-tinted bounce in the material shader. A thin bar over a plane
  // checks the constant-thickness occluder model.
  SmokeScene('ambient_occlusion_gtao', () {
    final scene = Scene();
    _configureAmbientOcclusion(scene);
    scene.ambientOcclusion
      ..method = AmbientOcclusionMethod.groundTruth
      ..radius = 0.6
      ..intensity = 1.5
      ..sliceCount = 3
      ..stepsPerSlice = 6
      ..visibilityBitmask = true
      ..thickness = 0.35
      ..multiBounce = 1.0;
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.72, 0.5, 0.34, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.9
      ..vertexColorWeight = 0.0;
    scene.add(
      Node(mesh: Mesh(PlaneGeometry(width: 8.0, depth: 2.4), material))
        ..localTransform =
            vm.Matrix4.translation(vm.Vector3(0, 0, -1.0)) *
            vm.Matrix4.rotationX(math.pi * 0.5),
    );
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(3.0, 0.12, 0.12)), material))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, -0.6, -0.9)),
    );
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(0.8, 0.8, 0.8)), material))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(-1.6, -0.5, -1.1)),
    );
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0, 0.4, 4.0),
        target: vm.Vector3(0, -0.2, -1.0),
      ),
    );
  }),
  // Rect area lights via linearly transformed cosines: a warm wide panel and
  // a cool tall panel over a glossy plane. Guards the LTC atlas tiles, the
  // edge integration, and the stretched panel reflections across backends.
  SmokeScene('area_light', () {
    final scene = Scene();
    scene.environmentIntensity = 0.05;
    // Aims a node's local +Z (the panel emission axis) at [target].
    vm.Matrix4 aim(vm.Vector3 position, vm.Vector3 target) {
      final forward = (target - position).normalized();
      final right = vm.Vector3(0, 1, 0).cross(forward)..normalize();
      final up = forward.cross(right).normalized();
      return vm.Matrix4.columns(
        vm.Vector4(right.x, right.y, right.z, 0),
        vm.Vector4(up.x, up.y, up.z, 0),
        vm.Vector4(forward.x, forward.y, forward.z, 0),
        vm.Vector4(position.x, position.y, position.z, 1),
      );
    }

    final floor = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.08, 0.08, 0.09, 1.0)
      ..metallicFactor = 0.3
      ..roughnessFactor = 0.2
      ..vertexColorWeight = 0.0;
    scene.add(Node(mesh: Mesh(PlaneGeometry(width: 4.4, depth: 3.4), floor)));
    final subject = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.8, 0.78, 0.75, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.4
      ..vertexColorWeight = 0.0;
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(0.7, 0.9, 0.7)), subject))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, 0.45, 0)),
    );
    scene.add(
      Node()
        ..addComponent(
          RectAreaLightComponent(
            RectAreaLight(
              color: vm.Vector3(1.0, 0.7, 0.4),
              intensity: 8.0,
              width: 1.6,
              height: 1.0,
            ),
          ),
        )
        ..localTransform = aim(
          vm.Vector3(-1.4, 1.3, 1.0),
          vm.Vector3(0, 0.45, 0),
        ),
    );
    scene.add(
      Node()
        ..addComponent(
          RectAreaLightComponent(
            RectAreaLight(
              color: vm.Vector3(0.35, 0.55, 1.0),
              intensity: 6.0,
              width: 0.4,
              height: 1.8,
            ),
          ),
        )
        ..localTransform = aim(
          vm.Vector3(1.5, 1.1, -0.6),
          vm.Vector3(0, 0.45, 0),
        ),
    );
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0, 1.6, 3.6),
        target: vm.Vector3(0, 0.4, 0),
      ),
    );
  }),
  // Percentage-closer soft shadows plus screen-space contact shadows. The
  // tall pillar's shadow must sharpen at its base and widen with distance
  // (the PCSS blocker search), and the floating slab must catch a soft
  // screen-space contact patch beneath its near edge. Guards the blocker
  // search, the penumbra scaling, and the contact march across backends.
  SmokeScene('soft_shadows', () {
    final scene = Scene();
    scene.add(
      _directionalLightNode(
        vm.Vector3(-0.55, -1.0, -0.3),
        DirectionalLight(
          castsShadow: true,
          shadowMaxDistance: 20.0,
          shadowFilter: DirectionalShadowFilter.pcss,
          angularRadius: 0.025,
          shadowSoftness: 0.28,
          contactShadows: true,
          contactShadowDistance: 0.6,
        ),
      ),
    );
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.75, 0.74, 0.70, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.9
      ..vertexColorWeight = 0.0;
    scene.add(
      Node(mesh: Mesh(PlaneGeometry(width: 4.0, depth: 3.2), material)),
    );
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(0.16, 2.2, 0.16)), material))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(-0.5, 1.1, 0.2)),
    );
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(1.1, 0.12, 0.8)), material))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0.7, 0.1, -0.4)),
    );
    return (scene: scene, camera: _shadowCamera());
  }),
  // Low-roughness metallic: sensitive to IBL/reflections breaking (would go
  // dark or flat).
  SmokeScene('pbr_metallic', () {
    final scene = Scene();
    scene.add(_cuboid(vm.Vector4(0.95, 0.95, 0.95, 1.0), 1.0, 0.15));
    return (scene: scene, camera: _camera());
  }),
  // Layered physical shader with several factor-only lobes enabled.
  SmokeScene('physical_layered', () {
    final scene = Scene();
    scene.add(
      Node(mesh: Mesh(SphereGeometry(radius: 0.85), _layeredPhysicalMaterial!)),
    );
    return (scene: scene, camera: _camera());
  }, preload: loadSmokeMaterials),
  // Screen-space transmission over an opaque object, including depth-driven
  // volume attenuation and RGB dispersion.
  SmokeScene('physical_transmission', () {
    final scene = Scene();
    scene.add(
      _cuboid(vm.Vector4(0.95, 0.35, 0.08, 1.0), 0.0, 0.55)
        ..localTransform =
            vm.Matrix4.translation(vm.Vector3(0, 0, -0.65)) *
            vm.Matrix4.rotationY(0.5),
    );
    scene.add(
      Node(
        mesh: Mesh(
          SphereGeometry(radius: 0.72),
          _transmissionPhysicalMaterial!,
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(0, 0, 0.45)),
    );
    scene.add(
      Node(
        mesh: Mesh(SphereGeometry(radius: 0.5), _transmissionPhysicalMaterial!),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(0.2, 0, -0.15)),
    );
    return (scene: scene, camera: _camera());
  }, preload: loadSmokeMaterials),
  // Issue #134 regression: a negative-scale (mirrored) node must render
  // right-side-out, not inside-out.
  SmokeScene('mirrored_node', () {
    final scene = Scene();
    final node = _cuboid(vm.Vector4(0.20, 0.55, 0.90, 1.0), 0.1, 0.5)
      ..localTransform =
          vm.Matrix4.rotationY(0.6) *
          vm.Matrix4.rotationX(0.3) *
          vm.Matrix4.diagonal3Values(-1.0, 1.0, 1.0);
    scene.add(node);
    return (scene: scene, camera: _camera());
  }),
  // Two instanced meshes plus a plain mesh, all sharing a lit pipeline. The
  // instanced geometries occupy separate slices of one geometry buffer arena.
  // Covers hardware instancing, arena offsets, and engine-lighting bind
  // bookkeeping between instanced and non-instanced draws.
  SmokeScene('instanced_lighting', () {
    final scene = Scene();
    final arena = GeometryBufferArena(blockSizeInBytes: 1024 * 1024);
    final cubeData = CuboidGeometry(
      vm.Vector3(0.5, 0.5, 0.5),
    ).extractMeshData();
    scene.add(
      _directionalLightNode(vm.Vector3(-0.4, -1.0, -0.35), DirectionalLight()),
    );
    // Non-instanced receiver, drawn from the same pipeline as the instances.
    scene.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 4.0, depth: 4.0),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.78, 0.78, 0.80, 1.0)
            ..metallicFactor = 0.0
            ..roughnessFactor = 0.9
            ..vertexColorWeight = 0.0,
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(0, -0.6, 0)),
    );
    // Two separate instanced meshes, so the second one draws after a
    // same-pipeline run has already started.
    for (var mesh = 0; mesh < 2; mesh++) {
      final instanced = InstancedMesh(
        geometry: MeshGeometry.fromMeshData(
          cubeData,
          bufferArena: arena,
          retainCpuData: false,
        ),
        material: PhysicallyBasedMaterial()
          ..baseColorFactor = mesh == 0
              ? vm.Vector4(0.85, 0.35, 0.20, 1.0)
              : vm.Vector4(0.20, 0.55, 0.90, 1.0)
          ..metallicFactor = 0.1
          ..roughnessFactor = 0.45
          ..vertexColorWeight = 0.0,
      );
      for (var i = 0; i < 3; i++) {
        instanced.addInstance(
          vm.Matrix4.translation(
                vm.Vector3((i - 1) * 0.85, mesh * 0.75, mesh * 0.6 - 0.3),
              ) *
              vm.Matrix4.rotationY(0.5 + i * 0.3),
        );
      }
      scene.add(Node()..addComponent(InstancedMeshComponent(instanced)));
    }
    return (scene: scene, camera: _camera());
  }),
  // A directional light casting a shadow from a floating cuboid onto a
  // ground plane. Exercises the ShadowPass (a depth-only shadow-map pass)
  // and the lit material's shadow sampling, which the other scenes don't.
  SmokeScene('directional_shadow', () {
    final scene = Scene();
    scene.add(
      _directionalLightNode(
        vm.Vector3(-0.4, -1.0, -0.35),
        DirectionalLight(castsShadow: true, shadowMaxDistance: 20.0),
      ),
    );
    // Ground plane (receiver), centered at the origin in the XZ plane.
    scene.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 3.0, depth: 3.0),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.78, 0.78, 0.80, 1.0)
            ..metallicFactor = 0.0
            ..roughnessFactor = 0.9
            ..vertexColorWeight = 0.0,
        ),
      ),
    );
    // Caster, floating above the plane so its shadow reads as a distinct
    // blob (a stronger visual-diff signal than a shadow merged into the base).
    final caster = _cuboid(vm.Vector4(0.85, 0.45, 0.25, 1.0), 0.0, 0.6)
      ..localTransform =
          vm.Matrix4.translation(vm.Vector3(0, 1.0, 0)) *
          vm.Matrix4.rotationY(0.6);
    scene.add(caster);
    return (scene: scene, camera: _shadowCamera());
  }),
  // A cuboid textured from an in-memory compressed KTX2 payload (mipped and
  // supercompressed), the shape an imported compressed texture takes. Covers
  // the whole compressed-texture path per backend: block encode, the device's
  // per-family transcode (or the rgba8 decode fallback), and the per-level
  // mip-chain upload. Run with --dart-define=SMOKE_FORCE_RGBA8_TEXTURES=true
  // to skip the compressed families and exercise the rgba8 decode fallback
  // (and its mip upload) on a device that supports compression.
  SmokeScene('compressed_texture', () {
    const size = 256;
    if (const bool.fromEnvironment('SMOKE_FORCE_RGBA8_TEXTURES')) {
      compressionFamilyPreference = [];
    }
    final pixels = Uint8List(size * size * 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final i = (y * size + x) * 4;
        final checker = ((x >> 3) + (y >> 3)).isEven;
        pixels[i] = checker ? 235 : 30;
        pixels[i + 1] = checker ? 120 : 160;
        pixels[i + 2] = checker ? 40 : 220;
        pixels[i + 3] = 255;
      }
    }
    final texture = gpuTextureFromKtx2Texture(
      encodeImageToKtx2(
        pixels,
        size,
        size,
        generateMips: true,
        supercompress: true,
      ),
    );
    final material = PhysicallyBasedMaterial()
      ..baseColorTexture = GpuTextureSource(texture)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.7
      ..vertexColorWeight = 0.0;
    final scene = Scene();
    scene.add(
      Node(
        mesh: Mesh(CuboidGeometry(vm.Vector3(1, 1, 1)), material),
      )..localTransform = vm.Matrix4.rotationY(0.6) * vm.Matrix4.rotationX(0.3),
    );
    return (scene: scene, camera: _camera());
  }),
  // The single custom-material scene: one .fmat that customizes BOTH the
  // vertex stage (a world-space ripple, which also displaces the shadow) and
  // the fragment color (blended from a per-vertex attribute forwarded through a
  // varying). Covers the whole custom-material path end to end: the build hook,
  // the generated fragment and vertex variants, sidecar params, a custom
  // attribute, a custom varying, and the depth/shadow variant.
  SmokeScene('fmat_custom_material', () {
    final material = _fmatMaterial('CustomMaterial')
      ..parameters.setFloat('amplitude', 0.3);
    final scene = Scene();
    scene.add(
      _directionalLightNode(
        vm.Vector3(-0.4, -1.0, -0.35),
        DirectionalLight(castsShadow: true, shadowMaxDistance: 20.0),
      ),
    );
    // Ground receiver, to catch the rippled shadow.
    scene.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 3.6, depth: 3.6),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.8, 0.8, 0.82, 1.0)
            ..metallicFactor = 0.0
            ..roughnessFactor = 0.9
            ..vertexColorWeight = 0.0,
        ),
      ),
    );
    // The custom-material hero: a grid carrying a per-vertex `phase` attribute,
    // rippled by the vertex stage and colored from the attribute. Floats above
    // the ground so its displaced shadow reads clearly.
    final grid = _phaseGrid();
    scene.add(
      Node(mesh: Mesh(grid, material))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, 1.0, 0)),
    );
    // A thick-ribbon wireframe derived from the hero grid through the public
    // readback chain (extractMeshData, extractEdges, LineSegmentsGeometry),
    // floating above it. Covers the segment-expansion vertex shader and the
    // derivation pipeline on every backend within this one scene.
    scene.add(
      Node(
        mesh: Mesh(
          LineSegmentsGeometry(
            grid.extractMeshData().extractEdges(),
            width: 0.02,
            normalOffset: 0.01,
          ),
          UnlitMaterial()..baseColorFactor = vm.Vector4(0.2, 0.9, 1.0, 1.0),
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(0, 0.5, 0)),
    );
    return (scene: scene, camera: _shadowCamera());
  }, preload: loadSmokeMaterials),
  // Distance fog: a near and a far cuboid, the far one fading toward the fog
  // color, with height fog and sun in-scatter enabled so those branches of
  // ApplyFog run too. Geometry stays central so the corners keep the clear
  // color (the frame-sanity check). One scene covers the global per-fragment
  // fog path across backends.
  SmokeScene('fog', () {
    final scene = Scene();
    scene.fog
      ..enabled = true
      ..mode = FogMode.exponential
      ..color = vm.Vector3(0.55, 0.62, 0.78)
      ..density = 0.09
      ..height = 0.0
      ..heightFalloff = 0.2
      ..sunInScatter = 0.6
      ..sunInScatterExponent = 6.0
      // Blend the fog color toward the sky sampled in the view direction so the
      // env-sampling fog path is exercised too.
      ..skyColorInfluence = 0.7;
    scene.add(
      _directionalLightNode(vm.Vector3(-0.5, -0.4, -0.75), DirectionalLight()),
    );
    // A near cuboid (lightly fogged) and a far one (heavily fogged toward the
    // fog color), so the fog gradient is a clear visual-diff signal while the
    // corners stay the magenta clear.
    scene.add(_cuboid(vm.Vector4(0.85, 0.85, 0.88, 1.0), 0.0, 0.6));
    scene.add(
      _cuboid(vm.Vector4(0.85, 0.85, 0.88, 1.0), 0.0, 0.6)
        ..localTransform =
            vm.Matrix4.translation(vm.Vector3(-1.4, 0, -12)) *
            vm.Matrix4.rotationY(0.6) *
            vm.Matrix4.rotationX(0.3),
    );
    return (scene: scene, camera: _camera());
  }),
  // Auto exposure pinned at its upper clamp: the mostly-empty background
  // meters far below the reference luminance, so the adapted factor lands on
  // exp2(maxEv) during the startup snap frames and holds there on every
  // later frame, deterministically brightening the dimly-lit cuboid. Covers
  // the whole chain (seed, downsample, adaptation, resolve composite) with a
  // clamp-pinned value that is robust to small cross-backend metering
  // differences.
  SmokeScene('auto_exposure', () {
    final scene = Scene();
    scene.environmentIntensity = 0.4;
    scene.autoExposure.enabled = true;
    scene.add(_cuboid(vm.Vector4(0.30, 0.60, 0.85, 1.0), 0.0, 0.5));
    return (scene: scene, camera: _camera());
  }),
  // A procedural anisotropic splat cloud (degree-1 SH) composited around an
  // opaque cuboid, with a crop box carving one side. One scene covers the
  // splat path across backends, the vertex-stage data texture fetch, the EWA
  // covariance projection and 2D eigendecomposition, the background depth
  // sort, premultiplied translucent blending over opaque geometry, the SH
  // texture fetch and evaluation, and the crop branch. The surrounding
  // cuboid exercises the splat/mesh depth composite (occlusion both ways).
  SmokeScene('gaussian_splats', () {
    final scene = Scene();
    scene.add(_cuboid(vm.Vector4(0.85, 0.75, 0.20, 1.0), 0.1, 0.5));
    final splats = SplatComponent(_splatCloud())
      // Exclude a slab off the -x side, so the crop branch culls real splats
      // while the central coverage the frame-sanity check samples stays high.
      ..setCropBox(
        vm.Matrix4.compose(
          vm.Vector3(-1.25, 0, 0),
          vm.Quaternion.identity(),
          vm.Vector3(0.6, 2.0, 2.0),
        ),
        mode: SplatCropMode.exclude,
      );
    scene.add(Node()..addComponent(splats));
    return (scene: scene, camera: _camera());
  }),
  // A skinned mesh (two bone-driven triangles) posed by seeking a paused
  // animation clip to a fixed mid-swing time, so the deformation is
  // deterministic. The only scene that draws through the skinned vertex
  // shader, whose joints texture rides in the vertex stage on top of the lit
  // fragment shader's full sampler set. On GLES that combination overflows
  // the per-stage texture-unit validation on drivers reporting the minimum
  // 16 fragment units (the skinned-draw crash on Windows ANGLE), so this
  // scene reproduces that crash on CI's GLES backends.
  SmokeScene('skinned_animation', () {
    final scene = Scene();
    final model = _skinnedModel!;
    scene.add(model);
    model
        .createAnimationClip(model.findAnimationByName('Metronome')!)
        .seek(0.4);
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0.8, 2.0, -6.5),
        target: vm.Vector3(0, 1.5, 0),
      ),
    );
  }, preload: loadSmokeModels),

  // A hand-written vertex/fragment pair driven through ShaderMaterial, with no
  // engine vertex shader involved. The vertex stage displaces the grid along
  // its normal from a vertex-stage uniform block, so a backend that fails to
  // compile the pair, mismatches the described layout, or drops the vertex
  // uniform draws a flat or empty surface instead of a ripple.
  SmokeScene('raw_shader_pair', () {
    final material =
        ShaderMaterial(
          vertexShader: _rawPairLibrary!['RawPairVertex']!,
          fragmentShader: _rawPairLibrary!['RawPairFragment']!,
        )..setUniformBlockFromFloats('TintInfo', [
          0.45, 0.85, 1.0, 1.0, // crest
          0.04, 0.16, 0.42, 1.0, // trough
        ]);
    // Fixed time, so the frame is deterministic.
    material.setUniformBlock(
      'RippleInfo',
      ByteData.sublistView(Float32List.fromList([1.2, 0.3, 0.22, 1.0])),
      stage: ShaderStage.vertex,
    );

    const n = 48;
    const size = 3.0;
    final count = (n + 1) * (n + 1);
    final positions = Float32List(count * 3);
    final normals = Float32List(count * 3);
    var v = 0;
    for (var r = 0; r <= n; r++) {
      for (var c = 0; c <= n; c++) {
        positions[v * 3] = (c / n - 0.5) * size;
        positions[v * 3 + 2] = (r / n - 0.5) * size;
        normals[v * 3 + 1] = 1.0;
        v++;
      }
    }
    final indices = <int>[];
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final i0 = r * (n + 1) + c;
        final i2 = i0 + (n + 1);
        indices.addAll([i0, i0 + 1, i2, i0 + 1, i2 + 1, i2]);
      }
    }
    final scene = Scene()..environmentIntensity = 0.0;
    scene.add(
      Node(
        mesh: Mesh(
          MeshGeometry.fromArrays(
            positions: positions,
            normals: normals,
            indices: indices,
          ),
          material,
        ),
      ),
    );
    return (
      scene: scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0, 2.6, 3.4),
        target: vm.Vector3.zero(),
      ),
    );
  }, preload: loadSmokeMaterials),
];

/// Renders one [SmokeScene] into a fixed-size [RepaintBoundary] over the
/// magenta clear.
/// The CPU/GPU noise parity probe (see `assets/noise_parity.fmat`). Not part
/// of [kSmokeScenes]; its test samples decoded pixel values numerically
/// instead of uploading a screenshot, so the frame never reaches the visual
/// diff service. Tone mapping and anti-aliasing are configured so the packed
/// bytes survive the display encode exactly.
({Scene scene, PerspectiveCamera camera}) buildNoiseParityScene() {
  final scene = Scene()
    ..toneMapping = ToneMappingMode.linear
    ..antiAliasingMode = AntiAliasingMode.none;
  // A camera-facing quad spanning world [-1, 1] in x/y; the material derives
  // its tile grid from world position, so no texture coordinates are needed.
  final quad = MeshGeometry.fromArrays(
    positions: Float32List.fromList([
      -1, -1, 0, 1, -1, 0, 1, 1, 0, //
      -1, -1, 0, 1, 1, 0, -1, 1, 0,
    ]),
  );
  scene.add(Node(mesh: Mesh(quad, _fmatMaterial('NoiseParity'))));
  // 45-degree vertical FOV at distance 2.6 sees a half-height of ~1.08, so
  // the quad fits with a small margin; the marker scan derives the tile
  // mapping from the frame, so exact framing does not matter.
  return (
    scene: scene,
    camera: PerspectiveCamera(
      position: vm.Vector3(0, 0, -2.6),
      target: vm.Vector3.zero(),
    ),
  );
}

class SmokeSceneView extends StatefulWidget {
  const SmokeSceneView(this.scene, {super.key});

  final SmokeScene scene;

  @override
  State<SmokeSceneView> createState() => _SmokeSceneViewState();
}

class _SmokeSceneViewState extends State<SmokeSceneView> {
  late final Scene _scene;
  late final PerspectiveCamera _camera;

  @override
  void initState() {
    super.initState();
    final setup = widget.scene.setup();
    _scene = setup.scene;
    _camera = setup.camera;

    // The first paint happens before flutter_scene's static resources finish
    // loading and is skipped; this view is otherwise static, so trigger one
    // repaint when initialization completes so the scene actually renders.
    Scene.initializeStaticResources().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: smokeSceneKey,
      child: SizedBox(
        width: kSmokeSize.toDouble(),
        height: kSmokeSize.toDouble(),
        child: Container(
          color: kSmokeClear,
          child: CustomPaint(
            size: Size.infinite,
            painter: _SmokePainter(_scene, _camera),
          ),
        ),
      ),
    );
  }
}

class _SmokePainter extends CustomPainter {
  _SmokePainter(this.scene, this.camera);

  final Scene scene;
  final PerspectiveCamera camera;

  @override
  void paint(Canvas canvas, Size size) {
    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
