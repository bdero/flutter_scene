/// The window: four fixed regions, a rail, and a status line.
///
/// There is no docking here, and that is the design rather than a stage on the
/// way to one. Panels that can be dragged anywhere have to be arranged before
/// they can be used, every arrangement is somebody's private one, and a screen
/// full of tab strips spends on chrome what the scene should be spending on
/// pixels. Fixed regions cost the ability to make a window nobody else can
/// read, and buy a window everybody already knows.
///
/// Regions resize and collapse. That is the whole vocabulary.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import 'editor_theme.dart';
import 'panel_chrome.dart';

/// What the viewport is showing: where you stand, where the player stands, or
/// both at once.
///
/// The scene alone is the default. The other two are there for when the
/// question is what the game's camera sees; most of the time the question is
/// what you are building, and that wants the whole width.
enum ViewportMode {
  scene('Scene', Icons.videocam_outlined),
  game('Game', Icons.sports_esports_outlined),
  both('Scene and game', Icons.vertical_split_outlined);

  const ViewportMode(this.label, this.icon);

  final String label;
  final IconData icon;

  static ViewportMode byName(String? name) => values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => ViewportMode.scene,
  );
}

/// Which surface the bottom shelf is showing.
///
/// One at a time and never a tab strip: the shelf is a place, and what is in
/// it is a mode of that place.
enum ShelfMode {
  project('Project', Icons.folder_outlined),
  console('Console', Icons.terminal),
  animation('Animation', Icons.animation),
  profiler('Profiler', Icons.speed);

  const ShelfMode(this.label, this.icon);

  final String label;
  final IconData icon;

  static ShelfMode byName(String? name) => values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => ShelfMode.project,
  );
}

/// Region sizes, collapse state, and which shelf mode is up.
///
/// Per user and per machine, never in the project file: how wide somebody
/// likes their inspector is not a property of the game.
class EditorWorkspace extends ChangeNotifier {
  EditorWorkspace({
    this.hierarchyWidth = 220,
    this.inspectorWidth = 300,
    this.shelfHeight = 260,
    this.hierarchyOpen = true,
    this.inspectorOpen = true,
    this.shelfOpen = true,
    this.shelfMode = ShelfMode.project,
    this.viewportMode = ViewportMode.scene,
  });

  /// Reads a workspace previously written by [toJsonString].
  ///
  /// Anything unreadable -- including a saved dock layout from before the
  /// regions landed -- returns null, and the caller starts from defaults. A
  /// broken workspace file must never be a broken editor.
  static EditorWorkspace? tryParse(String? source) {
    if (source == null || source.isEmpty) return null;
    try {
      final json = jsonDecode(source);
      if (json is! Map || json['type'] != 'regions') return null;
      double size(Object? value, double fallback) =>
          value is num ? value.toDouble() : fallback;
      bool open(Object? value) => value is bool ? value : true;
      return EditorWorkspace(
        // Clamped on the way in: a width stored on a wide display should not
        // arrive on a laptop as a panel with no scene beside it.
        hierarchyWidth: size(
          json['hierarchyWidth'],
          220,
        ).clamp(minHierarchyWidth, maxHierarchyWidth),
        inspectorWidth: size(
          json['inspectorWidth'],
          300,
        ).clamp(minInspectorWidth, maxInspectorWidth),
        shelfHeight: size(json['shelfHeight'], 260),
        hierarchyOpen: open(json['hierarchyOpen']),
        inspectorOpen: open(json['inspectorOpen']),
        shelfOpen: open(json['shelfOpen']),
        shelfMode: ShelfMode.byName(json['shelfMode'] as String?),
        viewportMode: ViewportMode.byName(json['viewportMode'] as String?),
      );
    } on FormatException {
      return null;
    }
  }

  /// The narrowest the scene is allowed to get.
  ///
  /// The side panels give way before the viewport does: they are readable at
  /// their minimum, and a scene three hundred pixels wide is not a scene you
  /// can work in.
  static const double minViewportWidth = 360;

  static const double minHierarchyWidth = 180;
  static const double maxHierarchyWidth = 420;
  static const double minInspectorWidth = 260;
  static const double maxInspectorWidth = 520;
  static const double minShelfHeight = 120;

  double hierarchyWidth;
  double inspectorWidth;
  double shelfHeight;
  bool hierarchyOpen;
  bool inspectorOpen;
  bool shelfOpen;
  ShelfMode shelfMode;
  ViewportMode viewportMode;

  void resizeHierarchy(double delta) {
    hierarchyWidth = (hierarchyWidth + delta).clamp(
      minHierarchyWidth,
      maxHierarchyWidth,
    );
    notifyListeners();
  }

