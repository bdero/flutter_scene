import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_scene/src/importer/model_reload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelReloadTracker', () {
    test('reports no change for identical content', () async {
      final bundle = _FakeBundle({'k': utf8.encode('aaa')});
      final tracker = ModelReloadTracker();
      await tracker.prime('k', bundle: bundle);
      expect(await tracker.hasChanged('k', bundle: bundle), isFalse);
    });

    test('reports a change when content changes, then re-baselines', () async {
      final bundle = _FakeBundle({'k': utf8.encode('aaa')});
      final tracker = ModelReloadTracker();
      await tracker.prime('k', bundle: bundle);

      bundle.assets['k'] = utf8.encode('bbbb');
      expect(await tracker.hasChanged('k', bundle: bundle), isTrue);
      // The baseline updated, so the same content is no longer a change.
      expect(await tracker.hasChanged('k', bundle: bundle), isFalse);
    });

    test(
      'first observation records a baseline without reporting a change',
      () async {
        final bundle = _FakeBundle({'k': utf8.encode('aaa')});
        final tracker = ModelReloadTracker();
        expect(await tracker.hasChanged('k', bundle: bundle), isFalse);
        bundle.assets['k'] = utf8.encode('ccc');
        expect(await tracker.hasChanged('k', bundle: bundle), isTrue);
      },
    );
  });
}

final class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.assets);

  final Map<String, List<int>> assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = assets[key];
    if (bytes == null) {
      throw StateError('Missing test asset: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}
