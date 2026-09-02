/// Editor dialog for a project's build configurations, a list with
/// add/duplicate/remove and a detail form (name, mode, command templates,
/// working directory, a live variable preview, and reset-to-template). Edits
/// save to the `.fproject` immediately.
library;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart' hide FTheme;

import 'fproject.dart';
import '../shell/editor_theme.dart';
import '../shell/panel_chrome.dart';
import '../shell/editor_dialog.dart';

const _modes = ['debug', 'profile', 'release'];

/// Shows the configuration editor for [project]. [onChanged] fires after
/// every persisted edit (the host refreshes toolbars/selection).
/// [previewVariables] supplies each configuration's live variable values for
/// the preview panel (selected installation and device included).
Future<void> showBuildConfigDialog(
  BuildContext context, {
  required FProject project,
  required void Function() onChanged,
  Map<String, String> Function(BuildConfiguration configuration)?
  previewVariables,
}) {
  return showEditorDialog<void>(
    context,
    builder: (context) => Dialog(
      child: _BuildConfigEditor(
        project: project,
        onChanged: onChanged,
        previewVariables: previewVariables,
      ),
    ),
  );
}

class _BuildConfigEditor extends StatefulWidget {
  const _BuildConfigEditor({
    required this.project,
    required this.onChanged,
    this.previewVariables,
  });

  final FProject project;
  final void Function() onChanged;
  final Map<String, String> Function(BuildConfiguration configuration)?
  previewVariables;

  @override
  State<_BuildConfigEditor> createState() => _BuildConfigEditorState();
}

class _BuildConfigEditorState extends State<_BuildConfigEditor> {
  String? _selectedId;

  FProject get _project => widget.project;

  @override
  void initState() {
    super.initState();
    if (_project.buildConfigurations.isNotEmpty) {
      _selectedId = _project.buildConfigurations.first.id;
    }
  }

  BuildConfiguration? get _selected => _project.configurationById(_selectedId);

  void _mutate(void Function() edit) {
    setState(edit);
    _project.save();
    widget.onChanged();
  }

  String _freshId(String base) {
    var id = base;
    var counter = 2;
    while (_project.configurationById(id) != null) {
      id = '$base-${counter++}';
    }
    return id;
  }

  void _add() {
    final template = buildConfigurationTemplate('debug');
    final config = BuildConfiguration(
      id: _freshId(template.id),
      name: 'New configuration',
      mode: template.mode,
      buildCommand: template.buildCommand,
      run: template.run,
    );
    _mutate(() {
      _project.buildConfigurations.add(config);
      _selectedId = config.id;
    });
  }

  void _duplicate(BuildConfiguration config) {
    final copy = BuildConfiguration(
      id: _freshId(config.id),
      name: '${config.name} copy',
      mode: config.mode,
      buildCommand: config.buildCommand,
      run: config.run,
      workingDirectory: config.workingDirectory,
    );
    _mutate(() {
      _project.buildConfigurations.add(copy);
      _selectedId = copy.id;
    });
  }

  void _addTask() {
    var id = 'task';
    var counter = 2;
    while (_project.taskById(id) != null) {
      id = 'task-${counter++}';
    }
    _mutate(
      () => _project.tasks.add(
        ProjectTask(id: id, name: 'New task', command: ''),
      ),
    );
  }

  void _updateTask(ProjectTask updated) {
    final index = _project.tasks.indexWhere((task) => task.id == updated.id);
    if (index < 0) return;
    _mutate(() => _project.tasks[index] = updated);
  }

  void _removeTask(ProjectTask task) {
    _mutate(
      () => _project.tasks.removeWhere((candidate) => candidate.id == task.id),
    );
  }

  void _remove(BuildConfiguration config) {
    _mutate(() {
      _project.buildConfigurations.removeWhere(
        (candidate) => candidate.id == config.id,
      );
      if (_selectedId == config.id) {
        _selectedId = _project.buildConfigurations.isEmpty
            ? null
            : _project.buildConfigurations.first.id;
      }
    });
  }

