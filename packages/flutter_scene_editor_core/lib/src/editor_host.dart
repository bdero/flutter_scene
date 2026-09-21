/// The application around the document, reached by application commands.
///
/// The editor implements this over the same paths its menus use, so opening a
/// document, running the project, switching tool, or focusing a panel is one
/// verb whether a person, a script, or an agent asks for it. A headless
/// session has no host, which leaves every application command inapplicable.
library;

/// What an application command acts on.
abstract class EditorHost {
  /// Whether the command named [command] can run right now. Hosts override
  /// this for state-dependent cases, such as running a project when none is
  /// open. Commands consult it through their `applicable` predicate.
  bool supports(String command) => true;

  /// Replaces the open document with an empty one.
  Future<void> newDocument();

  /// Opens the `.fscene` at [path].
  Future<void> openDocument(String path);

  /// Saves the open document, to [path] when given.
  Future<void> saveDocument({String? path});

  /// Opens the project at [path] (an `.fproject`, or the directory holding
  /// one).
  Future<void> openProject(String path);

  /// Closes the open project.
  Future<void> closeProject();

  /// Selects the build configuration with [id].
  Future<void> selectBuildConfiguration(String id);

  /// Selects the target device with [id].
  Future<void> selectDevice(String id);

  /// Builds the project.
  Future<void> buildProject();

  /// Runs the project.
  Future<void> runProject();

  /// Stops the running project.
  Future<void> stopProject();

  /// Hot reloads the running project.
  Future<void> hotReload();

  /// Hot restarts the running project.
  Future<void> hotRestart();

  /// Reloads the running project's scene from the document.
  Future<void> reloadScene();

  /// Imports the model at [path], optionally under [parentId] and scaled.
  Future<void> importModel(String path, {String? parentId, double scale});

  /// Imports the environment image at [path].
  Future<void> importEnvironment(String path);

  /// The active viewport tool (`translate`, `rotate`, `scale`, ...).
  String get toolMode;

  /// Switches the active viewport tool.
  void setToolMode(String mode);

  /// The viewport tools this host offers.
  List<String> get toolModes;

  /// Shows the panel with [id], docking it when it is not in the layout.
  void showPanel(String id);

  /// Focuses the panel with [id].
  void focusPanel(String id);

  /// The panels this host knows about.
  List<String> get panels;

  /// The viewport debug modes this host offers.
  List<String> get viewportDebugModes;

  /// Switches the viewport debug mode.
  void setViewportDebugMode(String mode);
}
