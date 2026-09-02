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
import '../shell/panel_chrome.dart';
import '../shell/tool_rail.dart';
import '../toolchains/device_catalog.dart';
import '../toolchains/editor_build_info.dart';
import '../toolchains/flutter_installation.dart';
import 'app_session.dart';
import 'fproject.dart';
import 'project_runner.dart';
import 'project_version_check.dart';

/// Which half of the build toolbar to draw.
///
/// The selectors belong at the left of the toolbar row and the transport in
/// the middle of it, so the two are placed by the shell rather than
/// travelling together as one clump pushed to one side.
enum BuildToolbarPart {
  /// The vertical form: icon triggers and the transport, sized for the rail.
  ///
  /// The names go into the tooltips and the menus. A rail cannot show
  /// "Built-in toolchain" and "iPhone 15 Pro" at once, and the alternative --
  /// a bar across the window holding four labels -- costs the scene a band of
  /// its height on every machine, to answer a question asked twice a day.
  rail,

  /// Toolchain, configuration and device.
  selectors,

  /// Play, and what a running session turns that into.
  transport,

  /// Both, in one row. What a host that lays the bar out itself asks for.
  both,
}

class BuildToolbar extends StatelessWidget {
  const BuildToolbar({
    super.key,
    this.part = BuildToolbarPart.both,
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

  /// Which half to draw.
  final BuildToolbarPart part;

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
    final selectors = <Widget>[
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
    ];
    final transport = _ActionButtons(
      rail: part == BuildToolbarPart.rail,
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
    );
    if (part == BuildToolbarPart.rail) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _InstallationDropdown(
            settings: settings,
            buildInfo: buildInfo,
            inspector: inspector,
            onSelect: onSelectInstallation,
            onManage: onManageInstallations,
            rail: true,
          ),
          _ConfigurationDropdown(
            project: project,
            selected: selectedConfiguration,
            versionCheck: versionCheck,
            onSelect: onSelectConfiguration,
            onEdit: onEditConfigs,
            onRunTask: onRunTask,
            rail: true,
          ),
          _DeviceDropdown(
            installation: settings.selectedInstallation,
            catalog: deviceCatalog,
            selected: selectedDevice,
            onSelect: onSelectDevice,
            rail: true,
          ),
          transport,
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: switch (part) {
        BuildToolbarPart.rail => const [],
        BuildToolbarPart.selectors => selectors,
        BuildToolbarPart.transport => [transport],
        BuildToolbarPart.both => [
          ...selectors,
          const SizedBox(width: 2),
          transport,
        ],
      },
    );
  }
}

/// The rail's form of a picker: an icon that opens the same menu, with the
/// name in the tooltip because forty pixels cannot hold it.
Widget _railTrigger({
  required IconData icon,
  required String tooltip,
  required MenuController controller,
  required VoidCallback onOpen,
  Widget? badge,
}) => EditorRailTooltip(
  label: tooltip,
  child: _RailPickerButton(
    icon: icon,
    badge: badge,
    onTap: () => controller.isOpen ? controller.close() : onOpen(),
  ),
);

/// A rail-sized picker trigger, with the same pill the rail's own buttons use.
class _RailPickerButton extends StatefulWidget {
  const _RailPickerButton({
    required this.icon,
    required this.onTap,
    this.badge,
    this.active = false,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Widget? badge;
  final bool active;
  final bool enabled;

  @override
  State<_RailPickerButton> createState() => _RailPickerButtonState();
}

class _RailPickerButtonState extends State<_RailPickerButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.enabled
        ? SystemMouseCursors.click
        : SystemMouseCursors.basic,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? widget.onTap : null,
      child: SizedBox(
        width: editorRailWidth,
        height: editorRailButtonHeight,
        child: Center(
          child: EditorRailPill(
            active: widget.active,
            hovered: _hovered && widget.enabled,
            child: widget.badge == null
                ? Icon(
                    widget.icon,
                    size: editorRailIconSize,
                    color: widget.active
                        ? editorAccentColor
                        : editorTextColor.withValues(
                            alpha: widget.enabled ? 0.75 : 0.35,
                          ),
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        widget.icon,
                        size: editorRailIconSize,
                        color: editorTextColor.withValues(alpha: 0.75),
                      ),
                      Positioned(right: 2, top: 4, child: widget.badge!),
                    ],
                  ),
          ),
        ),
      ),
    ),
  );
}

