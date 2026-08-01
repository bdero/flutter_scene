// Covers the ownership half of the GPU memory story: a ResourceGroup gives
// back the claims it took, and the memory report's value types. The registry
// refcounts are exercised through the loaders, which need an asset bundle and
// a GPU, so they are covered by the example app rather than here.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ResourceGroup ownership', () {
    test('dispose gives back every tracked claim', () async {
      final released = <String>[];
      final group = ResourceGroup();
      group.track(
        Future<int>.value(1),
        release: () async => released.add('terrain'),
      );
      group.track(
        Future<int>.value(2),
        release: () async => released.add('props'),
      );
      await group.ready;

      expect(released, isEmpty, reason: 'nothing is released before dispose');
      group.dispose();
      expect(released, ['terrain', 'props']);
    });

    test('release can be called without disposing, and is idempotent', () {
      var releases = 0;
      final group = ResourceGroup();
      group.track(Future<int>.value(1), release: () async => releases++);

      group.release();
      expect(releases, 1);
      // A second release must not hand the same claim back twice, which would
      // drop a cache entry another holder still owns.
      group.release();
      expect(releases, 1);
      group.dispose();
      expect(releases, 1);
    });

    test('track still counts toward progress like add', () async {
      final group = ResourceGroup();
      group.track(Future<int>.value(1), release: () async {});
      expect(group.total, 1);
      await group.ready;
      expect(group.completed, 1);
      expect(group.isReady, isTrue);
      group.dispose();
    });

    test('a failed tracked load still releases its claim', () async {
      var releases = 0;
      final group = ResourceGroup();
      group.track(
        Future<int>.error(StateError('boom')),
        release: () async => releases++,
      );
      await group.ready;

      expect(group.hasFailures, isTrue);
      group.dispose();
      expect(releases, 1, reason: 'a load that failed may still have cached');
    });
  });

  group('memory report', () {
    test('totals only the categories that can report a size', () {
      const report = MemoryReport([
        MemoryCategory(name: 'textures', bytes: 2 * 1024 * 1024, count: 3),
        MemoryCategory(name: 'scene templates', bytes: null, count: 2),
      ]);
      expect(report.totalBytes, 2 * 1024 * 1024);
      expect(report.toString(), contains('2.00 MiB'));
      expect(report.toString(), contains('scene templates: 2'));
    });

    test('reports empty caches rather than throwing', () {
      final report = takeMemoryReport();
      expect(report.categories, isNotEmpty);
      expect(report.totalBytes, 0);
      for (final category in report.categories) {
        expect(category.count, 0);
      }
    });
  });
}
