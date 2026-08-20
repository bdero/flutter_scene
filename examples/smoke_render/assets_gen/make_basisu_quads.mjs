// Builds basisu_quads.glb, two subdivided quads side by side, each sampling a
// KHR_texture_basisu KTX2 texture. One quad is a mipped, zstd
// supercompressed UASTC sRGB file with no alpha; the other is ETC1S sRGB
// whose alpha blob is drawn with alphaMode BLEND, so the backdrop shows
// through it. Both materials are unlit, so the frame reads the decoded texels
// rather than a lighting response.
//
// The KTX2 payloads are the committed decoder fixtures from
// packages/flutter_scene/test/fixtures/ktx2/. generate.sh compresses the mesh
// with Draco afterwards.
import { readFileSync } from 'node:fs';
import { Document, NodeIO } from '@gltf-transform/core';
import {
  KHRMaterialsUnlit,
  KHRTextureBasisu,
} from '@gltf-transform/extensions';

const fixtures = '../../../packages/flutter_scene/test/fixtures/ktx2';
const cells = 6; // subdivision per side, enough for Draco to predict across
const half = 0.6;
const centerX = 0.68;

// One quad in the XY plane facing +Z, centered at [cx, 0, 0]. UVs run left to
// right and top to bottom, the glTF convention.
function quad(cx) {
  const verts = (cells + 1) * (cells + 1);
  const pos = new Float32Array(verts * 3);
  const nrm = new Float32Array(verts * 3);
  const uv = new Float32Array(verts * 2);
  let v = 0;
  for (let r = 0; r <= cells; r++) {
    for (let c = 0; c <= cells; c++) {
      const u = c / cells;
      const w = r / cells;
      pos[v * 3] = cx + (u - 0.5) * 2 * half;
      pos[v * 3 + 1] = (0.5 - w) * 2 * half;
      pos[v * 3 + 2] = 0;
      nrm[v * 3 + 2] = 1;
      uv[v * 2] = u;
      uv[v * 2 + 1] = w;
      v++;
    }
  }
  const idx = new Uint16Array(cells * cells * 6);
  let o = 0;
  for (let r = 0; r < cells; r++) {
    for (let c = 0; c < cells; c++) {
      const i0 = r * (cells + 1) + c;
      const i2 = i0 + cells + 1;
      idx.set([i0, i2, i0 + 1, i0 + 1, i2, i2 + 1], o);
      o += 6;
    }
  }
  return { pos, nrm, uv, idx };
}

const doc = new Document();
const buffer = doc.createBuffer();
doc.createExtension(KHRTextureBasisu).setRequired(true);
const unlit = doc.createExtension(KHRMaterialsUnlit);

function addQuad(name, cx, ktx2File, blend) {
  const { pos, nrm, uv, idx } = quad(cx);
  const texture = doc
    .createTexture(name)
    .setMimeType('image/ktx2')
    .setImage(new Uint8Array(readFileSync(`${fixtures}/${ktx2File}`)));
  const material = doc
    .createMaterial(name)
    .setBaseColorFactor([1, 1, 1, 1])
    .setBaseColorTexture(texture)
    .setAlphaMode(blend ? 'BLEND' : 'OPAQUE')
    .setDoubleSided(true);
  material.setExtension('KHR_materials_unlit', unlit.createUnlit());
  const prim = doc
    .createPrimitive()
    .setAttribute(
      'POSITION',
      doc.createAccessor().setType('VEC3').setArray(pos).setBuffer(buffer),
    )
    .setAttribute(
      'NORMAL',
      doc.createAccessor().setType('VEC3').setArray(nrm).setBuffer(buffer),
    )
    .setAttribute(
      'TEXCOORD_0',
      doc.createAccessor().setType('VEC2').setArray(uv).setBuffer(buffer),
    )
    .setIndices(
      doc.createAccessor().setType('SCALAR').setArray(idx).setBuffer(buffer),
    )
    .setMaterial(material);
  return doc.createNode(name).setMesh(doc.createMesh(name).addPrimitive(prim));
}

const scene = doc.createScene('scene');
scene.addChild(
  addQuad('uastc', -centerX, 'uastc_srgb_mips_zstd_64.ktx2', false),
);
scene.addChild(addQuad('etc1s', centerX, 'etc1s_alpha_srgb_32.ktx2', true));

const io = new NodeIO().registerExtensions([
  KHRMaterialsUnlit,
  KHRTextureBasisu,
]);
await io.write('basisu_quads.glb', doc);
console.log('wrote basisu_quads.glb');
