# What exists in flutter_scene

Complete public API inventory (package version 0.22.0). flutter_scene has lights, shadows, PBR
materials, instancing, LOD, skeletal animation, and a full post-processing stack. If you think a
feature is missing, it is almost certainly here under the name below. Look before you hand-roll.

The public surface is the explicit `show` lists in `lib/scene.dart` (plus the separate barrels
`gpu.dart`, `fscene.dart`, `build_hooks.dart`, `physics.dart`, `audio.dart`). Nothing under
`lib/src` is public unless a barrel shows it.

Import:
```dart
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;   // NOT vector_math_64
```

---

## Node and scene graph

`Node` (`base class Node implements SceneGraph`). Construct `Node({String name = '', Matrix4?
localTransform, Mesh? mesh})`. A non-null `mesh` is wrapped in a `MeshComponent`.

Transform API (0.22.0 added the component properties; older docs say only `localTransform` exists):

| Member | Type | Notes |
| --- | --- | --- |
| `position` | `Vector3` get/set | Getter returns a copy; editing the copy in place throws in debug. Assign to move. |
| `rotation` | `Quaternion` get/set | Same copy rule. |
| `scale` | `Vector3` get/set | Same copy rule. |
| `localTransform` | `Matrix4` get/set | Getter returns the LIVE matrix; in-place edit throws in debug on next read. Assign a fresh matrix. |
| `mutateLocalTransform(void Function(Matrix4) edit)` | method | Edits in place AND dirties the cache. Correct raw-matrix path. |
| `globalTransform` | `Matrix4` get/set | Cached world transform; setter solves for the needed local. |
| `lookAt(target, {up})` | method | Orients the node's forward axis (local +Z) at a world-space target; preserves world position and scale. |
| `lookAtFrom(eye, target, {up})` | method | Positions at `eye` and aims +Z at `target` in one call (the imperative camera one-liner). |
| `Node.lookAtTransform(eye, target, {up})` | static -> `Matrix4` | The `lookAt` basis as a local transform, for `Node(localTransform:)` and declarative `transform:`. |

+Z is the forward axis engine-wide (cameras, directional/spot lights, imported models), so the
lookAt helpers aim any of them. Compose a plain matrix with `vm.Matrix4.translation(v)`,
`vm.Matrix4.rotationY(a)`, `vm.Matrix4.compose(t, q, s)`. There is no `translate`/`rotateX` on Node.

Hierarchy (`SceneGraph` is a mixin): `add`, `addAll`, `addMesh`, `remove`, `removeAll`. `add` throws
if the child already has a parent. `parent`, `children`, `detach()`, `getRoot()`, `getDepth()`.

Lookup: `getChildByName(name, {excludeAnimationPlayers})`, `getChildByNamePath`,
`getChildByIndexPath`, static `getNamePath`/`getIndexPath`, `meshNodes`, `clone({recursive = true})`.

Per-node flags: `visible` (true), `frustumCulled` (true), `layers` (`kRenderLayerDefault`, a 32-bit
mask, NOT inherited), `castsShadows` (true, not inherited), `shadowStatic` (false), `raycastable`
(true), `highlightColor` (`Vector4?`), `skin` (`Skin?`, set by importers).

Bounds: `combinedLocalBounds`, `combinedWorldBounds`, `markBoundsDirty()`, `isVisibleTo(camera,
size)`. A `null` bounds means always-visible.

Loading models (see Assets): `Node.fromGlbAsset`, `Node.fromGlbBytes`, `Node.fromGltfBytes`.

Geometry readback: `extractMeshData({Matrix4? transform})` flattens the subtree to one `MeshData`.
Throws on instanced meshes, non-triangle primitives, caller-managed geometry, or an empty subtree.

`Scene` (`base class Scene implements SceneGraph`, cannot be subclassed). See the render/lighting/
post sections. `Mesh(geometry, material)`/`Mesh.primitives({primitives})`; `MeshPrimitive(geometry,
material)`; `Mesh.clone()` (shallow, shares geometry+material); `Mesh.localBounds`,
`Mesh.markLocalBoundsDirty()`.

### Camera

- `PerspectiveCamera({double fovRadiansY = 45 * degrees2Radians, Vector3? position /*(0,0,-5)*/,
  Vector3? target /*(0,0,0)*/, Vector3? up /*(0,1,0)*/, double fovNear = 0.1, double fovFar =
  1000.0})`. Field names are `fovNear`/`fovFar`, NOT `near`/`far`.
- `PerspectiveCamera.framing(Aabb3 bounds, {direction, fovRadiansY, up, margin = 1.1})`.
- `PerspectiveProjection({fovRadiansY, near = 0.1, far = 1000.0})` and abstract `CameraProjection`,
  `Camera`. Camera helpers: `screenPointToRay`, `worldToScreen`, `getViewMatrix`, `getFrustum`.
