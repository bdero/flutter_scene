#!/bin/sh
# Regenerates the Draco test fixtures in this directory.
#
# synthetic.glb is a small static mesh built by make_synthetic.mjs and cube.glb
# a flat shaded cube built by make_cube.mjs (both need @gltf-transform/core).
# The *_draco_* files are compressed with the gltf-transform CLI and the
# *_decoded.glb references are produced by a copy pass, which decodes Draco
# payloads on read. two_triangles.glb is the skinned corpus asset from
# examples/assets_src/.
#
# Coverage notes. Speed 0 selects the stronger prediction schemes (constrained
# multi parallelogram, portable tex coords, geometric normals) plus prediction
# degree traversal. Valence coded traversal additionally needs 1000+ faces
# (the 23-resolution grid). The cube's deduplicated corners force per-corner
# attribute seams.
set -e
node make_synthetic.mjs
node make_synthetic.mjs 23 synthetic_big.glb
node make_cube.mjs
cp ../../../../../examples/assets_src/two_triangles.glb .
npx @gltf-transform/cli draco synthetic.glb synthetic_draco_eb.glb
npx @gltf-transform/cli draco synthetic.glb synthetic_draco_seq.glb --method sequential
npx @gltf-transform/cli draco synthetic.glb synthetic_draco_eb_cl10.glb --encode-speed 0 --decode-speed 0
npx @gltf-transform/cli draco synthetic_big.glb synthetic_draco_eb_valence.glb --encode-speed 0 --decode-speed 0
npx @gltf-transform/cli draco cube.glb cube_draco_eb.glb
npx @gltf-transform/cli draco cube.glb cube_draco_eb_cl10.glb --encode-speed 0 --decode-speed 0
npx @gltf-transform/cli draco two_triangles.glb two_triangles_draco_eb.glb
for f in synthetic_draco_eb synthetic_draco_seq synthetic_draco_eb_cl10 \
    synthetic_draco_eb_valence cube_draco_eb cube_draco_eb_cl10 \
    two_triangles_draco_eb; do
  npx @gltf-transform/cli copy $f.glb ${f}_decoded.glb
done
rm -f synthetic.glb synthetic_big.glb cube.glb two_triangles.glb
