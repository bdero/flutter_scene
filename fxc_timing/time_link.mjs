// Times WebGL2 compile, link, and first draw of each shader variant in Chrome,
// one fresh browser per run so no program cache carries over.
//
//   node time_link.mjs <chrome.exe> <out.json> <angle flag> <variant>...
import puppeteer from 'puppeteer-core';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const [chrome, outFile, angle, ...variants] = process.argv.slice(2);
const runs = Number(process.env.RUNS ?? 2);

async function measure(vs, fs_) {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 4;
  document.body.appendChild(canvas);
  const gl = canvas.getContext('webgl2');
  if (!gl) return { error: 'no webgl2' };
  const dbg = gl.getExtension('WEBGL_debug_renderer_info');
  const renderer = dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : '?';
  const now = () => performance.now();

  const t0 = now();
  const shader = (type, src) => {
    const s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
      throw new Error('compile: ' + gl.getShaderInfoLog(s));
    }
    return s;
  };
  let v, f;
  try {
    v = shader(gl.VERTEX_SHADER, vs);
    f = shader(gl.FRAGMENT_SHADER, fs_);
  } catch (e) {
    return { renderer, error: String(e) };
  }
  const t1 = now();
  const p = gl.createProgram();
  gl.attachShader(p, v);
  gl.attachShader(p, f);
  gl.linkProgram(p);
  const linked = gl.getProgramParameter(p, gl.LINK_STATUS);
  const t2 = now();
  if (!linked) {
    return { renderer, error: 'link: ' + gl.getProgramInfoLog(p) };
  }

  // Bind something to every input so the draw is valid and the backend builds
  // the executable it really draws with.
  gl.useProgram(p);
  const blocks = gl.getProgramParameter(p, gl.ACTIVE_UNIFORM_BLOCKS);
  for (let i = 0; i < blocks; i++) {
    const size = gl.getActiveUniformBlockParameter(
      p, i, gl.UNIFORM_BLOCK_DATA_SIZE);
    const b = gl.createBuffer();
    gl.bindBuffer(gl.UNIFORM_BUFFER, b);
    gl.bufferData(gl.UNIFORM_BUFFER, size, gl.STATIC_DRAW);
    gl.uniformBlockBinding(p, i, i);
    gl.bindBufferBase(gl.UNIFORM_BUFFER, i, b);
  }
  const samplerTypes = new Set([
    gl.SAMPLER_2D, gl.SAMPLER_CUBE, gl.SAMPLER_3D, gl.SAMPLER_2D_SHADOW,
    gl.SAMPLER_2D_ARRAY, gl.INT_SAMPLER_2D, gl.UNSIGNED_INT_SAMPLER_2D,
  ]);
  const uniforms = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
  let unit = 0;
  for (let i = 0; i < uniforms; i++) {
    const u = gl.getActiveUniform(p, i);
    if (samplerTypes.has(u.type)) {
      gl.uniform1i(gl.getUniformLocation(p, u.name), unit++);
    }
  }
  const attribs = gl.getProgramParameter(p, gl.ACTIVE_ATTRIBUTES);
  const vb = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, vb);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(3 * 16), gl.STATIC_DRAW);
  for (let i = 0; i < attribs; i++) {
    const a = gl.getActiveAttrib(p, i);
    const loc = gl.getAttribLocation(p, a.name);
    if (loc < 0) continue;
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 4, gl.FLOAT, false, 64, 0);
  }
  gl.drawArrays(gl.TRIANGLES, 0, 3);
  gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array(4));
  const t3 = now();
  return {
    renderer,
    compileMs: t1 - t0,
    linkMs: t2 - t1,
    firstDrawMs: t3 - t2,
    totalMs: t3 - t0,
    glError: gl.getError(),
    fragBytes: fs_.length,
  };
}

const results = [];
for (const variant of variants) {
  const dir = path.join('shaders', variant);
  const vs = fs.readFileSync(path.join(dir, 'vert.glsl'), 'utf8');
  const fsrc = fs.readFileSync(path.join(dir, 'frag.glsl'), 'utf8');
  for (let run = 0; run < runs; run++) {
    const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'chrome-'));
    const browser = await puppeteer.launch({
      executablePath: chrome,
      headless: true,
      protocolTimeout: 30 * 60 * 1000,
      args: [
        `--user-data-dir=${profile}`,
        `--use-angle=${angle}`,
        '--ignore-gpu-blocklist',
        '--disable-gpu-shader-disk-cache',
        '--disable-gpu-program-cache',
        '--enable-logging=stderr',
        '--v=0',
      ],
      dumpio: true,
    });
    const page = await browser.newPage();
    await page.goto('about:blank');
    const r = await page.evaluate(measure, vs, fsrc);
    await browser.close();
    const row = { variant, angle, run, ...r };
    console.log(JSON.stringify(row));
    fs.appendFileSync(outFile + 'l', JSON.stringify(row) + '\n');
    results.push(row);
  }
}
fs.writeFileSync(outFile, JSON.stringify(results, null, 2));