- There is NO `OrthographicCamera`. Implement `CameraProjection`/`Camera` for other projections.
- Node-driven: `CameraComponent({CameraProjection? projection, activateOnMount = false})` ->
  `toCamera()` gives a `NodeCamera`. Camera node must not be scaled.
- Interactive cameras: `CameraController` components attached to the camera node. `OrbitCameraController`
  (turntable around `target`; `orbitBy`/`dollyBy`/`panBy`/`frame`), `FlyCameraController` (WASD + drag
  free flight; `moveVertical: false` = grounded first-person; `look`), `FollowCameraController`
  (third-person easing behind `followTarget` node; `orbitBy`/`dollyBy`). All ease with frame-rate
  independent `smoothing` (settle seconds), clamp pitch short of vertical, and write the node via
  `lookAtFrom`. Wire input with the `CameraControls({required controller, enabled, autofocus, child})`
  widget (Focus + gestures + wheel); `SceneView` has no camera-input params by design.

---

## Components

`abstract class Component`. Lifecycle hooks (exact names): `onAttach`, `onLoad` (async), `onMount`,
`update(double deltaSeconds)` (NOT `onUpdate`), `fixedUpdate(double)`, `onUnmount`, `onDetach`,
`cloneFor(Node)`. Node side: `addComponent`, `removeComponent`, `getComponent<T>()`,
`getComponents<T>()`.

| Component | Constructor/notes |
| --- | --- |
| `MeshComponent` | `MeshComponent(mesh)`; `mesh` get/set, `refreshMaterials()` |
| `InstancedMeshComponent` | `InstancedMeshComponent(instancedMesh)` |
| `LodComponent` | `LodComponent(List<LodLevel>, {lodBias = 1.0, hysteresis = 0.1, blendRange = 0.0})`; extends MeshComponent |
| `CameraComponent`, `NodeCamera` | see Camera |
| `DirectionalLightComponent` | `(light)` aims down node local +Z; `.aimed(light, localDir)`; `.fromLightDirection(light)` |
| `PointLightComponent` | `(light)`; `worldPosition` |
| `SpotLightComponent` | `(light)`; `worldPosition`, `worldDirection` |
| `RectAreaLightComponent` | `(light)`; `worldPosition`, `worldRight`, `worldUp` |
| `EnvironmentVolumeComponent` | `({required settings, shape = box, extents, radius = 5.0, blendDistance = 1.0, priority = 0.0, weight = 1.0})` |
| `ReflectionProbeComponent` | `({extents = Vector3.all(5), blendDistance = 1.0, priority = 10.0, weight = 1.0, faceResolution = 128, captureOnActivate = true})`; parallax-corrected local reflections in the box; `requestCapture()` re-captures |
| `MaterialsVariantsComponent` | No public ctor. `MaterialsVariantsComponent.of(root)`/`.allOf(root)`, then `select(name)`, `variants`, `selected` |
| `SemanticsComponent` | `({label, value, hint, button, onTap, ... boundsOverride, properties})` |
| `WidgetComponent` | `({required Widget child, required Size size, pixelRatio = 1.0, worldHeight = 1.0, update = everyFrame, input = automatic, ...})`; `.bindOnly(...)` |
| `SplatComponent` | `SplatComponent(GaussianSplats)`; `opacity`, `splatScale`, `tint`, `shDegree`, `cropBox`, `cropMode` |
| `ParticleEmitterComponent` | `({required system, SpriteMaterial? material})`; `facing`, `flipbookColumns/Rows/Blend`, `paused` |
| `MeshParticleEmitterComponent` | `({required system, required List<Geometry> geometries, required material, facing = tumble})` |
| `TrailComponent` | `({width = 0.25, lifetime = 0.6, minVertexDistance = 0.05, maxPoints = 48, ...})`; `emitting`, `clear()` |

`SemanticsComponent`, `SplatComponent`, particle emitters, `TrailComponent`, `WidgetInput`,
`MeshParticleFacing`, `LodLevel`, `EnvironmentVolumeShape` are all exported.

---

## Geometry

### Primitives (`primitives.dart`, all factory constructors, all `extends MeshGeometry`)

