// The history is bounded, and dirtiness tracks everything that saves with the
// document (the camera included, which is never an undo step).
import 'dart:typed_data';

import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:scene/scene.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

class _View implements ViewHost {
  @override
  EditorCameraSpec camera = EditorCameraSpec(
    azimuth: 0,
    elevation: 0,
    radius: 1,
    target: Vector3.zero(),
  );

  @override
  void setCamera(EditorCameraSpec pose) => camera = pose;

  @override
  bool frame(Iterable<LocalId> ids) => true;
}

/// A transaction that adds a payload of [bytes] bytes, the heavy kind of
/// record the byte ceiling exists for.
Transaction _payload(SceneDocument document, int bytes) {
  final id = document.allocator.mint();
  return Transaction(
    name: 'Import',
    records: [
      ChangeRecord(
        targetId: id,
        slot: ChangeSlot.poolPayload,
        oldValue: const PayloadChange(null),
        newValue: PayloadChange(
          PayloadSpec(
            id,
            encoding: PayloadEncoding.bytes,
            bytes: Uint8List(bytes),
          ),
        ),
      ),
    ],
  );
}

void main() {
  test('the step cap drops the oldest edits', () {
    final session = EditorSession.empty();
    final history = EditHistory(
      DocumentMutator(session.document),
      selection: session.selection,
      maxEntries: 3,
    );
    for (var i = 0; i < 6; i++) {
      history.commit(_payload(session.document, 1));
    }
    expect(history.transactions, hasLength(3));
    expect(history.cursor, 3);
  });

  test('the byte ceiling drops heavy edits even under the step cap', () {
    final session = EditorSession.empty();
    final history = EditHistory(
      DocumentMutator(session.document),
      selection: session.selection,
      maxPayloadBytes: 2048,
    );
    for (var i = 0; i < 5; i++) {
      history.commit(_payload(session.document, 1024));
    }
    expect(history.transactions.length, lessThanOrEqualTo(2));
  });

  group('dirty', () {
    test('starts clean, and an edit dirties it', () {
      final session = EditorSession.empty();
      expect(session.isDirty, isFalse);
      session.run('createNode', {'name': 'a'});
      expect(session.isDirty, isTrue);
      session.markSaved();
      expect(session.isDirty, isFalse);
    });

    test('selection and the camera both dirty the document', () {
      final session = EditorSession.empty()..viewHost = _View();
      final id = session
          .run('createNode', {'name': 'a'})
          .records
          .first
          .targetId;
      session.markSaved();

      session.run('selectNodes', {
        'nodeIds': [id.toToken()],
      });
      expect(session.isDirty, isTrue, reason: 'selection saves with the file');

      session.markSaved();
      final steps = session.history.transactions.length;
      session.run('setViewportCamera', {'radius': 4.0});
      expect(session.isDirty, isTrue, reason: 'the camera saves with it too');
      expect(
        session.history.transactions,
        hasLength(steps),
        reason: 'but it is not an undo step',
      );
    });

    test('undo dirties too, since it moves away from what was saved', () {
      final session = EditorSession.empty();
      session.run('createNode', {'name': 'a'});
      session.markSaved();
      session.undo();
      expect(session.isDirty, isTrue);
    });
  });
}
