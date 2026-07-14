#version 460 core

// Plain full-screen copy: replays the opaque scene-color snapshot into the
// second half of a split scene pass (the non-MSAA path; MSAA carries its
// multisample attachment across the split instead).

precision highp float;

uniform sampler2D source_texture;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  frag_color = texture(source_texture, v_uv);
}
