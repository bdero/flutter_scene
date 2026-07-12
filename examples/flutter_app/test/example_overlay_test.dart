import 'package:example_app/example_action_hint.dart';
import 'package:example_app/example_overlay.dart';
import 'package:example_app/example_splats.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('top overlays clear system and app chrome', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(400, 800),
          padding: EdgeInsets.only(top: 24),
        ),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            height: 800,
            child: Stack(children: [_TopOverlayProbe()]),
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byKey(const ValueKey('probe'))).dy, 88);
    expect(tester.getSize(find.byType(Center)).height, 20);
  });

  testWidgets('bottom overlays clear the navigation inset', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(400, 800),
          padding: EdgeInsets.only(bottom: 24),
        ),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            height: 800,
            child: Stack(children: [_BottomOverlayProbe()]),
          ),
        ),
      ),
    );

    final stackHeight = tester.getSize(find.byType(Stack)).height;
    expect(
      tester.getBottomRight(find.byKey(const ValueKey('probe'))).dy,
      stackHeight - 24,
    );
  });

  testWidgets(
    'header actions move below chrome when the centred slot is narrow',
    (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 600),
            padding: EdgeInsets.only(top: 24),
          ),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 800,
              height: 600,
              child: Stack(children: [_HeaderActionProbe()]),
            ),
          ),
        ),
      );

      expect(
        tester.getTopLeft(find.byKey(const ValueKey('header-probe'))).dy,
        88,
      );
    },
  );

  testWidgets('header actions use the safe viewport geometric centre', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 600);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(1200, 600),
          padding: EdgeInsets.only(top: 24),
        ),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 1200,
            height: 600,
            child: Stack(children: [_HeaderActionProbe()]),
          ),
        ),
      ),
    );

    expect(
      tester.getRect(find.byKey(const ValueKey('header-probe'))).center.dx,
      600,
    );
  });

  testWidgets(
    'header actions use available space below the wide-screen threshold',
    (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(700, 600),
            padding: EdgeInsets.only(top: 24),
          ),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 700,
              height: 600,
              child: Stack(children: [_CompactHeaderActionProbe()]),
            ),
          ),
        ),
      );

      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('compact-header-probe')))
            .dy,
        24,
      );
    },
  );

  testWidgets('wide header actions use their available width before fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(900, 600),
          padding: EdgeInsets.only(top: 24),
        ),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 900,
            height: 600,
            child: Stack(children: [_ConstrainedHeaderActionProbe()]),
          ),
        ),
      ),
    );

    final action = find.byKey(const ValueKey('constrained-header-probe'));
    expect(tester.getTopLeft(action).dy, 24);
    expect(tester.getSize(action).width, 500);
  });

  testWidgets('full-width fly hints stay on a wide header when they fit', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(1100, 600),
          padding: EdgeInsets.only(top: 24),
        ),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 1100,
            height: 600,
            child: Stack(children: [_FlyCameraHintProbe()]),
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.byKey(const ValueKey('fly-hint-probe'))).dy,
      24,
    );
  });

  testWidgets('leading actions sit after the shared picker', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(800, 600),
          padding: EdgeInsets.only(top: 24),
        ),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 800,
            height: 600,
            child: Stack(children: [_LeadingActionProbe()]),
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.byKey(const ValueKey('leading-probe'))),
      const Offset(232, 24),
    );
  });

  testWidgets('wide leading action groups move below chrome when needed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(600, 600),
          padding: EdgeInsets.only(top: 24),
        ),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 600,
            height: 600,
            child: Stack(children: [_WideLeadingActionProbe()]),
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.byKey(const ValueKey('wide-leading-probe'))).dy,
      88,
    );
  });

  testWidgets('centred actions avoid a leading navigation action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(800, 600),
          padding: EdgeInsets.only(top: 24),
        ),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 800,
            height: 600,
            child: Stack(children: [_CentredWithLeadingProbe()]),
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.byKey(const ValueKey('centred-leading-probe'))).dy,
      88,
    );
  });

  testWidgets('centred header groups stay centred when chrome has room', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(800, 600),
          padding: EdgeInsets.only(top: 24),
        ),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 800,
            height: 600,
            child: Stack(children: [_CentredHeaderGroupProbe()]),
          ),
        ),
      ),
    );

    final group = find.byKey(const ValueKey('centred-header-group'));
    expect(tester.getRect(group).center.dx, 400);
    expect(tester.getTopLeft(group).dy, 24);
  });

  testWidgets('tall left panels stay below shared app chrome', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(400, 800),
          padding: EdgeInsets.only(top: 24, bottom: 24),
        ),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            height: 800,
            child: Stack(children: [_TallBottomLeftPanelProbe()]),
          ),
        ),
      ),
    );

    final probe = find.byKey(const ValueKey('probe'));
    final stackHeight = tester.getSize(find.byType(Stack)).height;
    expect(tester.getTopLeft(probe).dy, 88);
    expect(tester.getBottomRight(probe).dy, stackHeight - 24);
  });

  testWidgets('side panels give flex content a finite width', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(900, 600),
          padding: EdgeInsets.only(top: 24, bottom: 24),
        ),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 900,
            height: 600,
            child: Stack(children: [_SidePanelProbe()]),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const ValueKey('left-panel'))).width, 340);
    expect(
      tester.getSize(find.byKey(const ValueKey('right-panel'))).width,
      340,
    );
  });

  testWidgets('paired side panels keep a centre gap on compact screens', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(400, 800),
          padding: EdgeInsets.only(top: 24, bottom: 24),
        ),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            height: 800,
            child: Stack(children: [_PairedSidePanelProbe()]),
          ),
        ),
      ),
    );

    final left = tester.getRect(find.byKey(const ValueKey('paired-left')));
    final right = tester.getRect(find.byKey(const ValueKey('paired-right')));
    expect(left.width, lessThan(340));
    expect(right.width, lessThan(340));
    expect(right.left, greaterThan(left.right));
  });

  testWidgets('scene action buttons use the shared translucent dark surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ExampleActionButton(
              key: const ValueKey('action-button'),
              tooltip: 'Clear scene',
              icon: Icons.delete_outline,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Material && widget.color == Colors.black54,
      ),
      findsOneWidget,
    );
  });

  testWidgets('example dropdowns use the shared rounded dark menu style', (
    tester,
  ) async {
    String selected = 'DVR';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: 160,
                child: ExampleDropdown<String>(
                  value: selected,
                  onChanged: (value) {
                    if (value != null) setState(() => selected = value);
                  },
                  items: const [
                    DropdownMenuItem(value: 'MPR', child: Text('MPR')),
                    DropdownMenuItem(value: 'DVR', child: Text('DVR')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final trigger = tester.widget<Material>(
      find.byKey(const ValueKey('example-dropdown-surface')),
    );
    expect(trigger.color, Colors.black54);
    expect(
      (trigger.borderRadius as BorderRadius).topLeft,
      const Radius.circular(8),
    );
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);

    await tester.tap(find.text('DVR'));
    await tester.pumpAndSettle();

    final scrollbarTheme = tester.widget<ScrollbarTheme>(
      find.byKey(const ValueKey('example-dropdown-scrollbar-theme')),
    );
    expect(
      scrollbarTheme.data.thumbColor?.resolve(<WidgetState>{}),
      Colors.transparent,
    );
    expect(find.text('MPR'), findsOneWidget);

    await tester.tap(find.text('MPR'));
    await tester.pumpAndSettle();
    expect(selected, 'MPR');
  });

  testWidgets('camera toggle follows the navigation action style', (
    tester,
  ) async {
    bool freeCamera = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => ExampleCameraToggle(
                active: freeCamera,
                inactiveLabel: 'Orbit camera',
                activeLabel: 'Fly camera',
                inactiveIcon: Icons.videocam_outlined,
                activeIcon: Icons.videocam,
                onToggle: () => setState(() => freeCamera = !freeCamera),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Orbit camera'), findsOneWidget);
    expect(find.text('Fly camera'), findsNothing);
    expect(
      tester
          .widget<Material>(
            find.byKey(const ValueKey('example-camera-toggle-surface')),
          )
          .color,
      Colors.black54,
    );

    await tester.tap(find.text('Orbit camera'));
    await tester.pumpAndSettle();
    expect(freeCamera, isTrue);
    expect(find.text('Fly camera'), findsOneWidget);
  });

  testWidgets('Gaussian splat toggles fit the side-panel content width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 312,
              child: GaussianSplatToggleControls(
                antialiased: true,
                cropSweep: false,
                orbit: true,
                onAntialiasedChanged: (_) {},
                onCropSweepChanged: (_) {},
                onOrbitChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Antialiased'), findsOneWidget);
    expect(find.text('Crop sweep'), findsOneWidget);
    expect(find.text('Orbit'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(3));
  });

  testWidgets('Gaussian splats requests readable light system chrome', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GaussianSplatSystemChrome(child: SizedBox.expand()),
      ),
    );

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    );
    expect(region.value.statusBarIconBrightness, Brightness.light);
  });

  testWidgets('Gaussian splat settings scroll inside a short side panel', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 340,
              height: 264,
              child: GaussianSplatSettingsPanel(
                header: const SizedBox(height: 68),
                controls: const SizedBox(
                  key: ValueKey('splat-controls-end'),
                  height: 300,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byKey(const ValueKey('splat-controls-end')), findsOneWidget);
  });
}

