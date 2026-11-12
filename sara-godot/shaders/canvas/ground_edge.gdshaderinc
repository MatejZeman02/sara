// The edge of the sheet beyond the document rectangle, which a ground's view
// shader draws when the ground's `edge` asks for one. A sheet of paper ends
// in a cut, a deckle or a torn edge and a canvas turns over its stretcher,
// where a ruled rectangle reads as a screen. Every edge lies wholly outside
// the page: inside it the colour is handed back as it came, so no pixel of
// the painting is hidden or cut, and an export, which reads the document and
// never this rect, is the rectangle it was. Past the edge the sheet casts a
// soft shadow on whatever the view shows behind it.
//
// Widths are in millimetres at the document's resolution, `pixel_mm` of
// ground_relief.gdshaderinc, which has to be included before this file, so a
// deckle is as wide on a sheet of 300 dpi as on one of 72.
//
// The edges by number, as the ground's `edge` parameter holds them: 0 none,
// the ground running on past the page, which is how the infinite canvas draws
// it whatever the ground asks, 1 Cut, 2 Deckle, 3 Torn, 4 Wrapped. On a
// bounded page the rect past it is shown only for an edge, and is transparent
// past the edge's reach. A ground saved before there were edges has no `edge`
// and draws as before.

// The edge the ground asks for, by the numbers above.
uniform float edge = 0.0;
// The page's size in document pixels, its top left corner at the origin.
uniform vec2 page_size = vec2(0.0);

const float EDGE_DECKLE_MM = 3.0;
const float EDGE_TORN_MM = 2.5;
// The radius a canvas turns over its stretcher's edge with, in millimetres.
const float EDGE_WRAP_MM = 4.0;
const float EDGE_SHADOW_MM = 3.0;
const float EDGE_SHADOW = 0.32;
// Past this every edge and its shadow are spent: the widest, a wrap's turn or
// the shadow a millimetre off the sheet and three wide, reach four.
const float EDGE_SPENT_MM = 5.0;

