/// Remote control for the editor's own interface: the viewport tool and the
/// panels.
///
/// The shell and the viewport attach themselves when they come up, so a
/// command can switch tool or bring a panel forward the same way a menu item
/// does. Nothing is attached in a headless editor, which leaves those
/// commands inapplicable.
library;

/// The viewport tools and editor panels a host can drive.
class EditorUiHandle {
  String Function()? _readTool;
  void Function(String mode)? _writeTool;
  List<String> Function()? _readPanels;
  void Function(String id, {required bool focus})? _showPanel;

  /// Called by the viewport that owns the transform gizmo.
  void attachTool(String Function() read, void Function(String mode) write) {
    _readTool = read;
    _writeTool = write;
  }

  /// Called by that viewport on dispose.
  void detachTool(String Function() read) {
    if (identical(_readTool, read)) {
      _readTool = null;
      _writeTool = null;
    }
  }

  /// Called by the shell that owns the dock layout.
  void attachPanels(
    List<String> Function() panels,
    void Function(String id, {required bool focus}) show,
  ) {
    _readPanels = panels;
    _showPanel = show;
  }

  /// Called by that shell on dispose.
  void detachPanels(List<String> Function() panels) {
    if (identical(_readPanels, panels)) {
      _readPanels = null;
      _showPanel = null;
    }
  }

  /// Whether a viewport is attached.
  bool get hasTool => _writeTool != null;

  /// Whether a shell is attached.
  bool get hasPanels => _showPanel != null;

  /// The tools a viewport offers.
  static const List<String> toolModes = ['translate', 'rotate', 'scale'];

  /// The active tool, or `translate` when no viewport is attached.
  String get toolMode => _readTool?.call() ?? 'translate';

  /// Switches the active tool.
  void setToolMode(String mode) => _writeTool?.call(mode);

  /// The panels the shell knows about.
  List<String> get panels => _readPanels?.call() ?? const [];

  /// Shows the panel with [id], focusing it when [focus] is set.
  void showPanel(String id, {bool focus = false}) =>
      _showPanel?.call(id, focus: focus);
}