| Class | Constructor | Facing/notes |
| --- | --- | --- |
| `CuboidGeometry` | `CuboidGeometry(Vector3 extents, {debugColors = false})` | positional extents; box `-extents/2..+extents/2`; debugColors off |
| `WedgeGeometry` | `WedgeGeometry(Vector3 size)` | triangular prism; base on `y=0`, not Y-centered |
| `PlaneGeometry` | `({width = 1.0, depth = 1.0, segmentsX = 1, segmentsZ = 1})` | XZ plane, faces +Y; no collisionShape |
| `SphereGeometry` | `({radius = 0.5, segments = 32, rings = 16})` | UV sphere |
| `CylinderGeometry` | `({bottomRadius = 0.5, topRadius = 0.5, height = 1.0, radialSegments = 32, heightSegments = 1, bottomCap = true, topCap = true})` | topRadius 0 = cone |
| `CapsuleGeometry` | `({radius = 0.5, height = 1.0, radialSegments = 32, capRings = 8})` | `height` is the mid-section; total Y = height + 2*radius |
| `TorusGeometry` | `({radius = 0.5, tubeRadius = 0.2, radialSegments = 32, tubularSegments = 16})` | XZ plane |
| `DiscGeometry` | `({radius = 0.5, segments = 32})` | XZ, faces +Y |
| `RingGeometry` | `({innerRadius = 0.25, outerRadius = 0.5, segments = 32})` | annulus, XZ, +Y |
| `IcosphereGeometry` | `({radius = 0.5, subdivisions = 2})` | subdivided icosahedron |

Every primitive except `PlaneGeometry` has a `Shape get collisionShape`.

### Swept/procedural (sweep a `ScenePath`; also `BezierPath`, `CatmullRomPath`, `PolylinePath`)

- `RibbonGeometry(path, {width = 1.0, stations = 64, alignment = RibbonAlignment.ground, up, storage = fixed})`; `updatePath(path)`. `RibbonAlignment` = `ground` | `path`.
- `TubeGeometry(path, {radius = 0.5, radialSegments = 12, stations = 64, caps = true, storage})`.
- `ExtrudeGeometry(path, {required List<Vector2> profile, stations = 64, caps = true, storage})`.
- `PolylineGeometry(List<Vector3> points, {width = 8.0, widthMode = screenPixels, cap = butt, dash, perVertexWidth, perVertexColor})`. INERT until `updateForCamera(camera, viewportSize)` is called every frame. `PolylineWidthMode` = `screenPixels` | `worldUnits`; `PolylineCap` = `butt` | `round`; `DashPattern({dashLength, gapLength, cap})`.
- `LineSegmentsGeometry(LineSegmentData segments, {width = 0.01, normalOffset = 0.0})`. `extends Geometry`, GPU-expanded, no per-frame CPU work. For large independent-segment sets.
- `BillboardGeometry({capacity = 256})`. `floatsPerInstance = 14`; `BillboardFacing` = `spherical` | `axisLocked` | `velocityStretched`.

### MeshGeometry, GeometryBuilder, MeshData

`MeshGeometry.fromArrays({required Float32List positions, Float32List? normals, texCoords,
texCoords1, colors, tangents, List<int>? indices, primitiveType = triangle, Aabb3? bounds, storage =
fixed, GeometryBufferArena? bufferArena, retainCpuData = true})`. Components per vertex: positions 3,
normals 3, texCoords/texCoords1 2, colors/tangents 4. Omitted normals on a triangle list are
generated. Omitted indices need a vertex count divisible by 3. `bounds` skips the position scan (it
must actually cover every vertex).

`MeshGeometry.fromMeshData(MeshData data, {storage, bufferArena, retainCpuData})`.

In-place update (require `GeometryStorage.updatable`, all take `{dirtyStart, dirtyCount}`):
`updatePositions`, `updateNormals`, `updateTexCoords`, `updateTexCoords1`, `updateColors`,
`updateTangents`. `rebuild({positions, normals, ...})` may change the vertex/index count.
`applyMeshData(data)`. `GeometryStorage` = `fixed` | `updatable`.

`GeometryBuilder({deduplicate = true})`: `normal(v)`, `texCoord(v)`, `texCoord1(v)`, `color(v)`,
`tangent(v)`, `addVertex(Vector3) -> int`, `addTriangle(a, b, c)` (throws RangeError on bad index),
`packVertices()`, `build({storage, bufferArena, retainCpuData})`. Attribute setters are STICKY.
Calling `normal()` once disables generated normals for the whole mesh.

`MeshData` (isolate-transferable, pure): `MeshData({required positions, required vertexCount,
normals, ..., customAttributes})`, `MeshData.build({required positions, ...})` (derives vertexCount,
generates normals). Derivations: `triangleCount`, `triangles`, `transformed(Matrix4)` (inverse
transpose for normals; a mirror flips winding), `toTriMeshShape()` (hollow static collider),
`toConvexHullShape()` (dynamic body), `unweld({attributes})`, `extractEdges({creaseAngleDegrees})`,
static `merge(parts)`. `MeshAttributeData(data, {components})`; `UnweldAttribute` = `centroid` |
`seed` | `triangleIndex` | `barycentric`; `LineSegmentData({positions, normals})`.

