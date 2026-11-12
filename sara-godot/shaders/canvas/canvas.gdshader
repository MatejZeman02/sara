// The document's woven canvas beyond the document rectangle:
// the same weave canvas.gmacs writes inside it, on a rect so large in document
// pixels that it reaches the viewport edges at any zoom. The uniforms are what
// SaGeneratedLayer.apply_view sets, the colours already in display space with
// the layer's opacity in their alpha.
//
// The noise below is libs/noise.gmacs copied by hand, as paper.gdshader copies
// it, and `crown` and `weave` are canvas.gmacs's own, because a canvas_item
// shader cannot import a compute dialect file and the two sides of the
// document edge have to agree. If one changes the other changes with it.
//
// **What the two sides have to agree on is what the eye sees.** Inside the
// rectangle the eye sees the kernel's texels through the view's tonemap
// shader, which draws a texel as a square at 100 percent and above and below it
// averages the texels a pixel covers, about as a box of `texels_per_pixel - 1`
// texels would. So this shader reads the texel the pixel centre falls in, the
// way the kernel reads its own, and below 100 percent it averages the weave
// over that footprint with a few taps.
//
// A weave is a pattern with threads and not a noise, so paper.gdshader's way
// of fading each octave by what an average leaves of it does not apply. A few
// taps average the weave over the footprint, which keeps the threads running
// across the edge, and the average is faded toward the mean shade of the weave
// as the footprint grows, because nine taps read a speckle the view's
// thirty-six do not. Each alone matched the view worse.
//
// **Threads two texels wide hold a tone no footprint settles**, because the
// kernel reads the weave at texel centres, two to a thread at the slider's
// floor, so the document's own texels carry blotches a few dozen texels wide
// and even an ideal box over a pixel keeps some of the weave's contrast. The
// fade is therefore wider at a spacing of 2 and gone by 2.5, and the taps sit on
// a lattice that puts each one in its own row and its own column, since
// staggered rows lined up with two-texel threads at some footprints. No lattice
// of eight to twelve taps is free of such a footprint, this one's being where
// three taps fall a twill's repeat apart along a diagonal.
//
// **The threads are lit as the canvas's tooth is inside.** `raise_tooth`
// stands the weave's height up, so the slope comes from that height at the
// texel's four neighbours, averaged over the same taps as the shade, and
// ground_relief.gdshaderinc lights it with the document's relief light.
//
// **The cloth ends at an edge**, ground_edge.gdshaderinc's, when the ground's
// `edge` asks for one, and a wrapped canvas reads its weave on the arc the
// cloth turns over, so the threads foreshorten into the turn.
shader_type canvas_item;

#include "res://shaders/canvas/ground_relief.gdshaderinc"

uniform vec4 color_a : source_color = vec4(0.92, 0.89, 0.83, 1.0);
uniform vec4 color_b : source_color = vec4(0.66, 0.61, 0.53, 1.0);
// The thread spacing in document pixels.
uniform float scale = 8.0;
uniform float thickness = 0.36;
uniform float irregularity = 0.35;
// The weave's turn in degrees.
uniform float angle = 0.0;
// The slubs, the fuzz, the crimp and the priming, as canvas.gmacs reads them.
uniform float slub = 0.0;
uniform float fuzz = 0.0;
uniform float crimp = 0.0;
uniform float priming = 0.0;
// The rect's place in document pixels, so the weave reads where it is.
uniform vec2 rect_origin = vec2(0.0);
uniform vec2 rect_size = vec2(1.0);
// How many document pixels one screen pixel covers, the reciprocal of the
// canvas's zoom taken with the window's interface scale. One or less is a view
// at 100 percent or past it, where a texel is a square and nothing is averaged.
uniform float texels_per_pixel = 1.0;

