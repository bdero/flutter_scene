// Regenerates the ETC1S goldens in test/fixtures/ktx2/ with the reference
// transcoder: the WASI build of basisu from basis_universal's bin/ (v2.50.0),
// run by Node 20+.
//
//   node tool/etc1s_goldens.mjs <basisu_st.wasm> [--rgba] [fixture...]
//
// Writes <name>.etc1, .etc2_rgba, .bc1 and .bc3 (and .rgba with --rgba),
// levels concatenated base first.

import { closeSync, mkdtempSync, openSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { WASI } from 'node:wasi';
import { inflateSync } from 'node:zlib';

const fixtureDir = resolve(new URL('../test/fixtures/ktx2/', import.meta.url).pathname);
const defaultFixtures = [
  'etc1s_srgb_mips_64',
  'etc1s_alpha_srgb_32',
  'etc1s_linear_20x14',
  'alpha_simple_basis',
  'etc1s_features_rgba_64',
];

const args = process.argv.slice(2);
const wantRgba = args.includes('--rgba');
const positional = args.filter((a) => !a.startsWith('--'));
if (positional.length < 1) {
  console.error('usage: node tool/etc1s_goldens.mjs <basisu_st.wasm> [--rgba] [fixture...]');
  process.exit(64);
}
const wasmModule = await WebAssembly.compile(readFileSync(positional[0]));
const fixtures = positional.length > 1 ? positional.slice(1) : defaultFixtures;

async function basisu(argv) {
  // The tool reports every file it writes; only its errors are kept.
  const quiet = openSync('/dev/null', 'w');
  try {
    const wasi = new WASI({
      version: 'preview1',
      args: ['basisu', ...argv],
      preopens: { '/': '/' },
      stdout: quiet,
      returnOnExit: true,
    });
    const instance = await WebAssembly.instantiate(wasmModule, wasi.getImportObject());
    const code = wasi.start(instance);
    if (code !== 0) throw new Error(`basisu ${argv.join(' ')} exited with ${code}`);
  } finally {
    closeSync(quiet);
  }
}

// The mip levels of an uncompressed-header KTX1 file, base first.
function ktx1Levels(path) {
  const data = readFileSync(path);
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  const levelCount = Math.max(1, view.getUint32(12 + 11 * 4, true));
  let offset = 64 + view.getUint32(12 + 12 * 4, true);
  const levels = [];
  for (let i = 0; i < levelCount; i++) {
    const size = view.getUint32(offset, true);
    offset += 4;
    levels.push(data.subarray(offset, offset + size));
    offset += size + ((4 - (size % 4)) % 4);
  }
  return levels;
}

// Decodes a non-interlaced 8-bit RGB or RGBA PNG to RGBA8 pixels (opaque
// images come out of basisu as RGB).
function pngRgba(path) {
  const data = readFileSync(path);
  let offset = 8;
  let width = 0;
  let height = 0;
  let channels = 0;
  const idat = [];
  while (offset < data.length) {
    const length = data.readUInt32BE(offset);
    const type = data.toString('latin1', offset + 4, offset + 8);
    const body = data.subarray(offset + 8, offset + 8 + length);
    if (type === 'IHDR') {
      width = body.readUInt32BE(0);
      height = body.readUInt32BE(4);
      channels = { 2: 3, 6: 4 }[body[9]] ?? 0;
      if (body[8] !== 8 || channels === 0 || body[12] !== 0) {
        throw new Error(`${path}: expected 8-bit non-interlaced RGB or RGBA`);
      }
    } else if (type === 'IDAT') {
      idat.push(body);
    }
    offset += 12 + length;
  }
  const raw = inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const pixels = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let x = 0; x < stride; x++) {
      const a = x >= channels ? pixels[y * stride + x - channels] : 0;
      const b = y > 0 ? pixels[(y - 1) * stride + x] : 0;
      const c = x >= channels && y > 0 ? pixels[(y - 1) * stride + x - channels] : 0;
      let predictor = 0;
      if (filter === 1) predictor = a;
      else if (filter === 2) predictor = b;
      else if (filter === 3) predictor = (a + b) >> 1;
      else if (filter === 4) {
        const p = a + b - c;
        const pa = Math.abs(p - a);
        const pb = Math.abs(p - b);
        const pc = Math.abs(p - c);
        predictor = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      }
      pixels[y * stride + x] = (line[x] + predictor) & 0xff;
    }
  }
  if (channels === 4) return pixels;
  const out = Buffer.alloc(width * height * 4, 255);
  for (let i = 0; i < width * height; i++) {
    pixels.copy(out, i * 4, i * 3, i * 3 + 3);
  }
  return out;
}

const targets = [
  ['ETC1_RGB', 'etc1'],
  ['ETC2_RGBA', 'etc2_rgba'],
  ['BC1_RGB', 'bc1'],
  ['BC3_RGBA', 'bc3'],
];

for (const name of fixtures) {
  const work = mkdtempSync(join(tmpdir(), 'etc1s-goldens-'));
  try {
    const source = join(work, `${name}.ktx2`);
    writeFileSync(source, readFileSync(join(fixtureDir, `${name}.ktx2`)));
    await basisu(['-unpack', source, '-output_path', work]);
    const files = readdirSync(work);
    for (const [format, extension] of targets) {
      const file = files.find((f) => f === `${name}_transcoded_${format}_layer_0000.ktx`);
      if (!file) throw new Error(`${name}: basisu wrote no ${format} file`);
      const bytes = Buffer.concat(ktx1Levels(join(work, file)));
      writeFileSync(join(fixtureDir, `${name}.${extension}`), bytes);
      console.log(`${name}.${extension}: ${bytes.length} bytes`);
    }
    if (wantRgba) {
      const levels = files
        .map((f) => f.match(new RegExp(`^${name}_unpacked_rgba_RGBA32_level_(\\d+)_face_0_layer0000\\.png$`)))
        .filter(Boolean)
        .sort((a, b) => Number(a[1]) - Number(b[1]))
        .map((m) => pngRgba(join(work, m[0])));
      const bytes = Buffer.concat(levels);
      writeFileSync(join(fixtureDir, `${name}.rgba`), bytes);
      console.log(`${name}.rgba: ${bytes.length} bytes (${levels.length} levels)`);
    }
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}