`Geometry` base: `primitiveType`, `localBounds`, `localBoundingSphere`, `setLocalBounds(aabb,
sphere)`, `setVertices(BufferView, vertexCount)`, `setIndices(BufferView, indexType)`,
`setCustomAttribute(name, Float32List, {required components})` (1..4; not fetched by depth passes so
it does not affect shadows), `uploadVertexData(ByteData, vertexCount, ByteData? indices, {indexType =
int16})`, `isReadable`, `extractMeshData()`, `setVertexShader`/`setVertexShaderName`,
`setVertexLayout(descriptor, {bindsModelTransform = true})`, `draw(pass, {instanceCount = 1})`.
`SkinnedGeometry`/`UnskinnedGeometry` subclasses. `GeometryBufferArena({blockSizeInBytes = 16MB})`.

Vertex layout: unskinned 72 bytes/18 floats = position(3) normal(3) texture_coords(2)
texture_coords_1(2) color(4) tangent(4). Skinned 104 bytes/26 floats = + joints(4) weights(4). Do
not hand-pack; use `fromArrays`/`fromMeshData`/`GeometryBuilder`.

### Instancing and LOD

`InstancedMesh({required geometry, required material, cullInstances = false,
sortTransparentInstances = true})`: `instanceCount`, `addInstance(Matrix4, {Vector4? color}) -> int`
(clones the matrix), `setInstanceTransform(i, m)`, `updateInstanceTransforms(update,
{recomputeWinding = true})`, `setInstanceColor(i, color)`, `removeInstanceAt(i)`, `clearInstances()`.
Attach via `InstancedMeshComponent`.

`LodLevel({required geometry, required material, required double screenSize})` (screenSize = projected
bounding-sphere diameter as a fraction of viewport height, descending, last is the cull floor).
Attach via `LodComponent`. Shadow/depth passes always draw level 0.

---

## Materials and textures

`Material` (abstract): `name`, `doubleSided` (false), `depthBias` (0.0), `setFragmentShader`,
`setFragmentShaderName(name, {cubeName})`, `setRadianceCubeFragmentShader`, `isOpaque()`.

### UnlitMaterial

`UnlitMaterial({TextureSource? colorTexture})`. `baseColorTexture` (field name differs from the ctor
arg), `baseColorTextureTransform`, `baseColorTextureTexCoord` (0), `alphaMode` (`opaque`; `mask` not
implemented, behaves as blend), `baseColorFactor` (white), `vertexColorWeight` (1.0). Fog applies.

### PhysicallyBasedMaterial

`PhysicallyBasedMaterial({baseColorTexture, metallicRoughnessTexture, normalTexture, emissiveTexture,
occlusionTexture, EnvironmentMap? environment})`. Every texture slot is a `TextureSource?` with a
`<slot>TextureTransform` and `<slot>TextureTexCoord`.

Core: `baseColorFactor` (white), `vertexColorWeight` (1.0), `metallicFactor` (1.0), `roughnessFactor`
(1.0), `normalScale` (1.0), `emissiveFactor` (`Vector4.zero()`), `emissiveStrength` (1.0),
`occlusionStrength` (1.0), `environment` (null, falls back to `Scene.environment`), `alphaMode`
(opaque), `alphaCutoff` (0.5), `specularAntiAliasingVariance` (0.15), `specularAntiAliasingThreshold`
(0.2).

Advanced KHR_materials_* (setting any flips onto an internal physical-variant shader; each has a
`<name>Texture`): `specular` (1.0), `specularColor`, `ior` (1.5), `clearcoat` (0.0),
`clearcoatRoughness` (0.0), `clearcoatNormalScale`, `sheenColor` (zero), `sheenRoughness` (0.0),
`transmission` (0.0), `diffuseTransmission`, `diffuseTransmissionColor`, `thickness` (0.0),
`attenuationDistance` (inf), `attenuationColor`, `dispersion` (0.0), `iridescence` (0.0),
`iridescenceIor` (1.3), `iridescenceThicknessMinimum` (100.0), `iridescenceThicknessMaximum` (400.0),
`anisotropy` (0.0), `anisotropyRotation` (0.0).

`isOpaque()` is false when `transmission > 0`, `alphaMode == blend`, or `baseColorFactor.a < 1.0`.

`AlphaMode` = `opaque` | `mask` | `blend`. `TextureTransform({offset, scale, rotation})` (glTF
KHR_texture_transform order).

### SpriteMaterial

`SpriteMaterial({TextureSource? colorTexture})`: `colorTexture`, `tint` (white), `blendMode`
(`SpriteBlendMode.alpha` | `additive`), `softDepthFade` (0.0), `cameraNearFade` (0.0), `sampler`.
Always non-opaque, always cull none.

### ShaderMaterial (raw GLSL escape hatch)