// Taps to a side of the footprint at most, so nine reads of the weave a pixel.
const int MAX_TAPS = 3;
// The step of the lattice the taps sit on, for four taps and for nine. Tap `i`
// of `n` is in column `i` and row `i * step` modulo `n`, so no two share a row
// or a column and none lines up with a thread square to the document.
const int LATTICE_STEP_FOUR = 3;
const int LATTICE_STEP_NINE = 2;
// What the fade keeps far out: nine taps against the view's six by six, whose
// own average leaves a speckle the root of nine over thirty-six of the taps'.
const float FADE_FLOOR = 0.5;
// The footprint in texels up to which the taps read what the view does and the
// fade keeps all of it.
const float FADE_FROM = 3.4;
// How wide the fade is past FADE_FROM, in thread spacings, and how much wider
// it is at a spacing of 2, falling off by 1 over e for every FADE_TWO_FALL the
// spacing rises above 2. The four, with FADE_STEEP, are fitted on the port to
// the view's own filter over spacings from 2 to 24 and footprints from 1.25 to
// 33 texels, which the outside meets to a mean of 11 percent, and to 11 at a
// spacing of 2 and footprints up to 12 texels.
const float FADE_PER_SPACING = 0.6;
const float FADE_AT_TWO = 3.5;
const float FADE_TWO_FALL = 0.15;
const float FADE_STEEP = 3.5;

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

#include "res://shaders/canvas/ground_edge.gdshaderinc"

