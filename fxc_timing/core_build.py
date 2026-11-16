# Builds lean-based variants that drop one core lit feature each, to GLSL ES 300 and Metal.
import os, subprocess, shutil, json, sys
IMP=os.path.expanduser('~/projects/flutter/flutter/bin/cache/artifacts/engine/darwin-x64/impellerc')
SH=sys.argv[1]; OUT=os.path.abspath(sys.argv[2])
L=['FLUTTER_SCENE_LEAN_LIGHTING']
V={
 'lean': L,
 'lean_no_pcss': L+['T_NO_PCSS'],
 'lean_no_pcf_kernel': L+['T_NO_PCF_KERNEL'],
 'lean_no_bilinear': L+['T_NO_BILINEAR'],
 'lean_poisson_only': L+['T_NO_PCSS','T_NO_BILINEAR'],
 'lean_bilinear_only': L+['T_NO_PCSS','T_NO_PCF_KERNEL'],
 'lean_no_spot_shadows': L+['T_NO_SPOT_SHADOWS'],
 'lean_no_punctual': L+['T_NO_PUNCTUAL'],
 'lean_no_fog': L+['T_NO_FOG'],
 'lean_no_shadows': L+['FLUTTER_SCENE_SKIP_SHADOWS'],
 'lean_no_sun': L+['FLUTTER_SCENE_NO_DIRECTIONAL_LIGHT'],
 'lean_floor': L+['T_NO_PCSS','T_NO_BILINEAR','T_NO_SPOT_SHADOWS','T_NO_FOG','T_NO_PUNCTUAL'],
}
shutil.rmtree(OUT, ignore_errors=True)
inc=['--include='+SH,'--include='+os.path.dirname(IMP)+'/shader_lib']
def run(*a):
  r=subprocess.run([IMP,*a,*inc], capture_output=True, text=True)
  if r.returncode: print(r.stdout, r.stderr); raise SystemExit(1)
for name,defs in V.items():
  d=os.path.join(OUT,name); os.makedirs(d)
  D=['--define='+x for x in defs]
  run('--opengl-es','--gles-language-version=300','--input='+SH+'/flutter_scene_standard.frag','--sl='+d+'/frag.glsl','--spirv='+d+'/f.spv',*D)
  run('--metal-desktop','--input='+SH+'/flutter_scene_standard.frag','--sl='+d+'/frag.metal','--spirv='+d+'/m.spv',*D)
  run('--opengl-es','--gles-language-version=300','--input='+SH+'/flutter_scene_unskinned.vert','--sl='+d+'/vert.glsl','--spirv='+d+'/v.spv')
  print(f"{name:24s} glsl {os.path.getsize(d+'/frag.glsl'):7d}")
json.dump(V, open(os.path.join(OUT,'variants.json'),'w'), indent=1)
