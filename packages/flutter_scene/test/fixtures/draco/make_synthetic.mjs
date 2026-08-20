// Builds a small synthetic static mesh (bumpy grid) with POSITION, NORMAL,
// TEXCOORD_0, and COLOR_0, saved as synthetic.glb. Enough triangles for
// EdgeBreaker traversal and parallelogram prediction to be exercised.
import { Document, NodeIO } from '@gltf-transform/core';

// Grid resolution and output name are overridable; N=23 (1058 triangles)
// crosses Draco's 1000-face threshold for valence coded traversal.
const N = Number(process.argv[2] ?? 9); // (N+1)^2 vertices, 2*N*N triangles
const outName = process.argv[3] ?? 'synthetic.glb';
const doc = new Document();
const buffer = doc.createBuffer();

const verts = (N + 1) * (N + 1);
const pos = new Float32Array(verts * 3);
const nrm = new Float32Array(verts * 3);
const uv = new Float32Array(verts * 2);
const col = new Float32Array(verts * 4);

for (let j = 0; j <= N; j++) {
  for (let i = 0; i <= N; i++) {
    const k = j * (N + 1) + i;
    const x = i / N - 0.5;
    const z = j / N - 0.5;
    const y = 0.15 * Math.sin(6.28318 * x) * Math.cos(6.28318 * z);
    pos[k * 3] = x;
    pos[k * 3 + 1] = y;
    pos[k * 3 + 2] = z;
    // Analytic-ish normal of the height field.
    const dx = 0.15 * 6.28318 * Math.cos(6.28318 * x) * Math.cos(6.28318 * z);
    const dz = -0.15 * 6.28318 * Math.sin(6.28318 * x) * Math.sin(6.28318 * z);
    const len = Math.hypot(-dx, 1, -dz);
    nrm[k * 3] = -dx / len;
    nrm[k * 3 + 1] = 1 / len;
    nrm[k * 3 + 2] = -dz / len;
    uv[k * 2] = i / N;
    uv[k * 2 + 1] = j / N;
    col[k * 4] = i / N;
    col[k * 4 + 1] = j / N;
    col[k * 4 + 2] = 1 - i / N;
    col[k * 4 + 3] = 1;
  }
}

const idx = new Uint16Array(N * N * 6);
let o = 0;
for (let j = 0; j < N; j++) {
  for (let i = 0; i < N; i++) {
    const a = j * (N + 1) + i;
    const b = a + 1;
    const c = a + (N + 1);
    const d = c + 1;
    idx[o++] = a; idx[o++] = c; idx[o++] = b;
    idx[o++] = b; idx[o++] = c; idx[o++] = d;
  }
}

const position = doc.createAccessor().setType('VEC3').setArray(pos).setBuffer(buffer);
const normal = doc.createAccessor().setType('VEC3').setArray(nrm).setBuffer(buffer);
const texcoord = doc.createAccessor().setType('VEC2').setArray(uv).setBuffer(buffer);
const color = doc.createAccessor().setType('VEC4').setArray(col).setBuffer(buffer);
const indices = doc.createAccessor().setType('SCALAR').setArray(idx).setBuffer(buffer);

const prim = doc.createPrimitive()
  .setAttribute('POSITION', position)
  .setAttribute('NORMAL', normal)
  .setAttribute('TEXCOORD_0', texcoord)
  .setAttribute('COLOR_0', color)
  .setIndices(indices);

const mesh = doc.createMesh('bumpy').addPrimitive(prim);
const node = doc.createNode('bumpy').setMesh(mesh);
doc.createScene('scene').addChild(node);

await new NodeIO().write(outName, doc);
console.log('wrote', outName, verts, 'verts', idx.length / 3, 'tris');
