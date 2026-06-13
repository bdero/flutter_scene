// Tests for the inspector's descriptor-driven field generation. These run
// headless (no GPU) against the core session and command schema.
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
// ignore: implementation_imports
import 'package:flutter_scene_editor_core/src/builtin_commands.dart'
    show setNodeTransform, createNode, setNodeName;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('uiDescriptors', () {
    test('setNodeTransform produces expected descriptors', () {
      final descs = uiDescriptors(setNodeTransform);
      expect(descs.map((d) => d.field).toList(), [
        'nodeId',
        'translation',
        'rotation',
        'scale',
      ]);
      expect(descs.first.type, ParamType.nodeRef);
      expect(descs.first.required, isTrue);
      expect(descs[1].required, isFalse); // translation is optional
    });

    test('createNode descriptors have name optional and parentId optional', () {
      final descs = uiDescriptors(createNode);
      final nameDesc = descs.firstWhere((d) => d.field == 'name');
      final parentDesc = descs.firstWhere((d) => d.field == 'parentId');
      expect(nameDesc.required, isFalse);
      expect(parentDesc.required, isFalse);
    });

    test('setNodeName descriptors have name required', () {
      final descs = uiDescriptors(setNodeName);
      final nameDesc = descs.firstWhere((d) => d.field == 'name');
      expect(nameDesc.required, isTrue);
    });
  });

  group('builtinCommands', () {
    test('all commands have non-empty name and doc', () {
      for (final cmd in builtinCommands) {
        expect(cmd.name, isNotEmpty, reason: 'command name missing');
        expect(cmd.doc, isNotEmpty, reason: '${cmd.name} has no doc');
      }
    });

    test('all commands have a category', () {
      for (final cmd in builtinCommands) {
        expect(cmd.category, isNotEmpty, reason: '${cmd.name} has no category');
      }
    });
  });
}
