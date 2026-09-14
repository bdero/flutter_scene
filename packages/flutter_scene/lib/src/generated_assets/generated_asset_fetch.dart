/// Loads generated engine assets (shader bundles and the JSON that pairs with
/// them) so a rebuilt app never reads a stale copy.
///
/// Generated assets keep a fixed URL across flutter_scene and engine versions,
/// and on web a browser's HTTP cache can serve an old one beside new Dart code,
/// which breaks every draw that binds a block the old bundle lacks. The web
/// implementation revalidates each load; elsewhere this reads [AssetBundle]s
/// directly.
library;

export 'generated_asset_fetch_io.dart'
    if (dart.library.js_interop) 'generated_asset_fetch_web.dart';
