/// The menu bar's right-side toolchain and build controls, the Flutter
/// installation dropdown (global selection with health badges), the build
/// configuration dropdown (per-project selection, the flutter_scene version
/// badge, and project tasks), the device dropdown, the Build button, and the
/// Play session cluster (launch, then hot reload/restart/stop with a state
/// chip while an app runs). Buttons disable with an explanatory tooltip
/// rather than a bare gray state.
library;

import 'package:flutter/material.dart';

import '../settings/editor_settings.dart';
import '../shell/editor_theme.dart';
import '../toolchains/device_catalog.dart';
import '../toolchains/editor_build_info.dart';
import '../toolchains/flutter_installation.dart';
import 'app_session.dart';
import 'fproject.dart';
import 'project_runner.dart';
import 'project_version_check.dart';

class BuildToolbar extends StatelessWidget {
  const BuildToolbar({
    super.key,
    required this.settings,
    required this.buildInfo,
    required this.inspector,
    required this.runner,
    required this.session,
    required this.project,
    required this.selectedConfiguration,
    required this.deviceCatalog,
    required this.selectedDevice,
    required this.onSelectInstallation,
    required this.onSelectConfiguration,
    required this.onSelectDevice,
    required this.onManageInstallations,
    required this.onEditConfigs,
    required this.onPlay,
    this.onRunTask,
    this.restartOnSave = false,
    this.onToggleRestartOnSave,
  });

  final EditorSettings settings;
  final EditorBuildInfo buildInfo;
  final InstallationInspector inspector;
  final ProjectRunner runner;
  final AppSession session;
  final FProject? project;
  final BuildConfiguration? selectedConfiguration;
  final DeviceCatalog deviceCatalog;
  final FlutterDevice? selectedDevice;
  final void Function(String? id) onSelectInstallation;
  final void Function(String id) onSelectConfiguration;
  final void Function(FlutterDevice device) onSelectDevice;
  final VoidCallback onManageInstallations;
  final VoidCallback? onEditConfigs;

  /// Launches the Play session (the host owns the launch context).
  final VoidCallback onPlay;

  /// Runs a project task as a raw subprocess.
  final void Function(ProjectTask task)? onRunTask;

  /// Whether saving the scene hot-restarts the running session.
  final bool restartOnSave;
  final VoidCallback? onToggleRestartOnSave;

  @override
  Widget build(BuildContext context) {
    final versionCheck = project == null
        ? FlutterSceneVersionCheck.ok
        : checkFlutterSceneVersion(project!, buildInfo);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _InstallationDropdown(
          settings: settings,
          buildInfo: buildInfo,
          inspector: inspector,
          onSelect: onSelectInstallation,
          onManage: onManageInstallations,
        ),
        const SizedBox(width: 4),
        _ConfigurationDropdown(
          project: project,
          selected: selectedConfiguration,
          versionCheck: versionCheck,
          onSelect: onSelectConfiguration,
          onEdit: onEditConfigs,
          onRunTask: onRunTask,
        ),
        const SizedBox(width: 4),
        _DeviceDropdown(
          installation: settings.selectedInstallation,
          catalog: deviceCatalog,
          selected: selectedDevice,
          onSelect: onSelectDevice,
        ),
        const SizedBox(width: 2),
        _ActionButtons(
          settings: settings,
          buildInfo: buildInfo,
          inspector: inspector,
          runner: runner,
          session: session,
          project: project,
          configuration: selectedConfiguration,
          device: selectedDevice,
          onPlay: onPlay,
          restartOnSave: restartOnSave,
          onToggleRestartOnSave: onToggleRestartOnSave,
        ),
      ],
    );
  }
}

class _InstallationDropdown extends StatelessWidget {
  const _InstallationDropdown({
    required this.settings,
    required this.buildInfo,
    required this.inspector,
    required this.onSelect,
    required this.onManage,
  });

