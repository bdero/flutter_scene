# Builds the GLSL ES 300 sources of a realistic warm-up pipeline set.
#
#   python3 warmup/build.py <flutter_scene/packages/flutter_scene/shaders>
import json, os, subprocess, sys, tempfile
IMP = os.path.expanduser('~/projects/flutter/flutter/bin/cache/artifacts/engine/darwin-x64/impellerc')
SH = sys.argv[1]
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'shaders')
SHADERS = {
    'UnskinnedVertex': 'flutter_scene_unskinned.vert',
    'SkinnedVertex': 'flutter_scene_skinned.vert',
    'UnskinnedDepthVertex': 'flutter_scene_unskinned_depth.vert',
    'FullscreenVertex': 'flutter_scene_fullscreen.vert',
    'StandardFragment': 'flutter_scene_standard.frag',
    'StandardLeanFragment': 'flutter_scene_standard_lean.frag',
    'StandardLeanNoShadowFragment': 'flutter_scene_standard_lean_no_shadow.frag',
    'UnlitFragment': 'flutter_scene_unlit.frag',
    'DepthOnlyFragment': 'flutter_scene_depth_only.frag',
    'DepthOnlyMaskedFragment': 'flutter_scene_depth_only_masked.frag',
    'ResolveFragment': 'flutter_scene_resolve.frag',
}
# (vertex, fragment): a lit scene with a sun shadow, skinned characters, and
# a depth prepass, under both lit tiers.
PIPELINES = [
    ['UnskinnedVertex', 'StandardFragment'],
    ['UnskinnedVertex', 'StandardLeanFragment'],
    ['SkinnedVertex', 'StandardFragment'],
    ['SkinnedVertex', 'StandardLeanFragment'],
    ['UnskinnedVertex', 'StandardLeanNoShadowFragment'],
    ['UnskinnedVertex', 'UnlitFragment'],
    ['UnskinnedDepthVertex', 'DepthOnlyFragment'],
    ['UnskinnedDepthVertex', 'DepthOnlyMaskedFragment'],
    ['SkinnedVertex', 'DepthOnlyFragment'],
    ['FullscreenVertex', 'ResolveFragment'],
]
os.makedirs(OUT, exist_ok=True)
for name, src in SHADERS.items():
    subprocess.run([IMP, '--opengl-es', '--gles-language-version=300',
                    '--input=' + os.path.join(SH, src),
                    '--sl=' + os.path.join(OUT, name + '.glsl'),
                    '--spirv=' + os.path.join(tempfile.gettempdir(), name + '.spv'),
                    '--include=' + SH,
                    '--include=' + os.path.dirname(IMP) + '/shader_lib'],
                   check=True)
json.dump(PIPELINES, open(os.path.join(OUT, 'pipelines.json'), 'w'), indent=1)
print('built', len(SHADERS), 'shaders,', len(PIPELINES), 'pipelines')
