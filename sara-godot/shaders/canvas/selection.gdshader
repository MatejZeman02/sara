// The selection's edge and the quick mask's tint, over one mask chunk drawn
// as a texture in document pixels (ui/canvas/selection_overlay.gd).
//
// The edge is found by sampling the four neighbouring screen pixels, so the
// ants are one screen pixel wide at any zoom and lie on the inside of the texel
// boundary they outline. A step of a texel, which this once took above 100
// percent, marked every screen pixel of the edge texel and widened the ants
// with the zoom. The dashes move on the shader's clock.
//
// A sample past the chunk's own square reads the chunk beside it, which the
// overlay binds as one of the eight neighbour textures below, and a neighbour
// the selection does not hold reads as unselected. So a selection that runs on
// into the next chunk shows no edge along the seam, and one that stops at the
// seam shows its edge there. A sample clamped to the texel itself would also
// hide an edge where the chunk beside holds nothing: a selection that begins
// on the first texel past a seam with an empty chunk left of it would draw no
// ants down its whole left side.
//
// A dash is a stripe pattern read along the edge, so a dash is as long as the
// stripe period divided by how much the stripe direction agrees with the edge.
// One fixed direction therefore gives a different dash length on every
// orientation, and an edge that runs with the stripes comes out solid. The
// direction is the edge's own, read from
// the mask around the fragment and snapped to one of ANT_SECTORS, which holds
// every orientation within two percent of one dash length.
//
// Snapping is what keeps it a stripe. A phase built from the unsnapped tangent
// is not the gradient of anything: it is measured from the screen origin, so on
// a curve it races and the dashes collapse. Snapping instead pays a phase break
// where the estimate crosses into the next sector, which is one broken dash
// each time and is the price of holding the length everywhere else.
shader_type canvas_item;

uniform bool quick_mask = false;
uniform vec4 tint : source_color = vec4(1.0, 0.0, 0.0, 0.5);
uniform vec4 ant_dark : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 ant_light : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float ant_period = 8.0;
uniform float ant_speed = 16.0;

// How far around a fragment the edge direction is read, in screen pixels. It
// has to span more than one step of the staircase a rasterised diagonal makes,
// or the direction wobbles from texel to texel and the dashes break up. It also
// has to stay well under the radius of anything being outlined, because inside
// that distance of a corner the estimate is the corner's and not the edge's.
const float ANT_LOOK = 6.0;

// How many samples the disc is read with, spread by the golden angle so that
// every one of them lies at a radius and a direction of its own. Rings were
// tried first and are worse at the same cost: a ring only ever answers with a
// direction it samples, so eight spokes snapped the estimate to eight answers
// and the sixteenth of a turn between two of them decided the sector.
const int ANT_TAPS = 48;
const float ANT_GOLDEN = 2.39996322973;

// Directions the edge is snapped to, over the full turn. Twelve, measured
// rather than reasoned about: a sector count trades the direction error
// inside a sector, which stretches a dash by 1 / cos of it, against the number
// of sector crossings, each of which breaks one dash. The crossings dominate,
// so more sectors is worse, and the count that wins is the one that puts the
// four axis directions in the middle of a sector and leaves the rest spread.
//
// Measured as the third quartile of the dash lengths over the first, off the
// shots of `scenarios/marching-ants-2.json`, twelve holds the spread lowest
// on an ellipse, a lasso, a polygon and a rectangle at every zoom, where eight
// and sixteen each spread worse on an ellipse. The one place sixteen wins is a
// regular sixteen sided polygon at zoom 1, whose edges land one per sector, and
// that is a shape in the test rather than one a painter draws.
const float ANT_SECTORS = 12.0;

// The chunks around this one, by compass point, north being up the document.
// One the selection does not hold is left unset and reads as the default
// black, which is unselected.
uniform sampler2D west : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D east : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D north : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D south : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D north_west : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D north_east : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D south_west : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D south_east : hint_default_black, filter_nearest, repeat_disable;