`ShaderMaterial({gpu.Shader? fragmentShader, radianceCubeFragmentShader, vertexShader,
skinnedVertexShader, depthVertexShader, useEnvironment = false, cullingMode = backFace, windingOrder =
counterClockwise, isOpaqueOverride = true})`. `setVertexShader(shader, {variant = unskinned})`,
`vertexShaderFor(variant)`, `setUniformBlock(name, ByteData?, {stage = fragment})`,
`setUniformBlockFromFloats(name, List<double>, {stage})`, `getUniformBlock`, `uniformBlockNames`,
`setTexture(name, texture, {sampler, stage})` (accepts `gpu.Texture`/`Texture2D`/`RenderTexture`),
`getTexture`, `textureNames`. `ShaderStage` = `vertex` | `fragment`; `MeshVariant` = `unskinned` |
`skinned` | `depth`.

Fragment shaders MUST output linear HDR premultiplied by alpha (exposure, tone mapping, and the
display encode are applied later by the resolve pass). Same contract for `ShaderSkySource` and
`PostInsertion.beforeTonemap` effects. std140 packing is by hand.

### .fmat (declarative, recommended over ShaderMaterial)

`loadFmatMaterial(sourcePath) -> PreprocessedMaterial`, `loadFmatSky(...) -> PreprocessedSky`.
`PreprocessedMaterial`: `parameters` (`MaterialParameters`), `shadingModel`, `environment`.
`MaterialParameters` (typed, reflection-backed, throws on wrong type/name): `setFloat`, `setInt`,
`setVec2/3/4`, `setMat4`, `setColor(name, Color)`, `setTexture(name, gpu.Texture, {sampler})`,
`operator []=`, `parameterNames`, `samplerNames`, `hasUniformBlock`.

### Textures

`TextureSource` (interface): implementers are `Texture2D`, `RenderTexture`, `GpuTextureSource`. Every
built-in material slot takes a `TextureSource`, not a raw `gpu.Texture`.

`Texture2D` (factories, generates a mip chain): `Texture2D.fromPixels(Uint8List, w, h, {content =
color, sampling})`, `fromImage(ui.Image, {...})`, `fromAsset(String, {content = color, sampling,
bundle})`. `TextureContent` = `color` (sRGB) | `data` (linear, e.g. metallic-roughness/AO) | `normal`
(vector-averaged). `TextureSampling({mipmaps = true, maxMipmapLevels, minFilter = linear, magFilter =
linear, mipFilter = linear, maxAnisotropy = 8, addressMode = repeat})`.

`GpuTextureSource(gpu.Texture, {sampler})` adapts a raw texture. Barrel helpers:
`gpuTextureFromImage`, `gpuTextureFromAsset` (mipless, aliases on materials), `imageFromAsset`,
`imageFromBytes`. Cooked `.fstex`: `loadTexture(sourcePath, {package, bundle, sampling}) ->
TextureSource`, `releaseTexture`, `clearTextureCache`.

Custom-shader GPU barrel (`package:flutter_scene/gpu.dart`): `Shader`, `ShaderLibrary`,
`loadShaderLibraryAsync` (use this, not `ShaderLibrary.fromAsset` which throws on web),
`resolveShaderBundleKey`, `Texture`, `SamplerOptions`, `MinMagFilter`, `MipFilter`,
`SamplerAddressMode`, `IndexType`, `VertexFormat`, `VertexStepMode`.

---

## Lighting and environment

Lights (all in `light.dart`, all fields mutable):

- `DirectionalLight({direction /*(-0.3,-1,-0.2)*/, color, intensity = 3.0, priority = 0, castsShadow
  = false, cacheStaticShadows = true, shadowFadeRange = 2.0, shadowSoftness = 0.08, shadowCascadeCount
  = 4, shadowMaxDistance = 150.0, shadowCascadeSplitLambda = 0.6, shadowMapResolution = 1024,
  shadowDepthBias = 0.02, shadowNormalBias = 0.02, shadowAmbientStrength = 0.0, shadowFilter =
  rotatedPoisson, shadowCasterFaces = front, contactShadows = false, contactShadowDistance = 0.3,
  angularRadius = 0.005})`.
- `PointLight({color, intensity = 1.0, range = 0.0, falloffExponent = 2.0, castsShadow = false,
  shadowMapResolution = 512, shadowNear = 0.1, shadowDepthBias = 0.0, shadowNormalBias = 0.1,
  shadowSoftness = 1.0, shadowCasterFaces = front})`. Shadows render six cube faces into the shared
  atlas (a limited number of point casters per frame; the rest shade unshadowed).
- `SpotLight({color, intensity = 1.0, range = 0.0, falloffExponent = 2.0, direction /*(0,-1,0)*/,
  innerConeAngle = 0.0, outerConeAngle = pi/4, castsShadow = false, ...})`.
- `RectAreaLight({color, intensity = 1.0, width = 1.0, height = 1.0, range = 0.0})`. Local XY plane,
  emits along +Z, no shadows.
- `SunLight(SunSky source, {castsShadow = true, ...})` drives `Scene.directionalLight` from a sky.

