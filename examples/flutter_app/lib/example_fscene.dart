import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/geometry/interleaved_layout.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/texture/ktx2_image.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/geometry/primitives.dart'
    show buildCuboidArrays;
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// Builds a scene as an `.fscene` document in code and runs it through the
/// whole format pipeline both ways: document -> `.fsceneb` -> live graph
/// (realize), then live graph -> document (serialize) -> `.fsceneb` -> live
/// graph again. The twice-realized scene is what renders, so anything that
/// fails to survive serialization would visibly drop out. It exercises
/// procedural geometry, a payload-backed mesh, parameter materials, a
/// directional light, an embedded `rgba8` texture, a compressed KTX2 block
/// texture, and the asynchronously-loaded resources: an external image-asset
/// texture, an encoded (PNG) image payload, and an `fmat` custom material.
class ExampleFscene extends StatefulWidget {
  const ExampleFscene({super.key});

  @override
  State<ExampleFscene> createState() => _ExampleFsceneState();
}

class _ExampleFsceneState extends State<ExampleFscene> {
  final Scene scene = Scene();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // An encoded image to carry as a PNG payload chunk (decoded at load).
    final pano = await rootBundle.load('assets/little_paris_eiffel_tower.png');
    final pngBytes = pano.buffer.asUint8List(
      pano.offsetInBytes,
      pano.lengthInBytes,
    );

    // Realize the authored document, serialize the live graph back to a
    // document, then realize that. What renders is the round-tripped scene.
    // The async loader preloads external assets, encoded payloads, and fmat
    // materials before realizing.
    final document = _buildDocument(pngBytes);
    final realized = await loadFscenebBytesAsync(writeFsceneb(document));

    // A hand-built mesh (no document behind it) added to the live graph: the
    // serializer re-packs its interleaved streams and reads back the material
    // factors, so it survives the round trip below like everything else.
    realized.add(
      Node(
        name: 'handBuilt',
        localTransform: vm.Matrix4.translation(vm.Vector3(0, 5.2, 0)),
      )..addComponent(
        MeshComponent(
          Mesh(
            SphereGeometry(radius: 0.6),
            PhysicallyBasedMaterial()
              ..baseColorFactor = vm.Vector4(1.0, 0.85, 0.1, 1.0)
              ..metallicFactor = 1.0
              ..roughnessFactor = 0.25,
          ),
        ),
      ),
    );

    final roundTripped = serializeScene(realized);
    if (!mounted) return;
    scene.add(await loadFscenebBytesAsync(writeFsceneb(roundTripped)));

    // Stage round trip: apply the authored stage (a gradient skybox that
    // also drives the lighting), read it back from the live scene, and apply
    // the read-back copy. What renders is the round-tripped stage.
    await realizeStage(document, scene);
    final stageDocument = SceneDocument();
    serializeStage(scene, stageDocument);
    if (!mounted) return;
    await realizeStage(stageDocument, scene);
  }

  @override
  Widget build(BuildContext context) {
    return SceneView(
      scene,
      cameraBuilder: (elapsed) {
        final t = elapsed.inMicroseconds / 1e6;
        return PerspectiveCamera(
          position: vm.Vector3(sin(t) * 10, 5, cos(t) * 10),
          target: vm.Vector3(0, 1.5, 0),
        );
      },
      onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
    );
  }
}

