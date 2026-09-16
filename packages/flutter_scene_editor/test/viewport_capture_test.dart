import 'package:flutter/widgets.dart';
import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_scene_mcp/flutter_scene_mcp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('captures while the app is hidden', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: key,
          child: const SizedBox(
            width: 8,
            height: 6,
            child: ColoredBox(color: Color(0xFF00FF00)),
          ),
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(tester.binding.framesEnabled, isFalse);

    final capture = viewportScreenshot(key)();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    final shot = (await tester.runAsync(() => capture))!;

    expect((shot.width, shot.height), (8, 6));
    expect(shot.pngBytes, isNotEmpty);
  });

  testWidgets('fails instead of hanging when no frame arrives', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: const SizedBox()));

    final capture = viewportScreenshot(
      key,
      frameTimeout: const Duration(seconds: 1),
    )();
    final failure = expectLater(capture, throwsA(isA<ToolError>()));
    // Advances fake time without producing a frame.
    await tester.binding.delayed(const Duration(seconds: 2));
    await failure;
  });
}
