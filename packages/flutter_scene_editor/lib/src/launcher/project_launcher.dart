/// The launcher: the gallery the editor opens to.
///
/// A grid of project cards with cover art, searchable and sortable, plus the
/// scene-level entry points the editor has always had. Double-clicking a card
/// opens the project.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../shell/editor_theme.dart';
import 'project_covers.dart';
import 'project_library.dart';

/// Which side of the launcher is showing.
enum LauncherTab {
  /// The project gallery.
  projects('Projects', Icons.grid_view_rounded),

  /// Loose `.fscene` files opened without a project.
  scenes('Scenes', Icons.movie_outlined);

  const LauncherTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The editor's start screen.
class ProjectLauncher extends StatefulWidget {
  const ProjectLauncher({
    super.key,
    required this.library,
    required this.recentScenes,
    required this.onOpenProject,
    required this.onNewProject,
    required this.onBrowseForProject,
    required this.onForgetProject,
    required this.onOpenScene,
    required this.onNewScene,
    required this.onBrowseForScene,
    required this.onImportModel,
    required this.onForgetScene,
    required this.onClearScenes,
    required this.onRefresh,
    this.busy,
    this.error,
  });

  /// The projects to show, already read from disk.
  final ProjectLibrary library;

  /// Recently opened `.fscene` paths, most recent first.
  final List<String> recentScenes;

  final ValueChanged<String> onOpenProject;
  final VoidCallback onNewProject;
  final VoidCallback onBrowseForProject;
  final ValueChanged<String> onForgetProject;

  final ValueChanged<String> onOpenScene;
  final VoidCallback onNewScene;
  final VoidCallback onBrowseForScene;
  final VoidCallback onImportModel;
  final ValueChanged<String> onForgetScene;
  final VoidCallback onClearScenes;

  /// Re-reads the library from disk.
  final VoidCallback onRefresh;

  /// What the editor is doing, when it is doing something; the gallery is
  /// replaced by a progress message.
  final String? busy;

  /// The last failure, shown as a banner above the gallery.
  final String? error;

