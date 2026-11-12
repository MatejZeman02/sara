// The tooth of a ground beyond the document rectangle, lit as the view lights
// it inside. Inside, the relief sums the ground's `raise_tooth` height under
// the paint, takes its slope by central differences in millimetres
// (relief_normal.gmacs) and the tonemap shader lights the colour by it. Beyond
// the rectangle there is no relief texture, so a ground's view shader works
// out the same height at the texel and its four neighbours itself and hands
// the slope to sa_ground_lit. The uniforms are what
// SaGeneratedLayer.apply_view sets.
#include "res://shaders/canvas/relief_light.gdshaderinc"

// Whether the relief is shown and the ground has a tooth to show.
uniform bool relief_enabled = false;
uniform vec3 relief_light = vec3(-0.5, -0.5, 0.70710678);
uniform float relief_strength = 2.0;
// How high the grain stands, in virtual millimetres, and how much of it the
// relief counts, the ground's opacity, as `raise_tooth` is handed it.
uniform float tooth = 0.0;
uniform float tooth_weight = 1.0;
// How many millimetres one document pixel spans, the document's resolution.
uniform float pixel_mm = 0.2645833;

// The mirrored sRGB pair of tonemap.gdshader, which a canvas_item shader that
// does not include it cannot reach. The colours here are display sRGB.
vec3 ground_to_linear(vec3 c) {
    vec3 m = abs(c);
    vec3 lo = m / 12.92;
    vec3 hi = pow((m + 0.055) / 1.055, vec3(2.4));
    return sign(c) * mix(lo, hi, step(vec3(0.04045), m));
}

vec3 ground_to_srgb(vec3 c) {
    vec3 m = abs(c);
    vec3 lo = 12.92 * m;
    vec3 hi = 1.055 * pow(m, vec3(1.0 / 2.4)) - 0.055;
    return sign(c) * mix(lo, hi, step(vec3(0.0031308), m));
}

// Whether the tooth is worth working out at all.
bool ground_lit_wanted() {
    return relief_enabled && relief_strength > 0.0 && tooth * tooth_weight > 0.0;
}

// The surface's normal from the grain's height on either side, *left* and
// *right*, *up* and *down*, as the grain reads before the tooth scales it.
vec3 ground_normal(float left, float right, float up, float down) {
    float rise = tooth * tooth_weight / (2.0 * pixel_mm);
    return normalize(vec3(-(right - left) * rise, -(down - up) * rise, 1.0));
}

// *colour* lit by *normal*, the alpha left as it is.
vec4 sa_ground_lit(vec4 colour, vec3 normal) {
    if (normal.x == 0.0 && normal.y == 0.0) {
        return colour;
    }
    vec3 lin = sa_relief_shade(ground_to_linear(colour.rgb), normal, relief_light, relief_strength);
    return vec4(ground_to_srgb(lin), colour.a);
}
