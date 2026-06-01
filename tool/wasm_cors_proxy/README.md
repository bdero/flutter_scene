# wasm CORS proxy

A Cloudflare Worker that re-serves the `flutter_scene_rapier` WebAssembly
module (a GitHub release asset) with CORS headers, so the web backend can
fetch it cross-origin. GitHub release assets have no
`Access-Control-Allow-Origin` header, which a browser `fetch` requires.

The module stays a release asset (the same one the native build hook
downloads); this proxy only adds CORS and caching. The web backend
verifies the module's sha256 after download, so the proxy is untrusted
transport.

## Deploy

```sh
npx wrangler login      # one time, against the Cloudflare account
npx wrangler deploy     # from this directory
```

`deploy` prints the worker URL, e.g.
`https://flutter-scene-wasm.<subdomain>.workers.dev`. Set
`wasmReleaseBaseUrl` in
`packages/flutter_scene_rapier/lib/src/ffi/wasm_release.dart` to that URL.

The web backend then fetches
`<worker-url>/<tag>/flutter_scene_rapier_native.wasm`, which the worker
maps to the matching GitHub release asset.

## Verify CORS

```sh
curl -sIL -H 'Origin: https://example.com' \
  https://flutter-scene-wasm.<subdomain>.workers.dev/<tag>/flutter_scene_rapier_native.wasm \
  | grep -i access-control-allow-origin
```
