/// Sponsor placement in the editor, the start-screen strip and the About
/// dialog.
library;

import 'package:material_ui/material_ui.dart';

import '../io/open_url.dart';
import '../shell/editor_dialog.dart';
import '../toolchains/editor_build_info.dart';
import 'sponsors.dart';

const _siteUrl = 'https://fscene.dev';
const _sponsorUrl = 'https://fscene.dev/sponsors';
const _repoUrl = 'https://github.com/bdero/flutter_scene';

/// "Supported by" logos for sponsors at Gold and above. Renders nothing when
/// no sponsor qualifies, so the start screen never shows an empty heading.
class SponsorStrip extends StatelessWidget {
  const SponsorStrip({super.key, required this.manifest, this.day});

  final SponsorManifest manifest;

  /// The day placement is evaluated for; defaults to now. Tests pin it.
  final DateTime? day;

  @override
  Widget build(BuildContext context) {
    final shown = manifest.forStartScreen(day ?? DateTime.now());
    if (shown.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Supported by',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 22,
          runSpacing: 12,
          children: [
            for (final sponsor in shown)
              _SponsorMark(
                sponsor: sponsor,
                height: 26 * sponsor.tier.startScreenScale,
              ),
          ],
        ),
      ],
    );
  }
}

class _SponsorMark extends StatelessWidget {
  const _SponsorMark({required this.sponsor, required this.height});

  final Sponsor sponsor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logo = sponsor.logoFor(theme.brightness);
    final name = Text(
      sponsor.name,
      style: theme.textTheme.titleMedium?.copyWith(
        fontSize: height * 0.62,
        fontWeight: FontWeight.w600,
      ),
    );
    final Widget mark = logo == null
        ? name
        : Image.asset(
            logo,
            height: height,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => name,
          );
    final url = sponsor.url;
    return Tooltip(
      message: url ?? sponsor.name,
      child: InkWell(
        onTap: url == null ? null : () => openUrl(url),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: mark,
        ),
      ),
    );
  }
}

/// The editor's About dialog, versions, project links, and sponsor credits.
Future<void> showEditorAboutDialog(
  BuildContext context, {
  required EditorBuildInfo buildInfo,
  required SponsorManifest sponsors,
  DateTime? day,
}) {
  return showEditorDialog<void>(
    context,
    builder: (context) =>
        _AboutDialog(buildInfo: buildInfo, sponsors: sponsors, day: day),
  );
}

class _AboutDialog extends StatelessWidget {
  const _AboutDialog({
    required this.buildInfo,
    required this.sponsors,
    this.day,
  });

  final EditorBuildInfo buildInfo;
  final SponsorManifest sponsors;
  final DateTime? day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = day ?? DateTime.now();
    final companies = sponsors.forAboutDialog(today);
    final version = buildInfo.flutterSceneVersion;
    final framework = buildInfo.frameworkVersion;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Image.asset(
                  'packages/flutter_scene_editor/assets/flutter_scene_logo.png',
                  width: 64,
                  height: 64,
                  cacheWidth: 128,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Scene Editor',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              if (version != null || framework != null) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    if (version != null) 'flutter_scene $version',
                    if (framework != null) 'Flutter $framework',
                  ].join(', '),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Flutter Scene is an independent open source project, MIT '
                'licensed, and not affiliated with Google.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () => openUrl(_siteUrl),
                    child: const Text('fscene.dev'),
                  ),
                  TextButton(
                    onPressed: () => openUrl(_repoUrl),
                    child: const Text('GitHub'),
                  ),
                  TextButton(
                    onPressed: () => openUrl(_sponsorUrl),
                    child: const Text('Sponsor Flutter Scene'),
                  ),
                ],
              ),
              if (companies.isNotEmpty) ...[
                const Divider(height: 24),
                Text('Sponsors', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final sponsor in companies) _SponsorRow(sponsor: sponsor),
              ],
              if (sponsors.backers.isNotEmpty) ...[
                const Divider(height: 24),
                Text('Backers', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  sponsors.backers.join(', '),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SponsorRow extends StatelessWidget {
  const _SponsorRow({required this.sponsor});

  final Sponsor sponsor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logo = sponsor.logoFor(theme.brightness);
    final url = sponsor.url;
    return InkWell(
      onTap: url == null ? null : () => openUrl(url),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            if (logo != null) ...[
              Image.asset(
                logo,
                height: 20,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(sponsor.name, style: theme.textTheme.bodyMedium),
            ),
            Text(
              sponsor.tier.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
