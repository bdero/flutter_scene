// The pose saves with the document, so a move has to be reported (the editor
// marks the scene dirty) while restoring a saved pose must not be.
import 'package:flutter_scene_editor/src/viewport/orbit_camera.dart';
import 'package:flutter_scene_editor/src/viewport/viewport_camera_handle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  late OrbitCamera camera;
  late ViewportCameraHandle handle;
  late int moves;

  setUp(() {
    camera = OrbitCamera(radius: 10);
    handle = ViewportCameraHandle();
    moves = 0;
  });

  test('a move is reported, a restore is not', () {
    handle.attach(camera, () => moves++);

    handle.setPose(azimuth: 1);
    expect(camera.azimuth, 1);
    expect(moves, 1);

    handle.restorePose(azimuth: 2, target: Vector3(3, 0, 0));
    expect(camera.azimuth, 2);
    expect(camera.target.x, 3);
    expect(moves, 1, reason: 'the document already holds a restored pose');
  });

  test('a pose held for a viewport that has not come up yet is a restore', () {
    handle.restorePose(azimuth: 4);
    handle.attach(camera, () => moves++);

    expect(camera.azimuth, 4);
    expect(moves, 0);
  });

  test('framing reports a move', () {
    handle.attach(camera, () => moves++);
    handle.frame(Aabb3.minMax(Vector3.zero(), Vector3.all(1)));
    expect(moves, 1);
  });
}
