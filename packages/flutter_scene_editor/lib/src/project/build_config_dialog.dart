/// Editor dialog for a project's build configurations, a list with
/// add/duplicate/remove and a detail form (name, platform, mode, command
/// templates with variable help and reset-to-template). Edits save to the
/// `.fproject` immediately.
library;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart' hide FTheme;

import 'fproject.dart';

const _platforms = ['macos', 'ios', 'android', 'linux', 'windows', 'web'];
const _modes = ['debug', 'profile', 'release'];

/// Shows the configuration editor for [project]. [onChanged] fires after
/// every persisted edit (the host refreshes toolbars/selection).
Future<void> showBuildConfigDialog(
  BuildContext context, {
  required FProject project,
  required void Function() onChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: _BuildConfigEditor(project: project, onChanged: onChanged),
    ),
  );
}

class _BuildConfigEditor extends StatefulWidget {
  const _BuildConfigEditor({required this.project, required this.onChanged});

  final FProject project;
  final void Function() onChanged;

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
    final defaults = defaultBuildConfigurations(_project.resolvedProjectRoot);
    final template = defaults.first;
    final config = BuildConfiguration(
      id: _freshId(template.id),
      name: 'New configuration',
      platform: template.platform,
      mode: template.mode,
      buildCommand: template.buildCommand,
      runCommand: template.runCommand,
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
      platform: config.platform,
      mode: config.mode,
      buildCommand: config.buildCommand,
      runCommand: config.runCommand,
    );
    _mutate(() {
      _project.buildConfigurations.add(copy);
      _selectedId = copy.id;
    });
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
    final scheme = Theme.of(context).colorScheme;
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
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
                        border: Border.all(color: scheme.outlineVariant),
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
                                      '${config.platform} · ${config.mode}',
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
                            projectRoot: _project.resolvedProjectRoot,
                            onChanged: _update,
                          ),
                  ),
                ],
              ),
            ),
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
}

class _ConfigForm extends StatefulWidget {
  const _ConfigForm({
    super.key,
    required this.config,
    required this.projectRoot,
    required this.onChanged,
  });

  final BuildConfiguration config;
  final String projectRoot;
  final void Function(BuildConfiguration updated) onChanged;

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
  late final TextEditingController _run = TextEditingController(
    text: widget.config.runCommand,
  );
  late String _platform = widget.config.platform;
  late String _mode = widget.config.mode;

  @override
  void dispose() {
    _name.dispose();
    _build.dispose();
    _run.dispose();
    super.dispose();
  }

  void _commit() {
    widget.onChanged(
      widget.config.copyWith(
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        platform: _platform,
        mode: _mode,
        buildCommand: _build.text.trim(),
        runCommand: _run.text.trim(),
      ),
    );
  }

  void _resetToTemplate() {
    final defaults = defaultBuildConfigurations(widget.projectRoot);
    final template = defaults.firstWhere(
      (candidate) => candidate.platform == _platform && candidate.mode == _mode,
      orElse: () => defaults.first,
    );
    setState(() {
      _build.text = template.buildCommand;
      _run.text = template.runCommand;
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
              _dropdownRow(
                'Platform',
                _platform,
                _platforms,
                (value) => setState(() {
                  _platform = value;
                  _commit();
                }),
              ),
              const SizedBox(width: 16),
              _dropdownRow(
                'Mode',
                _mode,
                _modes,
                (value) => setState(() {
                  _mode = value;
                  _commit();
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _textRow('Build', _build, monospace: true),
          _textRow('Run', _run, monospace: true),
          const SizedBox(height: 4),
          Text(
            'Variables, \${FLUTTER_CLI} \${DART_CLI} \${FLUTTER_ROOT} '
            '\${IMPELLERC} \${PROJECT_ROOT} \${MODE} \${PLATFORM}. Commands '
            'run from the project root without a shell (double quotes group '
            'arguments).',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
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

  Widget _textRow(
    String label,
    TextEditingController controller, {
    bool monospace = false,
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
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
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

  Widget _dropdownRow(
    String label,
    String value,
    List<String> options,
    void Function(String) onChanged,
  ) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: value,
          isDense: true,
          items: [
            for (final option in options)
              DropdownMenuItem(
                value: option,
                child: Text(option, style: const TextStyle(fontSize: 11)),
              ),
          ],
          onChanged: (selected) =>
              selected == null ? null : onChanged(selected),
        ),
      ],
    );
  }
}
