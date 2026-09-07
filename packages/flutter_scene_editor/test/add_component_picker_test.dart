// The Add Component picker's grouping and search, as plain functions over
// plain data so they run without a GPU.
import 'package:flutter_scene_editor/src/panels/inspector_panel.dart';
import 'package:flutter_test/flutter_test.dart';

ComponentTypeInfo _info({String? category, String? icon, String? provenance}) =>
    (category: category, icon: icon, provenance: provenance);

void main() {
  group('category', () {
    test('a declared category wins', () {
      expect(addComponentCategory(_info(category: 'Physics')), 'Physics');
      expect(
        addComponentCategory(_info(category: 'Physics', provenance: 'live')),
        'Physics',
      );
    });

    test('a project component with no category is a Script', () {
      expect(addComponentCategory(_info(provenance: 'live')), 'Scripts');
      expect(addComponentCategory(_info(provenance: 'cache')), 'Scripts');
    });

    test('a dependency component with no category is a Package', () {
      expect(
        addComponentCategory(_info(provenance: 'package:widgets')),
        'Packages',
      );
    });

    test('an empty category is treated as none, not as a group name', () {
      expect(addComponentCategory(_info(category: '')), 'Other');
    });

    test('a compiled type declaring nothing falls to Other', () {
      expect(addComponentCategory(_info()), 'Other');
    });
  });

  group('grouping', () {
    final types = <String, ComponentTypeInfo>{
      'spotLight': _info(category: 'Rendering'),
      'camera': _info(category: 'Cameras'),
      'rigidBody': _info(category: 'Physics'),
      'directionalLight': _info(category: 'Rendering'),
      'spinner': _info(provenance: 'live'),
      'mystery': _info(),
    };

    test('collects types under their category, sorted by name', () {
      final groups = Map.fromEntries(groupComponentTypes(types));
      expect(groups['Rendering'], ['directionalLight', 'spotLight']);
      expect(groups['Physics'], ['rigidBody']);
      expect(groups['Scripts'], ['spinner']);
      expect(groups['Other'], ['mystery']);
    });

    test('built-in groups sort before Scripts, Packages and Other', () {
      final order = groupComponentTypes(types).map((e) => e.key).toList();
      expect(order.indexOf('Cameras'), lessThan(order.indexOf('Scripts')));
      expect(order.indexOf('Rendering'), lessThan(order.indexOf('Other')));
      // Among the built-in groups the order is alphabetical, so the list does
      // not shuffle as a project grows.
      expect(order.takeWhile((name) => name != 'Scripts').toList(), [
        'Cameras',
        'Physics',
        'Rendering',
      ]);
      expect(order.last, 'Other');
    });

    test('an empty set produces no groups', () {
      expect(groupComponentTypes(const {}), isEmpty);
    });
  });

  group('search', () {
    test('an empty query matches everything', () {
      expect(matchesComponentQuery('camera', _info(), ''), isTrue);
    });

    test('matches on the type name, case-insensitively', () {
      expect(
        matchesComponentQuery('rigidBody', _info(category: 'Physics'), 'BODY'),
        isTrue,
      );
    });

    test('matches on the category, so a group name finds its members', () {
      // Typing "phys" should find rigidBody even though the word is not in
      // its name.
      expect(
        matchesComponentQuery('rigidBody', _info(category: 'Physics'), 'phys'),
        isTrue,
      );
    });

    test('finds a project component by searching for scripts', () {
      expect(
        matchesComponentQuery('spinner', _info(provenance: 'live'), 'script'),
        isTrue,
      );
    });

    test('rejects a non-match', () {
      expect(
        matchesComponentQuery('camera', _info(category: 'Cameras'), 'audio'),
        isFalse,
      );
    });
  });

  group('glyphs', () {
    test('a declared icon wins over the category fallback', () {
      // Compared against a category whose fallback is something else, since a
      // schema icon that happens to match its category's glyph (light-point
      // in Rendering) is indistinguishable either way, and rightly so.
      expect(
        componentPickerGlyph(_info(category: 'Physics', icon: 'camera')),
        componentPickerGlyph(_info(icon: 'camera')),
      );
      expect(
        componentPickerGlyph(_info(category: 'Physics', icon: 'camera')),
        isNot(componentPickerGlyph(_info(category: 'Physics'))),
      );
    });

    test('every category has a glyph of its own', () {
      const categories = [
        'Mesh',
        'Effects',
        'Rendering',
        'Cameras',
        'Physics',
        'Audio',
        'Navigation',
        'UI',
        'Scripts',
        'Packages',
      ];
      final glyphs = {
        for (final category in categories)
          category: componentPickerGlyph(_info(category: category)),
      };
      // Distinct, or the grouping reads as noise rather than as structure.
      expect(glyphs.values.toSet(), hasLength(categories.length));
    });

    test('a type declaring nothing still gets a glyph', () {
      // A row with no icon would read as a gap in the list.
      expect(componentPickerGlyph(_info()), isNotNull);
    });

    test('an unknown icon name falls back rather than blanking', () {
      expect(
        componentPickerGlyph(_info(category: 'Physics', icon: 'no-such-icon')),
        componentPickerGlyph(_info(category: 'Physics')),
      );
    });
  });
}
