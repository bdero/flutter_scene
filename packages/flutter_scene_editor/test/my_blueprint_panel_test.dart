// The My Blueprint sidebar's grouping. Which sections exist, what they are
// called, and which ones show when empty -- decisions about a blueprint's
// shape, so they need no controller and no GPU.

import 'package:flutter_scene_editor/src/panels/my_blueprint_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/visual_script.dart';

void main() {
  test('every graph kind has a section heading and a glyph', () {
    for (final kind in VisualScriptGraphKind.values) {
      expect(MyBlueprintPanel.sectionLabel(kind), isNotEmpty, reason: '$kind');
      expect(MyBlueprintPanel.kindGlyph(kind), isNotNull, reason: '$kind');
    }
  });

  test('the headings are distinct, so two kinds never merge visually', () {
    final labels = {
      for (final kind in VisualScriptGraphKind.values)
        MyBlueprintPanel.sectionLabel(kind),
    };
    expect(labels, hasLength(VisualScriptGraphKind.values.length));
  });

  test('the glyphs are distinct too', () {
    final glyphs = {
      for (final kind in VisualScriptGraphKind.values)
        MyBlueprintPanel.kindGlyph(kind),
    };
    expect(glyphs, hasLength(VisualScriptGraphKind.values.length));
  });

  test(
    'graphs and construction show when empty; functions and macros do not',
    () {
      // Every blueprint has or wants those two. A simple script should not open
      // onto four empty headings.
      expect(
        MyBlueprintPanel.showsWhenEmpty(VisualScriptGraphKind.eventGraph),
        isTrue,
      );
      expect(
        MyBlueprintPanel.showsWhenEmpty(
          VisualScriptGraphKind.constructionScript,
        ),
        isTrue,
      );
      expect(
        MyBlueprintPanel.showsWhenEmpty(VisualScriptGraphKind.function),
        isFalse,
      );
      expect(
        MyBlueprintPanel.showsWhenEmpty(VisualScriptGraphKind.macro),
        isFalse,
      );
    },
  );
}