  final EditorSettings settings;
  final EditorBuildInfo buildInfo;
  final InstallationInspector inspector;
  final void Function(String? id) onSelect;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final selected = settings.selectedInstallation;
    final label = selected?.name ?? 'Built-in toolchain';
    return MenuAnchor(
      menuChildren: [
        _menuRow(
          context,
          label: 'Built-in toolchain',
          checked: selected == null,
          badge: null,
          onTap: () => onSelect(null),
        ),
        for (final installation in settings.flutterInstallations)
          _menuRow(
            context,
            label: installation.name,
            checked: installation.id == selected?.id,
            badge: _InstallationBadge(
              installation: installation,
              inspector: inspector,
              buildInfo: buildInfo,
            ),
            onTap: () => onSelect(installation.id),
          ),
        const Divider(height: 8),
        MenuItemButton(
          onPressed: onManage,
          child: const Text('Manage installations…'),
        ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: 'Flutter installation',
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          borderRadius: BorderRadius.circular(3),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _InstallationBadge(
                      installation: selected,
                      inspector: inspector,
                      buildInfo: buildInfo,
                    ),
                  ),
                const Icon(Icons.flutter_dash, size: 13),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuRow(
    BuildContext context, {
    required String label,
    required bool checked,
    required Widget? badge,
    required VoidCallback onTap,
  }) {
    return MenuItemButton(
      onPressed: onTap,
      leadingIcon: editorMenuCheckmark(checked),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (badge != null) ...[const SizedBox(width: 6), badge],
        ],
      ),
    );
  }
}

/// The selected installation's worst validation severity as a badge icon.
class _InstallationBadge extends StatelessWidget {
  const _InstallationBadge({
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
            size: 12,
            color: error ? Colors.redAccent : Colors.orangeAccent,
          ),
        );
      },
    );
  }
}

class _ConfigurationDropdown extends StatelessWidget {
  const _ConfigurationDropdown({
    required this.project,
    required this.selected,
    required this.versionCheck,
    required this.onSelect,
    required this.onEdit,
    this.onRunTask,
  });

