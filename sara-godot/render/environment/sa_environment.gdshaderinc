// The Environment view's half of the canvas shader: a camera of yaw, pitch and
// field of view turns each screen pixel into a direction, and the direction into
// the document position the projection's kind maps it to. For a kind whose view
// is a disc, the flat view's pan and zoom turn each screen pixel into a point of
// the disc instead.
//
// Included into whatever shader the flat canvas draws with at the time, the
// tonemap or a module's view mode, by `SaEnvironmentView.Composer`, which puts
// these lines ahead of `fragment` and the position this answers in place of UV,
// so the roll-off, the soft proof and False Colour run after it unchanged.
//
// The kind's map is read and never written here. `sa_env_lookup` holds, for
// each direction of a grid in azimuth and angle from the zenith, the document
// position `SaProjection.from_view` answers for it, as a fraction of the size.
// The view knows no kind by name, and a module's kind is drawn through its own
// map with no shader of its own.

// The camera's basis in Godot's frame, y up and minus z ahead, written by the
// view whenever the camera moves. On a plane it is the map from the drawn
// rectangle's pixels to the plane, the forward vector its origin.
uniform vec3 sa_env_right = vec3(1.0, 0.0, 0.0);
uniform vec3 sa_env_up = vec3(0.0, 1.0, 0.0);
uniform vec3 sa_env_forward = vec3(0.0, 0.0, -1.0);
// Where the middle of the view stands, as a fraction of the drawn rectangle:
// the middle of what the dockers and the bar leave uncovered, which is not the
// middle of the window.
uniform vec2 sa_env_centre = vec2(0.5, 0.5);
// How far one unit ahead a step of the whole drawn rectangle reaches, across
// and down: twice the tangent of half the field of view over the uncovered
// height, times the rectangle's size in pixels.
uniform vec2 sa_env_reach = vec2(2.0, 2.0);
// Whether the document joins its edges across and down, the kind's wrap.
uniform bvec2 sa_env_wraps = bvec2(true, false);
// The kind's map, read texel by texel, so a jump across the document's seam is
// unwrapped before two neighbours are blended.
uniform sampler2D sa_env_lookup : filter_nearest, repeat_disable;
// Whether the kind's view is a plane, a disc seen face on, rather than a sphere
// seen from inside. The grid's angles on a plane are the azimuth round the
// disc from up, turning right, and the radius as a fraction of the rim's.
uniform bool sa_env_plane = false;

// The direction through *screen_uv*, the position across the view from its top
// left corner, nought to one each way, or on a plane the point under it.
vec3 sa_env_ray(vec2 screen_uv) {
    vec2 off = (screen_uv - sa_env_centre) * sa_env_reach;
    vec3 point = sa_env_forward + off.x * sa_env_right - off.y * sa_env_up;
    return sa_env_plane ? point : normalize(point);
}

// Whether *screen_uv* is off the kind's view, past the rim of a disc. A sphere
// is seen whichever way the camera looks.
bool sa_env_off(vec2 screen_uv) {
    return sa_env_plane && length(sa_env_ray(screen_uv).xy) > 1.0;
}

// Where *ray* falls on the lookup's grid: the azimuth from straight ahead,
// turning right, as a fraction of a turn, and the angle from the zenith as a
// fraction of a half turn. On a plane, the azimuth from up and the radius, the
// centre's azimuth nought, where the angle has no value.
vec2 sa_env_cell(vec3 ray) {
    if (sa_env_plane) {
        float turn = dot(ray.xy, ray.xy) > 0.0 ? atan(ray.x, ray.y) / TAU : 0.0;
        return vec2(fract(turn), length(ray.xy));
    }
    float across = atan(ray.x, -ray.z) / TAU;
    return vec2(fract(across), acos(clamp(ray.y, -1.0, 1.0)) / PI);
}

// *value* moved by whole documents along each axis that wraps, to the copy
// nearest *to*.
vec2 sa_env_near(vec2 value, vec2 to) {
    return mix(value, value + round(to - value), vec2(sa_env_wraps));
}

// The document position the kind's map gives *ray*, as a fraction of the size
// and not yet folded back inside it. The lookup's four nearest entries are
// blended by hand, after each is moved next to the first, so a ray that lands
// beside the seam blends two neighbours that are one texel apart and not a
// whole width. Within half a row of the grid's top or bottom edge the two
// outer rows are carried on rather than held, so the centre of a disc reads
// its own row and not the first row's. The Sphere docker's ball reads it with
// a ray of its own.
vec2 sa_env_position(vec3 ray) {
    vec2 cells = vec2(textureSize(sa_env_lookup, 0));
    vec2 at = sa_env_cell(ray) * cells - 0.5;
    at.y = clamp(at.y, -0.5, cells.y - 0.5);
    vec2 base = floor(at);
    base.y = clamp(base.y, 0.0, cells.y - 2.0);
    vec2 t = at - base;
    int x0 = int(mod(base.x, cells.x));
    int x1 = int(mod(base.x + 1.0, cells.x));
    int y0 = int(base.y);
    int y1 = y0 + 1;
    vec2 a = texelFetch(sa_env_lookup, ivec2(x0, y0), 0).xy;
    vec2 b = sa_env_near(texelFetch(sa_env_lookup, ivec2(x1, y0), 0).xy, a);
    vec2 c = sa_env_near(texelFetch(sa_env_lookup, ivec2(x0, y1), 0).xy, a);
    vec2 d = sa_env_near(texelFetch(sa_env_lookup, ivec2(x1, y1), 0).xy, a);
    return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
}

// The document position under *screen_uv*, the camera's ray through it.
vec2 sa_env_unwrapped(vec2 screen_uv) {
    return sa_env_position(sa_env_ray(screen_uv));
}

// A step between two neighbouring pixels' positions, taken the short way round
// each axis that wraps, so the footprint the tonemap filters over is the
// pixel's own across the seam too.
vec2 sa_env_step(vec2 step) {
    return sa_env_near(step, vec2(0.0));
}

// *position* folded back inside the document along each axis that wraps, and
// held half a texel inside each edge that does not, so the filter never blends
// the top row with the bottom.
vec2 sa_env_folded(vec2 position, vec2 texel) {
    vec2 folded = mix(position, fract(position), vec2(sa_env_wraps));
    vec2 held = clamp(folded, texel * 0.5, vec2(1.0) - texel * 0.5);
    return mix(held, folded, vec2(sa_env_wraps));
}