// The mask at *uv*, in this chunk's texture coordinates, read from this chunk
// inside its square and from the chunk beside it past an edge. Further than
// one chunk away is unselected, which only the direction disc reaches, and only
// at a zoom where a chunk is a few screen pixels across.
float mask_at(sampler2D own, vec2 uv) {
    vec2 cell = floor(uv);
    if (cell == vec2(0.0)) {
        return textureLod(own, uv, 0.0).r;
    }
    if (abs(cell.x) > 1.0 || abs(cell.y) > 1.0) {
        return 0.0;
    }
    vec2 inner = uv - cell;
    if (cell.y == 0.0) {
        return cell.x < 0.0 ? textureLod(west, inner, 0.0).r : textureLod(east, inner, 0.0).r;
    }
    if (cell.y < 0.0) {
        if (cell.x == 0.0) {
            return textureLod(north, inner, 0.0).r;
        }
        return cell.x < 0.0 ? textureLod(north_west, inner, 0.0).r : textureLod(north_east, inner, 0.0).r;
    }
    if (cell.x == 0.0) {
        return textureLod(south, inner, 0.0).r;
    }
    return cell.x < 0.0 ? textureLod(south_west, inner, 0.0).r : textureLod(south_east, inner, 0.0).r;
}


// Where the mask's weight lies around *uv*, in screen pixels, which points into
// the selection. Zero when the disc is entirely inside or entirely outside.
//
// The square root spreads the taps by equal area rather than by equal radius,
// so the disc is sampled evenly and the answer is the shape's first moment.
vec2 mask_weight(sampler2D mask, vec2 uv, vec2 uv_dx, vec2 uv_dy, float radius) {
    vec2 mass = vec2(0.0);
    for (int i = 0; i < ANT_TAPS; i++) {
        float span = radius * sqrt((float(i) + 0.5) / float(ANT_TAPS));
        float angle = float(i) * ANT_GOLDEN;
        vec2 offset = vec2(cos(angle), sin(angle)) * span;
        mass += mask_at(mask, uv + uv_dx * offset.x + uv_dy * offset.y) * offset;
    }
    return mass;
}


void fragment() {
    float m = texture(TEXTURE, UV).r;
    // One screen pixel each, so the edge test and the disc below are measured
    // in screen pixels whatever the zoom and the rotation are.
    vec2 uv_dx = dFdx(UV);
    vec2 uv_dy = dFdy(UV);
    if (quick_mask) {
        COLOR = vec4(tint.rgb, tint.a * (1.0 - m));
    } else {
        bool inside = m >= 0.5;
        bool edge = inside
            && (mask_at(TEXTURE, UV - uv_dx) < 0.5
                || mask_at(TEXTURE, UV + uv_dx) < 0.5
                || mask_at(TEXTURE, UV - uv_dy) < 0.5
                || mask_at(TEXTURE, UV + uv_dy) < 0.5);
        if (!edge) {
            COLOR = vec4(0.0);
        } else {
            // An ant is within a screen pixel of the boundary, so the disc
            // always reaches across it, and at a high zoom it reads the one
            // step of the staircase it sits on, whose own direction the
            // dashes then run along.
            vec2 inward = mask_weight(TEXTURE, UV, uv_dx, uv_dy, ANT_LOOK);
            if (dot(inward, inward) < 0.000001) {
                inward = vec2(
                    mask_at(TEXTURE, UV + uv_dx) - mask_at(TEXTURE, UV - uv_dx),
                    mask_at(TEXTURE, UV + uv_dy) - mask_at(TEXTURE, UV - uv_dy));
            }
            vec2 along = dot(inward, inward) < 0.000001 ? vec2(1.0, 0.0) : vec2(-inward.y, inward.x);
            float sector = TAU / ANT_SECTORS;
            float snapped = floor(atan(along.y, along.x) / sector + 0.5) * sector;
            vec2 walk = vec2(cos(snapped), sin(snapped));
            float phase = fract((dot(FRAGCOORD.xy, walk) + TIME * ant_speed) / ant_period);
            COLOR = phase < 0.5 ? ant_dark : ant_light;
        }
    }
}