class _TopOverlayProbe extends StatelessWidget {
  const _TopOverlayProbe();

  @override
  Widget build(BuildContext context) => ExampleOverlay.topCenter(
    child: const SizedBox(key: ValueKey('probe'), width: 100, height: 20),
  );
}

class _BottomOverlayProbe extends StatelessWidget {
  const _BottomOverlayProbe();

  @override
  Widget build(BuildContext context) => ExampleOverlay.bottomLeft(
    child: const SizedBox(key: ValueKey('probe'), width: 100, height: 20),
  );
}

class _TallBottomLeftPanelProbe extends StatelessWidget {
  const _TallBottomLeftPanelProbe();

  @override
  Widget build(BuildContext context) => ExampleOverlay.bottomLeftPanel(
    child: const SizedBox(key: ValueKey('probe'), width: 100, height: 900),
  );
}

class _HeaderActionProbe extends StatelessWidget {
  const _HeaderActionProbe();

  @override
  Widget build(BuildContext context) => ExampleOverlay.topCenterAction(
    child: const SizedBox(
      key: ValueKey('header-probe'),
      width: 100,
      height: 20,
    ),
  );
}

class _CompactHeaderActionProbe extends StatelessWidget {
  const _CompactHeaderActionProbe();

  @override
  Widget build(BuildContext context) => ExampleOverlay.topCenterAction(
    leadingReservation: 112,
    maxWidth: 420,
    child: const SizedBox(
      key: ValueKey('compact-header-probe'),
      width: 420,
      height: 20,
    ),
  );
}

