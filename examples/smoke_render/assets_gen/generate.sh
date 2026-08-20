#!/bin/sh
# Regenerates ../assets/basisu_quads_draco.glb, the fixture the
# basisu_textures smoke scene loads.
#
# make_basisu_quads.mjs builds the uncompressed source (two quads sampling the
# committed KTX2 decoder fixtures through KHR_texture_basisu); the gltf-transform
# CLI then Draco-compresses the geometry, so one scene covers compressed import
# and Basis Universal transcode all the way to pixels. Needs
# @gltf-transform/core and @gltf-transform/extensions.
set -e
node make_basisu_quads.mjs
npx @gltf-transform/cli draco basisu_quads.glb ../assets/basisu_quads_draco.glb
rm -f basisu_quads.glb