// The sine-free hash of libs/noise.gmacs, for the reason written there: GLSL
// does not pin sin's precision, so the usual one-liner grains differently on
// two drivers and a capture cannot check it.
// The weave's thread twist reads it, at points that are no lattice corner.
float sa_hash21(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
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

float sa_value_fbm(vec2 p) {
    float total = 0.0;
    float amplitude = 0.5;
    float weight = 0.0;
    vec2 at = p;
    for (int i = 0; i < 3; i++) {
        total += amplitude * sa_value_noise(at);
        weight += amplitude;
        amplitude *= 0.5;
        at *= 2.0;
    }
    return total / weight;
}

float crown(float across) {
    return sqrt(max(1.0 - across * across, 0.0));
}

// The weave's shade and, as canvas.gmacs's `weave` answers, its height.
vec2 weave(vec2 doc) {
    float turn = radians(angle);
    float c = cos(turn);
    float s = sin(turn);
    vec2 p = vec2(c * doc.x + s * doc.y, c * doc.y - s * doc.x) / max(scale, 2.0);
    vec2 slow = p / 12.0;
    vec2 bend = vec2(sa_value_fbm(slow + vec2(17.0, 3.0)), sa_value_fbm(slow + vec2(-41.0, 29.0))) - 0.5;
    p += bend * irregularity * 4.0;
    p += irregularity * 0.5 * (vec2(sa_value_noise(vec2(p.x + 5.3, p.y / 5.0)), sa_value_noise(vec2(p.x / 5.0, p.y + 71.9))) - 0.5);
    vec2 thread = floor(p);
    vec2 within = fract(p) - 0.5;
    float warp_width = thickness * (1.0 + irregularity * 0.7 * (sa_value_noise(vec2(thread.x * 7.31, p.y / 3.0)) - 0.5));
    float weft_width = thickness * (1.0 + irregularity * 0.7 * (sa_value_noise(vec2(p.x / 3.0, thread.y * 7.31 + 101.0)) - 0.5));
    float warp_slub = 0.0;
    float weft_slub = 0.0;
    if (slub > 0.0) {
        warp_slub = slub * smoothstep(0.72, 0.95, sa_value_noise(vec2(thread.x * 5.17 + 33.0, p.y / 2.2)));
        weft_slub = slub * smoothstep(0.72, 0.95, sa_value_noise(vec2(p.x / 2.2, thread.y * 5.17 + 77.0)));
        warp_width *= 1.0 + warp_slub;
        weft_width *= 1.0 + weft_slub;
    }
    float warp_on_top = 1.0 - mod(thread.x + thread.y, 2.0);
    float warp_lift = 0.5 + 0.5 * (1.0 - 4.0 * within.y * within.y) * (2.0 * warp_on_top - 1.0);
    float weft_lift = 0.5 + 0.5 * (1.0 - 4.0 * within.x * within.x) * (1.0 - 2.0 * warp_on_top);
    if (crimp > 0.0) {
        warp_width *= 1.0 - 0.4 * crimp * (1.0 - warp_lift);
        weft_width *= 1.0 - 0.4 * crimp * (1.0 - weft_lift);
    }
    float warp_crown = crown(within.x / max(0.5 * warp_width, 0.01));
    float weft_crown = crown(within.y / max(0.5 * weft_width, 0.01));
    float warp_height = warp_crown * (0.35 + 0.65 * warp_lift) * warp_width / (thickness * (1.0 + 0.35 * irregularity));
    float weft_height = weft_crown * (0.35 + 0.65 * weft_lift) * weft_width / (thickness * (1.0 + 0.35 * irregularity));
    float warp_twist = abs(fract(p.y * 2.5 + within.x * 1.5 + sa_hash21(vec2(thread.x, 3.7))) - 0.5) * 2.0;
    float weft_twist = abs(fract(p.x * 2.5 + within.y * 1.5 + sa_hash21(vec2(11.3, thread.y))) - 0.5) * 2.0;
    float warp_tone = sa_value_noise(vec2(thread.x * 3.1 + 11.0, p.y / 6.0));
    float weft_tone = sa_value_noise(vec2(p.x / 6.0, thread.y * 3.1 + 57.0));
    float warp_seen = step(weft_height, warp_height);
    float height = max(warp_height, weft_height);
    float lift = mix(weft_lift, warp_lift, warp_seen);
    float twist = mix(weft_twist, warp_twist, warp_seen);
    float tone = mix(weft_tone, warp_tone, warp_seen);
    float shade = sqrt(height) * (0.55 + 0.45 * lift) * (0.85 + 0.15 * twist);
    shade *= 1.0 + irregularity * 0.4 * (tone - 0.5);
    shade += 0.06 * (sa_value_noise(doc * 0.7) - 0.5);
    if (crimp > 0.0) {
        shade *= 1.0 - 0.35 * crimp * (1.0 - lift);
    }
    if (slub > 0.0) {
        float lump = mix(weft_slub, warp_slub, warp_seen);
        height /= 1.0 + 0.5 * slub;
        shade += 0.12 * lump * height;
    }
    if (fuzz > 0.0) {
        vec2 one = vec2(doc.x + doc.y, doc.y - doc.x) * 0.70710678;
        float hairs = max(smoothstep(0.8, 0.95, sa_value_noise(vec2(one.x / max(scale, 2.0), one.y / 0.9) + vec2(13.0, 0.0))), smoothstep(0.8, 0.95, sa_value_noise(vec2(one.y / max(scale, 2.0), one.x / 0.9) + vec2(0.0, 29.0))));
        float gap = 1.0 - min(height, 1.0);
        shade += fuzz * (0.45 * hairs * gap + 0.12 * (sa_value_noise(doc * 0.9 + vec2(7.0, 3.0)) - 0.5));
        height += 0.3 * fuzz * hairs * gap;
    }
    if (priming > 0.0) {
        float level = 0.6 * priming;
        float filled = clamp((level - height) / 0.15, 0.0, 1.0);
        shade = mix(shade, 0.9, max(filled, 0.35 * priming));
        height = max(height, level);
    }
    return vec2(clamp(shade, 0.0, 1.0), height);
}

float weave_shade(vec2 doc) {
    return weave(doc).x;
}

// The surface's normal at *texel*, from the threads' height at its four
// neighbours, as relief_normal.gmacs takes it inside.
vec3 weave_normal(vec2 texel) {
    float left = weave(texel - vec2(1.0, 0.0)).y;
    float right = weave(texel + vec2(1.0, 0.0)).y;
    float up = weave(texel - vec2(0.0, 1.0)).y;
    float down = weave(texel + vec2(0.0, 1.0)).y;
    return ground_normal(left, right, up, down);
}

// The shade the weave settles to over many threads. A quadratic in the thread
// thickness and linear in the irregularity, fitted to the mean of the shade over
// a field of 1400 by 1400 texels at thicknesses from 0.3 to 1 and
// irregularities from a quarter to 1, within 0.003 of it. The spacing and the
// angle do not move it. A machine weave, irregularity 0, has no steady mean:
// the texels sample a perfect pattern at their own lattice, so the figure there
// is the weave's own to a few hundredths and the fit is the nearest smooth one.
float weave_mean() {
    return -0.0171 + 1.1468 * thickness - 0.4259 * thickness * thickness - irregularity * (0.0068 + 0.0861 * thickness);
}

// The weave a screen pixel shows when its centre is at document position
// `centre`. At 100 percent and past it that is the texel the centre falls in.
// Below it, taps spread over a box `footprint - 1` texels wide, the width the
// view's own filter averages (each of its taps is already a texel wide), as
// many to a side as it takes to leave one to a texel up to three, and the
// result is pulled toward the mean as the footprint passes FADE_FROM.
float footprint_shade(vec2 centre) {
    if (texels_per_pixel <= 1.0) {
        return weave_shade(floor(centre));
    }
    float width = max(texels_per_pixel - 1.0, 1.0);
    int side = int(clamp(ceil(texels_per_pixel - 1.0), 2.0, float(MAX_TAPS)));
    int count = side * side;
    int step = side == 2 ? LATTICE_STEP_FOUR : LATTICE_STEP_NINE;
    float total = 0.0;
    for (int i = 0; i < MAX_TAPS * MAX_TAPS; i++) {
        if (i < count) {
            vec2 across = (vec2(float(i), float((i * step) % count)) + 0.5) / float(count) - 0.5;
            total += weave_shade(floor(centre + across * width));
        }
    }
    float spacing = max(scale, 2.0);
    float fade_width = FADE_PER_SPACING * spacing + FADE_AT_TWO * exp((2.0 - spacing) / FADE_TWO_FALL);
    float reach = max(texels_per_pixel - FADE_FROM, 0.0) / fade_width;
    float kept = FADE_FLOOR + (1.0 - FADE_FLOOR) / (1.0 + pow(reach, FADE_STEEP));
    float mean_shade = weave_mean();
    return mean_shade + kept * (total / float(count) - mean_shade);
}

// The normal a screen pixel shows, the normals at the same taps
// footprint_shade reads averaged, as the view averages the relief's over a
// pixel's footprint inside the rectangle.
vec3 footprint_normal(vec2 centre) {
    if (texels_per_pixel <= 1.0) {
        return weave_normal(floor(centre));
    }
    float width = max(texels_per_pixel - 1.0, 1.0);
    int side = int(clamp(ceil(texels_per_pixel - 1.0), 2.0, float(MAX_TAPS)));
    int count = side * side;
    int step = side == 2 ? LATTICE_STEP_FOUR : LATTICE_STEP_NINE;
    vec3 total = vec3(0.0);
    for (int i = 0; i < MAX_TAPS * MAX_TAPS; i++) {
        if (i < count) {
            vec2 across = (vec2(float(i), float((i * step) % count)) + 0.5) / float(count) - 0.5;
            total += weave_normal(floor(centre + across * width));
        }
    }
    return total / float(count);
}

void fragment() {
    // Read from the position rather than from UV, for the reason
    // paper.gdshader gives.
    vec2 doc = rect_origin + UV * rect_size;
    if (sa_ground_past_edge(doc)) {
        discard;
    }
    vec2 at = sa_ground_fold(doc);
    vec4 colour = mix(color_b, color_a, footprint_shade(at));
    if (ground_lit_wanted()) {
        colour = sa_ground_lit(colour, footprint_normal(at));
    }
    COLOR = sa_ground_edged(colour, doc, texels_per_pixel);
}
