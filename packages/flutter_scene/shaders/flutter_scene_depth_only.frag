// Fragment shader for the directional-light shadow pass.
//
// Pairs with the engine's standard vertex shaders (UnskinnedVertex /
// SkinnedVertex), driven with the light-space view-projection matrix in
// place of the camera transform. Writes the window-space depth into the
// color attachment's red channel so it can be sampled as the shadow map
// (the pass also has a transient depth attachment for the depth test).
// Any vertex outputs the standard vertex shaders produce that aren't
// consumed here are simply unused.
out vec4 frag_color;

void main() { frag_color = vec4(gl_FragCoord.z, 0.0, 0.0, 1.0); }