SceneDocument _buildDocument(Uint8List pngBytes) {
  final doc = SceneDocument();

  // A sunset gradient sky: the skybox shows it, and the sky-lighting binding
  // bakes the same source into the image-based lighting, so reflections and
  // ambient light match the backdrop.
  final sky = GradientSkySpec(
    zenithColor: vm.Vector3(0.07, 0.18, 0.45),
    horizonColor: vm.Vector3(0.95, 0.55, 0.32),
    groundColor: vm.Vector3(0.18, 0.14, 0.12),
    sunDirection: vm.Vector3(0.3, 0.25, 0.8),
    sunColor: vm.Vector3(4.0, 2.6, 1.6),
  );
  doc.stage
    ..skybox = SkyboxSpec(sky)
    ..skyEnvironment = SkyEnvironmentSpec(sky);

  // A sun, pitched down toward the scene.
  doc.createNode(
    name: 'sun',
    root: true,
    transform: TrsTransform(
      rotation: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -1.0),
    ),
    components: [
      ComponentSpec(
        'directionalLight',
        properties: {
          'intensity': const DoubleValue(3.0),
          'castsShadow': const BoolValue(true),
        },
      ),
    ],
  );

  final red = doc.addResource(
    MaterialResource(
      doc.newId(),
      type: 'physicallyBased',
      properties: {
        'baseColor': const ColorValue(0.9, 0.2, 0.2, 1.0),
        'roughness': const DoubleValue(0.4),
      },
    ),
  );
  final blue = doc.addResource(
    MaterialResource(
      doc.newId(),
      type: 'physicallyBased',
      properties: {
        'baseColor': const ColorValue(0.2, 0.4, 0.9, 1.0),
        'metallic': const DoubleValue(0.8),
        'roughness': const DoubleValue(0.3),
      },
    ),
  );

  final planeGeometry = doc.addResource(
    GeometryResource(
      doc.newId(),
      procedural: PlaneGeometrySpec(width: 10, depth: 10),
    ),
  );
  doc.createNode(
    name: 'ground',
    root: true,
    transform: TrsTransform(translation: vm.Vector3(0, -1, 0)),
    components: [
      ComponentSpec(
        'mesh',
        properties: {
          'geometry': ResourceRefValue(planeGeometry.id),
          'material': ResourceRefValue(blue.id),
        },
      ),
    ],
  );

  final cubeGeometry = doc.addResource(
    GeometryResource(
      doc.newId(),
      procedural: CuboidGeometrySpec(extents: vm.Vector3(1, 1, 1)),
    ),
  );
  for (var i = 0; i < 5; i++) {
    final angle = i / 5 * 2 * pi;
    doc.createNode(
      name: 'cube$i',
      root: true,
      transform: TrsTransform(
        translation: vm.Vector3(cos(angle) * 2.5, 0, sin(angle) * 2.5),
      ),
      components: [
        ComponentSpec(
          'mesh',
          properties: {
            'geometry': ResourceRefValue(cubeGeometry.id),
            'material': ResourceRefValue(i.isEven ? red.id : blue.id),
          },
        ),
      ],
    );
  }

  // A payload-backed mesh: its geometry lives in binary vertex/index chunks
  // (the same interleaved layout an imported model produces) rather than a
  // procedural descriptor. It rides above the ring so it is easy to pick out.
  final green = doc.addResource(
    MaterialResource(
      doc.newId(),
      type: 'physicallyBased',
      properties: {
        'baseColor': const ColorValue(0.2, 0.8, 0.3, 1.0),
        'roughness': const DoubleValue(0.5),
      },
    ),
  );
  final payloadCube = _payloadCuboid(doc, vm.Vector3(1.4, 1.4, 1.4));
  doc.createNode(
    name: 'payloadCube',
    root: true,
    transform: TrsTransform(translation: vm.Vector3(0, 1.6, 0)),
    components: [
      ComponentSpec(
        'mesh',
        properties: {
          'geometry': ResourceRefValue(payloadCube.id),
          'material': ResourceRefValue(green.id),
        },
      ),
    ],
  );

  // A textured cube: its material samples a checkerboard image carried as an
  // rgba8 payload chunk (the shape an imported texture takes). Unlit so the
  // pattern reads directly.
  final checker = _checkerTexture(doc);
  final tiles = doc.addResource(
    MaterialResource(
      doc.newId(),
      type: 'unlit',
      properties: {'baseColorTexture': ResourceRefValue(checker.id)},
    ),
  );
  doc.createNode(
    name: 'texturedCube',
    root: true,
    transform: TrsTransform(translation: vm.Vector3(0, 0.5, 3.6)),
    components: [
      ComponentSpec(
        'mesh',
        properties: {
          'geometry': ResourceRefValue(cubeGeometry.id),
          'material': ResourceRefValue(tiles.id),
        },
      ),
    ],
  );

  // A cube textured from a compressed KTX2 block payload (gradient image),
  // exercising the compressed-texture load path.
  final ktx2Material = doc.addResource(
    MaterialResource(
      doc.newId(),
      type: 'unlit',
      properties: {'baseColorTexture': ResourceRefValue(_ktx2Texture(doc).id)},
    ),
  );
  doc.createNode(
    name: 'ktx2Cube',
    root: true,
    transform: TrsTransform(translation: vm.Vector3(0, 0.5, -3.6)),
    components: [
      ComponentSpec(
        'mesh',
        properties: {
          'geometry': ResourceRefValue(cubeGeometry.id),
          'material': ResourceRefValue(ktx2Material.id),
        },
      ),
    ],
  );

  // A KTX2 cube whose texture carries alpha: the compressed payload keeps a
  // translucent checkerboard (alpha-capable transcode on BC/ETC2 devices,
  // rgba8 fallback elsewhere), blended by the material's alphaMode.
  final alphaMaterial = doc.addResource(
    MaterialResource(
      doc.newId(),
      type: 'physicallyBased',
      properties: {
        'baseColorTexture': ResourceRefValue(_alphaKtx2Texture(doc).id),
        'alphaMode': const StringValue('blend'),
        'roughness': const DoubleValue(0.8),
      },
    ),
  );
  doc.createNode(
    name: 'alphaCube',
    root: true,
    transform: TrsTransform(translation: vm.Vector3(3.6, 0.5, 0)),
    components: [
      ComponentSpec(
        'mesh',
        properties: {
          'geometry': ResourceRefValue(cubeGeometry.id),
          'material': ResourceRefValue(alphaMaterial.id),
        },
      ),
    ],
  );

  // A row of asynchronously-loaded resources above the ring.
  // 1. An external image-asset texture (referenced by path, not embedded).
  final assetTexture = doc.addResource(
    TextureResource(
      doc.newId(),
      asset: const AssetRef('assets/little_paris_eiffel_tower.png'),
    ),
  );
  _meshNode(
    doc,
    name: 'assetTextureCube',
    position: vm.Vector3(-3, 3, 0),
    geometry: cubeGeometry.id,
    material: doc
        .addResource(
          MaterialResource(
            doc.newId(),
            type: 'unlit',
            properties: {'baseColorTexture': ResourceRefValue(assetTexture.id)},
          ),
        )
        .id,
  );

  // 2. The same image as an encoded (PNG) payload chunk, decoded at load.
  final pngPayload = doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.image,
      format: 'png',
      bytes: pngBytes,
    ),
  );
  final pngTexture = doc.addResource(
    TextureResource(doc.newId(), payload: pngPayload.id),
  );
  _meshNode(
    doc,
    name: 'encodedTextureCube',
    position: vm.Vector3(0, 3, 0),
    geometry: cubeGeometry.id,
    material: doc
        .addResource(
          MaterialResource(
            doc.newId(),
            type: 'unlit',
            properties: {'baseColorTexture': ResourceRefValue(pngTexture.id)},
          ),
        )
        .id,
  );

  // 3. An `fmat` custom material, loaded by source path.
  _meshNode(
    doc,
    name: 'fmatCube',
    position: vm.Vector3(3, 3, 0),
    geometry: cubeGeometry.id,
    material: doc
        .addResource(
          MaterialResource(
            doc.newId(),
            type: 'fmat',
            asset: const AssetRef('assets/toon.fmat'),
          ),
        )
        .id,
  );

  return doc;
}