`Node.shadowCastingMode` (`ShadowCastingMode` = `on` (default) | `off` | `doubleSided` |
`shadowsOnly`) selects how a node's meshes cast; `Node.castsShadows` is a deprecated two-state
view of it. Every light also has `shadowCasterChannelMask` (8-bit), tested against
`Node.lightChannelMask`, to drop casters from one light's map.

`ShadowCasterFaces` = `front` | `back` | `both`. `DirectionalShadowFilter` = `rotatedPoisson` |
`fixedPcf` | `pcss`. `ShadowCascade`, `Lighting` (per-draw state) are exported.

Scene lighting: `Scene.directionalLight` (`DirectionalLight?`, null = IBL only; honors `direction`;
highest-priority one gets cascaded shadows), `Scene.sunLight`, `Scene.environment` (`EnvironmentMap?`,
null falls back to `EnvironmentMap.studio()`; for genuinely no IBL use `EnvironmentMap.empty()`),
`Scene.environmentIntensity` (1.0), `Scene.environmentTransform` (`Matrix3.identity()`),
`Scene.skybox` (`Skybox?`, null = transparent), `Scene.skyEnvironment`.

### EnvironmentMap

Carries a prefiltered specular radiance atlas AND SH-9 diffuse coefficients (one texture path, no
separate radiance/irradiance). Factories: `.empty()`, `.constantDiffuse(ambientRadiance)`,
`.fromGpuTextures({required prefilteredRadiance, diffuseSphericalHarmonics, diffuseShTexture})` (the
texture must already be prefiltered), `.fromUIImages({required radianceImage, ...})`,
`.fromEquirectHdr({required Float32List linearPixels, w, h, ...})`,
`.fromEquirectImageAsset({required assetPath, maxWidth = 4096, ...})` (auto-detects .hdr/.exr/LDR),
`.fromEquirectImageBytes(...)`, `.fromSky(SkySource, {...})`, `.studio()` (zero-config default).
Deprecated: `.fromAssets` (use `.fromEquirectImageAsset`). Env images must be equirect 2:1.
`prefilterEquirectRadiance` is exported. `Scene.loadEnvironment(assetPath, {showSkybox = true,
skyBlur = 0.0, intensity, exposure, rotationY, maxWidth = 4096, bundle})` is one-call setup.

### Skybox/sky sources

`Skybox(SkySource source, {intensity = 1.0})`. `SkySource` implementers: `EnvironmentSkySource({blurriness
= 0.0})`, `ShaderSkySource({fragmentShader, fragmentShaderName, radianceCubeFragmentShader,
useEnvironment = false})`, `GradientSkySource({zenithColor, horizonColor, groundColor, sunDirection,
sunColor, sunSharpness = 400.0})`, `PhysicalSkySource({sunDirection, sunAngularRadius = 0.0175,
rayleighCoefficient = 2.0, mieCoefficient = 0.005, turbidity = 10.0, energy = 1.0, ...})`.
`SkyEnvironment(ShaderSkySource, {refresh = manual, interval, faceResolution = 128, equirectWidth =
512})`; `SkyEnvironmentRefresh` = `manual` | `interval` | `everyFrame`.

### Exposure and tone mapping

`Scene.exposure` (1.0; not 2.0), `Scene.toneMapping` (`ToneMappingMode.pbrNeutral`; also `aces`,
`reinhard`, `linear`, `agx`), `Scene.agxWhite` (16.29), `Scene.agxContrast` (1.25). Static
`Scene.physicalCameraExposure({required aperture, shutterSpeed, iso})` returns a multiplier to assign
to `exposure`.

---

## Post-processing

Every effect is a settings object on `Scene`, off by default, turned on with `enabled`. Environment
looks blend via `EnvironmentSettings` (snapshot/lerp of the whole look) and `EnvironmentVolume` /
`EnvironmentVolumeComponent` (spatial).

| Scene field | Type | Key fields (default) | Requires |
| --- | --- | --- | --- |
| `ambientOcclusion` | `AmbientOcclusionSettings` | `method` (obscurance/`groundTruth`), `radius` (0.33), `intensity` (1.0), `power` (1.5), `bentNormals` (false), `halfResolution` (true), `indirectLight` (0.0 = SSGI), `specularMode` | perspective camera |
| `screenSpaceReflections` | `ScreenSpaceReflectionsSettings` | `intensity` (1.0), `maxDistance` (24.4), `thickness` (0.46), `stride` (9.0), `maxSteps` (90), `blur` (0.3), `debugView` | perspective camera |
| `fog` | `Fog` | `mode` (`FogMode.exponential`; also none/linear/exponentialSquared), `color`, `density` (0.02), `start`/`end`, needs both `enabled` AND non-none `mode` | any camera |
| `godRays` | `GodRaysSettings` | `intensity` (1.0), `density` (0.5), `anisotropy` (0.7), `stepCount` (24), `maxDistance` (200), `color` | shadow-casting DirectionalLight + perspective camera |
| `depthOfField` | `DepthOfField` | `focusDistance` (10.0), `fStop` (2.8), `focalLength`, `sensorHeight` (0.024), `bladeCount`, `quality` (low/medium/high) | perspective camera |
| `autoExposure` | `AutoExposureSettings` | `strength` (0.55), `compensation`, `minEv` (-4), `maxEv` (4), `speedUp` (3.0), `speedDown` (1.0); multiplies on top of `exposure` | none |
| `postProcess` | `PostProcessSettings` | see below | none |

