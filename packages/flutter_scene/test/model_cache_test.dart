import 'package:flutter_scene/src/importer/model_cache.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelImportCache', () {
    test('imports once and returns a fresh clone per load', () async {
      final cache = ModelImportCache();
      var imports = 0;
      Future<Node> import() async {
        imports++;
        return Node(name: 'template');
      }

      final a = await cache.load('k', import);
      final b = await cache.load('k', import);

      expect(imports, 1); // parsed and uploaded once
      expect(a, isNot(same(b))); // each load is its own clone
      expect(a.name, 'template');
      expect(b.name, 'template');
    });

    test('deduplicates concurrent loads of the same key', () async {
      final cache = ModelImportCache();
      var imports = 0;
      Future<Node> import() async {
        imports++;
        await Future<void>.delayed(Duration.zero);
        return Node(name: 'template');
      }

      final results = await Future.wait([
        cache.load('k', import),
        cache.load('k', import),
      ]);

      expect(imports, 1);
      expect(results[0], isNot(same(results[1])));
    });

    test('evict forces a re-import', () async {
      final cache = ModelImportCache();
      var imports = 0;
      Future<Node> import() async {
        imports++;
        return Node(name: 'template');
      }

      await cache.load('k', import);
      expect(cache.contains('k'), isTrue);

      cache.evict('k');
      expect(cache.contains('k'), isFalse);

      await cache.load('k', import);
      expect(imports, 2);
    });

    test('does not cache a failed import', () async {
      final cache = ModelImportCache();
      var attempts = 0;
      Future<Node> import() async {
        attempts++;
        if (attempts == 1) {
          throw StateError('boom');
        }
        return Node(name: 'ok');
      }

      await expectLater(cache.load('k', import), throwsStateError);
      expect(cache.contains('k'), isFalse);

      final node = await cache.load('k', import); // retry succeeds
      expect(node.name, 'ok');
      expect(attempts, 2);
    });
  });
}
