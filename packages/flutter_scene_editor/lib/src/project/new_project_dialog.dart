/// The New Project dialog. Collects a location, app name, and Flutter
/// installation (a configured one, or the editor's managed SDK installed on
/// the spot), then scaffolds the app, showing each job's phases and log in
/// place. Wrapping an existing Flutter app is offered alongside.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:forui/forui.dart' hide FTheme;
import 'package:material_ui/material_ui.dart';

import '../shell/editor_dialog.dart';
import '../shell/editor_theme.dart';
import '../toolchains/flutter_installation.dart';
import '../toolchains/managed_checkout.dart';
import 'fproject.dart';
import 'project_scaffold.dart';

/// How the New Project dialog ended, a created [project] or a request to
/// wrap an existing Flutter app instead ([useExisting]).
typedef NewProjectChoice = ({FProject? project, bool useExisting});

/// Shows the New Project dialog. Resolves to null when dismissed.
///
/// The installation picker lists [installations] plus, when [installManaged]
/// is given, an entry that installs the editor's managed Flutter SDK
/// ([managedVersion] names it). It starts on [initialInstallation], else the
/// managed entry, else the first installation. [recommended] is marked as
/// matching the editor. [onInstallationUsed] receives the installation the
/// app is created with (a freshly installed one included) before
/// scaffolding starts.
Future<NewProjectChoice?> showNewProjectDialog(
  BuildContext context, {
  required List<FlutterInstallation> installations,
  FlutterInstallation? initialInstallation,
  FlutterInstallation? recommended,
  ManagedCheckoutJob Function()? installManaged,
  void Function(FlutterInstallation installation)? onInstallationUsed,
  String? managedVersion,
  String? flutterSceneVersion,
  String? initialLocation,
  ProjectScaffolder Function(FlutterInstallation installation)? scaffolderFor,
}) {
  return showEditorDialog<NewProjectChoice>(
    context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      child: _NewProjectDialog(
        installations: installations,
        initialInstallation: initialInstallation,
        recommended: recommended,
        installManaged: installManaged,
        onInstallationUsed: onInstallationUsed,
        managedVersion: managedVersion,
        scaffolderFor:
            scaffolderFor ??
            (installation) => ProjectScaffolder(
              installation: installation,
              flutterSceneVersion: flutterSceneVersion,
            ),
        initialLocation: initialLocation ?? _homeDirectory(),
      ),
    ),
  );
}

String _homeDirectory() =>
    Platform.environment['USERPROFILE'] ??
    Platform.environment['HOME'] ??
    Directory.current.path;

