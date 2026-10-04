/// Hoists read-only, constant-initialized function variables in SPIR-V into
/// shared module-scope private variables, before the WGSL translation.
///
/// GLSL compilers lower a dynamically indexed `const` array (a noise
/// gradient table, say) to a function-scope variable stored from a constant,
/// and inlining gives every call site its own. SPIRV-Cross folds them back
/// into one constant, but Tint keeps each as a WGSL `var`, and Metal's
/// compiler then sees hundreds of private array copies. A large shader (240
/// copies of a 256-float table) crashed it outright. Hoisting leaves one
/// `var<private>` per distinct constant.
///
/// Binary layout per the SPIR-V specification, section 2.3 (Physical Layout
/// of a SPIR-V Module and Instruction).
library;

import 'dart:typed_data';

const int _opName = 5;
const int _opMemberName = 6;
const int _opEntryPoint = 15;
const int _opTypeArray = 28;
const int _opTypePointer = 32;
const int _opConstantTrue = 41;
const int _opConstantFalse = 42;
const int _opConstant = 43;
const int _opConstantComposite = 44;
const int _opConstantNull = 46;
const int _opFunction = 54;
const int _opVariable = 59;
const int _opLoad = 61;
const int _opStore = 62;
const int _opAccessChain = 65;
const int _opInBoundsAccessChain = 66;
const int _opDecorate = 71;

const int _storageFunction = 7;
const int _storagePrivate = 6;

const Set<int> _constantOps = {
  _opConstantTrue,
  _opConstantFalse,
  _opConstant,
  _opConstantComposite,
  _opConstantNull,
};

/// One instruction: its opcode and operand words (everything after the
/// first word).
final class _Instruction {
  _Instruction(this.opcode, this.operands);

  final int opcode;
  final List<int> operands;
}

