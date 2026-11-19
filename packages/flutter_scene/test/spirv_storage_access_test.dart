// ignore_for_file: implementation_imports
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_scene/src/generated_assets/spirv_storage_access.dart';
import 'package:flutter_test/flutter_test.dart';

const int _opDecorate = 71;
const int _opMemberDecorate = 72;
const int _nonWritable = 24;
const int _nonReadable = 25;
const int _binding = 33;

int _op(int opcode, int count) => count << 16 | opcode;

/// A module header followed by [body], as little-endian bytes.
Uint8List _module(List<int> body) => Uint32List.fromList([
  0x07230203,
  0x00010000,
  0,
  10,
  0,
  ...body,
]).buffer.asUint8List();

void main() {
  test('drops NonReadable and keeps every other decoration', () {
    final out = dropNonReadable(
      _module([
        _op(_opDecorate, 3),
        1,
        _nonReadable,
        _op(_opMemberDecorate, 4),
        2,
        0,
        _nonReadable,
        _op(_opMemberDecorate, 4),
        3,
        0,
        _nonWritable,
        _op(_opDecorate, 4),
        1,
        _binding,
        1,
      ]),
    );
    expect(
      out,
      _module([
        _op(_opMemberDecorate, 4),
        3,
        0,
        _nonWritable,
        _op(_opDecorate, 4),
        1,
        _binding,
        1,
      ]),
    );
  });

  test('returns a module with nothing to drop unchanged', () {
    final module = _module([_op(_opDecorate, 3), 1, _nonWritable]);
    expect(identical(dropNonReadable(module), module), isTrue);
  });

  test('passes anything that is not a module through', () {
    final bytes = Uint8List.fromList([3, 2, 35, 7]);
    expect(identical(dropNonReadable(bytes), bytes), isTrue);
  });
}