`AmbientOcclusionMethod` = `obscurance` (McGuire SAO) | `groundTruth` (GTAO). `SpecularAmbientOcclusionMode`
= `none` | `simple` | `bentCone`. `SsrDebugView` = composite/reflectedUv/hitMask/normal/confidence/depth.

`PostProcessSettings` (all sub-settings off by default; mutate the nested objects):
- `colorGrading` (`ColorGradingSettings`): `brightness` (1.0), `contrast` (1.0), `saturation` (1.0),
  `temperature`, `tint`, `lift`/`gamma`/`gain`, `lut` (`ColorLut?`, applies after tone mapping,
  independent of `enabled`), `lutBlend` (1.0).
- `chromaticAberration` (`intensity` 0.2), `vignette` (`intensity` 0.5, `radius` 0.75, `smoothness`
  0.5), `filmGrain` (`intensity` 0.3), `bloom` (`threshold` 1.0, `intensity` 0.15, `scatter` 0.7,
  and `lensFlare`: `enabled` false, `intensity` 1.0, `ghostCount` 4, `ghostSpacing` 0.3, `haloRadius`
  0.35, `haloIntensity` 1.0, `chromaticAberration` 0.005; rides the bloom, needs bloom enabled).
- `customEffects` (`List<PostEffect>`).

`ColorLut.fromCubeString`/`.fromCubeAsset` (Adobe `.cube`, edge 2..64).

Custom post: `PostEffect({gpu.Shader? fragmentShader, insertion = beforeTonemap, enabled = true,
useFrameInfo = false})`, added to `scene.postProcess.customEffects`. Engine binds `uniform sampler2D
input_color` at `in vec2 v_uv`. `PostInsertion` = `beforeTonemap` (linear HDR premultiplied) |
`afterTonemap` (display-referred).

---

## Scene, render, and widgets

`Scene()` (no args; calls `initializeStaticResources()`, needs a live Flutter GPU context). Methods:
`add`, `addAll`, `addMesh`, `remove`, `removeAll`, `update(dt)` (optional), `render(camera, canvas,
{viewport, pixelRatio})`, `renderViews(views, canvas, {region, pixelRatio})`, `warmUp(views,
{includeOffscreen})`, `raycast(ray, {maxDistance, layerMask, where, includeInvisible})`,
`raycastAll(...)`, `addRenderPass`/`removeRenderPass`, `captureRenderGraph({viewIndex, request,
timeout})`, `captureEnvironment({required position, faceResolution = 128, equirectWidth = 512,
layerMask})` -> `EnvironmentMap` (one-shot static capture; use `ReflectionProbeComponent` for a
node-anchored, parallax-corrected, auto-blended probe). Statics: `Scene.initializeStaticResources()`,
`Scene.isReadyToRender`, `Scene.physicalCameraExposure`, `Scene.isAntiAliasingModeSupported`,
`Scene.effectiveAntiAliasingMode`.

`Scene.antiAliasingMode` (`AntiAliasingMode.auto` -> msaa or fxaa; also `none`, `msaa`, `fxaa`,
`smaa`, `taa`), `Scene.smaa` (`SmaaSettings`: threshold, search steps, corner rounding),
`Scene.temporalAntiAliasing` (`TemporalAntiAliasingSettings`),
`Scene.renderScale` (1.0), `Scene.filterQuality` (`FilterQuality.medium`), `Scene.views`
(`List<RenderView>` for RenderTexture targets).

`RenderView({required Camera camera, RenderTexture? target, Rect? viewport /*normalized 0..1,
ignored when target set*/, int layerMask = kRenderLayerAll, order = 0, AntiAliasingMode?
antiAliasingMode, double? renderScale, FilterQuality? filterQuality, List<Plane> cullingPlanes})`.
`kRenderLayerDefault = 1`, `kRenderLayerAll = 0xFFFFFFFF`.

`RenderTexture`, `RenderTextureSampling`, `RenderTextureUpdate`, `RenderTextureView(renderTexture,
{fit = contain, filterQuality = medium, followLayout = false})`.

Widgets:
- `SceneView(Scene scene, {Camera? camera, SceneCameraBuilder? cameraBuilder, SceneViewsBuilder?
  viewsBuilder, autoTick = true, pixelRatio, onTick, loading, loadingBuilder, revealMinDuration,
  warmUp = false, children})`. App-owned scene; does not write scene properties. `camera`,
  `cameraBuilder`, `viewsBuilder` are mutually exclusive.