class _ConstrainedHeaderActionProbe extends StatelessWidget {
  const _ConstrainedHeaderActionProbe();

  @override
  Widget build(BuildContext context) => ExampleOverlay.topCenterAction(
    leadingReservation: 176,
    maxWidth: 520,
    minHeaderWidth: 400,
    child: const SizedBox(
      key: ValueKey('constrained-header-probe'),
      width: 500,
      height: 20,
    ),
  );
}

class _FlyCameraHintProbe extends StatelessWidget {
  const _FlyCameraHintProbe();

  @override
  Widget build(BuildContext context) => ExampleOverlay.topCenterAction(
    leadingReservation: 176,
    maxWidth: 520,
    child: const SizedBox(
      key: ValueKey('fly-hint-probe'),
      width: 520,
      height: 20,
    ),
  );
}

class _LeadingActionProbe extends StatelessWidget {
  const _LeadingActionProbe();

  @override
  Widget build(BuildContext context) => ExampleOverlay.topLeadingAction(
    child: const SizedBox(
      key: ValueKey('leading-probe'),
      width: 48,
      height: 48,
    ),
  );
}

class _WideLeadingActionProbe extends StatelessWidget {
  const _WideLeadingActionProbe();

  @override
  Widget build(BuildContext context) => ExampleOverlay.topLeadingAction(
    minWidth: 336,
    child: const SizedBox(
      key: ValueKey('wide-leading-probe'),
      width: 336,
      height: 48,
    ),
  );
}

class _CentredWithLeadingProbe extends StatelessWidget {
  const _CentredWithLeadingProbe();

  @override
  Widget build(BuildContext context) => ExampleOverlay.topCenterAction(
    leadingReservation: 280,
    maxWidth: 280,
    child: const SizedBox(
      key: ValueKey('centred-leading-probe'),
      width: 280,
      height: 48,
    ),
  );
}

class _CentredHeaderGroupProbe extends StatelessWidget {
  const _CentredHeaderGroupProbe();

  @override
  Widget build(BuildContext context) => ExampleOverlay.topCenterAction(
    leadingReservation: 160,
    maxWidth: 400,
    child: const SizedBox(
      key: ValueKey('centred-header-group'),
      width: 400,
      height: 96,
    ),
  );
}

class _SidePanelProbe extends StatelessWidget {
  const _SidePanelProbe();

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ExampleOverlay.bottomLeftPanel(
        child: Card(
          key: const ValueKey('left-panel'),
          child: const Row(
            children: [
              SizedBox(width: 80, height: 20),
              Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
      ExampleOverlay.bottomRightPanel(
        child: Card(
          key: const ValueKey('right-panel'),
          child: const Row(
            children: [
              SizedBox(width: 80, height: 20),
              Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    ],
  );
}

class _PairedSidePanelProbe extends StatelessWidget {
  const _PairedSidePanelProbe();

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ExampleOverlay.bottomLeftPanel(
        paired: true,
        child: const SizedBox(key: ValueKey('paired-left'), height: 20),
      ),
      ExampleOverlay.bottomRightPanel(
        paired: true,
        child: const SizedBox(key: ValueKey('paired-right'), height: 20),
      ),
    ],
  );
}
