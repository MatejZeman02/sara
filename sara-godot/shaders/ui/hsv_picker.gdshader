shader_type canvas_item;

// The classic shapes beside the Oklab ones, the HSV square and triangle and
// the HSL square: plain RGB hue, saturation
// and value or lightness, the maths every other painting program draws its
// picker with, in the sRGB encoding rather than in linear light, because that
// is what those programs do and what the painters who cannot live without the
// shape have their hands trained on.
//
// 0 = the HSV hue ring, 1 = the HSV square, saturation across and value up,
// 2 = the HSV triangle, the hue at the top and white and black at the two
// bottom corners, 3 = the HSL square, saturation across and lightness up,
// 4 = the hue bar beside the HSL square, red at the top and round to red again.
uniform int picker_mode = 0;
uniform float current_hue = 0.0; // 0.0 to 1.0
uniform float inner_radius = 0.83; // Inner normalized radius of the hue ring
uniform float outer_radius = 0.98; // Outer normalized radius of the hue ring

// Where pure sRGB red, yellow, green, cyan, blue and magenta sit round the
// ring, in turns clockwise from the right, the same uniform and the same
// numbers okhsv_picker.gdshader takes. The hue bar reads its marks from these
// too, through hue_at_angle, so one list serves the ring and the bar.
uniform float mark_angles[6];

// How far outside the triangle a fragment still blends, in barycentric
// weight, so its three edges have an edge rather than a staircase.
uniform float triangle_edge_softness = 0.008;

vec3 hsv_to_rgb(float h, float s, float v) {
	vec3 k = vec3(1.0, 2.0 / 3.0, 1.0 / 3.0);
	vec3 p = abs(fract(vec3(h) + k) * 6.0 - 3.0);
	return v * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
}

vec3 hsl_to_rgb(float h, float s, float l) {
	float c = (1.0 - abs(2.0 * l - 1.0)) * s;
	vec3 k = vec3(1.0, 2.0 / 3.0, 1.0 / 3.0);
	vec3 p = abs(fract(vec3(h) + k) * 6.0 - 3.0);
	return (clamp(p - 1.0, 0.0, 1.0) - 0.5) * c + l;
}

// The triangle's three corners in the area's own UV, on the circle of radius
// a half around its centre: the hue at the top, white bottom left and black
// bottom right. The GDScript twin in ui/widgets/picker/sa_picker_shape.gd puts the
// cursor by the same three points, so the two cannot disagree.
const vec2 TRI_HUE = vec2(0.5, 0.0);
const vec2 TRI_WHITE = vec2(0.066987, 0.75);
const vec2 TRI_BLACK = vec2(0.933013, 0.75);

// The ring is laid out by Oklab hue with yellow straight down, the way the
// OKHSV ring in okhsv_picker.gdshader is, so a colour sits at one angle in
// either family. Each primary goes to its own Oklab hue and the HSV hues
// between two primaries are spread evenly over that span. ring_hue in
// ui/widgets/picker/sa_picker_shape.gd is the GDScript twin and holds the
// same numbers: red, yellow, green, cyan, blue and magenta, in turns.
const float RING_YELLOW_HUE = 0.30494;
const float RING_YELLOW_ANGLE = 0.25;
const float PRIMARY_HUES[7] = float[7](0.08121, 0.30494, 0.39582, 0.54102, 0.73348, 0.91212, 1.08121);

// The HSV hue at *angle* turns round the ring.
float hue_at_angle(float angle) {
	float oklab_hue = fract(angle - RING_YELLOW_ANGLE + RING_YELLOW_HUE);
	// Below red's own Oklab hue is the last sixth, magenta back round to red.
	if (oklab_hue < PRIMARY_HUES[0]) {
		oklab_hue += 1.0;
	}
	int i = 5;
	for (int k = 0; k < 6; k++) {
		if (oklab_hue < PRIMARY_HUES[k + 1]) {
			i = k;
			break;
		}
	}
	float t = (oklab_hue - PRIMARY_HUES[i]) / (PRIMARY_HUES[i + 1] - PRIMARY_HUES[i]);
	return fract((float(i) + t) / 6.0);
}

// The marks, as okhsv_picker.gdshader draws them: a mid grey, half a width,
// and a feather, in the ring's radius units where 1 is the frame's edge.
const vec3 MARK_GREY = vec3(0.5);
const float MARK_HALF_WIDTH = 0.01;
const float MARK_SOFTNESS = 0.004;