/// Whether `git` runs; the managed SDK is a git checkout.
Future<bool> _gitAvailable() async {
  try {
    return (await Process.run('git', ['--version'])).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog({
    required this.installations,
    required this.initialInstallation,
    required this.recommended,
    required this.installManaged,
    required this.onInstallationUsed,
    required this.managedVersion,
    required this.scaffolderFor,
    required this.initialLocation,
  });

  final List<FlutterInstallation> installations;
  final FlutterInstallation? initialInstallation;
  final FlutterInstallation? recommended;
  final ManagedCheckoutJob Function()? installManaged;
  final void Function(FlutterInstallation installation)? onInstallationUsed;
  final String? managedVersion;
  final ProjectScaffolder Function(FlutterInstallation installation)
  scaffolderFor;
  final String initialLocation;

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

enum _PhaseState { pending, active, done, failed }

class _NewProjectDialogState extends State<_NewProjectDialog> {
  late final TextEditingController _location = TextEditingController(
    text: widget.initialLocation,
  );
  final TextEditingController _name = TextEditingController(text: 'my_scene');
  // The picked installation's id, or [_installManagedId].
  late String? _choice =
      widget.initialInstallation?.id ??
      (widget.installManaged != null
          ? _installManagedId
          : widget.installations.firstOrNull?.id);
  String? _error;
  bool _starting = false;
  ManagedCheckoutJob? _sdkJob;
  ProjectScaffoldJob? _job;

  // Not a valid installation id (those are generated or `managed-<sha>`).
  static const _installManagedId = ' install-managed';

  bool get _canCreate => _choice != null;

  String get _managedName =>
      'Flutter${widget.managedVersion == null ? '' : ' ${widget.managedVersion}'}';

  FlutterInstallation? get _chosenInstallation {
    for (final installation in widget.installations) {
      if (installation.id == _choice) return installation;
    }
    return null;
  }

  bool get _running => _sdkJob != null || _job != null;

  @override
  void dispose() {
    _location.dispose();
    _name.dispose();
    _sdkJob?.removeListener(_onSdkJob);
    _sdkJob?.dispose();
    _job?.removeListener(_onJob);
    _job?.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_canCreate || _starting) return;
    final parent = Directory(
      _location.text.trim(),
    ).absolute.path.replaceAll(RegExp(r'[/\\]$'), '');
    final name = _name.text.trim();
    // Checked before any download so a bad name fails in a second, not after
    // the SDK install.
    final error =
        validateProjectName(name) ??
        validateProjectDirectory('$parent${Platform.pathSeparator}$name');
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final installation = _chosenInstallation;
    if (installation != null) {
      _scaffold(installation);
      return;
    }
    setState(() => _starting = true);
    final hasGit = await _gitAvailable();
    if (!mounted) return;
    if (!hasGit) {
      setState(() {
        _starting = false;
        _error =
            'Installing Flutter needs Git. Install it from '
            'https://git-scm.com, then try again.';
      });
      return;
    }
    final job = widget.installManaged!()..addListener(_onSdkJob);
    setState(() {
      _starting = false;
      _error = null;
      _sdkJob = job;
    });
  }

  void _onSdkJob() {
    final job = _sdkJob!;
    final installed = job.result;
    if (!job.done || installed == null || _job != null || !mounted) return;
    _scaffold(installed);
  }

  void _scaffold(FlutterInstallation installation) {
    widget.onInstallationUsed?.call(installation);
    final ProjectScaffoldJob job;
    try {
      job = widget
          .scaffolderFor(installation)
          .create(
            parentDirectory: _location.text.trim(),
            name: _name.text.trim(),
          );
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    job.addListener(_onJob);
    setState(() {
      _error = null;
      _job = job;
    });
  }

  void _onJob() {
    final job = _job!;
    if (job.done && job.result != null && mounted) {
      Navigator.of(context).pop((project: job.result, useExisting: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 560,
      height: _running ? 440 : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _running ? _progress(context) : _form(context),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final enabled = _canCreate && !_starting;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'New project',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Creates a Flutter app set up for flutter_scene.',
          style: TextStyle(fontSize: 11, color: editorMutedTextColor),
        ),
        const SizedBox(height: 12),
        _field(
          'Location',
          _location,
          enabled: enabled,
          onBrowse: enabled
              ? () async {
                  final directory = await getDirectoryPath(
                    initialDirectory: _location.text.trim(),
                  );
                  if (directory != null) _location.text = directory;
                }
              : null,
        ),
        _field('Name', _name, enabled: enabled, onSubmitted: _create),
        _installationPicker(enabled: enabled),
        if (!_canCreate)
          const Text(
            'No Flutter installation is available. Configure one in Settings, '
            'or open an existing Flutter app.',
            style: TextStyle(fontSize: 11, color: editorErrorColor),
          )
        else if (_choice == _installManagedId)
          const Padding(
            padding: EdgeInsets.only(left: 70),
            child: Text(
              'A one-time download of a few GB, shared by every project.',
              style: TextStyle(fontSize: 11, color: editorMutedTextColor),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _error!,
              style: const TextStyle(fontSize: 11, color: editorErrorColor),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            FButton(
              variant: .ghost,
              size: .xs,
              mainAxisSize: .min,
              onPress: () =>
                  Navigator.of(context).pop((project: null, useExisting: true)),
              child: const Text('Existing Flutter app…'),
            ),
            const Spacer(),
            FButton(
              variant: .outline,
              size: .xs,
              mainAxisSize: .min,
              onPress: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FButton(
              size: .xs,
              mainAxisSize: .min,
              onPress: enabled ? _create : null,
              child: const Text('Create'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _installationPicker({required bool enabled}) {
    final items = [
      for (final installation in widget.installations)
        DropdownMenuItem(
          value: installation.id,
          child: Text(
            installation.id == widget.recommended?.id
                ? '${installation.name} (matches the editor)'
                : installation.name,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      if (widget.installManaged != null)
        DropdownMenuItem(
          value: _installManagedId,
          child: Text('Install $_managedName (managed)'),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 70,
            child: Text('Flutter', style: TextStyle(fontSize: 11)),
          ),
          Expanded(
            child: DropdownButton<String>(
              value: _choice,
              isExpanded: true,
              isDense: true,
              style: const TextStyle(fontSize: 11, color: editorTextColor),
              hint: const Text('None available'),
              items: items,
              onChanged: enabled && items.isNotEmpty
                  ? (value) => setState(() {
                      _choice = value;
                      _error = null;
                    })
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    required bool enabled,
    Future<void> Function()? onBrowse,
    VoidCallback? onSubmitted,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: const TextStyle(fontSize: 11)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
              onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
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

  Widget _progress(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_sdkJob, _job]),
      builder: (context, _) {
        final sdk = _sdkJob;
        final job = _job;
        final error = job?.error ?? sdk?.error;
        final done = job?.done ?? sdk!.done;
        final cancelling = job?.cancelled ?? sdk!.cancelled;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Creating ${_name.text.trim()}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            if (sdk != null)
              _phaseRow(
                sdk.result != null
                    ? _PhaseState.done
                    : sdk.done
                    ? _PhaseState.failed
                    : _PhaseState.active,
                'Installing $_managedName',
                detail: sdk.done ? null : sdk.phase.label,
              ),
            for (final phase in ProjectScaffoldPhase.values)
              _phaseRow(_scaffoldState(job, phase), phase.label),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: editorPanelBox(color: editorSurfaceColor),
                child: SingleChildScrollView(
                  reverse: true,
                  child: SelectableText(
                    [...?sdk?.log, ...?job?.log].join('\n'),
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error,
                  style: const TextStyle(fontSize: 11, color: editorErrorColor),
                ),
              ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FButton(
                variant: .outline,
                size: .xs,
                mainAxisSize: .min,
                onPress: done
                    ? () => Navigator.of(context).pop()
                    : cancelling
                    ? null
                    : (job?.cancel ?? sdk!.cancel),
                child: Text(done ? 'Close' : 'Cancel'),
              ),
            ),
          ],
        );
      },
    );
  }

  _PhaseState _scaffoldState(
    ProjectScaffoldJob? job,
    ProjectScaffoldPhase phase,
  ) {
    if (job == null) return _PhaseState.pending;
    if (phase.index < job.phase.index || (job.done && job.error == null)) {
      return _PhaseState.done;
    }
    if (phase != job.phase) return _PhaseState.pending;
    return job.done ? _PhaseState.failed : _PhaseState.active;
  }

  Widget _phaseRow(_PhaseState state, String label, {String? detail}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 14,
            child: switch (state) {
              _PhaseState.done => const Icon(
                Icons.check,
                size: 13,
                color: editorSuccessColor,
              ),
              _PhaseState.failed => const Icon(
                Icons.close,
                size: 13,
                color: editorErrorColor,
              ),
              _PhaseState.active => const SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              _PhaseState.pending => const SizedBox.shrink(),
            },
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: state == _PhaseState.pending ? editorMutedTextColor : null,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                detail,
                style: const TextStyle(
                  fontSize: 11,
                  color: editorMutedTextColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
