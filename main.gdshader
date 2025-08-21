shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float effect_amount : hint_range(0.0, 1.0) = 0.25;

uniform float scanline_strength : hint_range(0.0, 1.0) = 0.15;
uniform float subpixel_strength : hint_range(0.0, 1.0) = 0.12;
uniform float glow_intensity    : hint_range(0.0, 1.0) = 0.08;

uniform vec2  tex_offset = vec2(0.0);
uniform vec2  tex_scale  = vec2(1.0);
uniform float tex_rotation_degrees = 0.0;

uniform float pixel_quantize = 0.0;

vec2 rotate_uv(vec2 uv, float angle, vec2 pivot){
    float c = cos(angle), s = sin(angle);
    mat2 rot = mat2(vec2(c, s), vec2(-s, c));
    uv -= pivot; uv = rot * uv; uv += pivot;
    return uv;
}

void fragment() {
    vec2 uv = UV;
    vec2 pivot = vec2(0.5);
    float rad = radians(tex_rotation_degrees);
    uv = (uv - pivot) / max(tex_scale, vec2(1e-6)) + pivot;
    uv = rotate_uv(uv, rad, pivot);
    uv += tex_offset;

    vec2 suv = uv;
    if (pixel_quantize > 0.0) {
        vec2 grid = vec2(pixel_quantize);
        suv = floor(uv * grid) / grid;
    }

    vec3 col = texture(SCREEN_TEXTURE, suv).rgb;

    float px = SCREEN_PIXEL_SIZE.y;
    float line_freq = 1.0 / max(px, 1e-5);

    float scan = 0.5 + 0.5 * sin(uv.y * line_freq * 3.14159);
    float scan_mix = mix(1.0, scan, scanline_strength);

    float sub_idx = mod(uv.x * line_freq / 3.0, 1.0);
    vec3 mask = vec3(
        float(sub_idx < 1.0/3.0),
        float(sub_idx >= 1.0/3.0 && sub_idx < 2.0/3.0),
        float(sub_idx >= 2.0/3.0)
    );
    mask = mix(vec3(1.0), mask, subpixel_strength);

    float d = distance(uv, vec2(0.5));
    float vign = 1.0 - smoothstep(0.6, 0.95, d);
    float glow = vign * glow_intensity;

    vec3 stylized = col;
    stylized *= scan_mix;
    stylized *= mask;
    stylized += glow * 0.05;

    vec3 out_col = mix(col, stylized, effect_amount);

    COLOR = vec4(out_col, 1.0);
}
