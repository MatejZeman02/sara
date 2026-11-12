// The document's paper ground beyond the document rectangle:
// the same sheet between two colours that paper.gmacs writes inside it, its
// pulp's value noise with the fibres, the felt and the laid lines laid over,
// on a rect so large in document pixels that it reaches the viewport edges at
// any zoom. The uniforms are what SaGeneratedLayer.apply_view sets, the colours
// already in display space with the layer's opacity in their alpha.
//
// The first three functions below are libs/lattice_hash.gmacs and
// libs/noise.gmacs copied by hand, because a canvas_item shader cannot import a
// compute dialect library and the two sides of the document edge have to agree
// texel for texel. If one is ever changed the other has to change with it,
// which is what the scenario's shot of the edge is there to catch. The last is
// noise.gmacs's fbm with a width added.
//
// **What the two sides have to agree on is what the eye sees**, and inside the
// rectangle the eye sees the kernel's texels through the view's tonemap shader,
// which draws a texel as a square at 100 percent and above and averages the
// ones a pixel covers below it. So this shader reads the texel the pixel
// centre falls in, the way the kernel reads its own, and fades each octave of
// the noise by what an average over `texels_per_pixel` texels would leave of
// it. Read at the pixel centre instead, as this shader did, the grain sat half
// a texel off the kernel's and, past a pixel to the texel, aliased into a
// coarse speckle that does not shrink with the zoom while the document's
// paper beside it went smooth.
//
// **The grain is lit as the paper's tooth is inside.** `raise_tooth` stands
// the same noise up as height, so the slope comes from the grain at the
// texel's four neighbours, faded as the colour is, and ground_relief.gdshaderinc
// lights it with the document's relief light.
//
// **The sheet ends at an edge**, ground_edge.gdshaderinc's, when the ground's
// `edge` asks for one. Nothing of it reaches into the document.
shader_type canvas_item;

#include "res://shaders/canvas/ground_relief.gdshaderinc"

uniform vec4 color_a : source_color = vec4(0.93, 0.91, 0.86, 1.0);
uniform vec4 color_b : source_color = vec4(0.82, 0.79, 0.72, 1.0);
// The width of one noise cell in document pixels.
uniform float scale = 20.0;
// The rect's place in document pixels, so the grain reads where it is.
uniform vec2 rect_origin = vec2(0.0);
uniform vec2 rect_size = vec2(1.0);
// How much of each part of the sheet shows, as paper.gmacs reads them.
uniform float fibre = 0.0;
uniform float felt = 0.0;
uniform float felt_size = 16.0;
uniform float laid = 0.0;
// How many document pixels one screen pixel covers, the reciprocal of the
// canvas's zoom taken with the window's interface scale. One or less is a view
// at 100 percent or past it, where a texel is a square and nothing is averaged.
uniform float texels_per_pixel = 1.0;

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

// How much of an octave's contrast an average over `width` texels leaves, for
// an octave whose cells are `cell` texels across. Fitted to the box average of
// the noise itself, which falls as one over the width for cells of a texel and
// as the width over the cell for wider ones: within a tenth of the real
// figure from one texel to sixteen at every cell from one to twenty-four. A
// cell under a texel counts as one, because the kernel reads one value to the
// texel and the octave is white noise at that size. A width of one is no
// average and leaves everything.
float sa_octave_survival(float cell, float width) {
    float across = max(cell, 1.0);
    return inversesqrt(1.0 + (width * width - 1.0) / (1.6 * across * across - 0.6));
}

// libs/noise.gmacs's sa_value_fbm with each octave pulled to its mean, a half,
// by sa_octave_survival. `cell` is the first octave's cell in texels, and the
// octaves halve it as the original doubles the frequency.
float sa_value_fbm(vec2 p, float cell, float width) {
    float total = 0.0;
    float amplitude = 0.5;
    float weight = 0.0;
    vec2 at = p;
    float across = cell;
    for (int i = 0; i < 3; i++) {
        total += amplitude * (0.5 + sa_octave_survival(across, width) * (sa_value_noise(at) - 0.5));
        weight += amplitude;
        amplitude *= 0.5;
        at *= 2.0;
        across *= 0.5;
    }
    return total / weight;
}

// paper.gmacs's `paper_noise`, value noise on a plane of its own.
float paper_noise(vec2 p, int plane) {
    vec2 floored = floor(p);
    ivec3 cell = ivec3(ivec2(floored), plane);
    vec2 f = p - floored;
    vec2 smoothed = f * f * (3.0 - 2.0 * f);
    float a = sa_lattice_hash(cell);
    float b = sa_lattice_hash(cell + ivec3(1, 0, 0));
    float c = sa_lattice_hash(cell + ivec3(0, 1, 0));
    float d = sa_lattice_hash(cell + ivec3(1, 1, 0));
    return mix(mix(a, b, smoothed.x), mix(c, d, smoothed.x), smoothed.y);
}