// Value noise on a plane of its own, for the edge's wander, from the lattice
// hash every ground view shader carries.
float edge_noise(vec2 p, int plane) {
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

// Whether the ground draws an edge at all.
bool edge_wanted() {
    return edge > 0.5 && page_size.x > 0.0 && page_size.y > 0.0;
}

// How far *doc* lies outside the page, in document pixels, nought inside it.
float edge_outside(vec2 doc) {
    vec2 beyond = max(max(-doc, doc - page_size), vec2(0.0));
    return length(beyond);
}

// Whether *doc* lies past everything the edge draws, where the view shows the
// backdrop. A bounded page's rect is shown for its edge alone, so a view
// shader leaves such a pixel before it reads any grain.
bool sa_ground_past_edge(vec2 doc) {
    return edge_wanted() && edge_outside(doc) > EDGE_SPENT_MM / pixel_mm;
}

// A coordinate that runs along every side of the page and round its corners,
// so the edge's wander never jumps.
float edge_along(vec2 doc) {
    return doc.x + doc.y;
}

// Where a wrapped canvas's weave is read for *doc*: inside the page and past
// the turn it is *doc*, and on the turn the arc the canvas runs over, so the
// weave foreshortens as the cloth turns away from the eye.
vec2 sa_ground_fold(vec2 doc) {
    if (!edge_wanted() || edge < 3.5) {
        return doc;
    }
    float radius = EDGE_WRAP_MM / pixel_mm;
    vec2 nearest = clamp(doc, vec2(0.0), page_size);
    vec2 outward = doc - nearest;
    float across = length(outward);
    if (across <= 0.0 || across >= radius) {
        return doc;
    }
    float arc = radius * asin(across / radius);
    return nearest + outward * (arc / across);
}

// *colour*, the ground at *doc*, ended at the edge: whole inside the page,
// then the sheet's edge, then the shadow it casts. *tpp*, the texels a screen
// pixel covers, softens each line by a screen pixel so the edge never
// stair-steps.
vec4 sa_ground_edged(vec4 colour, vec2 doc, float tpp) {
    if (!edge_wanted()) {
        return colour;
    }
    float outside = edge_outside(doc);
    if (outside <= 0.0) {
        return colour;
    }
    float mm = 1.0 / pixel_mm;
    float soft = 0.5 * max(tpp, 1.0);
    float along = edge_along(doc);
    float sheet = 1.0;
    vec3 tint = colour.rgb;
    if (edge < 1.5) {
        // Cut: a knife's line, wandering a pixel or two.
        float reach = 0.6 + 1.4 * edge_noise(vec2(along / 90.0, 0.5), 51);
        sheet = 1.0 - smoothstep(reach - soft, reach + soft, outside);
    } else if (edge < 2.5) {
        // Deckle: a feathered fringe a few millimetres wide, its reach
        // wandering along the side, thinning to translucent at its end.
        float width = EDGE_DECKLE_MM * mm;
        float wander = 0.55 * edge_noise(vec2(along / (2.5 * mm), 0.5), 52) + 0.45 * edge_noise(vec2(along / (0.7 * mm), 0.5), 53);
        float reach = width * (0.35 + 0.65 * wander);
        float into = clamp(outside / max(reach, 0.001), 0.0, 1.5);
        float fibres = edge_noise(vec2(along / (0.25 * mm), outside / (0.6 * mm)), 54);
        float thin = smoothstep(0.25, 1.0, into);
        sheet = (1.0 - smoothstep(1.0 - soft / max(reach, 0.001), 1.0, into)) * mix(1.0, 0.35 + 0.65 * fibres, thin);
        sheet *= 1.0 - 0.55 * thin;
        tint = mix(colour.rgb, vec3(1.0), 0.12 * thin);
    } else if (edge < 3.5) {
        // Torn: a ragged line, with fibres standing out past it and the
        // sheet's paler core showing along the tear.
        float width = EDGE_TORN_MM * mm;
        float ragged = 0.5 * edge_noise(vec2(along / (2.0 * mm), 0.5), 55) + 0.3 * edge_noise(vec2(along / (0.7 * mm), 0.5), 56) + 0.2 * edge_noise(vec2(along / (0.2 * mm), 0.5), 57);
        float reach = width * (0.15 + 0.85 * ragged);
        float body = 1.0 - smoothstep(reach - soft, reach + soft, outside);
        float hair_line = edge_noise(vec2(along / (0.12 * mm), outside / (1.4 * mm)), 58);
        float past = clamp((outside - reach) / (1.2 * mm), 0.0, 1.0);
        float hairs = smoothstep(0.82, 0.95, hair_line) * (1.0 - past) * step(reach, outside);
        sheet = max(body, 0.7 * hairs);
        float core = 1.0 - smoothstep(0.0, 0.5 * mm, abs(outside - reach));
        tint = mix(colour.rgb, vec3(1.0), 0.18 * core * body);
    } else {
        // Wrapped: the cloth turning over the stretcher, its weave already
        // read on the arc by sa_ground_fold, darkening as it faces away, and
        // gone where it turns down out of sight.
        float radius = EDGE_WRAP_MM * mm;
        float facing = sqrt(max(1.0 - min(outside / radius, 1.0) * min(outside / radius, 1.0), 0.0));
        sheet = 1.0 - smoothstep(radius - soft, radius + soft, outside);
        tint = colour.rgb * (0.35 + 0.65 * facing);
    }
    // The shadow falls away from the relief's light, a millimetre off the
    // sheet, and fades over a few.
    vec2 away = -normalize(relief_light.xy + vec2(1.0e-6));
    float shadow_outside = edge_outside(doc - away * mm);
    float shadow = EDGE_SHADOW * (1.0 - smoothstep(0.0, EDGE_SHADOW_MM * mm, shadow_outside));
    float alpha = colour.a * sheet + shadow * (1.0 - colour.a * sheet);
    vec3 rgb = alpha > 0.0 ? tint * colour.a * sheet / alpha : tint;
    return vec4(rgb, alpha);
}
