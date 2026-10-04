// ignore_for_file: implementation_imports
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/src/generated_assets/spirv_constant_arrays.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/spirv/$name.spv').readAsBytesSync();

/// The storage class of every OpVariable, with whether it has an initializer.
List<(int storage, bool initialized)> _variables(Uint8List spirv) {
  final words = spirv.buffer.asUint32List(spirv.offsetInBytes);
  final out = <(int, bool)>[];
  for (var i = 5; i < words.length;) {
    final count = words[i] >> 16;
    if ((words[i] & 0xffff) == 59) out.add((words[i + 3], count > 4));
    i += count;
  }
  return out;
}

const int _function = 7;
const int _private = 6;

/// Runs spirv-val over [spirv] when it is on the PATH.
void _validate(Uint8List spirv) {
  final dir = Directory.systemTemp.createTempSync('spirv_hoist');
  try {
    final file = File('${dir.path}/out.spv')..writeAsBytesSync(spirv);
    final ProcessResult result;
    try {
      result = Process.runSync('spirv-val', [
        '--target-env',
        'vulkan1.1',
        file.path,
      ]);
    } on ProcessException {
      return;
    }
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main() {
  test('copies of a constant table become one private variable', () {
    final input = _fixture('constant_table');
    final before = _variables(input);
    // One table copy per function that reads it.
    expect(before.where((v) => v.$1 == _function).length, 6);

    final out = hoistConstantArrays(input);
    final after = _variables(out);
    expect(after.where((v) => v == (_private, true)).length, 1);
    // The four scalar locals remain; both table copies are gone.
    expect(after.where((v) => v.$1 == _function).length, 4);
    _validate(out);
  });

  test('is idempotent', () {
    final once = hoistConstantArrays(_fixture('constant_table'));
    expect(hoistConstantArrays(once), once);
  });

  test('leaves an array that is written after initialization alone', () {
    final input = _fixture('written_array');
    expect(hoistConstantArrays(input), same(input));
  });

  test('passes anything that is not a module through', () {
    final junk = Uint8List.fromList(List.filled(24, 7));
    expect(hoistConstantArrays(junk), same(junk));
    final short = Uint8List.fromList([3, 2, 35, 7]);
    expect(hoistConstantArrays(short), same(short));
  });
}
