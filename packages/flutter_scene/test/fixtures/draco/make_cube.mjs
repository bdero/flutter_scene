// Builds a flat-shaded cube (24 vertices, per-face normals and UV islands),
// saved as cube.glb. Draco's encoder deduplicates the shared corner positions,
// which forces per-corner attribute seams in the compressed stream.
import { Document, NodeIO } from '@gltf-transform/core';

const doc = new Document();
const buffer = doc.createBuffer();

const faceDefs = [
  { n: [0, 0, 1], corners: [[-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]] },
  { n: [0, 0, -1], corners: [[1, -1, -1], [-1, -1, -1], [-1, 1, -1], [1, 1, -1]] },
  { n: [1, 0, 0], corners: [[1, -1, 1], [1, -1, -1], [1, 1, -1], [1, 1, 1]] },
  { n: [-1, 0, 0], corners: [[-1, -1, -1], [-1, -1, 1], [-1, 1, 1], [-1, 1, -1]] },
  { n: [0, 1, 0], corners: [[-1, 1, 1], [1, 1, 1], [1, 1, -1], [-1, 1, -1]] },
  { n: [0, -1, 0], corners: [[-1, -1, -1], [1, -1, -1], [1, -1, 1], [-1, -1, 1]] },
];

const pos = new Float32Array(24 * 3);
const nrm = new Float32Array(24 * 3);
const uv = new Float32Array(24 * 2);
const idx = new Uint16Array(36);

let v = 0;
let o = 0;
for (let f = 0; f < 6; f++) {
  const { n, corners } = faceDefs[f];
  const u0 = (f % 3) / 3;
  const v0 = f < 3 ? 0 : 0.5;
  for (let c = 0; c < 4; c++) {
    pos.set(corners[c], (v + c) * 3);
    nrm.set(n, (v + c) * 3);
    uv[(v + c) * 2] = u0 + (c === 1 || c === 2 ? 1 / 3 : 0);
    uv[(v + c) * 2 + 1] = v0 + (c >= 2 ? 0.5 : 0);
  }
  idx.set([v, v + 1, v + 2, v, v + 2, v + 3], o);
  v += 4;
  o += 6;
}

const position = doc.createAccessor().setType('VEC3').setArray(pos).setBuffer(buffer);
const normal = doc.createAccessor().setType('VEC3').setArray(nrm).setBuffer(buffer);
const texcoord = doc.createAccessor().setType('VEC2').setArray(uv).setBuffer(buffer);
const indices = doc.createAccessor().setType('SCALAR').setArray(idx).setBuffer(buffer);

const prim = doc.createPrimitive()
  .setAttribute('POSITION', position)
  .setAttribute('NORMAL', normal)
  .setAttribute('TEXCOORD_0', texcoord)
  .setIndices(indices);

const mesh = doc.createMesh('cube').addPrimitive(prim);
const node = doc.createNode('cube').setMesh(mesh);
doc.createScene('scene').addChild(node);

await new NodeIO().write('cube.glb', doc);
console.log('wrote cube.glb');
