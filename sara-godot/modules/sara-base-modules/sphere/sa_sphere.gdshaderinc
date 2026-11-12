// The Sphere docker's half of the canvas shader: the panorama on a ball seen
// from outside, through the Environment view's own maths.
//
// Composed by `SaEnvironmentView.Composer` the way the view's include is, ahead
// of `fragment` of whatever shader the flat canvas draws with, so the roll-off,
// the soft proof and False Colour read the same on the ball as on the canvas.
// The camera's basis is the view's uniforms, and the kind's map is its lookup.
//
// Mirror-like: the point of the ball at *p* across the disc shows the direction
// right times p.x plus up times p.y plus forward times the depth, the direction
// the view from inside shows at the same place. A globe painted on its outside
// reads backwards, longitude running right to left, and this one reads the way
// the document and the view from inside do.

#include "res://render/environment/sa_environment.gdshaderinc"

// The direction the ball shows at *ball_uv*, the position across the square
// the disc stands in from its top left corner, nought to one each way. Off the
// disc the depth is nought, so the rim's colour carries on to the corner.
vec3 sa_ball_ray(vec2 ball_uv) {
    vec2 across = vec2(ball_uv.x * 2.0 - 1.0, 1.0 - ball_uv.y * 2.0);
    float depth = sqrt(max(1.0 - dot(across, across), 0.0));
    return normalize(sa_env_forward * depth + sa_env_right * across.x + sa_env_up * across.y);
}

// The document position the ball shows at *ball_uv*, as a fraction of the size
// and not yet folded back inside it, which the composed head reads in place of
// the view's `sa_env_unwrapped`.
vec2 sa_ball_unwrapped(vec2 ball_uv) {
    return sa_env_position(sa_ball_ray(ball_uv));
}
