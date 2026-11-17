// Times a WebGL2 warm-up of a realistic pipeline set in Chrome, replaying the
// GL calls flutter_scene's WebGL2 shim makes under three strategies.
//
//   before   compile and link each pipeline, waiting on each result, then
//            draw with it (no KHR_parallel_shader_compile)
//   step1    enable the extension and defer every status read to the
//            pipeline's first bind, which still follows its build at once
//   step2    enable the extension, issue every compile and link, poll
//            COMPLETION_STATUS_KHR off the main thread's critical path, then
//            bind and draw each
//
// Each run gets a fresh browser with the program caches off. A final pass
// reruns step2 with the caches on, twice in one browser and once after a
// relaunch on the same profile, to see whether repeat runs hit them.
//
//   node warmup/time_warmup.mjs <chrome.exe> <out.json> <angle flag>
import puppeteer from 'puppeteer-core';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const [chrome, outFile, angle] = process.argv.slice(2);
const runs = Number(process.env.RUNS ?? 3);
const modes = (process.env.MODES ?? 'before,step1,step2').split(',');
const dir = path.join(
  path.dirname(fileURLToPath(import.meta.url)), 'shaders');
const pipelines = JSON.parse(
  fs.readFileSync(path.join(dir, 'pipelines.json'), 'utf8'));
const sources = {};
for (const [v, f] of pipelines) {
  for (const name of [v, f]) {
    sources[name] ??= fs.readFileSync(path.join(dir, name + '.glsl'), 'utf8');
  }
}

async function warmUp(mode, sources, pipelines) {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 4;
  document.body.appendChild(canvas);
  const gl = canvas.getContext('webgl2');
  if (!gl) return { error: 'no webgl2' };
  const dbg = gl.getExtension('WEBGL_debug_renderer_info');
  const renderer = dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : '?';
  const now = () => performance.now();
  const COMPLETION_STATUS_KHR = 0x91B1;

  const t0 = now();
  // Main-thread busy time, as the synchronous slices between awaits.
  let blocked = 0;
  let longest = 0;
  let sliceStart = t0;
  const endSlice = () => {
    const d = now() - sliceStart;
    blocked += d;
    longest = Math.max(longest, d);
  };

  const parallel = mode !== 'before' &&
    gl.getExtension('KHR_parallel_shader_compile') != null;

  const shaders = {};
  const shader = (name) => {
    if (shaders[name]) return shaders[name];
    const s = gl.createShader(name.endsWith('Vertex')
      ? gl.VERTEX_SHADER : gl.FRAGMENT_SHADER);
    gl.shaderSource(s, sources[name]);
    gl.compileShader(s);
    if (mode === 'before' && !gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
      throw new Error(name + ': ' + gl.getShaderInfoLog(s));
    }
    return shaders[name] = s;
  };

  const build = ([v, f]) => {
    const p = gl.createProgram();
    gl.attachShader(p, shader(v));
    gl.attachShader(p, shader(f));
    gl.linkProgram(p);
    const pipeline = { p, name: v + '+' + f, checked: false };
    if (mode === 'before') firstUse(pipeline);
    return pipeline;
  };

  // WebGlRenderPipeline._ensureLinked and _buildUniformCaches.
  const firstUse = (pipeline) => {
    if (pipeline.checked) return;
    pipeline.checked = true;
    const { p } = pipeline;
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) {
      throw new Error(pipeline.name + ': ' + gl.getProgramInfoLog(p));
    }
    gl.useProgram(p);
    const yFlip = gl.getUniformLocation(p, '_impeller_y_flip');
    if (yFlip) gl.uniform1f(yFlip, -1);
    const blocks = gl.getProgramParameter(p, gl.ACTIVE_UNIFORM_BLOCKS);
    pipeline.blocks = [];
    for (let i = 0; i < blocks; i++) {
      const name = gl.getActiveUniformBlockName(p, i);
      const index = gl.getUniformBlockIndex(p, name);
      gl.uniformBlockBinding(p, index, i);
      pipeline.blocks.push(gl.getActiveUniformBlockParameter(
        p, index, gl.UNIFORM_BLOCK_DATA_SIZE));
    }
    const samplerTypes = new Set([
      gl.SAMPLER_2D, gl.SAMPLER_CUBE, gl.SAMPLER_3D, gl.SAMPLER_2D_SHADOW,
      gl.SAMPLER_2D_ARRAY, gl.INT_SAMPLER_2D, gl.UNSIGNED_INT_SAMPLER_2D,
    ]);
    let unit = 0;
    const uniforms = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < uniforms; i++) {
      const u = gl.getActiveUniform(p, i);
      if (samplerTypes.has(u.type)) {
        gl.uniform1i(gl.getUniformLocation(p, u.name), unit++);
      }
    }
  };

  const vb = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, vb);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(3 * 32), gl.STATIC_DRAW);
  const draw = (pipeline) => {
    const t = now();
    firstUse(pipeline);
    const { p } = pipeline;
    gl.useProgram(p);
    pipeline.blocks.forEach((size, i) => {
      const b = gl.createBuffer();
      gl.bindBuffer(gl.UNIFORM_BUFFER, b);
      gl.bufferData(gl.UNIFORM_BUFFER, Math.max(size, 16), gl.STATIC_DRAW);
      gl.bindBufferBase(gl.UNIFORM_BUFFER, i, b);
    });
    const attribs = gl.getProgramParameter(p, gl.ACTIVE_ATTRIBUTES);
    for (let i = 0; i < 16; i++) gl.disableVertexAttribArray(i);
    for (let i = 0; i < attribs; i++) {
      const loc = gl.getAttribLocation(p, gl.getActiveAttrib(p, i).name);
      if (loc < 0) continue;
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, 4, gl.FLOAT, false, 128, 0);
    }
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    pipeline.drawMs = now() - t;
  };

  const perPipeline = [];
  let issued;
  let ready;
  try {
    if (mode === 'step2') {
      const built = pipelines.map(build);
      issued = now() - t0;
      endSlice();
      // Scene.warmUp's awaitPipelinesReady: poll, yielding between polls.
      const pending = parallel ? [...built] : [];
      while (pending.length) {
        sliceStart = now();
        while (pending.length &&
          gl.getProgramParameter(pending.at(-1).p, COMPLETION_STATUS_KHR)) {
          pending.pop();
        }
        endSlice();
        if (pending.length) await new Promise((r) => setTimeout(r, 4));
      }
      ready = now() - t0;
      sliceStart = now();
      built.forEach(draw);
      perPipeline.push(...built);
    } else {
      for (const desc of pipelines) {
        const pipeline = build(desc);
        draw(pipeline);
        perPipeline.push(pipeline);
      }
    }
    gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array(4));
    endSlice();
  } catch (e) {
    return { renderer, parallel, error: String(e) };
  }
  return {
    renderer,
    parallel,
    wallMs: now() - t0,
    blockedMs: blocked,
    longestSliceMs: longest,
    issuedMs: issued,
    readyMs: ready,
    drawMs: Object.fromEntries(perPipeline.map((p) => [p.name, p.drawMs])),
    glError: gl.getError(),
  };
}

