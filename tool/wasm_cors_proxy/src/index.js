// CORS proxy for the flutter_scene_rapier WebAssembly module.
//
// GitHub release assets are served without Access-Control-Allow-Origin,
// so a browser cannot fetch the wasm module cross-origin. This Cloudflare
// Worker fetches the release asset server-side (no CORS there) and
// re-serves it with permissive CORS and long-lived caching. The module
// therefore lives only on the GitHub release, the same artifact the
// native build hook downloads; nothing is tracked in the repository.
//
// The web backend still verifies the module's sha256 after download, so
// this proxy is untrusted transport: a wrong or tampered response fails
// verification rather than loading bad code.
//
// Requests map /<tag>/<file>.wasm to
//   https://github.com/<repo>/releases/download/<tag>/<file>.wasm
// Only `.wasm` paths are proxied, so this is not an open proxy.

const RELEASE_BASE =
  'https://github.com/bdero/flutter_scene/releases/download';

export default {
  async fetch(request) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders() });
    }
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method not allowed', {
        status: 405,
        headers: corsHeaders(),
      });
    }

    const path = new URL(request.url).pathname.replace(/^\/+/, '');
    if (!path.endsWith('.wasm') || path.includes('..')) {
      return new Response('Not found', {
        status: 404,
        headers: corsHeaders(),
      });
    }

    const upstream = await fetch(`${RELEASE_BASE}/${path}`, {
      method: request.method,
      cf: { cacheEverything: true, cacheTtl: 31536000 },
    });
    if (!upstream.ok) {
      return new Response(`Upstream responded ${upstream.status}`, {
        status: upstream.status,
        headers: corsHeaders(),
      });
    }

    const headers = corsHeaders();
    headers.set('content-type', 'application/wasm');
    // Release assets are immutable per tag, so cache aggressively.
    headers.set('cache-control', 'public, max-age=31536000, immutable');
    return new Response(upstream.body, { status: 200, headers });
  },
};

function corsHeaders() {
  const headers = new Headers();
  headers.set('access-control-allow-origin', '*');
  headers.set('access-control-allow-methods', 'GET, HEAD, OPTIONS');
  headers.set('access-control-max-age', '86400');
  return headers;
}
