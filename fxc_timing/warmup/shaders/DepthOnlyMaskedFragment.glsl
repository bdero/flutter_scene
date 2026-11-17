#version 300 es
precision mediump float;
precision highp int;

layout(std140) uniform MaskInfo
{
    highp vec4 params;
    highp vec4 uv_transform;
    highp vec4 uv_rotation;
} mask_info;

uniform highp sampler2D mask_texture;

in highp vec2 v_texture_coords;
in highp vec2 v_texture_coords_1;
in highp vec4 v_color;
layout(location = 0) out highp vec4 frag_color;

void main()
{
    highp vec2 _284 = vec2(0.0);
    if (int(mask_info.uv_rotation.z + 0.5) == 1)
    {
        _284 = v_texture_coords_1;
    }
    else
    {
        _284 = v_texture_coords;
    }
    highp vec2 _247 = _284 * mask_info.uv_transform.zw;
    highp float _253 = _247.x;
    highp float _258 = _247.y;
    if (((texture(mask_texture, mask_info.uv_transform.xy + vec2((mask_info.uv_rotation.x * _253) + (mask_info.uv_rotation.y * _258), ((-mask_info.uv_rotation.y) * _253) + (mask_info.uv_rotation.x * _258))).w * mix(1.0, v_color.w, mask_info.params.z)) * mask_info.params.y) < mask_info.params.x)
    {
        discard;
    }
    frag_color = vec4(gl_FragCoord.z, 0.0, 0.0, 1.0);
}

