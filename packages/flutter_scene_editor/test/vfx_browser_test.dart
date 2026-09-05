// The effect catalogue, as the Add menu and the browser both read it. Plain
// data over the engine's shipped presets, so none of it needs a GPU.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every category the menu builds has effects in it', () {
    // The Add > VFX submenu is one entry per category; an empty one would be
    // a submenu that opens onto nothing.
    for (final category in VfxCategory.values) {
      expect(
        vfxPresetsIn(category),
        isNotEmpty,
        reason: '${category.label} would open onto an empty submenu',
      );
      expect(category.label, isNotEmpty);
    }
  });

  test('every preset carries the name and the line the menu shows', () {
    for (final preset in vfxPresets) {
      expect(preset.name, isNotEmpty);
      expect(preset.description, isNotEmpty, reason: preset.id);
    }
  });

  test('the categories partition the catalogue', () {
    final grouped = [
      for (final category in VfxCategory.values) ...vfxPresetsIn(category),
    ];
    expect(
      grouped.map((p) => p.id).toSet(),
      vfxPresets.map((p) => p.id).toSet(),
    );
    expect(grouped, hasLength(vfxPresets.length));
  });

  test('ids are unique, since a document names one', () {
    expect(vfxPresets.map((p) => p.id).toSet(), hasLength(vfxPresets.length));
  });
}
