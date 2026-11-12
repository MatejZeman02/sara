// The fixture's noise ground beyond the document rectangle: the grain
// noise_ground.gmacs writes inside it, on the rect SaGeneratedLayer.apply_view
// sizes to reach the viewport edges. The colours arrive in display space with
// the layer's opacity in their alpha, and `octaves` and `seed` are the
// module's own parameters, which apply_view sets under their own names.
//
// The lattice hash and the value noise are libs/lattice_hash.gmacs and
// libs/noise.gmacs copied by hand, because a canvas_item shader cannot import
// a compute library, as paper.gdshader says.
// Unlike the paper it fades nothing it cannot resolve, since a fixture's
// proof is the grain inside the document and this only has to agree there.
shader_type canvas_item;

uniform vec4 color_a : source_color = vec4(0.12, 0.2, 0.42, 1.0);
uniform vec4 color_b : source_color = vec4(0.95, 0.62, 0.25, 1.0);
uniform float scale = 40.0;
uniform float octaves = 5.0;
uniform float seed = 0.0;
uniform vec2 rect_origin = vec2(0.0);
uniform vec2 rect_size = vec2(1.0);

// The integer lattice hash of libs/lattice_hash.gmacs, copied by hand:
// Christopher Wellons' `lowbias32`, public domain under the Unlicense, and the
// axes folded through it z first, which is Sara's own. The value noise below
// hashes its corners with it, z nought, for the reason libs/noise.gmacs gives.
uint sa_lowbias32(uint x) {
    x = x ^ (x >> 16u);
    x *= 0x7feb352du;
    x = x ^ (x >> 15u);
    x *= 0x846ca68bu;
    x = x ^ (x >> 16u);
    return x;
}

float sa_lattice_hash(ivec3 corner) {
    uvec3 c = uvec3(corner);
    uint h = sa_lowbias32(c.z);
    h = sa_lowbias32(h + c.y);
    h = sa_lowbias32(h + c.x);
    // A power of two, so the product is the library's `ldexp` exactly. Godot's
    // shader language reads ldexp's exponent as an out argument and refuses a
    // literal there.
    return float(h >> 8u) * (1.0 / 16777216.0);
}

float sa_value_noise(vec2 p) {
    vec2 floored = floor(p);
    ivec3 cell = ivec3(ivec2(floored), 0);
    vec2 f = p - floored;
    vec2 smoothed = f * f * (3.0 - 2.0 * f);
    float a = sa_lattice_hash(cell);
    float b = sa_lattice_hash(cell + ivec3(1, 0, 0));
    float c = sa_lattice_hash(cell + ivec3(0, 1, 0));
    float d = sa_lattice_hash(cell + ivec3(1, 1, 0));
    return mix(mix(a, b, smoothed.x), mix(c, d, smoothed.x), smoothed.y);
}

// noise_ground.gmacs's grain, octave for octave.
float grain(vec2 at) {
    float total = 0.0;
    float amplitude = 0.5;
    float reached = 0.0;
    vec2 p = at + vec2(seed * 17.0, seed * 31.0);
    int count = clamp(int(octaves), 1, 8);
    for (int i = 0; i < count; i++) {
        total += amplitude * sa_value_noise(p);
        reached += amplitude;
        amplitude *= 0.5;
        p *= 2.0;
    }
    return total / reached;
}

void fragment() {
    vec2 texel = floor(rect_origin + UV * rect_size);
    COLOR = mix(color_a, color_b, grain(texel / max(scale, 1.0)));
}
