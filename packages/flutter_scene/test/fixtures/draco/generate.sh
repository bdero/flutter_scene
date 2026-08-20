#!/bin/sh
# Regenerates the Draco test fixtures in this directory.
#
# synthetic.glb is a small static mesh built by make_synthetic.mjs (needs
# @gltf-transform/core). The *_draco_* files are compressed with the
# gltf-transform CLI and the *_decoded.glb references are produced by a
# copy pass, which decodes Draco payloads on read. two_triangles.glb is the
# skinned corpus asset from examples/assets_src/.
set -e
node make_synthetic.mjs
cp ../../../../../examples/assets_src/two_triangles.glb .
npx @gltf-transform/cli draco synthetic.glb synthetic_draco_eb.glb
npx @gltf-transform/cli draco synthetic.glb synthetic_draco_seq.glb --method sequential
npx @gltf-transform/cli draco two_triangles.glb two_triangles_draco_eb.glb
for f in synthetic_draco_eb synthetic_draco_seq two_triangles_draco_eb; do
  npx @gltf-transform/cli copy $f.glb ${f}_decoded.glb
done
rm -f synthetic.glb two_triangles.glb