  void resizeInspector(double delta) {
    inspectorWidth = (inspectorWidth - delta).clamp(
      minInspectorWidth,
      maxInspectorWidth,
    );
    notifyListeners();
  }

  /// [available] is the centre column's height, so the shelf can never eat
  /// the viewport it is supposed to sit under.
  void resizeShelf(double delta, {required double available}) {
    final maximum = (available * 0.7).clamp(minShelfHeight, double.infinity);
    shelfHeight = (shelfHeight - delta).clamp(minShelfHeight, maximum);
    notifyListeners();
  }

  void toggleHierarchy() {
    hierarchyOpen = !hierarchyOpen;
    notifyListeners();
  }

  void toggleInspector() {
    inspectorOpen = !inspectorOpen;
    notifyListeners();
  }

  void showViewport(ViewportMode mode) {
    if (viewportMode == mode) return;
    viewportMode = mode;
    notifyListeners();
  }

  void toggleShelf() {
    shelfOpen = !shelfOpen;
    notifyListeners();
  }

  /// Picking a mode also opens the shelf: choosing Console from a menu and
  /// getting nothing because the shelf was collapsed is the kind of dead
  /// control this editor does not have.
  void showShelf(ShelfMode mode) {
    shelfMode = mode;
    shelfOpen = true;
    notifyListeners();
  }

  String toJsonString() => jsonEncode({
    'type': 'regions',
    'hierarchyWidth': hierarchyWidth,
    'inspectorWidth': inspectorWidth,
    'shelfHeight': shelfHeight,
    'hierarchyOpen': hierarchyOpen,
    'inspectorOpen': inspectorOpen,
    'shelfOpen': shelfOpen,
    'shelfMode': shelfMode.name,
    'viewportMode': viewportMode.name,
  });
}

/// A region: its header, and what is under it.
class EditorRegion {
  const EditorRegion({required this.header, required this.body});

  final Widget header;
  final Widget body;
}

/// The window scaffold.
///
/// The headers of the hierarchy, the viewport and the inspector line up across
/// the top because they are all [editorHeaderHeight] and they all start at the
/// same y. One horizontal line across the window, and the scene starts under
/// it.
/// How wide a draggable divider is, grab area included.
const double _dividerThickness = 7;

class EditorRegions extends StatelessWidget {
  const EditorRegions({
    super.key,
    required this.workspace,
    required this.rail,
    required this.hierarchy,
    required this.viewport,
    required this.shelf,
    required this.inspector,
    required this.statusBar,
    this.onWorkspaceChanged,
    this.windowControlsInset = 0,
  });

  final EditorWorkspace workspace;
  final Widget rail;
  final EditorRegion hierarchy;

  final Widget viewport;
  final EditorRegion shelf;
  final EditorRegion inspector;
  final Widget statusBar;

  /// Called when a size or a collapse state settles, so the host can persist
  /// it. Not called per drag frame.
  final VoidCallback? onWorkspaceChanged;

