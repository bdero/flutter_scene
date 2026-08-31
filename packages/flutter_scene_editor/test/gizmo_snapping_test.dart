// Transform snapping. Tolerances are 1e-6 rather than tighter because
// Vector3 stores float32, so an exact literal does not round-trip exactly.
// The controller accumulates a raw drag and exposes it
// snapped, so these drive the accumulator directly rather than through a
// viewport.
import 'package:flutter_scene_editor/src/viewport/transform_gizmo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Pushes [raw] into the controller's translation accumulator by grabbing an
/// axis and reporting a drag of exactly that much.
GizmoController translated(vm.Vector3 raw, {double snap = 0}) {
  final controller = GizmoController()
    ..mode = GizmoMode.translate
    ..translateSnap = snap;
  controller.debugSetAccumulated(translation: raw);
  return controller;
}

void main() {
  group('translation', () {
    test('no snap leaves the drag exactly as dragged', () {
      final c = translated(vm.Vector3(1.234, -0.5, 9.87));
      expect(c.translation.x, closeTo(1.234, 1e-6));
      expect(c.translation.z, closeTo(9.87, 1e-6));
    });

    test('snaps the running total to the nearest step', () {
      final c = translated(vm.Vector3(1.2, -0.4, 2.6), snap: 0.5);
      expect(c.translation.x, closeTo(1.0, 1e-6));
      expect(c.translation.y, closeTo(-0.5, 1e-6));
      expect(c.translation.z, closeTo(2.5, 1e-6));
    });

    test('a drag shorter than half a step does not move at all', () {
      // Otherwise the smallest nudge jumps a whole cell.
      final c = translated(vm.Vector3(0.2, 0, 0), snap: 1.0);
      expect(c.translation.x, closeTo(0, 1e-6));
    });

    test('it snaps the total, not each step, so it cannot drift', () {
      // Ten drags of 0.19 is 1.9, which snaps to 2. Snapping each delta
      // instead would round every one to zero and never move.
      final c = GizmoController()..translateSnap = 1.0;
      for (var i = 0; i < 10; i++) {
        c.debugAddTranslation(vm.Vector3(0.19, 0, 0));
      }
      expect(c.translation.x, closeTo(2.0, 1e-6));
    });

    test('suppressing snap restores the raw drag mid-gesture', () {
      final c = translated(vm.Vector3(1.2, 0, 0), snap: 0.5);
      expect(c.translation.x, closeTo(1.0, 1e-6));
      c.snapSuppressed = true;
      expect(c.translation.x, closeTo(1.2, 1e-6));
    });
  });

  group('rotation', () {
    test('snaps to the nearest step', () {
      final c = GizmoController()..rotateSnap = 0.5;
      c.debugSetAccumulated(angle: 1.3);
      expect(c.angle, closeTo(1.5, 1e-6));
    });

    test('negative turns snap the same way', () {
      final c = GizmoController()..rotateSnap = 0.5;
      c.debugSetAccumulated(angle: -1.3);
      expect(c.angle, closeTo(-1.5, 1e-6));
    });

    test('zero snap turns freely', () {
      final c = GizmoController();
      c.debugSetAccumulated(angle: 1.234);
      expect(c.angle, closeTo(1.234, 1e-6));
    });
  });

  group('scale', () {
    test('snaps each axis to the step', () {
      final c = GizmoController()..scaleSnap = 0.25;
      c.debugSetAccumulated(scale: vm.Vector3(1.1, 2.6, 0.9));
      expect(c.scale.x, closeTo(1.0, 1e-6));
      expect(c.scale.y, closeTo(2.5, 1e-6));
      expect(c.scale.z, closeTo(1.0, 1e-6));
    });

    test('never snaps a node down to nothing', () {
      // Zero scale is invisible and awkward to recover from, so the smallest
      // it lands on is one step.
      final c = GizmoController()..scaleSnap = 0.25;
      c.debugSetAccumulated(scale: vm.Vector3(0.1, 0.02, 0.12));
      expect(c.scale.x, closeTo(0.25, 1e-6));
      expect(c.scale.y, closeTo(0.25, 1e-6));
      expect(c.scale.z, closeTo(0.25, 1e-6));
    });

    test('zero snap scales freely', () {
      final c = GizmoController();
      c.debugSetAccumulated(scale: vm.Vector3(1.37, 1, 1));
      expect(c.scale.x, closeTo(1.37, 1e-6));
    });
  });
}