void _meshNode(
  SceneDocument doc, {
  required String name,
  required vm.Vector3 position,
  required LocalId geometry,
  required LocalId material,
}) {
  doc.createNode(
    name: name,
    root: true,
    transform: TrsTransform(translation: position),
    components: [
      ComponentSpec(
        'mesh',
        properties: {
          'geometry': ResourceRefValue(geometry),
          'material': ResourceRefValue(material),
        },
      ),
    ],
  );
}

/// Builds a high-contrast checkerboard as an rgba8 image payload referenced by
/// a [TextureResource], the way an imported texture is carried.
TextureResource _checkerTexture(SceneDocument doc) {
  const size = 16;
  final pixels = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      final lit = ((x ~/ 2) + (y ~/ 2)).isEven;
      pixels[i] = lit ? 235 : 25;
      pixels[i + 1] = lit ? 235 : 25;
      pixels[i + 2] = lit ? 235 : 25;
      pixels[i + 3] = 255;
    }
  }
  final payload = doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.image,
      format: 'rgba8',
      width: size,
      height: size,
      bytes: pixels,
    ),
  );
  return doc.addResource(TextureResource(doc.newId(), payload: payload.id));
}

/// A gradient image stored as a compressed KTX2 block payload (mipped and
/// supercompressed), the shape a compressed imported texture takes. The
/// realizer decodes it (or transcodes it to a GPU block format where
/// supported) at load.
TextureResource _ktx2Texture(SceneDocument doc) {
  const size = 64;
  final pixels = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      pixels[i] = x * 255 ~/ (size - 1);
      pixels[i + 1] = y * 255 ~/ (size - 1);
      pixels[i + 2] = 200 - (x * 160 ~/ (size - 1));
      pixels[i + 3] = 255;
    }
  }
  final ktx2 = encodeImageToKtx2Bytes(pixels, size, size, supercompress: true);
  final payload = doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.image,
      format: 'ktx2',
      width: size,
      height: size,
      bytes: ktx2,
    ),
  );
  return doc.addResource(TextureResource(doc.newId(), payload: payload.id));
}

