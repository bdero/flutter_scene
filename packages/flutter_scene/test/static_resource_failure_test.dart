/// A failed shader-bundle load used to be logged through `dart:developer`
/// `log()` (invisible on web) while the future completed normally, so the
/// developer's `await` succeeded and they hit the `baseShaderLibrary` getter
/// telling them to await the call they had just made. The load now reports
/// what actually went wrong.
library;

import 'package:flutter/services.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/generated_assets/generated_asset_lookup.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_test/flutter_test.dart';

/// A bundle with no assets at all, the state a build that never ran
/// flutter_scene's hook leaves behind.
final class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object?>{})!;
    }
    throw StateError('missing asset $key');
  }
}

void main() {
  tearDown(clearGeneratedAssetIndexCache);

  test('an unresolvable bundle key reports the missing-bundle cause', () async {
    // The resolution the loader runs first: with nothing built, there is no
    // key to load, which is what produces the failure the getter now names.
    expect(await resolveBaseShaderBundleKey(bundle: _EmptyBundle()), isNull);
  });

  test('a failed load reports, and the getter names why', () async {
    // Driven from a known state against a bundle with nothing in it, so the
    // failure path runs on every machine rather than only where the checkout
    // happens to lack a built bundle.
    debugResetBaseShaderLibrary();
    addTearDown(debugResetBaseShaderLibrary);

    await expectLater(
      loadBaseShaderLibrary(bundle: _EmptyBundle()),
      throwsA(isA<Object>()),
    );

    // Both halves of issue #244: the load must not report success on failure,
    // and the getter must name the cause rather than send the developer back
    // to initializeStaticResources(), which they have already awaited.
    expect(baseShaderLibraryLoadError, isNotNull);
    expect(
      () => baseShaderLibrary,
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          allOf(
            contains('failed to load'),
            isNot(contains('has not been loaded yet')),
          ),
        ),
      ),
    );
  });
}