  /// How far the host's own window controls reach across the top-left corner.
  /// A collapsed region under them puts its control below the band rather
  /// than beneath a traffic light.
  final double windowControlsInset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => _build(context, constraints.maxWidth),
    );
  }

  /// Side widths for a window this wide.
  ///
  /// The stored widths are what the user asked for; these are what fits. When
  /// the two panels would leave the scene less than [minViewportWidth] they
  /// give up the difference between them, in proportion, and never go below
  /// their own minimums.
  ({double hierarchy, double inspector}) _fittedWidths(double windowWidth) {
    final hierarchy = workspace.hierarchyOpen
        ? workspace.hierarchyWidth
        : editorHeaderHeight;
    final inspector = workspace.inspectorOpen
        ? workspace.inspectorWidth
        : editorHeaderHeight;
    // The dividers are part of the width too: forgetting them is how a
    // "minimum" ends up fourteen pixels under itself.
    final dividers =
        (workspace.hierarchyOpen ? _dividerThickness : 0) +
        (workspace.inspectorOpen ? _dividerThickness : 0);
    final spare =
        windowWidth -
        editorRailWidth -
        dividers -
        hierarchy -
        inspector -
        EditorWorkspace.minViewportWidth;
    if (spare >= 0) return (hierarchy: hierarchy, inspector: inspector);

    final shrinkable =
        (workspace.hierarchyOpen
            ? hierarchy - EditorWorkspace.minHierarchyWidth
            : 0) +
        (workspace.inspectorOpen
            ? inspector - EditorWorkspace.minInspectorWidth
            : 0);
    if (shrinkable <= 0) return (hierarchy: hierarchy, inspector: inspector);
    final take = (-spare).clamp(0.0, shrinkable) / shrinkable;
    return (
      hierarchy: workspace.hierarchyOpen
          ? hierarchy - (hierarchy - EditorWorkspace.minHierarchyWidth) * take
          : hierarchy,
      inspector: workspace.inspectorOpen
          ? inspector - (inspector - EditorWorkspace.minInspectorWidth) * take
          : inspector,
    );
  }

  Widget _build(BuildContext context, double windowWidth) {
    final widths = _fittedWidths(windowWidth);
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              rail,
              if (workspace.hierarchyOpen) ...[
                SizedBox(
                  width: widths.hierarchy,
                  child: _RegionColumn(region: hierarchy),
                ),
                EditorRegionDivider(
                  axis: Axis.vertical,
                  onDrag: workspace.resizeHierarchy,
                  onDragEnd: onWorkspaceChanged,
                ),
              ] else
                _CollapsedRegion(
                  label: 'Hierarchy',
                  clearControls: windowControlsInset > editorRailWidth,
                  onExpand: () {
                    workspace.toggleHierarchy();
                    onWorkspaceChanged?.call();
                  },
                ),
              Expanded(child: _CentreColumn(this)),
              if (workspace.inspectorOpen) ...[
                EditorRegionDivider(
                  axis: Axis.vertical,
                  onDrag: workspace.resizeInspector,
                  onDragEnd: onWorkspaceChanged,
                ),
                SizedBox(
                  width: widths.inspector,
                  child: _RegionColumn(region: inspector),
                ),
              ] else
                _CollapsedRegion(
                  label: 'Inspector',
                  onExpand: () {
                    workspace.toggleInspector();
                    onWorkspaceChanged?.call();
                  },
                ),
            ],
          ),
        ),
        statusBar,
      ],
    );
  }
}

/// The viewport and the shelf under it.
///
/// The shelf runs under the viewport only. It is tempting to let it span the
/// hierarchy as well and gain a few hundred pixels of asset grid, and it costs
/// the thing the hierarchy is for: a deep tree is unusable in the third of the
/// window a spanning shelf leaves it.
class _CentreColumn extends StatelessWidget {
  const _CentreColumn(this.regions);

  final EditorRegions regions;

  @override
  Widget build(BuildContext context) {
    final workspace = regions.workspace;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight;
        return Column(
          children: [
            Expanded(child: regions.viewport),
            if (workspace.shelfOpen) ...[
              EditorRegionDivider(
                axis: Axis.horizontal,
                onDrag: (delta) =>
                    workspace.resizeShelf(delta, available: available),
                onDragEnd: regions.onWorkspaceChanged,
              ),
              SizedBox(
                height: workspace.shelfHeight.clamp(
                  EditorWorkspace.minShelfHeight,
                  (available * 0.7).clamp(
                    EditorWorkspace.minShelfHeight,
                    double.infinity,
                  ),
                ),
                child: _RegionColumn(region: regions.shelf),
              ),
            ] else
              regions.shelf.header,
          ],
        );
      },
    );
  }
}

class _RegionColumn extends StatelessWidget {
  const _RegionColumn({required this.region});

  final EditorRegion region;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      region.header,
      Expanded(child: EditorPanelBody(child: region.body)),
    ],
  );
}

/// A collapsed side region: a strip with the way back.
class _CollapsedRegion extends StatelessWidget {
  const _CollapsedRegion({
    required this.label,
    required this.onExpand,
    this.clearControls = false,
  });

  final String label;
  final VoidCallback onExpand;

  /// Whether the host's window controls reach this strip.
  final bool clearControls;

  @override
  Widget build(BuildContext context) => Container(
    width: editorHeaderHeight,
    decoration: const BoxDecoration(
      color: editorPanelColor,
      border: Border(
        left: BorderSide(color: editorLineColor),
        right: BorderSide(color: editorLineColor),
      ),
    ),
    child: Column(
      children: [
        if (clearControls) const SizedBox(height: editorHeaderHeight),
        SizedBox(
          height: editorHeaderHeight,
          child: EditorPanelIconButton(
            icon: Icons.chevron_left,
            tooltip: 'Show $label',
            onPressed: onExpand,
          ),
        ),
        Expanded(
          child: RotatedBox(
            quarterTurns: 1,
            child: Center(
              child: Text(
                label.toUpperCase(),
                style: editorHeaderText.copyWith(color: editorMutedTextColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