/// A translucent checkerboard carried as a compressed KTX2 payload: opaque
/// warm cells over cells fading with a vertical alpha ramp, so missing alpha
/// reads as a solid cube immediately.
TextureResource _alphaKtx2Texture(SceneDocument doc) {
  const size = 64;
  final pixels = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      final checker = ((x >> 3) + (y >> 3)).isEven;
      pixels[i] = checker ? 240 : 40;
      pixels[i + 1] = checker ? 140 : 90;
      pixels[i + 2] = checker ? 40 : 220;
      pixels[i + 3] = checker ? 255 : (y * 255 ~/ (size - 1));
    }
  }
  final ktx2 = encodeImageToKtx2Bytes(pixels, size, size, supercompress: true);
  final payload = doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.image,
      format: 'ktx2',
      width: size,
      height: size,
      bytes: ktx2,
    ),
  );
  return doc.addResource(TextureResource(doc.newId(), payload: payload.id));
}

/// Builds a cuboid as payload-backed geometry: the interleaved vertex buffer
/// and index buffer are packed into binary chunks and referenced by a
/// [GeometryResource], the way the importer will emit imported meshes.
GeometryResource _payloadCuboid(SceneDocument doc, vm.Vector3 extents) {
  final arrays = buildCuboidArrays(extents);
  final vertexBytes = InterleavedLayoutAdapter.packUnskinned(
    positions: arrays.positions,
    vertexCount: arrays.positions.length ~/ 3,
    normals: arrays.normals,
    texCoords: arrays.texCoords,
  );
  final packedIndices = InterleavedLayoutAdapter.packIndices(arrays.indices);

  final vertices = doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.vertexBuffer,
      layout: 'unskinned',
      bytes: vertexBytes,
    ),
  );
  final indices = doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.indexBuffer,
      format: packedIndices.is32Bit ? 'uint32' : 'uint16',
      bytes: packedIndices.bytes,
    ),
  );
  return doc.addResource(
    GeometryResource(doc.newId(), vertices: vertices.id, indices: indices.id),
  );
}