// How much of a mark covers the fragment *turn* turns round and *dist* out
// from the middle, for marks that run from radius *from* out to *to*.
float mark_cover(float turn, float dist, float from, float to) {
	float cover = 0.0;
	for (int i = 0; i < 6; i++) {
		float across = abs(fract(turn - mark_angles[i] + 0.5) - 0.5) * 2.0 * 3.141592653589793 * dist;
		cover = max(cover, smoothstep(MARK_HALF_WIDTH + MARK_SOFTNESS, MARK_HALF_WIDTH - MARK_SOFTNESS, across));
	}
	float along = smoothstep(from - MARK_SOFTNESS, from + MARK_SOFTNESS, dist) *
	              smoothstep(to + MARK_SOFTNESS, to - MARK_SOFTNESS, dist);
	return cover * along;
}

// The same for the hue bar, whose hue runs down it from red at the top: a
// mark across the left half of the bar at each colour's own HSV hue.
float bar_mark_cover(vec2 uv) {
	float cover = 0.0;
	for (int i = 0; i < 6; i++) {
		float across = abs(fract(uv.y - hue_at_angle(mark_angles[i]) + 0.5) - 0.5);
		cover = max(cover, smoothstep(MARK_HALF_WIDTH * 0.5 + MARK_SOFTNESS * 0.5, MARK_HALF_WIDTH * 0.5 - MARK_SOFTNESS * 0.5, across));
	}
	return cover * smoothstep(0.5 + MARK_SOFTNESS, 0.5 - MARK_SOFTNESS, uv.x);
}

void fragment() {
	if (picker_mode == 4) {
		COLOR = vec4(mix(hsv_to_rgb(fract(UV.y), 1.0, 1.0), MARK_GREY, bar_mark_cover(UV)), 1.0);
	} else if (picker_mode == 3) {
		float s = clamp(UV.x, 0.0, 1.0);
		float l = clamp(1.0 - UV.y, 0.0, 1.0);
		COLOR = vec4(hsl_to_rgb(current_hue, s, l), 1.0);
	} else if (picker_mode == 2) {
		// Barycentric weights against the three corners: how much of the hue,
		// of white and of black the fragment is. Value is what is not black,
		// and saturation is the hue's share of what is left.
		vec2 v0 = TRI_WHITE - TRI_HUE;
		vec2 v1 = TRI_BLACK - TRI_HUE;
		vec2 v2 = UV - TRI_HUE;
		float d00 = dot(v0, v0);
		float d01 = dot(v0, v1);
		float d11 = dot(v1, v1);
		float d20 = dot(v2, v0);
		float d21 = dot(v2, v1);
		float denom = d00 * d11 - d01 * d01;
		float w_white = (d11 * d20 - d01 * d21) / denom;
		float w_black = (d00 * d21 - d01 * d20) / denom;
		float w_hue = 1.0 - w_white - w_black;
		float inside = min(w_hue, min(w_white, w_black));
		float alpha = smoothstep(-triangle_edge_softness, triangle_edge_softness, inside);
		float v = clamp(1.0 - w_black, 0.0, 1.0);
		float s = v > 0.0 ? clamp(w_hue / max(w_hue + w_white, 1e-6), 0.0, 1.0) : 0.0;
		COLOR = vec4(hsv_to_rgb(current_hue, s, v), alpha);
	} else if (picker_mode == 0) {
		vec2 d = UV - vec2(0.5);
		float dist = length(d) * 2.0;
		if (dist < inner_radius - 0.01 || dist > outer_radius + 0.01) {
			COLOR = vec4(0.0);
		} else {
			float alpha = smoothstep(inner_radius - 0.01, inner_radius + 0.01, dist) *
			              smoothstep(outer_radius + 0.01, outer_radius - 0.01, dist);
			float turn = atan(d.y, d.x) / (2.0 * 3.141592653589793);
			vec3 col = hsv_to_rgb(hue_at_angle(turn), 1.0, 1.0);
			float mark = mark_cover(turn, dist, inner_radius, (inner_radius + outer_radius) * 0.5);
			COLOR = vec4(mix(col, MARK_GREY, mark), alpha);
		}
	} else {
		float s = clamp(UV.x, 0.0, 1.0);
		float v = clamp(1.0 - UV.y, 0.0, 1.0);
		COLOR = vec4(hsv_to_rgb(current_hue, s, v), 1.0);
	}
}