  @override
  State<ProjectLauncher> createState() => _ProjectLauncherState();
}

class _ProjectLauncherState extends State<ProjectLauncher> {
  LauncherTab _tab = LauncherTab.projects;
  ProjectSort _sort = ProjectSort.recent;
  String _query = '';
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: editorSurfaceColor,
      body: Row(
        children: [
          _Rail(
            tab: _tab,
            onSelected: (tab) => setState(() => _tab = tab),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                if (widget.error != null) _ErrorBanner(message: widget.error!),
                Expanded(
                  child: widget.busy != null
                      ? _BusyState(message: widget.busy!)
                      : _buildBody(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final projects = _tab == LauncherTab.projects;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      child: Row(
        children: [
          Text(_tab.label, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(width: 20),
          SizedBox(
            width: 260,
            height: 32,
            child: TextField(
              controller: _search,
              style: editorBodyText,
              decoration: InputDecoration(
                isDense: true,
                hintText: projects ? 'Search projects' : 'Search scenes',
                hintStyle: editorDetailText,
                prefixIcon: const Icon(Icons.search, size: 16),
                prefixIconConstraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          if (projects) ...[
            const SizedBox(width: 12),
            _SortControl(
              sort: _sort,
              onChanged: (sort) => setState(() => _sort = sort),
            ),
          ],
          const Spacer(),
          IconButton(
            tooltip: 'Rescan',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: widget.onRefresh,
          ),
          const SizedBox(width: 6),
          if (projects) ...[
            OutlinedButton.icon(
              onPressed: widget.onBrowseForProject,
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Open'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: widget.onNewProject,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New project'),
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: widget.onImportModel,
              icon: const Icon(Icons.view_in_ar, size: 16),
              label: const Text('Import glTF'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: widget.onBrowseForScene,
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Open .fscene'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: widget.onNewScene,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New scene'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) => switch (_tab) {
    LauncherTab.projects => _buildProjects(context),
    LauncherTab.scenes => _buildScenes(context),
  };

  Widget _buildProjects(BuildContext context) {
    final entries = widget.library.view(query: _query, sort: _sort);
    if (entries.isEmpty) {
      return _EmptyGallery(
        icon: Icons.grid_view_rounded,
        title: widget.library.isEmpty
            ? 'No projects yet'
            : 'Nothing matches "$_query"',
        message: widget.library.isEmpty
            ? 'A project is an .fproject file beside a Flutter app. Create one, '
                  'or open an existing project to add it here.'
            : 'Try a shorter search, or clear it to see everything.',
        action: widget.library.isEmpty
            ? FilledButton.icon(
                onPressed: widget.onNewProject,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New project'),
              )
            : null,
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        // Cover art plus two lines of caption.
        childAspectRatio: 4 / 3.4,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) => ProjectCard(
        entry: entries[index],
        onOpen: () => widget.onOpenProject(entries[index].path),
        onForget: () => widget.onForgetProject(entries[index].path),
      ),
    );
  }

  Widget _buildScenes(BuildContext context) {
    final needle = _query.trim().toLowerCase();
    final scenes = [
      for (final path in widget.recentScenes)
        if (needle.isEmpty || path.toLowerCase().contains(needle)) path,
    ];
    if (scenes.isEmpty) {
      return _EmptyGallery(
        icon: Icons.movie_outlined,
        title: widget.recentScenes.isEmpty
            ? 'No recent scenes'
            : 'Nothing matches "$_query"',
        message:
            'A scene opened outside a project shows up here. Most work starts '
            'from a project instead.',
        action: widget.recentScenes.isEmpty
            ? FilledButton.icon(
                onPressed: widget.onNewScene,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New scene'),
              )
            : null,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
            itemCount: scenes.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: editorLineColor),
            itemBuilder: (context, index) => _SceneRow(
              path: scenes[index],
              onOpen: () => widget.onOpenScene(scenes[index]),
              onForget: () => widget.onForgetScene(scenes[index]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: widget.onClearScenes,
              child: const Text('Clear recent scenes'),
            ),
          ),
        ),
      ],
    );
  }
}

/// One project's card: cover art, name, and where it lives.
class ProjectCard extends StatefulWidget {
  const ProjectCard({
    super.key,
    required this.entry,
    required this.onOpen,
    required this.onForget,
  });

  final ProjectEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onForget;

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return MouseRegion(
      cursor: entry.exists
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        // A single click selects nothing here, so both gestures open: a
        // double click is the gesture people bring to a launcher, and a
        // single one is what they try when it does not seem to work.
        onTap: entry.exists ? widget.onOpen : null,
        onDoubleTap: entry.exists ? widget.onOpen : null,
        child: Container(
          decoration: BoxDecoration(
            color: editorPanelColor,
            border: Border.all(
              color: _hovered && entry.exists
                  ? editorAccentColor
                  : editorLineColor,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ProjectCover(entry: entry),
                    if (entry.isBroken)
                      Container(
                        color: editorSurfaceColor.withValues(alpha: 0.72),
                        alignment: Alignment.center,
                        child: Text(
                          entry.exists ? 'Unreadable' : 'Missing',
                          style: editorBodyText.copyWith(
                            color: editorErrorColor,
                          ),
                        ),
                      ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: _hovered ? 1 : 0,
                        child: _CardAction(
                          icon: Icons.close,
                          tooltip: 'Remove from the gallery',
                          onPressed: widget.onForget,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.name,
                      style: editorSubheadText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(entry),
                      style: editorDetailText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitle(ProjectEntry entry) {
    if (!entry.exists) return entry.root;
    if (entry.problem != null) return entry.problem!;
    final scenes =
        '${entry.sceneCount} scene${entry.sceneCount == 1 ? '' : 's'}';
    final age = describeAge(entry.modified);
    return age.isEmpty ? scenes : '$scenes  ·  $age';
  }
}

/// A card's art: the project's last capture, or a placeholder tinted from its
/// path so cards without art are still telling apart.
class ProjectCover extends StatelessWidget {
  const ProjectCover({super.key, required this.entry});

  final ProjectEntry entry;

  @override
  Widget build(BuildContext context) {
    final cover = entry.coverPath;
    if (cover != null && File(cover).existsSync()) {
      return Image.file(
        File(cover),
        fit: BoxFit.cover,
        errorBuilder: (context, _, _) => _placeholder(),
        // The gallery is a grid of small cards; decoding covers at their
        // stored width would hold far more pixels than any of them show.
        cacheWidth: 480,
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    final hue = placeholderHue(entry.path);
    final base = HSLColor.fromAHSL(1, hue, 0.34, 0.30).toColor();
    final far = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.30, 0.17).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, far],
        ),
      ),
      child: Center(
        child: Text(
          entry.name.isEmpty ? '?' : entry.name.characters.first.toUpperCase(),
          style: TextStyle(
            fontSize: 46,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.30),
          ),
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.tab, required this.onSelected});

  final LauncherTab tab;
  final ValueChanged<LauncherTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      decoration: const BoxDecoration(
        color: editorPanelColor,
        border: Border(right: BorderSide(color: editorLineColor)),
      ),
      child: Column(
        children: [
          // The window has no title bar, so the rail's top is the drag strip's
          // territory; leave it clear.
          const SizedBox(height: 40),
          Image.asset(
            'packages/flutter_scene_editor/assets/flutter_scene_logo.png',
            width: 30,
            height: 30,
            cacheWidth: 60,
          ),
          const SizedBox(height: 22),
          for (final entry in LauncherTab.values)
            _RailButton(
              tab: entry,
              selected: entry == tab,
              onPressed: () => onSelected(entry),
            ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.tab,
    required this.selected,
    required this.onPressed,
  });

  final LauncherTab tab;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tab.label,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          height: 48,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? editorAccentColor : Colors.transparent,
                width: 2,
              ),
            ),
            color: selected
                ? editorAccentColor.withValues(alpha: 0.10)
                : Colors.transparent,
          ),
          child: Icon(
            tab.icon,
            size: 19,
            color: selected ? editorAccentColor : editorMutedTextColor,
          ),
        ),
      ),
    );
  }
}

class _SortControl extends StatelessWidget {
  const _SortControl({required this.sort, required this.onChanged});

  final ProjectSort sort;
  final ValueChanged<ProjectSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<ProjectSort>(
        value: sort,
        isDense: true,
        style: editorBodyText.copyWith(color: editorTextColor),
        dropdownColor: editorRaisedColor,
        items: [
          for (final option in ProjectSort.values)
            DropdownMenuItem(value: option, child: Text(option.label)),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _SceneRow extends StatelessWidget {
  const _SceneRow({
    required this.path,
    required this.onOpen,
    required this.onForget,
  });

  final String path;
  final VoidCallback onOpen;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final missing = !file.existsSync();
    return ListTile(
      dense: true,
      leading: Icon(
        missing ? Icons.insert_drive_file_outlined : Icons.description_outlined,
        size: 18,
        color: missing ? editorErrorColor : editorMutedTextColor,
      ),
      title: Text(
        path.replaceAll('\\', '/').split('/').last,
        style: editorBodyText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        missing ? 'Missing  ${file.parent.path}' : file.parent.path,
        style: editorDetailText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: 'Remove from recent scenes',
        icon: const Icon(Icons.close, size: 16),
        onPressed: onForget,
      ),
      onTap: missing ? null : onOpen,
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: editorSurfaceColor.withValues(alpha: 0.7),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 14, color: editorTextColor),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: editorErrorColor.withValues(alpha: 0.12),
        border: Border.all(color: editorErrorColor.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: editorErrorColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: editorBodyText.copyWith(color: editorErrorColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _BusyState extends StatelessWidget {
  const _BusyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(height: 14),
        Text(message, style: editorBodyText),
      ],
    ),
  );
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: editorMutedTextColor),
          const SizedBox(height: 14),
          Text(title, style: editorDialogTitleText),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: editorDetailText),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    ),
  );
}