  final FProject? project;
  final BuildConfiguration? selected;
  final FlutterSceneVersionCheck versionCheck;
  final void Function(String id) onSelect;
  final VoidCallback? onEdit;
  final void Function(ProjectTask task)? onRunTask;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (project == null) {
      return Tooltip(
        message: 'Open a project to select a build configuration',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune, size: 13, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                'No project',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    final badge = versionCheck.severity == VersionCheckSeverity.ok
        ? null
        : Tooltip(
            message: versionCheck.message,
            child: Icon(
              versionCheck.severity == VersionCheckSeverity.warning
                  ? Icons.warning_amber_outlined
                  : Icons.info_outline,
              size: 12,
              color: versionCheck.severity == VersionCheckSeverity.warning
                  ? Colors.orangeAccent
                  : scheme.onSurfaceVariant,
            ),
          );
    return MenuAnchor(
      menuChildren: [
        for (final config in project!.buildConfigurations)
          MenuItemButton(
            onPressed: () => onSelect(config.id),
            leadingIcon: editorMenuCheckmark(config.id == selected?.id),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(config.name),
                const SizedBox(width: 6),
                Text(config.mode, style: editorMenuItemDetailText),
              ],
            ),
          ),
        if (project!.tasks.isNotEmpty && onRunTask != null) ...[
          const Divider(height: 8),
          for (final task in project!.tasks)
            MenuItemButton(
              onPressed: () => onRunTask!(task),
              leadingIcon: const SizedBox(
                width: 16,
                child: Icon(Icons.play_arrow_outlined, size: 14),
              ),
              child: Text(task.name),
            ),
        ],
        const Divider(height: 8),
        MenuItemButton(
          onPressed: onEdit,
          child: const Text('Edit build configurations…'),
        ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: 'Build configuration',
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          borderRadius: BorderRadius.circular(3),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (badge != null) ...[badge, const SizedBox(width: 4)],
                const Icon(Icons.tune, size: 13),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: Text(
                    selected?.name ?? 'No configuration',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The device dropdown, sourced live from `flutter devices` against the
/// selected installation. Selection feeds `${DEVICE}`/`${BUILD_TARGET}`.
class _DeviceDropdown extends StatefulWidget {
  const _DeviceDropdown({
    required this.installation,
    required this.catalog,
    required this.selected,
    required this.onSelect,
  });

  final FlutterInstallation? installation;
  final DeviceCatalog catalog;
  final FlutterDevice? selected;
  final void Function(FlutterDevice device) onSelect;

  @override
  State<_DeviceDropdown> createState() => _DeviceDropdownState();
}

class _DeviceDropdownState extends State<_DeviceDropdown> {
  final MenuController _controller = MenuController();
  List<FlutterDevice>? _devices;
  bool _loading = false;
  String? _error;

  Future<void> _fetch({bool refresh = false}) async {
    final installation = widget.installation;
    if (installation == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final devices = await widget.catalog.list(installation, refresh: refresh);
      if (mounted) setState(() => _devices = devices);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final installation = widget.installation;
    if (installation == null) {
      return Tooltip(
        message:
            'Select a Flutter installation to list devices (the built-in '
            'toolchain cannot run flutter)',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.devices_outlined,
                size: 13,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                'No device',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    return MenuAnchor(
      controller: _controller,
      menuChildren: [
        if (_loading)
          const MenuItemButton(child: Text('Listing devices…'))
        else if (_error != null)
          MenuItemButton(
            child: Text(
              'Failed to list devices, $_error',
              style: const TextStyle(color: Colors.redAccent),
            ),
          )
        else if (_devices == null || _devices!.isEmpty)
          const MenuItemButton(child: Text('No devices found'))
        else
          for (final device in _devices!)
            MenuItemButton(
              onPressed: () => widget.onSelect(device),
              leadingIcon: editorMenuCheckmark(
                device.id == widget.selected?.id,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(device.name),
                  const SizedBox(width: 6),
                  Text(device.targetPlatform, style: editorMenuItemDetailText),
                ],
              ),
            ),
        const Divider(height: 8),
        MenuItemButton(
          closeOnActivate: false,
          onPressed: () => _fetch(refresh: true),
          child: const Text('Refresh'),
        ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: 'Target device',
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          borderRadius: BorderRadius.circular(3),
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              if (_devices == null) _fetch();
              controller.open();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.devices_outlined, size: 13),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    widget.selected?.name ?? 'No device',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.settings,
    required this.buildInfo,
    required this.inspector,
    required this.runner,
    required this.session,
    required this.project,
    required this.configuration,
    required this.device,
    required this.onPlay,
    this.restartOnSave = false,
    this.onToggleRestartOnSave,
  });

  final EditorSettings settings;
  final EditorBuildInfo buildInfo;
  final InstallationInspector inspector;
  final ProjectRunner runner;
  final AppSession session;
  final FProject? project;
  final BuildConfiguration? configuration;
  final FlutterDevice? device;
  final VoidCallback onPlay;
  final bool restartOnSave;
  final VoidCallback? onToggleRestartOnSave;

  String? _commonBlockedReason(InstallationValidation? validation) {
    final installation = settings.selectedInstallation;
    if (installation == null) {
      return 'Select a Flutter installation (the built-in toolchain cannot '
          'run flutter)';
    }
    if (validation != null &&
        validation.severity == InstallationSeverity.error) {
      return validation.summary;
    }
    if (project == null) return 'Open a project first';
    if (configuration == null) return 'Select a build configuration';
    return null;
  }

  // The build command is a free-form template; a device is only needed when
  // the template references it.
  String? _buildBlockedReason(InstallationValidation? validation) {
    final common = _commonBlockedReason(validation);
    if (common != null) return common;
    final referenced =
        '${configuration!.buildCommand} ${configuration!.workingDirectory}';
    if (device == null && referenced.contains(r'${DEVICE}')) {
      return 'Select a device (the configuration references \${DEVICE})';
    }
    if (device == null && referenced.contains(r'${BUILD_TARGET}')) {
      return 'Select a device (the configuration references '
          r'${BUILD_TARGET})';
    }
    return null;
  }

  // The session always targets a concrete device.
  String? _playBlockedReason(InstallationValidation? validation) =>
      _commonBlockedReason(validation) ??
      (device == null ? 'Select a device' : null);

  @override
  Widget build(BuildContext context) {
    final installation = settings.selectedInstallation;
    return FutureBuilder<InstallationValidation>(
      // The built-in pseudo-entry has nothing to validate.
      future: installation == null
          ? null
          : inspector.validate(installation, buildInfo),
      builder: (context, snapshot) {
        return ListenableBuilder(
          listenable: Listenable.merge([runner, session]),
          builder: (context, _) {
            final buildReason = _buildBlockedReason(snapshot.data);
            final playReason = _playBlockedReason(snapshot.data);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _iconButton(
                  context,
                  icon: Icons.autorenew,
                  tooltip: restartOnSave
                      ? 'Restart on scene save is on'
                      : 'Restart the running app on scene save',
                  active: restartOnSave,
                  onPressed: onToggleRestartOnSave,
                ),
                _iconButton(
                  context,
                  icon: Icons.build_outlined,
                  tooltip: buildReason ?? 'Build (${configuration?.name})',
                  onPressed: buildReason != null || runner.building
                      ? null
                      : () => runner.startBuild(
                          installation: installation!,
                          project: project!,
                          configuration: configuration!,
                          device: device,
                        ),
                ),
                if (!session.active)
                  _iconButton(
                    context,
                    icon: Icons.play_arrow_outlined,
                    tooltip: playReason ?? 'Play (${configuration?.name})',
                    onPressed: playReason != null ? null : onPlay,
                  )
                else ...[
                  _SessionStateChip(session: session),
                  if (session.supportsHotReload)
                    _iconButton(
                      context,
                      icon: Icons.bolt_outlined,
                      tooltip: 'Hot reload',
                      onPressed: session.state == AppSessionState.running
                          ? () => session.restart(fullRestart: false)
                          : null,
                    ),
                  if (session.supportsHotRestart)
                    _iconButton(
                      context,
                      icon: Icons.restart_alt,
                      tooltip: 'Hot restart',
                      onPressed: session.state == AppSessionState.running
                          ? () => session.restart()
                          : null,
                    ),
                  if (session.supportsPause)
                    _iconButton(
                      context,
                      icon: session.paused
                          ? Icons.play_arrow
                          : Icons.pause_outlined,
                      tooltip: session.paused
                          ? 'Release the app'
                          : 'Hold the app',
                      active: session.paused,
                      onPressed: session.state == AppSessionState.running
                          ? () => session.setPaused(!session.paused)
                          : null,
                    ),
                  _iconButton(
                    context,
                    icon: Icons.stop,
                    tooltip: 'Stop',
                    onPressed: session.state == AppSessionState.stopping
                        ? null
                        : session.stop,
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _iconButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool active = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        borderRadius: BorderRadius.circular(3),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          decoration: active
              ? BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(3),
                )
              : null,
          child: Icon(
            icon,
            size: 15,
            color: active
                ? scheme.primary
                : onPressed == null
                ? scheme.onSurfaceVariant
                : null,
          ),
        ),
      ),
    );
  }
}

/// The running session's state as a small chip next to its controls.
class _SessionStateChip extends StatelessWidget {
  const _SessionStateChip({required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = switch (session.state) {
      AppSessionState.launching => 'Launching…',
      AppSessionState.running => 'Running',
      AppSessionState.restarting => 'Restarting…',
      AppSessionState.stopping => 'Stopping…',
      AppSessionState.idle => '',
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: scheme.primary)),
    );
  }
}
