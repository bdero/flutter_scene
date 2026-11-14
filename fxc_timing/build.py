# Builds every lit variant to GLSL ES 300, Metal, and Vulkan SPIR-V.
import os, subprocess, shutil, json, sys
IMP=os.path.expanduser('~/projects/flutter/flutter/bin/cache/artifacts/engine/darwin-x64/impellerc')
SH=sys.argv[1] if len(sys.argv)>1 else '/Users/bdero/projects/flutter_scene_root/worktrees/bdero-lit-feature-defines/packages/flutter_scene/shaders'
ENTRY=sys.argv[2] if len(sys.argv)>2 else 'flutter_scene_standard.frag'
OUT=os.path.abspath(sys.argv[3] if len(sys.argv)>3 else 'out')
FEATS=['IRRADIANCE_FIELD','RECT_AREA_LIGHTS','ENVIRONMENT_BLEND','PARALLAX_REFLECTION','SCREEN_SPACE_OCCLUSION','POINT_SHADOWS']
V={'full':[], 'lean':['FLUTTER_SCENE_LEAN_LIGHTING'], 'allsix':['FLUTTER_SCENE_NO_'+f for f in FEATS]}
for f in FEATS:
  V['full_minus_'+f]=['FLUTTER_SCENE_NO_'+f]
  V['lean_plus_'+f]=['FLUTTER_SCENE_NO_'+g for g in FEATS if g!=f]
shutil.rmtree(OUT, ignore_errors=True)
def run(*a): subprocess.run([IMP,*a,'--include='+SH,'--include='+os.path.dirname(IMP)+'/shader_lib'], check=True, capture_output=True)
for name,defs in V.items():
  d=os.path.join(OUT,name); os.makedirs(d)
  D=['--define='+x for x in defs]
  run('--opengl-es','--gles-language-version=300','--input='+os.path.join(SH,ENTRY),'--sl='+d+'/frag.glsl','--spirv='+d+'/frag.gles.spv',*D)
  run('--metal-desktop','--input='+os.path.join(SH,ENTRY),'--sl='+d+'/frag.metal','--spirv='+d+'/frag.mtl.spv',*D)
  run('--vulkan','--input='+os.path.join(SH,ENTRY),'--sl='+d+'/frag.vk.spv','--spirv='+d+'/frag.vk.spirv',*D)
  run('--opengl-es','--gles-language-version=300','--input='+os.path.join(SH,'flutter_scene_unskinned.vert'),'--sl='+d+'/vert.glsl','--spirv='+d+'/vert.spv')
json.dump(V, open(os.path.join(OUT,'variants.json'),'w'), indent=1)
print('built', len(V))