- `SceneView.declarative({environment, environmentIntensity = 1.0, exposure = 1.0, toneMapping =
  pbrNeutral, camera, cameraBuilder, viewsBuilder, children, ...})`. View-owned scene.
- `SceneViewsBuilder` is exported as of 0.22.0 (older docs list it as a trap; it is public now).
- Declarative widgets: `SceneNode`, `SceneMesh`, `SceneModel`, `SceneSubtree`, `SceneNodeHost`,
  `SceneNodeController`, `SceneModelSource`, `AssetModelSource`, `MemoryModelSource`,
  `SceneAnimationSpec`. `WidgetTexture`, `WidgetTextureController`, `WidgetUpdatePolicy`. `SceneScope`.
- Camera resolution precedence: `camera` -> `cameraBuilder(elapsed)` -> `scene.camera` (or first
  mounted `CameraComponent`) -> default `PerspectiveCamera()`.

`CustomRenderPass`, `RenderInput`, `RenderPassContext`, `RenderStage`, `TransientWriter`,
`NodeFilter`, `HighlightStyle`, render-graph capture types (`CapturedPass`, `CapturedResource`,
`RenderGraphCaptureRequest`, `RenderGraphCaptureResult`) are all exported.

---

## Assets and animation

Setup: `flutter pub add flutter_scene` then `dart run flutter_scene:init`. Enable Flutter GPU with
`flutter run --enable-flutter-gpu` (native only; nothing for web). Requires Flutter 3.47 stable+, NOT
master. Impeller is default; do not pass `--enable-impeller`. Never pass
`--enable-experiment=native-assets` (breaks the build on Dart 3.10+).

Two model-loading paths, do not conflate:

- Pipeline (preferred, needs the `buildScenes` hook): `loadScene(sourcePath, {package, bundle,
  registry, onReload, applyStageTo}) -> Future<Node>`. `sourcePath` is the SOURCE path relative to
  the package root (e.g. `'assets/level.glb'`), NOT a generated name. Companions:
  `loadSceneSubtree`, `releaseScene`, `clearSceneTemplateCache`.
- Runtime glTF (no hook, parses every load): `Node.fromGlbAsset(assetPath)`,
  `Node.fromGlbBytes(bytes)`, `Node.fromGltfBytes(gltfJson, {required resolveUri})`. Each synthesizes
  a root node.

Sibling loaders: `loadTexture` (`.fstex`), `loadFmatMaterial`/`loadFmatSky` (`.fmat`).

Build hooks (`package:flutter_scene/build_hooks.dart`): `buildScenes({buildInput, buildOutput,
inputFilePaths, discoveryRoot = 'assets/', assetMode = generatedTree, compressTextures = false})`,
`buildMaterials({...})`, `buildTextures({..., required textures, contents})`, `buildEngineAssets`,
`buildTargetShaderBundleJson`. Outputs land in `flutter_scene_generated/` (never commit
`.fsceneb`/`.shaderbundle`/`.fmat.json`/`.fstex`). Removed 0.21.0: `legacyOnly`,
`dataAssetsIfAvailable`, `outputDirectory`.

Animation (`Animation`, `AnimationClip`, `AnimationPlayer` exported):

- Off a loaded model: `node.parsedAnimations`, `node.findAnimationByName(name)`,
  `node.createAnimationClip(animation)`, `node.removeAnimationClip(clip)`. Clips start paused at t=0;
  call `play()`.
- `AnimationClip`: `playbackTime` (assignment is seek), `playbackTimeScale` (1; negative reverses),
  `weight` (0..1), `playing`, `loop`. `play()`, `pause()`, `stop()`, `replay()`, `gotoAndPlay(t)`,
  `seek(t)`, `advance(dt)`, `rebind(newTarget, {animation})`. Channels bind by node NAME; channels
  whose node is absent from the subtree are dropped (0.22.0 asserts in debug when ALL channels drop).
- `AnimationPlayer`: `createAnimationClip(animation, bindTarget)` (a second call with the same
  `Animation.name` replaces), `getClipByName`, `rebind`, `update(dt)` (auto-driven per frame).
- `Animation({name, channels})`, `AnimationChannel`, `BindKey({required nodeName, property =
  translation})`, `AnimationProperty` = `translation` | `rotation` | `scale`.
- Declarative: `SceneModel(assetPath, animations: [SceneAnimationSpec(name, {playing = true, loop =
  true, weight = 1.0, speed = 1.0})])`. Note `SceneModel` loads via the runtime glTF path.

The engine-agnostic scene-document core is a separate package `scene` (0.2.0), re-exported through
`package:flutter_scene/fscene.dart`. `flutter_scene_importer` and `flutter_gpu_shim` no longer exist
(folded in). Physics and audio are separate barrels (`physics.dart`, `audio.dart`).
