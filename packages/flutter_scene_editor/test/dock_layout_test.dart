import 'package:flutter/widgets.dart';
import 'package:flutter_scene_editor/src/shell/dock_layout.dart';
import 'package:flutter_test/flutter_test.dart';

DockLayout _twoColumn() {
  return DockLayout(
    DockSplit(
      Axis.horizontal,
      [
        DockTabs(['viewport']),
        DockTabs(['outliner', 'inspector'], active: 1),
      ],
      [0.7, 0.3],
    ),
  );
}

void main() {
  test('json round-trips', () {
    final layout = _twoColumn();
    final restored = DockLayout.fromJsonString(layout.toJsonString());
    expect(restored.panelIds(), ['viewport', 'outliner', 'inspector']);
    final split = restored.root as DockSplit;
    expect(split.axis, Axis.horizontal);
    expect(split.weights, [0.7, 0.3]);
    expect((split.children[1] as DockTabs).active, 1);
  });

  test('removing a group\'s last panel collapses the split', () {
    final layout = _twoColumn();
    layout.removePanel('viewport');
    final tabs = layout.root as DockTabs;
    expect(tabs.panels, ['outliner', 'inspector']);
  });

  test('removing keeps the active tab pointed at the same panel', () {
    final layout = _twoColumn();
    layout.removePanel('outliner');
    final tabs = (layout.root as DockSplit).children[1] as DockTabs;
    expect(tabs.activePanel, 'inspector');
  });

  test('center dock moves a panel into the target group', () {
    final layout = _twoColumn();
    final target = (layout.root as DockSplit).children[0] as DockTabs;
    layout.dock('inspector', target, DockZone.center);
    expect(target.panels, ['viewport', 'inspector']);
    expect(target.activePanel, 'inspector');
    // The source group survives with its remaining tab.
    expect(layout.panelIds(), ['viewport', 'inspector', 'outliner']);
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
    expect((inner.children[0] as DockTabs).panels, ['viewport']);
    expect((inner.children[1] as DockTabs).panels, ['inspector']);
  });

  test('docking a sole tab onto its own group is a no-op', () {
    final layout = _twoColumn();
    final target = (layout.root as DockSplit).children[0] as DockTabs;
    final before = layout.toJsonString();
    layout.dock('viewport', target, DockZone.center);
    layout.dock('viewport', target, DockZone.left);
    expect(layout.toJsonString(), before);
  });

  test('tryParse drops unknown panels and appends missing ones', () {
    final source = DockLayout(
      DockSplit(
        Axis.horizontal,
        [
          DockTabs(['viewport', 'retired']),
          DockTabs(['outliner']),
        ],
        [0.5, 0.5],
      ),
    ).toJsonString();
    final layout = DockLayout.tryParse(
      source,
      knownPanels: ['viewport', 'outliner', 'inspector'],
    );
    expect(layout, isNotNull);
    expect(layout!.panelIds().toSet(), {'viewport', 'outliner', 'inspector'});
  });

  test('hide/show round-trips through the hidden list', () {
    final layout = _twoColumn();
    layout.hidePanel('viewport');
    expect(layout.isVisible('viewport'), isFalse);
    expect(layout.hidden, ['viewport']);
    expect(layout.root, isA<DockTabs>());
    layout.showPanel('viewport');
    expect(layout.isVisible('viewport'), isTrue);
    expect(layout.hidden, isEmpty);
  });

  test('float moves a panel out of the tree and dock() brings it back', () {
    final layout = _twoColumn();
    layout.floatPanel('inspector');
    expect(layout.floating, ['inspector']);
    expect(layout.panelIds(), ['viewport', 'outliner']);
    final target = layout.root as DockSplit;
    layout.dock('inspector', target.children[0] as DockTabs, DockZone.center);
    expect(layout.floating, isEmpty);
    expect(layout.isVisible('inspector'), isTrue);
  });

  test('v2 json round-trips hidden and floating', () {
    final layout = _twoColumn();
    layout.hidePanel('outliner');
    layout.floatPanel('inspector');
    final restored = DockLayout.fromJsonString(layout.toJsonString());
    expect(restored.hidden, ['outliner']);
    expect(restored.floating, ['inspector']);
    expect(restored.panelIds(), ['viewport']);
  });

  test('legacy root-only json still parses', () {
    const legacy =
        '{"type":"tabs","panels":["viewport","outliner"],"active":0}';
    final layout = DockLayout.tryParse(
      legacy,
      knownPanels: ['viewport', 'outliner'],
    );
    expect(layout, isNotNull);
    expect(layout!.panelIds(), ['viewport', 'outliner']);
    expect(layout.hidden, isEmpty);
    expect(layout.floating, isEmpty);
  });

  test('tryParse keeps hidden panels hidden and dedupes stale entries', () {
    final source = DockLayout(
      DockTabs(['viewport', 'outliner']),
      hidden: ['history', 'outliner', 'retired'],
      floating: ['assets'],
    ).toJsonString();
    final layout = DockLayout.tryParse(
      source,
      knownPanels: ['viewport', 'outliner', 'history', 'assets'],
    );
    expect(layout, isNotNull);
    // outliner is docked, so the stale hidden entry is dropped; history stays
    // hidden rather than being re-appended; assets stays floating.
    expect(layout!.panelIds(), ['viewport', 'outliner']);
    expect(layout.hidden, ['history']);
    expect(layout.floating, ['assets']);
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
      DockTabs(['viewport', 'viewport2', 'stale9']),
    ).toJsonString();
    bool isDynamic(String id) =>
        RegExp(r'^viewport\d+$').hasMatch(id) || id == 'stale9';
    final layout = DockLayout.tryParse(
      source,
      knownPanels: ['viewport'],
      isDynamic: RegExp(r'^viewport\d+$').hasMatch,
    );
    expect(layout, isNotNull);
    expect(layout!.panelIds(), ['viewport', 'viewport2']);
    // A layout without the dynamic panel does not grow one.
    final bare = DockLayout(DockTabs(['viewport'])).toJsonString();
    final reparsed = DockLayout.tryParse(
      bare,
      knownPanels: ['viewport'],
      isDynamic: isDynamic,
    );
    expect(reparsed!.panelIds(), ['viewport']);
  });

  test('tryParse rejects garbage', () {
    expect(DockLayout.tryParse('not json', knownPanels: ['viewport']), isNull);
    expect(
      DockLayout.tryParse('{"type":"nope"}', knownPanels: ['viewport']),
      isNull,
    );
    expect(DockLayout.tryParse(null, knownPanels: ['viewport']), isNull);
  });
}
