import 'package:flutter/widgets.dart';
import 'package:flutter_scene_editor/src/shell/dock_layout.dart';
import 'package:flutter_scene_editor/src/shell/editor_shell.dart';
import 'package:flutter_test/flutter_test.dart';

DockLayout _twoColumn() {
  return DockLayout(
    DockSplit(
      Axis.horizontal,
      [
        DockTabs(['scene']),
        DockTabs(['hierarchy', 'inspector'], active: 1),
      ],
      [0.7, 0.3],
    ),
  );
}

void main() {
  test('the default layout is the arrangement everybody already knows', () {
    // Hierarchy left, scene in the middle, inspector right, and the project
    // browser along the bottom under both rather than as a third column.
    final layout = defaultEditorDockLayout();
    final root = layout.root as DockSplit;
    expect(root.axis, Axis.horizontal);
    expect((root.children[1] as DockTabs).panels, ['inspector']);

    final main = root.children[0] as DockSplit;
    expect(main.axis, Axis.vertical);

    final top = main.children[0] as DockSplit;
    expect(top.axis, Axis.horizontal);
    expect((top.children[0] as DockTabs).panels, ['hierarchy']);
    expect((top.children[1] as DockTabs).panels, contains('scene'));

    final shelf = main.children[1] as DockTabs;
    expect(shelf.panels.first, 'project');
    expect(shelf.panels, contains('console'));
  });

  test('the bottom shelf runs under the hierarchy as well as the scene', () {
    // What makes it a shelf rather than a third column: it is a sibling of
    // the row holding both, not a sibling of the scene alone.
    final root = defaultEditorDockLayout().root as DockSplit;
    final main = root.children[0] as DockSplit;
    expect(main.children[1], isA<DockTabs>());
    expect((main.children[0] as DockSplit).children, hasLength(2));
  });

  test('json round-trips', () {
    final layout = _twoColumn();
    final restored = DockLayout.fromJsonString(layout.toJsonString());
    expect(restored.panelIds(), ['scene', 'hierarchy', 'inspector']);
    final split = restored.root as DockSplit;
    expect(split.axis, Axis.horizontal);
    expect(split.weights, [0.7, 0.3]);
    expect((split.children[1] as DockTabs).active, 1);
  });

  test('removing a group\'s last panel collapses the split', () {
    final layout = _twoColumn();
    layout.removePanel('scene');
    final tabs = layout.root as DockTabs;
    expect(tabs.panels, ['hierarchy', 'inspector']);
  });

  test('removing keeps the active tab pointed at the same panel', () {
    final layout = _twoColumn();
    layout.removePanel('hierarchy');
    final tabs = (layout.root as DockSplit).children[1] as DockTabs;
    expect(tabs.activePanel, 'inspector');
  });

  test('center dock moves a panel into the target group', () {
    final layout = _twoColumn();
    final target = (layout.root as DockSplit).children[0] as DockTabs;
    layout.dock('inspector', target, DockZone.center);
    expect(target.panels, ['scene', 'inspector']);
    expect(target.activePanel, 'inspector');
    // The source group survives with its remaining tab.
    expect(layout.panelIds(), ['scene', 'inspector', 'hierarchy']);
  });

  test('same-axis edge dock inserts a sibling and halves the weight', () {
    final layout = _twoColumn();
    final target = (layout.root as DockSplit).children[0] as DockTabs;
    layout.dock('inspector', target, DockZone.right);
    final split = layout.root as DockSplit;
    expect(split.children, hasLength(3));
    expect((split.children[1] as DockTabs).panels, ['inspector']);
    expect(split.weights[0], closeTo(0.35, 1e-9));
    expect(split.weights[1], closeTo(0.35, 1e-9));
  });

  test('cross-axis edge dock wraps the target in a new split', () {
    final layout = _twoColumn();
    final target = (layout.root as DockSplit).children[0] as DockTabs;
    layout.dock('inspector', target, DockZone.bottom);
    final inner = (layout.root as DockSplit).children[0] as DockSplit;
    expect(inner.axis, Axis.vertical);
    expect((inner.children[0] as DockTabs).panels, ['scene']);
    expect((inner.children[1] as DockTabs).panels, ['inspector']);
  });

  test('docking a sole tab onto its own group is a no-op', () {
    final layout = _twoColumn();
    final target = (layout.root as DockSplit).children[0] as DockTabs;
    final before = layout.toJsonString();
    layout.dock('scene', target, DockZone.center);
    layout.dock('scene', target, DockZone.left);
    expect(layout.toJsonString(), before);
  });

  test('tryParse drops unknown panels and appends missing ones', () {
    final source = DockLayout(
      DockSplit(
        Axis.horizontal,
        [
          DockTabs(['scene', 'retired']),
          DockTabs(['hierarchy']),
        ],
        [0.5, 0.5],
      ),
    ).toJsonString();
    final layout = DockLayout.tryParse(
      source,
      knownPanels: ['scene', 'hierarchy', 'inspector'],
    );
    expect(layout, isNotNull);
    expect(layout!.panelIds().toSet(), {'scene', 'hierarchy', 'inspector'});
  });

  test('hide/show round-trips through the hidden list', () {
    final layout = _twoColumn();
    layout.hidePanel('scene');
    expect(layout.isVisible('scene'), isFalse);
    expect(layout.hidden, ['scene']);
    expect(layout.root, isA<DockTabs>());
    layout.showPanel('scene');
    expect(layout.isVisible('scene'), isTrue);
    expect(layout.hidden, isEmpty);
  });

  test('float moves a panel out of the tree and dock() brings it back', () {
    final layout = _twoColumn();
    layout.floatPanel('inspector');
    expect(layout.floating, ['inspector']);
    expect(layout.panelIds(), ['scene', 'hierarchy']);
    final target = layout.root as DockSplit;
    layout.dock('inspector', target.children[0] as DockTabs, DockZone.center);
    expect(layout.floating, isEmpty);
    expect(layout.isVisible('inspector'), isTrue);
  });

  test('v2 json round-trips hidden and floating', () {
    final layout = _twoColumn();
    layout.hidePanel('hierarchy');
    layout.floatPanel('inspector');
    final restored = DockLayout.fromJsonString(layout.toJsonString());
    expect(restored.hidden, ['hierarchy']);
    expect(restored.floating, ['inspector']);
    expect(restored.panelIds(), ['scene']);
  });

  test('legacy root-only json still parses', () {
    const legacy =
        '{"type":"tabs","panels":["viewport","outliner"],"active":0}';
    final layout = DockLayout.tryParse(
      legacy,
      knownPanels: ['scene', 'hierarchy'],
    );
    expect(layout, isNotNull);
    expect(layout!.panelIds(), ['scene', 'hierarchy']);
    expect(layout.hidden, isEmpty);
    expect(layout.floating, isEmpty);
  });

  test('tryParse keeps hidden panels hidden and dedupes stale entries', () {
    final source = DockLayout(
      DockTabs(['scene', 'hierarchy']),
      hidden: ['history', 'hierarchy', 'retired'],
      floating: ['project'],
    ).toJsonString();
    final layout = DockLayout.tryParse(
      source,
      knownPanels: ['scene', 'hierarchy', 'history', 'project'],
    );
    expect(layout, isNotNull);
    // outliner is docked, so the stale hidden entry is dropped; history stays
    // hidden rather than being re-appended; assets stays floating.
    expect(layout!.panelIds(), ['scene', 'hierarchy']);
    expect(layout.hidden, ['history']);
    expect(layout.floating, ['project']);
  });

  test('dock() inserts a brand-new panel id', () {
    final layout = _twoColumn();
    final target = (layout.root as DockSplit).children[0] as DockTabs;
    layout.dock('viewport2', target, DockZone.right);
    final split = layout.root as DockSplit;
    expect((split.children[1] as DockTabs).panels, ['viewport2']);
  });

  test('tryParse keeps dynamic panels but never appends them', () {
    final source = DockLayout(
      DockTabs(['scene', 'viewport2', 'stale9']),
    ).toJsonString();
    bool isDynamic(String id) =>
        RegExp(r'^viewport\d+$').hasMatch(id) || id == 'stale9';
    final layout = DockLayout.tryParse(
      source,
      knownPanels: ['scene'],
      isDynamic: RegExp(r'^viewport\d+$').hasMatch,
    );
    expect(layout, isNotNull);
    expect(layout!.panelIds(), ['scene', 'viewport2']);
    // A layout without the dynamic panel does not grow one.
    final bare = DockLayout(DockTabs(['scene'])).toJsonString();
    final reparsed = DockLayout.tryParse(
      bare,
      knownPanels: ['scene'],
      isDynamic: isDynamic,
    );
    expect(reparsed!.panelIds(), ['scene']);
  });

  test('tryParse rejects garbage', () {
    expect(DockLayout.tryParse('not json', knownPanels: ['scene']), isNull);
    expect(
      DockLayout.tryParse('{"type":"nope"}', knownPanels: ['scene']),
      isNull,
    );
    expect(DockLayout.tryParse(null, knownPanels: ['scene']), isNull);
  });

  test('a layout saved with the Navigation panel still opens', () {
    // Navigation moved onto the node carrying the surface, so the id is no
    // longer a panel. A layout persisted before that must drop it rather
    // than failing to parse and losing the whole workspace.
    const saved =
        '{"root":{"type":"tabs","panels":["inspector","navigation"]},'
        '"floating":[]}';
    final layout = DockLayout.tryParse(
      saved,
      knownPanels: const ['inspector', 'scene'],
      isDynamic: (_) => false,
    );
    expect(layout, isNotNull);
    expect(layout!.panelIds(), isNot(contains('navigation')));
    expect(layout.panelIds(), contains('inspector'));
  });

  test('the default layout only names panels that exist', () {
    // Effects, Weather and Navigation were each retired into the place they
    // belonged, and a default layout still naming one opens onto a tab with
    // nothing behind it.
    final layout = defaultEditorDockLayout();
    for (final id in layout.panelIds()) {
      expect(
        editorPanelTitles.containsKey(id),
        isTrue,
        reason: 'the default layout opens "$id", which is not a panel',
      );
    }
  });

  group('renamed panels', () {
    test('a layout saved under the old names keeps its arrangement', () {
      // Without this the ids are simply unknown: the panels are dropped and
      // re-appended somewhere else, which does not break the workspace so
      // much as shuffle it -- harder to notice and just as annoying.
      const saved =
          '{"root":{"type":"split","axis":"h","weights":[0.3,0.7],'
          '"children":['
          '{"type":"tabs","panels":["outliner"],"active":0},'
          '{"type":"tabs","panels":["viewport","assets"],"active":0}]},'
          '"hidden":[],"floating":[]}';
      final layout = DockLayout.tryParse(
        saved,
        knownPanels: const ['scene', 'hierarchy', 'project', 'inspector'],
      );
      expect(layout, isNotNull);
      final root = layout!.root as DockSplit;
      expect((root.children[0] as DockTabs).panels, ['hierarchy']);
      expect(
        (root.children[1] as DockTabs).panels,
        containsAll(['scene', 'project']),
      );
      // The weights it was arranged with survive too.
      expect(root.weights, [0.3, 0.7]);
    });

    test('hidden and floating entries are renamed as well', () {
      const saved =
          '{"root":{"type":"tabs","panels":["viewport"],"active":0},'
          '"hidden":["outliner"],"floating":["assets"]}';
      final layout = DockLayout.tryParse(
        saved,
        knownPanels: const ['scene', 'hierarchy', 'project'],
      );
      expect(layout!.hidden, ['hierarchy']);
      expect(layout.floating, ['project']);
    });

    test('an extra view saved as viewport2 is kept, not renumbered', () {
      // Renumbering would move somebody's second view out from under the
      // arrangement they put it in.
      const saved =
          '{"root":{"type":"tabs","panels":["viewport","viewport2"],'
          '"active":0},"hidden":[],"floating":[]}';
      final layout = DockLayout.tryParse(
        saved,
        knownPanels: const ['scene'],
        isDynamic: RegExp(r'^(scene|viewport)\d+$').hasMatch,
      );
      expect(layout!.panelIds(), containsAll(['scene', 'viewport2']));
    });

    test('a name that was never renamed is left alone', () {
      for (final id in ['inspector', 'console', 'history', 'animation']) {
        expect(migratePanelId(id), id);
      }
    });

    test('every rename points somewhere, and never at itself', () {
      for (final entry in renamedPanelIds.entries) {
        expect(entry.value, isNotEmpty);
        expect(entry.key, isNot(entry.value));
        expect(renamedPanelIds.containsKey(entry.value), isFalse);
      }
    });
  });
}