async function launch(profile, cache) {
  return puppeteer.launch({
    executablePath: chrome,
    headless: true,
    protocolTimeout: 30 * 60 * 1000,
    args: [
      `--user-data-dir=${profile}`,
      `--use-angle=${angle}`,
      '--ignore-gpu-blocklist',
      ...(cache ? [] : [
        '--disable-gpu-shader-disk-cache',
        '--disable-gpu-program-cache',
      ]),
      '--enable-logging=stderr',
      '--v=0',
    ],
    dumpio: true,
  });
}

async function once(browser, mode) {
  const page = await browser.newPage();
  await page.goto('about:blank');
  const r = await page.evaluate(warmUp, mode, sources, pipelines);
  await page.close();
  return r;
}

const results = [];
const record = (row) => {
  console.log(JSON.stringify(row));
  fs.appendFileSync(outFile + 'l', JSON.stringify(row) + '\n');
  results.push(row);
};
// A discarded first launch, so a cold disk does not land on one mode.
{
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'chrome-'));
  const browser = await launch(profile, false);
  await once(browser, 'step1');
  await browser.close();
}
for (let run = 0; run < runs; run++) {
  for (const mode of modes) {
    const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'chrome-'));
    const browser = await launch(profile, false);
    record({ mode, angle, run, cache: 'off', ...await once(browser, mode) });
    await browser.close();
  }
}
// Program cache: cold, same browser again, then a relaunch on the profile.
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'chrome-'));
let browser = await launch(profile, true);
record({ mode: 'step2', angle, run: 0, cache: 'cold',
  ...await once(browser, 'step2') });
record({ mode: 'step2', angle, run: 0, cache: 'same browser',
  ...await once(browser, 'step2') });
await browser.close();
browser = await launch(profile, true);
record({ mode: 'step2', angle, run: 0, cache: 'relaunch',
  ...await once(browser, 'step2') });
await browser.close();
fs.writeFileSync(outFile, JSON.stringify(results, null, 2));
