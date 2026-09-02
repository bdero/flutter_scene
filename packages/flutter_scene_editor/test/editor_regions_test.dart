/// The region map: where the four regions are, and that they stay there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_scene_editor/src/shell/editor_regions.dart';
import 'package:flutter_scene_editor/src/shell/editor_theme.dart';
import 'package:flutter_scene_editor/src/shell/panel_chrome.dart';

const Key _rail = Key('rail');
const Key _hierarchyBody = Key('hierarchy-body');
const Key _viewport = Key('viewport');
const Key _shelfBody = Key('shelf-body');
const Key _inspectorBody = Key('inspector-body');
const Key _status = Key('status');

Future<void> _pumpRegions(
  WidgetTester tester,
  EditorWorkspace workspace, {
  Size surface = const Size(1200, 800),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: editorDarkTheme(),
      home: Scaffold(
        body: EditorRegions(
          workspace: workspace,
          rail: Container(key: _rail, width: editorRailWidth),
          hierarchy: EditorRegion(
            header: const EditorPanelHeader(label: 'Hierarchy'),
            body: const SizedBox.expand(key: _hierarchyBody),
          ),
          viewport: const SizedBox.expand(key: _viewport),
          shelf: EditorRegion(
            header: const EditorPanelHeader(label: 'Project'),
            body: const SizedBox.expand(key: _shelfBody),
          ),
          inspector: EditorRegion(
            header: const EditorPanelHeader(label: 'Inspector'),
            body: const SizedBox.expand(key: _inspectorBody),
          ),
          statusBar: Container(key: _status, height: 22),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the four regions land where the reference puts them', (
    tester,
  ) async {
    final workspace = EditorWorkspace();
    await _pumpRegions(tester, workspace);

    expect(tester.getTopLeft(find.byKey(_rail)).dx, 0);
    expect(tester.getSize(find.byKey(_rail)).width, editorRailWidth);

    // Hierarchy left of the viewport, inspector right of it, both at their
    // declared widths.
    expect(
      tester.getSize(find.byKey(_hierarchyBody)).width,
      workspace.hierarchyWidth,
    );
    expect(
      tester.getSize(find.byKey(_inspectorBody)).width,
      workspace.inspectorWidth,
    );
    expect(
      tester.getTopLeft(find.byKey(_hierarchyBody)).dx,
      lessThan(tester.getTopLeft(find.byKey(_viewport)).dx),
    );
    expect(
      tester.getTopLeft(find.byKey(_inspectorBody)).dx,
      greaterThan(tester.getTopLeft(find.byKey(_viewport)).dx),
    );
  });

  testWidgets('the region headers line up with the top of the scene', (
    tester,
  ) async {
    await _pumpRegions(tester, EditorWorkspace());

    final hierarchyHeader = tester.getTopLeft(
      find.widgetWithText(EditorPanelHeader, 'HIERARCHY'),
    );
    final inspectorHeader = tester.getTopLeft(
      find.widgetWithText(EditorPanelHeader, 'INSPECTOR'),
    );
    // With no top bar the viewport starts at the window's edge, and the two
    // side headers start with it: one horizontal line across the top.
    final viewport = tester.getTopLeft(find.byKey(_viewport));

    expect(hierarchyHeader.dy, viewport.dy);
    expect(inspectorHeader.dy, viewport.dy);
  });

  testWidgets('the shelf runs under the viewport, not under the hierarchy', (
    tester,
  ) async {
    await _pumpRegions(tester, EditorWorkspace());

    final shelf = tester.getRect(find.byKey(_shelfBody));
    final viewport = tester.getRect(find.byKey(_viewport));
    final hierarchy = tester.getRect(find.byKey(_hierarchyBody));

    expect(shelf.top, greaterThan(viewport.top));
    expect(shelf.left, viewport.left);
    // The hierarchy runs past the shelf's top edge: a deep tree keeps the
    // window's full height.
    expect(hierarchy.bottom, greaterThan(shelf.top));
  });

  testWidgets('the status bar spans the window under everything', (
    tester,
  ) async {
    await _pumpRegions(tester, EditorWorkspace());

    final status = tester.getRect(find.byKey(_status));
    expect(status.left, 0);
    expect(status.width, 1200);
    expect(status.top, greaterThan(tester.getRect(find.byKey(_rail)).top));
  });

  testWidgets('a collapsed region leaves a strip with the way back', (
    tester,
  ) async {
    final workspace = EditorWorkspace(hierarchyOpen: false);
    await _pumpRegions(tester, workspace);

    expect(find.byKey(_hierarchyBody), findsNothing);
    expect(find.text('HIERARCHY'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_left).first);
    await tester.pump();
    expect(workspace.hierarchyOpen, isTrue);
  });

  testWidgets('a collapsed shelf keeps its header', (tester) async {
    await _pumpRegions(tester, EditorWorkspace(shelfOpen: false));

    expect(find.byKey(_shelfBody), findsNothing);
    expect(find.text('PROJECT'), findsOneWidget);
  });

  test('regions resize within their limits', () {
    final workspace = EditorWorkspace();

    workspace.resizeHierarchy(-999);
    expect(workspace.hierarchyWidth, EditorWorkspace.minHierarchyWidth);
    workspace.resizeHierarchy(999);
    expect(workspace.hierarchyWidth, EditorWorkspace.maxHierarchyWidth);

    // The inspector is on the right, so dragging its divider left widens it.
    workspace.resizeInspector(-40);
    expect(workspace.inspectorWidth, 340);
    workspace.resizeInspector(-999);
    expect(workspace.inspectorWidth, EditorWorkspace.maxInspectorWidth);
  });

  test('the shelf can never eat the viewport', () {
    final workspace = EditorWorkspace();
    workspace.resizeShelf(-9999, available: 800);
    expect(workspace.shelfHeight, 800 * 0.7);
  });

  test('showing a shelf mode opens the shelf', () {
    final workspace = EditorWorkspace(shelfOpen: false);
    workspace.showShelf(ShelfMode.console);

    expect(workspace.shelfOpen, isTrue);
    expect(workspace.shelfMode, ShelfMode.console);
  });

  testWidgets('the side panels give way before the scene does', (tester) async {
    // Widths a wide display allowed, on a laptop that cannot hold them.
    final workspace = EditorWorkspace(
      hierarchyWidth: EditorWorkspace.maxHierarchyWidth,
      inspectorWidth: EditorWorkspace.maxInspectorWidth,
    );
    await _pumpRegions(tester, workspace, surface: const Size(900, 700));

    final viewport = tester.getSize(find.byKey(_viewport));
    expect(
      viewport.width,
      greaterThanOrEqualTo(EditorWorkspace.minViewportWidth - 1),
    );
    // And they stop at their own minimums rather than disappearing.
    expect(
      tester.getSize(find.byKey(_hierarchyBody)).width,
      greaterThanOrEqualTo(EditorWorkspace.minHierarchyWidth),
    );
  });

  test('a width stored on a wider display is clamped when it is read', () {
    final restored = EditorWorkspace.tryParse(
      '{"type":"regions","hierarchyWidth":900,"inspectorWidth":1200}',
    )!;

    expect(restored.hierarchyWidth, EditorWorkspace.maxHierarchyWidth);
    expect(restored.inspectorWidth, EditorWorkspace.maxInspectorWidth);
  });

  test('the workspace round trips, and a saved dock layout does not', () {
    final workspace = EditorWorkspace(
      hierarchyWidth: 260,
      inspectorWidth: 340,
      shelfHeight: 180,
      inspectorOpen: false,
      shelfMode: ShelfMode.animation,
    );

    final restored = EditorWorkspace.tryParse(workspace.toJsonString())!;

    expect(restored.hierarchyWidth, 260);
    expect(restored.inspectorWidth, 340);
    expect(restored.shelfHeight, 180);
    expect(restored.inspectorOpen, isFalse);
    expect(restored.shelfMode, ShelfMode.animation);

    // What a settings file written before the regions landed holds.
    expect(
      EditorWorkspace.tryParse(
        '{"type":"split","axis":"h","children":[],"weights":[]}',
      ),
      isNull,
    );
    expect(EditorWorkspace.tryParse('not json at all'), isNull);
    expect(EditorWorkspace.tryParse(null), isNull);
  });
}
