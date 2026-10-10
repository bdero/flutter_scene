import 'dart:convert';
import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Vector3;
import 'package:test/test.dart';

void main() {
  test('ids are stable, distinct, and round trip through their tokens', () {
    final allocator = IdAllocator();
    final a = allocator.mint();
    final b = allocator.mint();
    expect(a, isNot(b));
    expect(LocalId.parse(a.toToken()), a);
    final document = DocumentId.generate();
    expect(DocumentId.parse(document.toToken()), document);
  });

  test('an empty document round trips through .fscene text', () {
    final document = SceneDocument();
    final text = writeFscene(document);
    final reread = readFscene(text);
    expect(writeFscene(reread), text);
  });

  test('editor state round trips and prunes stale selection ids', () {
    final document = SceneDocument();
    final kept = document.newId();
    document.addNode(NodeSpec(id: kept, name: 'Kept'), root: true);
    final stale = document.newId();
    document.editor = EditorStateSpec(
      camera: EditorCameraSpec(
        azimuth: 1.25,
        elevation: -0.5,
        radius: 12,
        target: Vector3(1, 2, 3),
        orthographic: true,
      ),
      selection: [stale, kept],
    );
    final reread = readFscene(writeFscene(document));
    final editor = reread.editor!;
    expect(editor.camera!.azimuth, closeTo(1.25, 1e-9));
    expect(editor.camera!.elevation, closeTo(-0.5, 1e-9));
    expect(editor.camera!.radius, closeTo(12, 1e-9));
    expect(editor.camera!.target, Vector3(1, 2, 3));
    expect(editor.camera!.orthographic, isTrue);
    // The id that no longer names a node is dropped at read.
    expect(editor.selection, [kept]);
  });

  test('a document without editor state stays without it', () {
    final document = SceneDocument();
    final reread = readFscene(writeFscene(document));
    expect(reread.editor, isNull);
    expect(writeFscene(reread), writeFscene(document));
  });

  group('animation path channels', () {
    SceneDocument document() {
      final document = SceneDocument();
      final node = document.newId();
      document.addNode(NodeSpec(id: node, name: 'Lamp'), root: true);
      document.addAnimation(
        AnimationSpec(
          document.newId(),
          name: 'Blink',
          pathChannels: [
            AnimationPathChannelSpec(
              target: node,
              targetName: 'Lamp',
              path: 'visible',
              timeline: document.newId(),
              keyframes: document.newId(),
              interpolation: AnimationInterpolation.step,
            ),
          ],
        ),
      );
      return document;
    }

    test('round trip through .fscene text', () {
      final text = writeFscene(document());
      final channel = readFscene(
        text,
      ).animations.values.single.pathChannels.single;
      expect(channel.path, 'visible');
      expect(channel.targetName, 'Lamp');
      expect(channel.interpolation, AnimationInterpolation.step);
      expect(writeFscene(readFscene(text)), text);
    });

    test('a changed path or interpolation is an animation change', () {
      final base = document();
      SceneDocument edited({
        String? path,
        AnimationInterpolation? interpolation,
      }) {
        final copy = readFscene(writeFscene(base));
        final channels = copy.animations.values.single.pathChannels;
        final c = channels.single;
        channels[0] = AnimationPathChannelSpec(
          target: c.target,
          targetName: c.targetName,
          path: path ?? c.path,
          timeline: c.timeline,
          keyframes: c.keyframes,
          interpolation: interpolation ?? c.interpolation,
        );
        return copy;
      }

      expect(diffScene(base, edited()).animationsChanged, isFalse);
      expect(
        diffScene(base, edited(path: 'light/color')).animationsChanged,
        isTrue,
      );
      expect(
        diffScene(
          base,
          edited(interpolation: AnimationInterpolation.linear),
        ).animationsChanged,
        isTrue,
      );
    });

    test('a document that marked a held channel `step` reads as stepped', () {
      final text = writeFscene(document());
      final json = jsonDecode(text) as Map<String, dynamic>;
      final animation = (json['animations'] as Map).values.single as Map;
      final channel = (animation['pathChannels'] as List).single as Map;
      channel
        ..remove('interpolation')
        ..['step'] = true;

      final read = readFscene(jsonEncode(json));
      expect(
        read.animations.values.single.pathChannels.single.interpolation,
        AnimationInterpolation.step,
      );
      // It writes back as the current format does.
      expect(writeFscene(read), text);
    });

    test('the deprecated step flag is a view of interpolation', () {
      final channel = AnimationPathChannelSpec(
        target: const LocalId(1, 1),
        path: 'visible',
        timeline: const LocalId(1, 2),
        keyframes: const LocalId(1, 3),
        // ignore: deprecated_member_use_from_same_package
        step: true,
      );
      expect(channel.interpolation, AnimationInterpolation.step);
      // ignore: deprecated_member_use_from_same_package
      expect(channel.step, isTrue);
    });
  });

  group('animation channel interpolation', () {
    SceneDocument document(AnimationInterpolation interpolation) {
      final document = SceneDocument();
      final node = document.newId();
      document.addNode(NodeSpec(id: node, name: 'Cube'), root: true);
      document.addAnimation(
        AnimationSpec(
          document.newId(),
          name: 'Bounce',
          channels: [
            AnimationChannelSpec(
              target: node,
              targetName: 'Cube',
              property: AnimationProperty.translation,
              timeline: document.newId(),
              keyframes: document.newId(),
              interpolation: interpolation,
              inTangents: interpolation == AnimationInterpolation.cubicSpline
                  ? document.newId()
                  : null,
              outTangents: interpolation == AnimationInterpolation.cubicSpline
                  ? document.newId()
                  : null,
            ),
          ],
        ),
      );
      return document;
    }

    test('round trips through .fscene text', () {
      for (final interpolation in AnimationInterpolation.values) {
        final text = writeFscene(document(interpolation));
        final channel = readFscene(
          text,
        ).animations.values.single.channels.single;
        expect(channel.interpolation, interpolation);
        final cubic = interpolation == AnimationInterpolation.cubicSpline;
        expect(channel.inTangents != null, cubic);
        expect(channel.outTangents != null, cubic);
        expect(writeFscene(readFscene(text)), text);
      }
    });

    test('a changed tangent payload is an animation change', () {
      final base = document(AnimationInterpolation.cubicSpline);
      final edited = readFscene(writeFscene(base));
      final c = edited.animations.values.single.channels.single;
      edited.addPayload(
        PayloadSpec(
          c.outTangents!,
          encoding: PayloadEncoding.floats,
          bytes: Uint8List.fromList(const [0, 0, 128, 63]),
        ),
      );
      expect(diffScene(base, edited).animationsChanged, isTrue);
    });

    test('is written only when it is not linear', () {
      final linear = writeFscene(document(AnimationInterpolation.linear));
      expect(linear, isNot(contains('interpolation')));
      final cubic = writeFscene(document(AnimationInterpolation.cubicSpline));
      expect(cubic, contains('cubicSpline'));
    });

    test('a changed interpolation is an animation change', () {
      final base = document(AnimationInterpolation.linear);
      final edited = readFscene(writeFscene(base));
      final channels = edited.animations.values.single.channels;
      final c = channels.single;
      channels[0] = AnimationChannelSpec(
        target: c.target,
        targetName: c.targetName,
        property: c.property,
        timeline: c.timeline,
        keyframes: c.keyframes,
        interpolation: AnimationInterpolation.cubicSpline,
      );
      expect(diffScene(base, edited).animationsChanged, isTrue);
    });
  });

  test(
    'v5 .fscene documents migrate to v6 right-handed coordinates on read',
    () {
      final alloc = IdAllocator(session: 1);
      final docId = DocumentId.generate().toToken();
      final envId = alloc.mint();
      final geomId = alloc.mint();
      final chunkId = alloc.mint();
      final nodeId = alloc.mint();
      final skinId = alloc.mint();
      final animId = alloc.mint();
      final v5Json =
          '''
{
  "fscene": 5,
  "documentId": "$docId",
  "stage": {
    "environmentRef": "env:${envId.toToken()}"
  },
  "resources": {
    "env:${envId.toToken()}": {
      "kind": "environment",
      "name": "Sky",
      "environment": {"type": "studio"},
      "environmentIntensity": 1.0,
      "exposure": 1.0,
      "toneMapping": "agx",
      "skybox": {
        "source": {
          "type": "physical",
          "sunDirection": [0.2, 0.8, 0.5]
        },
        "intensity": 1.0
      }
    },
    "geo:${geomId.toToken()}": {
      "kind": "geometry",
      "vertices": "chunk:${chunkId.toToken()}",
      "bounds": {
        "min": [-1, -2, -3],
        "max": [4, 5, 6]
      }
    }
  },
  "nodes": {
    "n:${nodeId.toToken()}": {
      "name": "SunNode",
      "transform": {
        "trs": {
          "t": [1, 2, 3],
          "r": [0.1, 0.2, 0.3, 0.9],
          "s": [1, 1, 1]
        }
      },
      "components": [
        {
          "type": "directionalLight",
          "properties": {
            "localDirection": {"v3": [0, -1, 0.5]}
          }
        },
        {
          "type": "collider",
          "properties": {
            "shape": {
              "map": {
                "kind": {"s": "convexHull"}
              }
            }
          }
        }
      ]
    }
  },
  "roots": ["n:${nodeId.toToken()}"],
  "skins": {
    "skin:${skinId.toToken()}": {
      "joints": ["n:${nodeId.toToken()}"],
      "inverseBindMatrices": "chunk:${chunkId.toToken()}"
    }
  },
  "animations": {
    "anim:${animId.toToken()}": {
      "name": "Walk",
      "duration": 1.0,
      "channels": []
    }
  },
  "payloads": {
    "chunk:${chunkId.toToken()}": {
      "encoding": "vertexBuffer",
      "layout": "unskinned",
      "length": 8
    }
  },
  "editor": {
    "camera": {
      "azimuth": 0.5,
      "elevation": 0.2,
      "radius": 10.0,
      "target": [1, 2, 3]
    }
  }
}
''';
      final doc = readFscene(v5Json);
      expect(doc.formatVersion, 6);

      final env = doc.resources[envId]! as EnvironmentResource;
      final sky = env.skybox!.source as PhysicalSkySpec;
      expect(sky.sunDirection.x, closeTo(0.2, 1e-6));
      expect(sky.sunDirection.y, closeTo(0.8, 1e-6));
      expect(sky.sunDirection.z, closeTo(-0.5, 1e-6));

      final geom = doc.resources[geomId]! as GeometryResource;
      expect(geom.legacyLeftHanded, isTrue);
      expect(geom.bounds!.min.storage, [-1.0, -2.0, -6.0]);
      expect(geom.bounds!.max.storage, [4.0, 5.0, 3.0]);

      final skin = doc.skins[skinId]!;
      expect(skin.legacyLeftHanded, isTrue);

      final anim = doc.animations[animId]!;
      expect(anim.legacyLeftHanded, isTrue);

      final node = doc.nodes[nodeId]!;
      final trs = node.transform as TrsTransform;
      expect(trs.translation.storage, [1.0, 2.0, -3.0]);
      expect(trs.rotation.x, closeTo(-0.1, 1e-6));
      expect(trs.rotation.y, closeTo(-0.2, 1e-6));
      expect(trs.rotation.z, closeTo(0.3, 1e-6));
      expect(trs.rotation.w, closeTo(0.9, 1e-6));

      final lightProps = node.components[0].properties;
      final dir = (lightProps['localDirection']! as Vec3Value).value;
      expect(dir.storage, [0.0, -1.0, -0.5]);

      final colliderShape =
          (node.components[1].properties['shape']! as MapValue).values;
      expect((colliderShape['legacyLeftHanded']! as BoolValue).value, isTrue);

      expect(doc.editor!.camera!.target.storage, [1.0, 2.0, -3.0]);
    },
  );
}