/// Returns [spirv] (little-endian words) with every eligible array variable
/// hoisted, or [spirv] itself when nothing qualifies.
///
/// A variable qualifies when it is a function-scope array, every write to it
/// (its initializer and any `OpStore`) is the same constant, and every other
/// use is a load, directly or through access chains that are only loaded.
Uint8List hoistConstantArrays(Uint8List spirv) {
  if (spirv.length < 20 || spirv.length % 4 != 0) return spirv;
  final words = spirv.buffer.asUint32List(
    spirv.offsetInBytes,
    spirv.length ~/ 4,
  );
  if (words[0] != 0x07230203) return spirv;
  final version = words[1];
  var bound = words[3];

  final instructions = <_Instruction>[];
  for (var i = 5; i < words.length;) {
    final count = words[i] >> 16;
    if (count == 0 || i + count > words.length) return spirv;
    instructions.add(
      _Instruction(words[i] & 0xffff, words.sublist(i + 1, i + count)),
    );
    i += count;
  }

  final pointers = <int, (int, int)>{}; // id -> (storage, pointee)
  final pointerIds = <(int, int), int>{}; // (storage, pointee) -> id
  final arrays = <int>{};
  final constants = <int>{};
  for (final inst in instructions) {
    switch (inst.opcode) {
      case _opTypePointer:
        final key = (inst.operands[1], inst.operands[2]);
        pointers[inst.operands[0]] = key;
        pointerIds.putIfAbsent(key, () => inst.operands[0]);
      case _opTypeArray:
        arrays.add(inst.operands[0]);
      case final op when _constantOps.contains(op):
        constants.add(inst.operands[1]);
    }
  }

  // Candidate variables, with the constant every write stores.
  final value = <int, int?>{};
  final pointeeOf = <int, int>{};
  for (final inst in instructions) {
    if (inst.opcode != _opVariable || inst.operands[2] != _storageFunction) {
      continue;
    }
    final pointee = pointers[inst.operands[0]]?.$2;
    if (pointee == null || !arrays.contains(pointee)) continue;
    final initializer = inst.operands.length > 3 ? inst.operands[3] : null;
    if (initializer != null && !constants.contains(initializer)) continue;
    value[inst.operands[1]] = initializer;
    pointeeOf[inst.operands[1]] = pointee;
  }
  if (value.isEmpty) return spirv;

  // Pointers derived from a candidate through access chains, by root.
  final rootOf = <int, int>{for (final v in value.keys) v: v};
  final rejected = <int>{};
  for (final inst in instructions) {
    switch (inst.opcode) {
      case _opAccessChain || _opInBoundsAccessChain:
        final root = rootOf[inst.operands[2]];
        if (root != null) rootOf[inst.operands[1]] = root;
      case _opStore:
        final root = rootOf[inst.operands[0]];
        if (root == null) break;
        final stored = inst.operands[1];
        final previous = value[root];
        if (root != inst.operands[0] ||
            !constants.contains(stored) ||
            (previous != null && previous != stored)) {
          rejected.add(root);
        } else {
          value[root] = stored;
        }
    }
  }
  // Any use other than a load, a chain, a store, or a name rejects the root.
  // Function variables are only referenced inside functions, and the global
  // section's literals (constant values) would only alias ids by accident.
  var inFunctions = false;
  for (final inst in instructions) {
    final ops = inst.operands;
    inFunctions = inFunctions || inst.opcode == _opFunction;
    if (!inFunctions) continue;
    switch (inst.opcode) {
      case _opLoad:
        for (var i = 3; i < ops.length; i++) {
          if (rootOf.containsKey(ops[i])) rejected.add(rootOf[ops[i]]!);
        }
      case _opAccessChain || _opInBoundsAccessChain:
        for (var i = 3; i < ops.length; i++) {
          if (rootOf.containsKey(ops[i])) rejected.add(rootOf[ops[i]]!);
        }
      case _opStore:
        if (rootOf.containsKey(ops[1])) rejected.add(rootOf[ops[1]]!);
      case _opVariable || _opName || _opMemberName || _opDecorate:
        break;
      default:
        for (final operand in ops) {
          final root = rootOf[operand];
          if (root != null) rejected.add(root);
        }
    }
  }
  final hoisted = {
    for (final MapEntry(:key, value: constant) in value.entries)
      if (!rejected.contains(key) && constant != null) key: constant,
  };
  if (hoisted.isEmpty) return spirv;

  // One private variable per (array type, constant), and private pointer
  // types for every function pointer type the rewrite retargets.
  final added = <List<int>>[];
  int privatePointer(int pointee) =>
      pointerIds[(_storagePrivate, pointee)] ??= () {
        final id = bound++;
        added.add([_opTypePointer, id, _storagePrivate, pointee]);
        return id;
      }();
  final privateVars = <(int, int), int>{};
  final replacement = <int, int>{};
  for (final MapEntry(key: variable, value: constant) in hoisted.entries) {
    final pointee = pointeeOf[variable]!;
    replacement[variable] = privateVars[(pointee, constant)] ??= () {
      final type = privatePointer(pointee);
      final id = bound++;
      added.add([_opVariable, type, id, _storagePrivate, constant]);
      return id;
    }();
  }
  final derived = {
    for (final MapEntry(:key, :value) in rootOf.entries)
      if (hoisted.containsKey(value)) key,
  };
  // Every retargeted chain's private pointer type, made now so it is
  // declared with the other globals, ahead of the functions.
  final chainTypes = <int, int>{};
  for (final inst in instructions) {
    if ((inst.opcode == _opAccessChain ||
            inst.opcode == _opInBoundsAccessChain) &&
        derived.contains(inst.operands[2])) {
      chainTypes[inst.operands[1]] = privatePointer(
        pointers[inst.operands[0]]!.$2,
      );
    }
  }

  final out = <int>[...words.sublist(0, 5)];
  void emit(int opcode, List<int> operands) {
    out
      ..add((operands.length + 1) << 16 | opcode)
      ..addAll(operands);
  }

  var globalsWritten = false;
  for (final inst in instructions) {
    final ops = inst.operands;
    if (inst.opcode == _opFunction && !globalsWritten) {
      for (final a in added) {
        emit(a.first, a.sublist(1));
      }
      globalsWritten = true;
    }
    switch (inst.opcode) {
      case _opVariable when hoisted.containsKey(ops[1]):
        continue;
      case _opStore when hoisted.containsKey(ops[0]):
        continue;
      case _opName || _opDecorate when hoisted.containsKey(ops[0]):
        continue;
      case _opAccessChain || _opInBoundsAccessChain
          when derived.contains(ops[2]):
        emit(inst.opcode, [
          chainTypes[ops[1]]!,
          ops[1],
          replacement[ops[2]] ?? ops[2],
          ...ops.sublist(3),
        ]);
      case _opLoad when hoisted.containsKey(ops[2]):
        emit(_opLoad, [
          ops[0],
          ops[1],
          replacement[ops[2]]!,
          ...ops.sublist(3),
        ]);
      case _opEntryPoint when version >= 0x00010400:
        // From SPIR-V 1.4 an entry point lists every global it uses.
        emit(_opEntryPoint, [...ops, ...privateVars.values]);
      default:
        emit(inst.opcode, ops);
    }
  }
  if (!globalsWritten) return spirv;
  out[3] = bound;
  return Uint32List.fromList(out).buffer.asUint8List();
}
