import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene_editor_core/src/change.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A document with a root node `a` and a child `b`, allocated deterministically.
({SceneDocument doc, NodeSpec a, NodeSpec b}) _base() {
  final doc = SceneDocument(allocator: IdAllocator(session: 1));
  final a = doc.createNode(name: 'A', root: true);
  final b = doc.createNode(name: 'B');
  a.children.add(b.id);
  return (doc: doc, a: a, b: b);
}

void main() {
  group('Transaction apply and revert', () {
    test('scalar slot (name) round-trips', () {
      final base = _base();
      final mutator = DocumentMutator(base.doc);
      final tx = Transaction(
        name: 'Rename',
        records: [
          ChangeRecord(
            targetId: base.a.id,
            slot: ChangeSlot.name,
            oldValue: const StringChange('A'),
            newValue: const StringChange('Renamed'),
          ),
        ],
      );

      tx.apply(mutator);
      expect(base.doc.node(base.a.id)!.name, 'Renamed');
      tx.revert(mutator);
      expect(base.doc.node(base.a.id)!.name, 'A');
    });

    test('transform slot replaces the whole transform', () {
      final base = _base();
      final mutator = DocumentMutator(base.doc);
      final old = base.b.transform;
      final next = TrsTransform(translation: Vector3(1, 2, 3));
      final tx = Transaction(
        name: 'Move',
        records: [
          ChangeRecord(
            targetId: base.b.id,
            slot: ChangeSlot.transform,
            oldValue: TransformChange(old),
            newValue: TransformChange(next),
          ),
        ],
      );

      tx.apply(mutator);
      expect(base.doc.node(base.b.id)!.transform, same(next));
      tx.revert(mutator);
      expect(base.doc.node(base.b.id)!.transform, same(old));
    });

    test('component list snapshot is reversible', () {
      final base = _base();
      final mutator = DocumentMutator(base.doc);
      final added = ComponentSpec('directionalLight');
      final tx = Transaction(
        name: 'Add light',
        records: [
          ChangeRecord(
            targetId: base.a.id,
            slot: ChangeSlot.components,
            oldValue: ComponentListChange(List.of(base.a.components)),
            newValue: ComponentListChange([added]),
          ),
        ],
      );

      tx.apply(mutator);
      expect(base.doc.node(base.a.id)!.components, [added]);
      tx.revert(mutator);
      expect(base.doc.node(base.a.id)!.components, isEmpty);
    });

    test('pool node add via NodeChange, revert removes it', () {
      final base = _base();
      final mutator = DocumentMutator(base.doc);
      final newId = base.doc.newId();
      final added = NodeSpec(id: newId, name: 'C');
      final tx = Transaction(
        name: 'Add node',
        records: [
          ChangeRecord(
            targetId: newId,
            slot: ChangeSlot.poolNode,
            oldValue: const NodeChange(null),
            newValue: NodeChange(added),
          ),
          ChangeRecord(
            targetId: ChangeRecord.rootsTarget,
            slot: ChangeSlot.roots,
            oldValue: IdListChange(List.of(base.doc.roots)),
            newValue: IdListChange([...base.doc.roots, newId]),
          ),
        ],
      );

      tx.apply(mutator);
      expect(base.doc.node(newId), same(added));
      expect(base.doc.roots, contains(newId));

      tx.revert(mutator);
      expect(base.doc.node(newId), isNull);
      expect(base.doc.roots, isNot(contains(newId)));
    });

    test('children list snapshot is reversible', () {
      final base = _base();
      final mutator = DocumentMutator(base.doc);
      final tx = Transaction(
        name: 'Clear children',
        records: [
          ChangeRecord(
            targetId: base.a.id,
            slot: ChangeSlot.children,
            oldValue: IdListChange(List.of(base.a.children)),
            newValue: const IdListChange([]),
          ),
        ],
      );

      tx.apply(mutator);
      expect(base.doc.node(base.a.id)!.children, isEmpty);
      tx.revert(mutator);
      expect(base.doc.node(base.a.id)!.children, [base.b.id]);
    });

    test('empty transaction reports isEmpty', () {
      expect(Transaction(name: 'noop', records: const []).isEmpty, isTrue);
    });
  });
}
