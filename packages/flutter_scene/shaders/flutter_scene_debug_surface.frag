// The surface debug view for a material that does not participate in debug
// views (a raw ShaderMaterial that never opted in). Pairs with the draw's own
// vertex shader, like the depth prepass, so skinning, morphing, instancing,
// and a material's vertex block all still run; only the fragment stage is
// replaced. Serves the geometry and identity channels from the varyings and
// draws the not-participating stripes for everything that needs the surface
// description.

#define FLUTTER_SCENE_DEBUG_FALLBACK

#include <material_varyings.glsl>
#include <material_inputs.glsl>
#include <material_debug.glsl>

void main() {
  MaterialInputs material = InitMaterialInputs();
  frag_color = DebugSurfaceOutput(material);
}