  void _update(BuildConfiguration updated) {
    final index = _project.buildConfigurations.indexWhere(
      (candidate) => candidate.id == updated.id,
    );
    if (index < 0) return;
    _mutate(() => _project.buildConfigurations[index] = updated);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 820,
      height: 560,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Build configurations (${_project.name})',
              style: editorDialogTitleText,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 240,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: editorLineColor),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: ListView(
                              children: [
                                for (final config
                                    in _project.buildConfigurations)
                                  ListTile(
                                    dense: true,
                                    selected: config.id == _selectedId,
                                    title: Text(
                                      config.name,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    subtitle: Text(
                                      config.mode,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                    onTap: () =>
                                        setState(() => _selectedId = config.id),
                                  ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Add configuration',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.add, size: 16),
                                onPressed: _add,
                              ),
                              IconButton(
                                tooltip: 'Duplicate',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.copy, size: 14),
                                onPressed: _selected == null
                                    ? null
                                    : () => _duplicate(_selected!),
                              ),
                              IconButton(
                                tooltip: 'Remove',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.remove, size: 16),
                                onPressed: _selected == null
                                    ? null
                                    : () => _remove(_selected!),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _selected == null
                        ? const Center(
                            child: Text(
                              'Add a configuration.',
                              style: TextStyle(fontSize: 12),
                            ),
                          )
                        : _ConfigForm(
                            key: ValueKey(_selected!.id),
                            config: _selected!,
                            onChanged: _update,
                            previewVariables: widget.previewVariables,
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _tasksSection(context),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FButton(
                variant: .outline,
                size: .xs,
                mainAxisSize: .min,
                onPress: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Free-form command templates, runnable from the toolbar's configuration
  /// menu as raw subprocesses.
  Widget _tasksSection(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 120),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: editorLineColor),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Tasks',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              Text(
                'free-form commands, run from the configuration menu',
                style: const TextStyle(
                  fontSize: 10,
                  color: editorMutedTextColor,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Add task',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 14),
                onPressed: _addTask,
              ),
            ],
          ),
          if (_project.tasks.isNotEmpty)
            Expanded(
              child: ListView(
                children: [
                  for (final task in _project.tasks)
                    _TaskRow(
                      key: ValueKey(task.id),
                      task: task,
                      onChanged: _updateTask,
                      onRemove: () => _removeTask(task),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatefulWidget {
  const _TaskRow({
    super.key,
    required this.task,
    required this.onChanged,
    required this.onRemove,
  });

  final ProjectTask task;
  final void Function(ProjectTask updated) onChanged;
  final VoidCallback onRemove;

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  late final TextEditingController _name = TextEditingController(
    text: widget.task.name,
  );
  late final TextEditingController _command = TextEditingController(
    text: widget.task.command,
  );

  @override
  void dispose() {
    _name.dispose();
    _command.dispose();
    super.dispose();
  }

  void _commit() => widget.onChanged(
    widget.task.copyWith(
      name: _name.text.trim(),
      command: _command.text.trim(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    InputDecoration decoration(String hint) => InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 10),
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: TextField(
              controller: _name,
              style: const TextStyle(fontSize: 11),
              decoration: decoration('name'),
              onSubmitted: (_) => _commit(),
              onTapOutside: (_) => _commit(),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _command,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              decoration: decoration(r'command template, e.g. ${DART_CLI} …'),
              onSubmitted: (_) => _commit(),
              onTapOutside: (_) => _commit(),
            ),
          ),
          IconButton(
            tooltip: 'Remove task',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 14),
            onPressed: widget.onRemove,
          ),
        ],
      ),
    );
  }
}

class _ConfigForm extends StatefulWidget {
  const _ConfigForm({
    super.key,
    required this.config,
    required this.onChanged,
    this.previewVariables,
  });

  final BuildConfiguration config;
  final void Function(BuildConfiguration updated) onChanged;
  final Map<String, String> Function(BuildConfiguration configuration)?
  previewVariables;

  @override
  State<_ConfigForm> createState() => _ConfigFormState();
}

class _ConfigFormState extends State<_ConfigForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.config.name,
  );
  late final TextEditingController _build = TextEditingController(
    text: widget.config.buildCommand,
  );
  late final TextEditingController _runTarget = TextEditingController(
    text: widget.config.run.target,
  );
  late final TextEditingController _runArgs = TextEditingController(
    text: widget.config.run.args.join(' '),
  );
  late final TextEditingController _workingDirectory = TextEditingController(
    text: widget.config.workingDirectory,
  );
  late String _mode = widget.config.mode;

  @override
  void dispose() {
    _name.dispose();
    _build.dispose();
    _runTarget.dispose();
    _runArgs.dispose();
    _workingDirectory.dispose();
    super.dispose();
  }

  BuildConfiguration get _current => widget.config.copyWith(
    name: _name.text.trim().isEmpty ? null : _name.text.trim(),
    mode: _mode,
    buildCommand: _build.text.trim(),
    run: RunParameters(
      target: _runTarget.text.trim().isEmpty
          ? RunParameters.defaultTarget
          : _runTarget.text.trim(),
      args: tokenizeCommand(_runArgs.text.trim()),
    ),
    workingDirectory: _workingDirectory.text.trim(),
  );

  void _commit() => widget.onChanged(_current);

  void _resetToTemplate() {
    final template = buildConfigurationTemplate(_mode);
    setState(() {
      _build.text = template.buildCommand;
      _runTarget.text = template.run.target;
      _runArgs.text = template.run.args.join(' ');
    });
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _textRow('Name', _name),
          Row(
            children: [
              Text('Mode', style: const TextStyle(fontSize: 11)),
              const SizedBox(width: 8),
              EditorDropdown<String>(
                value: _modes.contains(_mode) ? _mode : 'debug',
                items: [
                  for (final mode in _modes)
                    DropdownMenuItem(
                      value: mode,
                      child: Text(mode, style: const TextStyle(fontSize: 11)),
                    ),
                ],
                onChanged: (mode) {
                  if (mode == null) return;
                  setState(() => _mode = mode);
                  _commit();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          _textRow('Build', _build, monospace: true),
          _textRow(
            'Run target',
            _runTarget,
            monospace: true,
            hint: 'entrypoint passed as --target (default lib/main.dart)',
          ),
          _textRow(
            'Run args',
            _runArgs,
            monospace: true,
            hint:
                'extra flutter run arguments; the editor supplies the device, '
                'mode, and --machine',
          ),
          _textRow(
            'Directory',
            _workingDirectory,
            monospace: true,
            hint:
                'working directory relative to \${PROJECT_ROOT} (empty '
                'runs from the project root)',
          ),
          const SizedBox(height: 4),
          Text(
            'The Mode above drives \${MODE}; the toolbar device drives '
            '\${DEVICE} and \${BUILD_TARGET}. Commands run without a shell '
            '(double quotes group arguments). Play launches an editor-managed '
            'flutter run session composed from the run fields.',
            style: TextStyle(fontSize: 10, color: editorMutedTextColor),
          ),
          const SizedBox(height: 8),
          _variablePreview(context),
          const SizedBox(height: 10),
          FButton(
            variant: .outline,
            size: .xs,
            mainAxisSize: .min,
            onPress: _resetToTemplate,
            child: const Text('Reset commands to template'),
          ),
        ],
      ),
    );
  }

  /// Every variable with its live value under the current installation,
  /// device, and this configuration.
  Widget _variablePreview(BuildContext context) {
    final provider = widget.previewVariables;
    if (provider == null) return const SizedBox.shrink();
    final variables = provider(_current);
    const known = [
      'FLUTTER_CLI',
      'DART_CLI',
      'FLUTTER_ROOT',
      'IMPELLERC',
      'PROJECT_ROOT',
      'MODE',
      'DEVICE',
      'BUILD_TARGET',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: editorPanelBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Variables',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          for (final name in known)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      '\${$name}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      variables[name] ??
                          (name == 'DEVICE' || name == 'BUILD_TARGET'
                              ? '(select a device in the toolbar)'
                              : '(unavailable)'),
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: variables.containsKey(name)
                            ? null
                            : editorMutedTextColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _textRow(
    String label,
    TextEditingController controller, {
    bool monospace = false,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label, style: const TextStyle(fontSize: 11)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              style: TextStyle(
                fontSize: 11,
                fontFamily: monospace ? 'monospace' : null,
              ),
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
        ],
      ),
    );
  }
}
