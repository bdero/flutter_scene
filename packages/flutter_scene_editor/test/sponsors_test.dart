import 'package:flutter_scene_editor/src/sponsors/sponsor_widgets.dart';
import 'package:flutter_scene_editor/src/sponsors/sponsors.dart';
import 'package:flutter_scene_editor/src/toolchains/editor_build_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _manifest = '''
{
  "updated": "2026-09-17",
  "sponsors": [
    {"name": "Bronze Co", "tier": "bronze", "url": "https://bronze.example"},
    {"name": "Silver Co", "tier": "silver", "url": "https://silver.example",
     "since": "2026-09-17"},
    {"name": "Gold Co", "tier": "gold", "logo": "assets/sponsors/logos/gold.png"},
    {"name": "Patron Co", "tier": "patron"},
    {"name": "Lapsed Co", "tier": "gold", "until": "2026-01-31"},
    {"name": "Later Co", "tier": "platinum", "since": "2027-01-01"},
    {"name": "", "tier": "gold"},
    {"name": "Odd Co", "tier": "diamond"}
  ],
  "backers": ["A. Backer", " B. Backer ", ""]
}
''';

final _today = DateTime(2026, 10, 1);

void main() {
  test('parse keeps well-formed entries and drops the rest', () {
    final manifest = SponsorManifest.parse(_manifest);
    expect(manifest.sponsors.map((s) => s.name), [
      'Bronze Co',
      'Silver Co',
      'Gold Co',
      'Patron Co',
      'Lapsed Co',
      'Later Co',
    ]);
    expect(manifest.backers, ['A. Backer', 'B. Backer']);
    final silver = manifest.sponsors[1];
    expect(silver.tier, SponsorTier.silver);
    expect(silver.url, 'https://silver.example');
    expect(silver.since, DateTime(2026, 9, 17));
  });

  test('malformed input yields the empty manifest', () {
    expect(SponsorManifest.parse('not json').isEmpty, isTrue);
    expect(SponsorManifest.parse('[1, 2]').isEmpty, isTrue);
    expect(SponsorManifest.parse('{"sponsors": 3}').isEmpty, isTrue);
  });

  test('active sponsors honor the term and sort highest tier first', () {
    final manifest = SponsorManifest.parse(_manifest);
    expect(manifest.active(_today).map((s) => s.name), [
      'Patron Co',
      'Gold Co',
      'Silver Co',
      'Bronze Co',
    ]);
    // Undated entries are always active; Gold Co and Lapsed Co share a tier
    // and fall back to name order.
    expect(manifest.active(DateTime(2026, 1, 15)).map((s) => s.name), [
      'Patron Co',
      'Gold Co',
      'Lapsed Co',
      'Bronze Co',
    ]);
  });

  test('placement follows the tier', () {
    final manifest = SponsorManifest.parse(_manifest);
    expect(manifest.forAboutDialog(_today).map((s) => s.name), [
      'Patron Co',
      'Gold Co',
      'Silver Co',
    ]);
    expect(manifest.forStartScreen(_today).map((s) => s.name), [
      'Patron Co',
      'Gold Co',
    ]);
    expect(SponsorTier.patron.startScreenScale, greaterThan(1));
    expect(SponsorTier.gold.startScreenScale, 1);
  });

  testWidgets('the strip shows Gold and above and nothing below', (
    tester,
  ) async {
    final manifest = SponsorManifest.parse(_manifest);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SponsorStrip(manifest: manifest, day: _today),
        ),
      ),
    );
    expect(find.text('Supported by'), findsOneWidget);
    expect(find.text('Patron Co'), findsOneWidget);
    // Gold Co has a logo path that does not resolve in tests, so the name
    // is the fallback.
    await tester.pump();
    expect(find.text('Gold Co'), findsOneWidget);
    expect(find.text('Silver Co'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SponsorStrip(
            manifest: SponsorManifest.parse(
              '{"sponsors": [{"name": "Only Silver", "tier": "silver"}]}',
            ),
            day: _today,
          ),
        ),
      ),
    );
    expect(find.text('Supported by'), findsNothing);
  });

  testWidgets('the About dialog lists versions, sponsors, and backers', (
    tester,
  ) async {
    final manifest = SponsorManifest.parse(_manifest);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showEditorAboutDialog(
              context,
              buildInfo: const EditorBuildInfo(
                frameworkVersion: '3.47.0',
                frameworkRevision: 'abcdef0123456789',
                flutterSceneVersion: '0.23.0',
              ),
              sponsors: manifest,
              day: _today,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Scene Editor'), findsOneWidget);
    expect(find.text('flutter_scene 0.23.0, Flutter 3.47.0'), findsOneWidget);
    expect(find.text('Sponsors'), findsOneWidget);
    expect(find.text('Silver Co'), findsOneWidget);
    expect(find.text('Bronze Co'), findsNothing);
    expect(find.text('Backers'), findsOneWidget);
    expect(find.text('A. Backer, B. Backer'), findsOneWidget);
    expect(find.text('Sponsor Flutter Scene'), findsOneWidget);
    // The dialog scrolls in the 800x600 test window.
    await tester.ensureVisible(find.text('Close'));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Scene Editor'), findsNothing);
  });
}