// paper.gmacs's three parts of the sheet, copied by hand.
float paper_fibres(vec2 doc) {
    float total = 0.0;
    for (int i = 0; i < 3; i++) {
        float turn = 0.6 + 2.0944 * float(i);
        float c = cos(turn);
        float s = sin(turn);
        vec2 slow = doc / 32.0;
        vec2 bent = doc + 16.0 * (vec2(paper_noise(slow, 11 + 2 * i), paper_noise(slow, 12 + 2 * i)) - 0.5);
        vec2 along = vec2(c * bent.x + s * bent.y, c * bent.y - s * bent.x);
        float crest = smoothstep(0.76, 0.92, paper_noise(along / vec2(14.0, 1.5), 21 + i));
        total += crest * (1.0 - 2.0 * float(i % 2));
    }
    return total - 0.060;
}

float paper_felt(vec2 doc) {
    vec2 p = doc / max(felt_size, 2.0);
    vec2 floored = floor(p);
    vec2 f = p - floored;
    float nearest = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            ivec2 cell = ivec2(floored) + ivec2(x, y);
            vec2 jitter = vec2(sa_lattice_hash(ivec3(cell, 31)), sa_lattice_hash(ivec3(cell, 32)));
            nearest = min(nearest, length(vec2(float(x), float(y)) + jitter - f));
        }
    }
    return 0.469 - smoothstep(0.0, 0.9, nearest);
}

float paper_laid(vec2 doc) {
    float wobble = 2.0 * (paper_noise(doc / 64.0, 41) - 0.5);
    float lines = 0.5 * cos(6.2831853 * (doc.y + wobble) / 9.0);
    float chain = mod(doc.x, 250.0) - 125.0;
    return lines + 0.8 * exp(-chain * chain / 8.0) - 0.016;
}

// paper.gmacs's `paper_sheet` with each part faded, as each octave of the
// pulp is, by what an average over *width* texels leaves of it: the fibres by
// their breadth of a texel and a half, the felt by half its cell and the laid
// lines by half their spacing. Each part is its own mean less, so a part
// faded away leaves the tone the average would.
float paper_sheet(vec2 texel, float cell, float width) {
    float sheet = sa_value_fbm(texel / cell, cell, width);
    if (fibre > 0.0) {
        sheet += 0.18 * fibre * sa_octave_survival(1.5, width) * paper_fibres(texel);
    }
    if (felt > 0.0) {
        sheet += 0.45 * felt * sa_octave_survival(0.5 * max(felt_size, 2.0), width) * paper_felt(texel);
    }
    if (laid > 0.0) {
        sheet += 0.12 * laid * sa_octave_survival(4.5, width) * paper_laid(texel);
    }
    return clamp(sheet, 0.0, 1.0);
}

void fragment() {
    // The rect reaches a million document pixels either way, so this sum is
    // two large numbers cancelling and the document position it lands on is
    // quantised to about a sixteenth of a pixel. That is far under a texel,
    // which is what the floor wants, and it is why the grain is read from the
    // position rather than from UV.
    if (sa_ground_past_edge(rect_origin + UV * rect_size)) {
        discard;
    }
    vec2 texel = floor(rect_origin + UV * rect_size);
    float cell = max(scale, 1.0);
    // At 100 percent and above the view draws a texel as it is. Below it the
    // view samples linearly, one tap that blends four texels and leaves about
    // what a box a texel and a half wide would, and past two texels to the
    // pixel it spreads taps over the width the pixel has beyond that.
    float width = texels_per_pixel > 1.0 ? max(texels_per_pixel - 0.5, 1.5) : 1.0;
    vec4 colour = mix(color_a, color_b, paper_sheet(texel, cell, width));
    if (ground_lit_wanted()) {
        float left = paper_sheet(texel - vec2(1.0, 0.0), cell, width);
        float right = paper_sheet(texel + vec2(1.0, 0.0), cell, width);
        float up = paper_sheet(texel - vec2(0.0, 1.0), cell, width);
        float down = paper_sheet(texel + vec2(0.0, 1.0), cell, width);
        colour = sa_ground_lit(colour, ground_normal(left, right, up, down));
    }
    COLOR = sa_ground_edged(colour, rect_origin + UV * rect_size, texels_per_pixel);
}
