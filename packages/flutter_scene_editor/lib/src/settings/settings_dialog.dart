/// The editor settings window, a category rail on the left with a General
/// tab (the source-editor launch command) and Flutter Installations, a
/// JetBrains-style list plus detail form over the global installation
/// registry, with per-row health badges, async identity probes, and hooks the
/// host wires for managed checkout creation/deletion and toolchain reloads.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart' hide FTheme;

import '../shell/editor_theme.dart';
import '../toolchains/editor_build_info.dart';
import '../toolchains/flutter_installation.dart';
import 'editor_settings.dart';
import 'open_in_editor.dart';
import '../shell/editor_dialog.dart';

/// Shows the settings window. Callbacks mutate/persist through the host.
Future<void> showSettingsDialog(
  BuildContext context, {
  required EditorSettings settings,
  required InstallationInspector inspector,
  required EditorBuildInfo buildInfo,
  required void Function() onChanged,
  required void Function() onSelectionChanged,
  Future<FlutterInstallation?> Function(BuildContext context)? onCreateManaged,
  Future<bool> Function(BuildContext context, FlutterInstallation installation)?
  onDeleteManaged,
}) {
  return showEditorDialog<void>(
    context,
    builder: (context) => Dialog(
      backgroundColor: editorSurfaceColor,
      child: SettingsDialog(
        settings: settings,
        inspector: inspector,
        buildInfo: buildInfo,
        onChanged: onChanged,
        onSelectionChanged: onSelectionChanged,
        onCreateManaged: onCreateManaged,
        onDeleteManaged: onDeleteManaged,
      ),
    ),
  );
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.settings,
    required this.inspector,
    required this.buildInfo,
    required this.onChanged,
    required this.onSelectionChanged,
    this.onCreateManaged,
    this.onDeleteManaged,
  });

  final EditorSettings settings;
  final InstallationInspector inspector;
  final EditorBuildInfo buildInfo;

  /// Persist the settings (any field changed).
  final void Function() onChanged;

  /// The active installation selection changed (the host reloads the fmat
  /// toolchain).
  final void Function() onSelectionChanged;

  /// Creates a managed checkout matching the editor's build and returns its
  /// installation record (null on failure/cancel); null hides the affordance.
  final Future<FlutterInstallation?> Function(BuildContext context)?
  onCreateManaged;

  /// Deletes a managed checkout from disk, returning whether it was deleted;
  /// null leaves managed rows undeletable.
  final Future<bool> Function(
    BuildContext context,
    FlutterInstallation installation,
  )?
  onDeleteManaged;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  /// The category shown on the right, an index into [_categories].
  int _category = 0;

  static const _categories = ['General', 'Flutter Installations'];

  /// The row highlighted in the list (not the globally active selection).
  String? _highlightedId;

  EditorSettings get _settings => widget.settings;

  @override
  void initState() {
    super.initState();
    _highlightedId = _settings.selectedInstallationId;
  }

  FlutterInstallation? get _highlighted =>
      _settings.installationById(_highlightedId);

  void _mutate(void Function() edit) {
    setState(edit);
    widget.onChanged();
  }

  Future<void> _addInstallation() async {
    final file = await openFile();
    final path = file?.path;
    if (path == null || !mounted) return;
    final installation = FlutterInstallation(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      name: _defaultName(path),
      flutterBin: path,
    );
    _mutate(() => _settings.flutterInstallations.add(installation));
    widget.inspector.invalidate(path);
    setState(() => _highlightedId = installation.id);
    // Re-name from the probe when identity resolves and the name was default.
    final probe = await widget.inspector.probe(installation);
    if (!mounted || probe.frameworkVersion == null) return;
    final index = _settings.flutterInstallations.indexWhere(
      (candidate) => candidate.id == installation.id,
    );
    if (index < 0) return;
    if (_settings.flutterInstallations[index].name == _defaultName(path)) {
      _mutate(() {
        _settings.flutterInstallations[index] = _settings
            .flutterInstallations[index]
            .copyWith(name: 'Flutter ${probe.frameworkVersion}');
      });
    }
  }

  static String _defaultName(String flutterBin) {
    final root = _sdkRootName(flutterBin);
    return root.isEmpty ? 'Flutter SDK' : 'Flutter ($root)';
  }

  static String _sdkRootName(String flutterBin) {
    final parts = flutterBin.replaceAll('\\', '/').split('/');
    // <...>/<root>/bin/flutter
    return parts.length >= 3 ? parts[parts.length - 3] : '';
  }

  void _removeInstallation(FlutterInstallation installation) {
    _mutate(() {
      _settings.flutterInstallations.removeWhere(
        (candidate) => candidate.id == installation.id,
      );
      if (_settings.selectedInstallationId == installation.id) {
        _settings.selectedInstallationId = null;
        widget.onSelectionChanged();
      }
      if (_highlightedId == installation.id) _highlightedId = null;
    });
  }

  void _selectActive(String? id) {
    if (_settings.selectedInstallationId == id) return;
    _mutate(() => _settings.selectedInstallationId = id);
    widget.onSelectionChanged();
  }

  Future<void> _createManaged(BuildContext context) async {
    final created = await widget.onCreateManaged!(context);
    if (created == null || !mounted) return;
    _mutate(() {
      _settings.flutterInstallations.removeWhere(
        (candidate) => candidate.id == created.id,
      );
      _settings.flutterInstallations.add(created);
      _highlightedId = created.id;
    });
    _selectActive(created.id);
  }

  Future<void> _deleteManaged(FlutterInstallation installation) async {
    final deleted = await widget.onDeleteManaged!(context, installation);
    if (!deleted || !mounted) return;
    _removeInstallation(installation);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 760,
      height: 540,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Settings', style: editorDialogTitleText),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 170, child: _categoryRail(context)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _category == 0
                        ? _generalTab(context)
                        : _installationsTab(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (_category == 1 && widget.onCreateManaged != null)
                  FButton(
                    variant: .outline,
                    size: .xs,
                    mainAxisSize: .min,
                    onPress: () => _createManaged(context),
                    prefix: const Icon(Icons.download_outlined, size: 14),
                    child: const Text('Create managed checkout…'),
                  ),
                const Spacer(),
                FButton(
                  variant: .outline,
                  size: .xs,
                  mainAxisSize: .min,
                  onPress: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryRail(BuildContext context) {
    return Container(
      decoration: editorPanelBox(),
      child: ListView(
        children: [
          for (var i = 0; i < _categories.length; i++)
            ListTile(
              dense: true,
              selected: _category == i,
              selectedTileColor: editorAccentColor.withValues(alpha: 0.12),
              title: Text(_categories[i], style: editorMenuItemText),
              onTap: () => setState(() => _category = i),
            ),
        ],
      ),
    );
  }

  Widget _generalTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EditorSectionHeader(label: 'General'),
        const SizedBox(height: 8),
        const Text('Source editor', style: editorBodyText),
        const SizedBox(height: 4),
        const Text(
          'Command that opens component source files. '
          '$kSourceFilePlaceholder is replaced with the file path, appended '
          'when absent.',
          style: editorDetailText,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _EditorCommandField(
                value: _settings.editorCommand,
                onCommit: (value) => _mutate(
                  () => _settings.editorCommand = value.trim().isEmpty
                      ? EditorSettings.defaultEditorCommand
                      : value.trim(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FButton(
              variant: .outline,
              size: .xs,
              mainAxisSize: .min,
              onPress: () => _browseEditorProgram(context),
              child: const Text('Browse…'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _browseEditorProgram(BuildContext context) async {
    final file = await openFile();
    final path = file?.path;
    if (path == null || !mounted) return;
    // Quote a picked program path so spaces survive the shell (single quotes
    // are literal in both sh and PowerShell); the source file rides the
    // placeholder.
    final quoted = path.contains(' ') ? quoteEditorCommandPath(path) : path;
    _mutate(() => _settings.editorCommand = '$quoted $kSourceFilePlaceholder');
  }

  Widget _installationsTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EditorSectionHeader(label: 'Flutter Installations'),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 270, child: _installationList(context)),
              const SizedBox(width: 12),
              Expanded(child: _detailPane(context)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _installationList(BuildContext context) {
    return Container(
      decoration: editorPanelBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              children: [
                _builtInRow(context),
                for (final installation in _settings.flutterInstallations)
                  _installationRow(context, installation),
              ],
            ),
          ),
          const Divider(height: 1),
          Row(
            children: [
              IconButton(
                tooltip: 'Add installation (pick a flutter CLI)',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 16),
                onPressed: _addInstallation,
              ),
              IconButton(
                tooltip: _highlighted?.managed == true
                    ? 'Managed checkouts are deleted from the detail pane'
                    : 'Remove installation (the checkout stays on disk)',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove, size: 16),
                onPressed: _highlighted == null || _highlighted!.managed
                    ? null
                    : () => _removeInstallation(_highlighted!),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _activeToggle(bool active, VoidCallback onSelect) => IconButton(
    tooltip: active ? 'Active installation' : 'Make active',
    visualDensity: VisualDensity.compact,
    icon: Icon(
      active ? Icons.radio_button_checked : Icons.radio_button_off,
      size: 15,
    ),
    onPressed: onSelect,
  );

  Widget _builtInRow(BuildContext context) {
    final active = _settings.selectedInstallationId == null;
    return ListTile(
      dense: true,
      selected: _highlightedId == null,
      leading: _activeToggle(active, () => _selectActive(null)),
      title: const Text('Built-in toolchain', style: TextStyle(fontSize: 12)),
      subtitle: const Text(
        'The editor\'s bundled shader compiler. No flutter CLI.',
        style: TextStyle(fontSize: 10),
      ),
      onTap: () => setState(() => _highlightedId = null),
    );
  }

  Widget _installationRow(
    BuildContext context,
    FlutterInstallation installation,
  ) {
    final active = _settings.selectedInstallationId == installation.id;
    return ListTile(
      dense: true,
      selected: _highlightedId == installation.id,
      leading: _activeToggle(active, () => _selectActive(installation.id)),
      title: Row(
        children: [
          Flexible(
            child: Text(
              installation.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          _ValidationBadge(
            installation: installation,
            inspector: widget.inspector,
            buildInfo: widget.buildInfo,
          ),
        ],
      ),
      subtitle: Text(
        installation.managed ? 'Managed by the editor' : installation.sdkRoot,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10),
      ),
      onTap: () => setState(() => _highlightedId = installation.id),
    );
  }

  Widget _detailPane(BuildContext context) {
    final installation = _highlighted;
    if (installation == null) {
      return _builtInDetail(context);
    }
    return _InstallationDetail(
      key: ValueKey(installation.id),
      installation: installation,
      inspector: widget.inspector,
      buildInfo: widget.buildInfo,
      onEdited: (updated) {
        final index = _settings.flutterInstallations.indexWhere(
          (candidate) => candidate.id == updated.id,
        );
        if (index < 0) return;
        _mutate(() => _settings.flutterInstallations[index] = updated);
        widget.inspector.invalidate(updated.flutterBin);
        if (_settings.selectedInstallationId == updated.id) {
          widget.onSelectionChanged();
        }
      },
      onDeleteManaged: widget.onDeleteManaged == null
          ? null
          : () => _deleteManaged(installation),
    );
  }

  Widget _builtInDetail(BuildContext context) {
    final info = widget.buildInfo;
    return _InfoPanel(
      title: 'Built-in toolchain',
      lines: [
        'The impellerc bundled with the editor, always matched to the '
            'renderer. Used for compiling .fmat materials when no '
            'installation is selected.',
        if (info.isKnown)
          'Editor built with Flutter ${info.frameworkVersion ?? ''} '
              '(${info.frameworkRevision?.substring(0, 10) ?? ''}), '
              'flutter_scene ${info.flutterSceneVersion ?? 'unknown'}.',
        'Build and Play need a full Flutter installation; add one or create '
            'a managed checkout.',
      ],
    );
  }
}

class _ValidationBadge extends StatelessWidget {
  const _ValidationBadge({
    required this.installation,
    required this.inspector,
    required this.buildInfo,
  });

  final FlutterInstallation installation;
  final InstallationInspector inspector;
  final EditorBuildInfo buildInfo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<InstallationValidation>(
      future: inspector.validate(installation, buildInfo),
      builder: (context, snapshot) {
        final validation = snapshot.data;
        if (validation == null ||
            validation.severity == InstallationSeverity.ok) {
          return const SizedBox.shrink();
        }
        final error = validation.severity == InstallationSeverity.error;
        return Tooltip(
          message: validation.summary,
          child: Icon(
            error ? Icons.error_outline : Icons.warning_amber_outlined,
            size: 13,
            color: error ? editorErrorColor : editorWarningColor,
          ),
        );
      },
    );
  }
}

class _InstallationDetail extends StatefulWidget {
  const _InstallationDetail({
    super.key,
    required this.installation,
    required this.inspector,
    required this.buildInfo,
    required this.onEdited,
    this.onDeleteManaged,
  });

  final FlutterInstallation installation;
  final InstallationInspector inspector;
  final EditorBuildInfo buildInfo;
  final void Function(FlutterInstallation updated) onEdited;
  final Future<void> Function()? onDeleteManaged;

  @override
  State<_InstallationDetail> createState() => _InstallationDetailState();
}

class _InstallationDetailState extends State<_InstallationDetail> {
  late final TextEditingController _name = TextEditingController(
    text: widget.installation.name,
  );
  late final TextEditingController _flutterBin = TextEditingController(
    text: widget.installation.flutterBin,
  );
  late final TextEditingController _impellerc = TextEditingController(
    text: widget.installation.impellerc ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _flutterBin.dispose();
    _impellerc.dispose();
    super.dispose();
  }

  void _commit() {
    widget.onEdited(
      widget.installation.copyWith(
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        flutterBin: _flutterBin.text.trim().isEmpty
            ? null
            : _flutterBin.text.trim(),
        impellerc: _impellerc.text.trim().isEmpty
            ? null
            : _impellerc.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editable = !widget.installation.managed;
    final resolvedImpellerc = widget.installation.resolvedImpellerc;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(context, 'Name', _name, editable: true),
          _field(
            context,
            'Flutter CLI',
            _flutterBin,
            editable: editable,
            onBrowse: editable
                ? () async {
                    final file = await openFile();
                    if (file != null) {
                      _flutterBin.text = file.path;
                      _commit();
                    }
                  }
                : null,
          ),
          _field(
            context,
            'impellerc',
            _impellerc,
            editable: editable,
            hint: resolvedImpellerc == null
                ? 'auto (unresolved)'
                : 'auto ($resolvedImpellerc)',
            onBrowse: editable
                ? () async {
                    final file = await openFile();
                    if (file != null) {
                      _impellerc.text = file.path;
                      _commit();
                    }
                  }
                : null,
          ),
          const SizedBox(height: 10),
          _probePanel(context),
          if (widget.installation.managed &&
              widget.onDeleteManaged != null) ...[
            const SizedBox(height: 12),
            FButton(
              variant: .outline,
              size: .xs,
              mainAxisSize: .min,
              onPress: widget.onDeleteManaged,
              prefix: const Icon(Icons.delete_outline, size: 14),
              child: const Text('Delete managed checkout…'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context,
    String label,
    TextEditingController controller, {
    required bool editable,
    String? hint,
    Future<void> Function()? onBrowse,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontSize: 11)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: editable,
              style: const TextStyle(fontSize: 11),
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 10),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
              onSubmitted: (_) => _commit(),
              onTapOutside: (_) => _commit(),
            ),
          ),
          if (onBrowse != null)
            IconButton(
              tooltip: 'Browse',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.folder_open, size: 15),
              onPressed: onBrowse,
            ),
        ],
      ),
    );
  }

  Widget _probePanel(BuildContext context) {
    return FutureBuilder<InstallationProbe>(
      future: widget.inspector.probe(widget.installation),
      builder: (context, snapshot) {
        final probe = snapshot.data;
        if (probe == null) {
          return const Text('Probing…', style: TextStyle(fontSize: 11));
        }
        return _InfoPanel(
          title: 'Detected',
          lines: [
            'Version, ${probe.frameworkVersion ?? 'unknown'}',
            'Revision, ${probe.frameworkRevision ?? 'unknown'}',
            if (probe.engineRevision != null) 'Engine, ${probe.engineRevision}',
            if (probe.dartSdkVersion != null) 'Dart, ${probe.dartSdkVersion}',
            if (probe.repositoryUrl != null)
              'Repository, ${probe.repositoryUrl}',
            if (!probe.bootstrapped)
              'Not bootstrapped (bin/cache is empty). Run flutter --version '
                  'in this SDK once, or use it in a Build to bootstrap.',
          ],
        );
      },
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: editorPanelBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(line, style: const TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

/// The editor-command text field, committing on submit or focus loss.
class _EditorCommandField extends StatefulWidget {
  const _EditorCommandField({required this.value, required this.onCommit});

  final String value;
  final ValueChanged<String> onCommit;

  @override
  State<_EditorCommandField> createState() => _EditorCommandFieldState();
}

class _EditorCommandFieldState extends State<_EditorCommandField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onCommit(_controller.text);
    });
  }

  @override
  void didUpdateWidget(_EditorCommandField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      style: const TextStyle(fontSize: 12),
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
      ),
      onSubmitted: widget.onCommit,
    );
  }
}
