import 'package:flutter/services.dart' show AssetBundle, ByteData, rootBundle;

/// Loads the generated asset at [key] from [bundle] (default [rootBundle]).
Future<ByteData> loadGeneratedAsset(String key, {AssetBundle? bundle}) =>
    (bundle ?? rootBundle).load(key);

/// Loads the generated asset at [key] from [bundle] as UTF-8 text.
Future<String> loadGeneratedAssetString(String key, {AssetBundle? bundle}) =>
    (bundle ?? rootBundle).loadString(key);
