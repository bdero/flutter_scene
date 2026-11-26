// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/mipmap.dart' show TextureContent;
import 'package:flutter_scene/src/texture/mipmap_async.dart';
import 'package:flutter_scene/src/texture/web_time_slicer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runs items in order within the budget without yielding', () async {
    final slicer = WebTimeSlicer(sliceBudget: const Duration(hours: 1));
    final events = <String>[];
    Timer.run(() => events.add('timer'));
    await Future.wait([
      slicer.run(() => events.add('a')),
      slicer.run(() => events.add('b')),
      slicer.run(() => events.add('c')),
    ]);
    expect(events, ['a', 'b', 'c']);
  });

  test('yields to the event loop once the budget is spent', () async {
    final slicer = WebTimeSlicer(sliceBudget: Duration.zero);
    final peer = WebTimeSlicer(sliceBudget: Duration.zero);
    final events = <String>[];
    Future<void>? peerDone;
    await Future.wait([
      slicer.run(() {
        events.add('a');
        peerDone = peer.run(() => events.add('peer'));
      }),
      slicer.run(() => events.add('b')),
    ]);
    await peerDone;
    expect(events, ['a', 'peer', 'b']);
  });

  test(
    'a failing item rejects its own future and the queue continues',
    () async {
      final slicer = WebTimeSlicer(sliceBudget: Duration.zero);
      final failing = slicer.run<int>(() => throw StateError('decode failed'));
      final next = slicer.run(() => 2);
      await expectLater(failing, throwsStateError);
      expect(await next, 2);
    },
  );

  test('generateMipChainAsync builds the full chain', () async {
    final pixels = Uint8List.fromList(List<int>.filled(4 * 4 * 4, 200));
    final levels = await generateMipChainAsync(
      pixels,
      4,
      4,
      TextureContent.color,
    );
    expect(levels.map((l) => (l.width, l.height)), [(4, 4), (2, 2), (1, 1)]);
  });
}
