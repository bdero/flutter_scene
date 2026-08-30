// How a node takes part in shadow casting. The bool it replaces could say
// "casts" or "does not"; the two cases it could not say are the ones worth
// having — a caster that stays invisible, and one that casts from every face.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the mode', () {
    test('casting and drawing are independent, except where they are not', () {
      expect(ShadowCastingMode.on.casts, isTrue);
      expect(ShadowCastingMode.on.drawsInColor, isTrue);

      // Off still draws: it is lit, it just throws nothing.
      expect(ShadowCastingMode.off.casts, isFalse);
      expect(ShadowCastingMode.off.drawsInColor, isTrue);

      // Shadows-only is exactly the other combination.
      expect(ShadowCastingMode.shadowsOnly.casts, isTrue);
      expect(ShadowCastingMode.shadowsOnly.drawsInColor, isFalse);

      // Double-sided is a casting detail, not a visibility one.
      expect(ShadowCastingMode.doubleSided.casts, isTrue);
      expect(ShadowCastingMode.doubleSided.drawsInColor, isTrue);
    });

    test('an unknown mode casts normally rather than vanishing', () {
      // A document from a newer build. A missing object is a worse failure
      // than a differently-shadowed one.
      expect(ShadowCastingMode.parse('somethingNew'), ShadowCastingMode.on);
      expect(ShadowCastingMode.parse(null), ShadowCastingMode.on);
    });

    test('a known mode parses back to itself', () {
      for (final mode in ShadowCastingMode.values) {
        expect(ShadowCastingMode.parse(mode.name), mode, reason: mode.name);
      }
    });
  });

  group('on a node', () {
    test('it defaults to casting normally', () {
      expect(Node().shadowCastingMode, ShadowCastingMode.on);
      expect(Node().castsShadows, isTrue);
    });

    test('the bool still reads and writes, because callers still use it', () {
      final node = Node()..castsShadows = false;
      expect(node.shadowCastingMode, ShadowCastingMode.off);
      expect(node.castsShadows, isFalse);

      node.castsShadows = true;
      expect(node.shadowCastingMode, ShadowCastingMode.on);
    });

    test('the bool reads true for the modes that cast', () {
      for (final mode in [
        ShadowCastingMode.on,
        ShadowCastingMode.doubleSided,
        ShadowCastingMode.shadowsOnly,
      ]) {
        expect(
          (Node()..shadowCastingMode = mode).castsShadows,
          isTrue,
          reason: mode.name,
        );
      }
    });

    test('writing the bool cannot reach the two richer modes', () {
      // Which is the point of keeping it as a narrow view rather than the
      // whole setting: it says what it can say and no more.
      final node = Node()..shadowCastingMode = ShadowCastingMode.shadowsOnly;
      node.castsShadows = true;
      expect(node.shadowCastingMode, ShadowCastingMode.on);
    });

    test('it is not inherited by children', () {
      final parent = Node()..shadowCastingMode = ShadowCastingMode.off;
      final child = Node();
      parent.add(child);
      expect(child.shadowCastingMode, ShadowCastingMode.on);
    });
  });
}