class _InstallationDropdown extends StatelessWidget {
  const _InstallationDropdown({
    this.rail = false,
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
  final bool rail;

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
      builder: (context, controller, _) => rail
          ? _railTrigger(
              icon: Icons.flutter_dash,
              tooltip: 'Flutter installation: $label',
              controller: controller,
              onOpen: controller.open,
              badge: selected == null
                  ? null
                  : _InstallationBadge(
                      installation: selected,
                      inspector: inspector,
                      buildInfo: buildInfo,
                    ),
            )
          : Tooltip(
              message: 'Flutter installation',
              waitDuration: const Duration(milliseconds: 600),
              child: InkWell(
                borderRadius: BorderRadius.circular(3),
                onTap: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
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
                      const Icon(Icons.flutter_dash, size: 14),
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
            color: error ? editorErrorColor : editorWarningColor,
          ),
        );
      },
    );
  }
}

class _ConfigurationDropdown extends StatelessWidget {
  const _ConfigurationDropdown({
    this.rail = false,
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
  final bool rail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (project == null) {
      if (rail) {
        return Tooltip(
          message: 'Open a project to select a build configuration',
          child: SizedBox(
            width: editorRailWidth,
            height: editorRailButtonHeight,
            child: Icon(
              Icons.tune,
              size: editorRailIconSize,
              color: editorMutedTextColor.withValues(alpha: 0.4),
            ),
          ),
        );
      }
      return Tooltip(
        message: 'Open a project to select a build configuration',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune, size: 14, color: scheme.onSurfaceVariant),
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
                  ? editorWarningColor
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
      builder: (context, controller, _) => rail
          ? _railTrigger(
              icon: Icons.tune,
              tooltip:
                  'Build configuration: ${selected?.name ?? 'none selected'}',
              controller: controller,
              onOpen: controller.open,
              badge: badge,
            )
          : Tooltip(
              message: 'Build configuration',
              waitDuration: const Duration(milliseconds: 600),
              child: InkWell(
                borderRadius: BorderRadius.circular(3),
                onTap: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (badge != null) ...[badge, const SizedBox(width: 4)],
                      const Icon(Icons.tune, size: 14),
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
    this.rail = false,
    required this.installation,
    required this.catalog,
    required this.selected,
    required this.onSelect,
  });

  final FlutterInstallation? installation;
  final DeviceCatalog catalog;
  final FlutterDevice? selected;
  final void Function(FlutterDevice device) onSelect;
  final bool rail;

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
      const message =
          'Select a Flutter installation to list devices (the built-in '
          'toolchain cannot run flutter)';
      if (widget.rail) {
        return Tooltip(
          message: message,
          child: SizedBox(
            width: editorRailWidth,
            height: editorRailButtonHeight,
            child: Icon(
              Icons.devices_outlined,
              size: editorRailIconSize,
              color: editorMutedTextColor.withValues(alpha: 0.4),
            ),
          ),
        );
      }
      return Tooltip(
        message: message,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.devices_outlined,
                size: 14,
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
              style: const TextStyle(color: editorErrorColor),
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
      builder: (context, controller, _) => widget.rail
          ? _railTrigger(
              icon: Icons.devices_outlined,
              tooltip:
                  'Target device: ${widget.selected?.name ?? 'none selected'}',
              controller: controller,
              onOpen: () {
                if (_devices == null) _fetch();
                controller.open();
              },
            )
          : Tooltip(
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.devices_outlined, size: 14),
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
    this.rail = false,
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

  /// Stacked for the rail rather than laid in a row.
  final bool rail;

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
            final children = <Widget>[
              _iconButton(
                context,
                icon: Icons.autorenew,
                tooltip: restartOnSave
                    ? 'Refresh on save is on (scenes and native sources)'
                    : 'Refresh the running app when a scene or a native '
                          'source is saved',
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
                // A text chip cannot fit a forty-pixel rail, and the icons
                // beside it already say what the session is doing.
                if (!rail) _SessionStateChip(session: session),
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
            ];
            return rail
                ? Column(mainAxisSize: MainAxisSize.min, children: children)
                : Row(mainAxisSize: MainAxisSize.min, children: children);
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
    if (rail) {
      // One size and one target for everything in the rail. A transport that
      // draws its own smaller button is the run of icons that does not line
      // up with the rest of the strip.
      return EditorRailTooltip(
        label: tooltip,
        child: _RailPickerButton(
          icon: icon,
          active: active,
          enabled: onPressed != null,
          onTap: onPressed ?? () {},
        ),
      );
    }
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
            size: 16,
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
