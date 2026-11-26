import 'dart:convert';

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
        expect(writeFscene(readFscene(text)), text);
      }
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
}
