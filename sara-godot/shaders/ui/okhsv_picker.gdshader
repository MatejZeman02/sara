shader_type canvas_item;

// 0 = Hue Ring, 1 = OKHSV Saturation/Value square, 2 = the OK-HSL disc,
// 3 = the hue's own OKLCh triangle,
// 4 = the same triangle transposed, chroma up from a neutral bottom edge,
// 5 = the disc's lightness bar, black at the foot to white at the head
uniform int picker_mode = 0;
uniform float current_hue = 0.0; // 0.0 to 1.0
uniform float inner_radius = 0.74; // Inner normalized radius of Hue Ring
uniform float outer_radius = 0.98; // Outer normalized radius of Hue Ring

// Where pure sRGB red, yellow, green, cyan, blue and magenta sit round the
// ring, in turns clockwise from the right, handed in by ring_angle in
// ui/widgets/picker/sa_picker_shape.gd so the marks sit where the colours do
// rather than at even sixths, small grey ticks that show where RGBCMY are.
uniform float mark_angles[6];

// The triangle's right edge is the hue's own cusp chroma, worked out
// in the shader by the same call the cursor's maths uses, so the two cannot
// drift apart. The softness is in the same chroma units and is what keeps the
// two slanted gamut edges from stepping.
uniform float triangle_edge_softness = 0.004;

// Where the OK-HSL disc's lightness slider stands, 0 to 1 and toe-mapped the
// way the square's Y axis was. The disc has no room for a third axis of its
// own, which is what the slider beside it is for.
uniform float disc_lightness = 0.5;

// The saturation the disc's lightness bar is drawn at, 0 to 1, with
// current_hue as its hue: the bar is the colour's own column of lightnesses.
uniform float bar_saturation = 1.0;

// How wide the disc's rim is feathered, as a fraction of its radius, so the
// circle has an edge rather than a staircase.
uniform float disc_edge_softness = 0.012;

// The ring's lightness is a profile: yellow lifted well above a base, the hue
// opposite yellow a little under it, smooth between, and at every hue the most
// chroma the sRGB gamut holds at that lightness. One lightness for every hue
// makes yellow a dark mustard nobody can find, and riding each hue's cusp
// swings yellow to L 0.968 and blue to 0.452. The base is that one lightness,
// yellow rises a fifth above it, the opposite hue sits a little under, and
// the two bumps are squared cosines, so the quarter points sit a hair over the
// base rather than halfway up. The chroma is sara_gamut_chroma at that
// lightness, from 0.11 at cyan to 0.30 at purple.
// One chroma for every hue, a circle seen from above, is no answer either: the
// gamut caps it at 0.11, cyan being the limit, and the ring comes out pastel.
// scripts/ring_profile.py prints the numbers, and the
// twin in utils/okhsl_conversions.gd is what the suite proves against.
const float RING_BASE_L = 0.65;
const float RING_LIFT_AT_YELLOW = 0.20;
const float RING_DIP_OPPOSITE = 0.07;
// sRGB yellow's own Oklab hue, 109.8 degrees, as a fraction of the turn.
const float RING_YELLOW_HUE = 0.30494;

// Where the ring puts yellow, a quarter turn clockwise from the right, which
// is straight down. The HSV ring in hsv_picker.gdshader puts it there too,
// and ring_angle in ui/widgets/picker/sa_picker_shape.gd is the GDScript twin.
const float RING_YELLOW_ANGLE = 0.25;

// The Oklab hue at *angle* turns round the ring or the disc.
float hue_at_angle(float angle) {
	return fract(angle - RING_YELLOW_ANGLE + RING_YELLOW_HUE);
}

float ring_lightness(float h) {
	float c = cos(2.0 * 3.141592653589793 * (fract(h) - RING_YELLOW_HUE));
	float towards_yellow = (1.0 + c) * 0.5;
	float away = (1.0 - c) * 0.5;
	return RING_BASE_L + RING_LIFT_AT_YELLOW * towards_yellow * towards_yellow - RING_DIP_OPPOSITE * away * away;
}

float cbrt(float x) {
	if (x == 0.0) return 0.0;
	if (x > 0.0) return pow(x, 1.0 / 3.0);
	return -pow(-x, 1.0 / 3.0);
}

float channel_rgb_to_srgb(float c) {
	if (c <= 0.0031308) return 12.92 * c;
	return 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

vec3 srgb_transfer_function(vec3 rgb) {
	return vec3(
		channel_rgb_to_srgb(rgb.x),
		channel_rgb_to_srgb(rgb.y),
		channel_rgb_to_srgb(rgb.z)
	);
}

vec3 oklab_to_linear_srgb(vec3 lab) {
	if (lab.x == 0.0 && lab.y == 0.0 && lab.z == 0.0) return vec3(0.0);

	float l_ = 1.0 * lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
	float m_ = 1.0 * lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
	float s_ = 1.0 * lab.x - 0.0894841775 * lab.y - 1.291485548 * lab.z;

	float l = l_ * l_ * l_;
	float m = m_ * m_ * m_;
	float s = s_ * s_ * s_;

	float r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
	float g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
	float b = -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s;

	return vec3(r, g, b);
}

float toe(float x) {
	float k_1 = 0.206;
	float k_2 = 0.03;
	float k_3 = (1.0 + k_1) / (1.0 + k_2);
	return 0.5 * (k_3 * x - k_1 + sqrt((k_3 * x - k_1) * (k_3 * x - k_1) + 4.0 * k_2 * k_3 * x));
}

float toe_inv(float x) {
	float k_1 = 0.206;
	float k_2 = 0.03;
	float k_3 = (1.0 + k_1) / (1.0 + k_2);
	return (x * x + k_1 * x) / (k_3 * (x + k_2));
}

// Ottosson's max-saturation solve with the coefficient set handed in rather
// than chosen inside, so the ring can ask all three what they would answer.
// One set per channel: red first, then green, then blue, each the polynomial
// that guesses where that channel reaches zero plus one Halley step onto it.
float max_saturation_with(float a, float b, float k0, float k1, float k2, float k3, float k4, float wl, float wm, float ws) {
	float S = k0 + k1 * a + k2 * b + k3 * a * a + k4 * a * b;

	float k_l = 0.3963377774 * a + 0.2158037573 * b;
	float k_m = -0.1055613458 * a - 0.0638541728 * b;
	float k_s = -0.0894841775 * a - 1.291485548 * b;

	float l_ = 1.0 + S * k_l;
	float m_ = 1.0 + S * k_m;
	float s_ = 1.0 + S * k_s;

	float l = l_ * l_ * l_;
	float m = m_ * m_ * m_;
	float s = s_ * s_ * s_;

	float l_dS = 3.0 * k_l * l_ * l_;
	float m_dS = 3.0 * k_m * m_ * m_;
	float s_dS = 3.0 * k_s * s_ * s_;

	float l_dS2 = 6.0 * k_l * k_l * l_;
	float m_dS2 = 6.0 * k_m * k_m * m_;
	float s_dS2 = 6.0 * k_s * k_s * s_;

	float f = wl * l + wm * m + ws * s;
	float f1 = wl * l_dS + wm * m_dS + ws * s_dS;
	float f2 = wl * l_dS2 + wm * m_dS2 + ws * s_dS2;

	if (f1 == 0.0) f1 = 1e-10;
	if (f1 * f1 - 0.5 * f * f2 == 0.0) f2 = 1e-10;

	S = S - (f * f1) / (f1 * f1 - 0.5 * f * f2);
	return S;
}

// Which channel runs out first, by Ottosson's own two half-plane tests. The
// triangle, the disc and the square all reach the cusp through this, and it is
// Ottosson's exactly: the ring is the only shape that departs from it.
float compute_max_saturation(float a, float b) {
	if (-1.88170328 * a - 0.80936493 * b > 1.0) {
		return max_saturation_with(a, b, 1.19086277, 1.76576728, 0.59662641, 0.75515197, 0.56771245,
			4.0767416621, -3.3077115913, 0.2309699292);
	}
	if (1.81444104 * a - 1.19445276 * b > 1.0) {
		return max_saturation_with(a, b, 0.73956515, -0.45954404, 0.08285427, 0.1254107, 0.14503204,
			-1.2684380046, 2.6097574011, -0.3413193965);
	}
	return max_saturation_with(a, b, 1.35733652, -0.00915799, -1.1513021, -0.50559606, 0.00692167,
		-0.0041960863, -0.7034186147, 1.707614701);
}

vec2 find_cusp(float a, float b) {
	float S_cusp = compute_max_saturation(a, b);
	vec3 rgb_at_max = oklab_to_linear_srgb(vec3(1.0, S_cusp * a, S_cusp * b));
	float max_rgb = max(max(rgb_at_max.x, rgb_at_max.y), rgb_at_max.z);
	if (max_rgb <= 0.0) max_rgb = 1e-10;
	float L_cusp = cbrt(1.0 / max_rgb);
	float C_cusp = L_cusp * S_cusp;
	return vec2(L_cusp, C_cusp);
}

vec2 get_ST_max(float a, float b) {
	vec2 cusp = find_cusp(a, b);
	float L = cusp.x;
	if (L >= 1.0) L = 1.0 - 1e-10;
	if (L <= 0.0) L = 1e-10;
	float C = cusp.y;
	return vec2(C / L, C / (1.0 - L));
}

vec3 okhsv_to_srgb(float h, float s, float v) {
	h = fract(h);
	s = clamp(s, 0.0, 1.0);
	v = clamp(v, 0.0, 1.0);

	float a_ = cos(2.0 * 3.141592653589793 * h);
	float b_ = sin(2.0 * 3.141592653589793 * h);

	vec2 st_max = get_ST_max(a_, b_);
	float S_max = st_max.x;
	float S_0 = 0.5;
	float T = st_max.y;
	float k = 1.0 - S_0 / S_max;

	float denom1 = (S_0 + T - T * k * s);
	if (denom1 == 0.0) denom1 = 1e-10;
	float L_v = 1.0 - (s * S_0) / denom1;
	float C_v = (s * T * S_0) / denom1;

	float L = v * L_v;
	float C = v * C_v;

	float L_vt = toe_inv(L_v);
	if (L_v == 0.0) L_v = 1e-10;
	float C_vt = (C_v * L_vt) / L_v;

	float L_new = toe_inv(L);
	if (L == 0.0) L = 1e-10;
	C = (C * L_new) / L;
	L = L_new;

	vec3 rgb_scale = oklab_to_linear_srgb(vec3(L_vt, a_ * C_vt, b_ * C_vt));
	float max_scale = max(max(rgb_scale.x, rgb_scale.y), max(rgb_scale.z, 0.0));
	if (max_scale <= 0.0) max_scale = 1e-10;
	float scale_L = cbrt(1.0 / max_scale);

	L = L * scale_L;
	C = C * scale_L;

	vec3 rgb_lin = oklab_to_linear_srgb(vec3(L, C * a_, C * b_));
	vec3 srgb = srgb_transfer_function(rgb_lin);
	return clamp(srgb, vec3(0.0), vec3(1.0));
}

float find_gamut_intersection_fixed_l(float a, float b, float L, vec2 cusp) {
	float t;
	if (L <= cusp.x) {
		t = L * (cusp.y / cusp.x);
	} else {
		t = cusp.y * (1.0 - L) / (1.0 - cusp.x);
		float k_l = 0.3963377774 * a + 0.2158037573 * b;
		float k_m = -0.1055613458 * a - 0.0638541728 * b;
		float k_s = -0.0894841775 * a - 1.291485548 * b;
		float l_ = L + t * k_l;
		float m_ = L + t * k_m;
		float s_ = L + t * k_s;
		float l = l_ * l_ * l_;
		float m = m_ * m_ * m_;
		float s = s_ * s_ * s_;
		float ldt = 3.0 * k_l * l_ * l_;
		float mdt = 3.0 * k_m * m_ * m_;
		float sdt = 3.0 * k_s * s_ * s_;
		float ldt2 = 6.0 * k_l * k_l * l_;
		float mdt2 = 6.0 * k_m * k_m * m_;
		float sdt2 = 6.0 * k_s * k_s * s_;
		float r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s - 1.0;
		float r1 = 4.0767416621 * ldt - 3.3077115913 * mdt + 0.2309699292 * sdt;
		float r2 = 4.0767416621 * ldt2 - 3.3077115913 * mdt2 + 0.2309699292 * sdt2;
		float u_r = r1 / (r1 * r1 - 0.5 * r * r2);
		float t_r = -r * u_r;
		if (u_r < 0.0) t_r = 1e5;
		float g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s - 1.0;
		float g1 = -1.2684380046 * ldt + 2.6097574011 * mdt - 0.3413193965 * sdt;
		float g2 = -1.2684380046 * ldt2 + 2.6097574011 * mdt2 - 0.3413193965 * sdt2;
		float u_g = g1 / (g1 * g1 - 0.5 * g * g2);
		float t_g = -g * u_g;
		if (u_g < 0.0) t_g = 1e5;
		float b_val = -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s - 1.0;
		float b1 = -0.0041960863 * ldt - 0.7034186147 * mdt + 1.707614701 * sdt;
		float b2 = -0.0041960863 * ldt2 - 0.7034186147 * mdt2 + 1.707614701 * sdt2;
		float u_b = b1 / (b1 * b1 - 0.5 * b_val * b2);
		float t_b = -b_val * u_b;
		if (u_b < 0.0) t_b = 1e5;
		t += min(t_r, min(t_g, t_b));
	}
	return t;
}

// One candidate cusp, from one channel's coefficient set: the point that
// saturation reaches, scaled so the brightest channel sits exactly at 1. The
// z component is the darkest channel as a fraction of the brightest, which is
// how far outside the cube the candidate fell, and it is negative for a
// candidate whose own channel is not the one that ran out.
vec3 ring_cusp_candidate(float a, float b, float S) {
	vec3 rgb = oklab_to_linear_srgb(vec3(1.0, S * a, S * b));
	float max_rgb = max(max(rgb.x, rgb.y), rgb.z);
	if (S <= 0.0 || max_rgb <= 0.0) return vec3(0.0, 0.0, -1.0);
	float L = cbrt(1.0 / max_rgb);
	return vec3(L, L * S, min(min(rgb.x, rgb.y), rgb.z) / max_rgb);
}

// How far outside the cube a candidate may sit and still count as the answer.
// Ottosson's solve lands a hair either side of the boundary, so a candidate
// that is exactly the cusp reports a thousandth of a channel outside as often
// as it reports zero.
const float RING_INSIDE = 0.001;

// And how far outside one may sit and still be blended towards. This is what
// carries the ring across the fold at blue, and two hundredths spreads it over
// four degrees of hue, which was eight pixels of a 292-unit picker.
const float RING_REACH = 0.02;

// How much more chroma an outside candidate has to reach before the ring
// crosses to it at all. Without this the blend also fires around hue 345, where
// a candidate a thousandth outside carries three thousandths more chroma, and
// spending gamut there buys nothing: there is no fold to cross.
const float RING_GAIN = 0.02;

// Keeps whichever candidate the ring should be using: the greatest chroma that
// is inside the cube, and separately the greatest chroma that is outside it but
// within reach, with how far outside it fell.
void ring_keep(vec3 candidate, inout vec2 inside, inout vec3 reaching) {
	if (candidate.z >= -RING_INSIDE) {
		if (candidate.y > inside.y) inside = candidate.xy;
	} else if (candidate.z > -RING_REACH && candidate.y > reaching.y) {
		reaching = candidate;
	}
}

// The ring's own cusp at hue *h*.
//
// Two things happen here that `find_cusp` does not do, and both are about the
// same place on the wheel. `compute_max_saturation` picks one candidate by a
// pair of half-plane tests, and near the blue vertex it picks the wrong one: at
// pure blue's own hue it answers a colour of chroma 0.284 while the vertex
// at that same hue holds 0.313, so the ring drew (2, 60, 255) where the
// gamut has (0, 0, 255). That is the note's complaint about yellow, in blue.
// Asking all three and keeping the largest fixes it.
//
// The second is the fold itself. Oklab's hue folds at the blue vertex: the
// saturated edge from cyan to blue passes hue 264 degrees twice, so the
// greatest chroma any hue owns genuinely jumps by 0.04 there. The gamut images
// measured from Ottosson's own Python show the same fold. Drawn honestly it is
// a hard vertical seam across the ring, green falling from 88 to 0 over two
// pixels. So the ring crosses to the far candidate over the few degrees where
// that candidate is still nearly in the cube, giving up a little chroma near
// the fold, spent at blue rather than at yellow. It costs at most 0.046 of chroma, between 260 and 265
// degrees, and nothing anywhere else on the wheel but the corner at pure red,
// which it rounds by 0.004. A corner is not a fold, and the corners at red and
// green are what a cube corner looks like.
vec2 ring_cusp(float h) {
	float a = cos(2.0 * 3.141592653589793 * fract(h));
	float b = sin(2.0 * 3.141592653589793 * fract(h));
	vec2 inside = vec2(0.0);
	vec3 reaching = vec3(0.0, 0.0, -1.0);
	ring_keep(ring_cusp_candidate(a, b, max_saturation_with(a, b, 1.19086277, 1.76576728, 0.59662641,
		0.75515197, 0.56771245, 4.0767416621, -3.3077115913, 0.2309699292)), inside, reaching);
	ring_keep(ring_cusp_candidate(a, b, max_saturation_with(a, b, 0.73956515, -0.45954404, 0.08285427,
		0.1254107, 0.14503204, -1.2684380046, 2.6097574011, -0.3413193965)), inside, reaching);
	ring_keep(ring_cusp_candidate(a, b, max_saturation_with(a, b, 1.35733652, -0.00915799, -1.1513021,
		-0.50559606, 0.00692167, -0.0041960863, -0.7034186147, 1.707614701)), inside, reaching);
	if (inside.y <= 0.0) inside = find_cusp(a, b);
	if (reaching.y <= inside.y) return inside;
	float crossing = smoothstep(-RING_REACH, -RING_INSIDE, reaching.z) *
	                 smoothstep(0.0, RING_GAIN, reaching.y - inside.y);
	return mix(inside, reaching.xy, crossing);
}


// Sara's own OKHSL and OKLCh, the GLSL half of utils/okhsl_conversions.gd.
// Saturation is the plain fraction of the chroma the hue reaches at that
// lightness, without the mid-chroma curve Ottosson's okhsl bends it with, so
// the definition is one the docstring beside it can state in a sentence.
vec3 sara_oklch_to_srgb(float h, float C, float L) {
	float a_ = cos(2.0 * 3.141592653589793 * fract(h));
	float b_ = sin(2.0 * 3.141592653589793 * fract(h));
	vec3 rgb = oklab_to_linear_srgb(vec3(L, C * a_, C * b_));
	return clamp(srgb_transfer_function(rgb), vec3(0.0), vec3(1.0));
}

// The largest chroma this hue reaches anywhere on its lightness axis, which is
// the chroma at its cusp. The triangle's right edge and the disc's rim are
// both this, so every hue fills its frame.
float sara_cusp_chroma(float h) {
	// Through ring_cusp rather than find_cusp: the half-plane tests pick the
	// wrong coefficient set at pure blue's own hue and answer 0.284 where the
	// vertex holds 0.313, so the triangle's own edge would stop short of the
	// colour it is supposed to reach.
	return ring_cusp(h).y;
}

// The chroma the sRGB gamut holds at Oklab lightness L, for this hue.
float sara_gamut_chroma(float h, float L) {
	if (L <= 0.0 || L >= 1.0) return 0.0;
	float a_ = cos(2.0 * 3.141592653589793 * fract(h));
	float b_ = sin(2.0 * 3.141592653589793 * fract(h));
	// The same cusp sara_cusp_chroma normalizes by, or the reach and the axis
	// disagree at blue and the cursor rides an edge the drawing has not got.
	return find_gamut_intersection_fixed_l(a_, b_, L, ring_cusp(h));
}

// The ring's colour at hue *h*: the profile's lightness, and the most chroma
// the gamut holds there. `ring_cusp` above is not the ring's, it is the cusp
// the shapes inside the ring are normalised by, and it keeps its name because
// three files and a suite reach it by that name.
vec3 ring_color(float h) {
	float L = ring_lightness(h);
	return sara_oklch_to_srgb(h, sara_gamut_chroma(h, L), L);
}

// The marks are a mid grey, dark enough to read on yellow and light enough to
// read on blue, and a little narrower than the ring's own cursor.
const vec3 MARK_GREY = vec3(0.5);
// Half a mark's width, in the same units as the ring's radius, where 1 is the
// frame's edge.
const float MARK_HALF_WIDTH = 0.01;
// How far a mark's edges are feathered, in the same units.
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

void fragment() {
	if (picker_mode == 5) {
		// The disc's lightness bar: every OK-HSL lightness of the colour's
		// own hue and saturation, black at the foot and white at the head,
		// toe-mapped the way the disc's lightness is.
		float L = toe_inv(clamp(1.0 - UV.y, 0.0, 1.0));
		float s = clamp(bar_saturation, 0.0, 1.0);
		COLOR = vec4(sara_oklch_to_srgb(current_hue, s * sara_gamut_chroma(current_hue, L), L), 1.0);
	} else if (picker_mode == 4) {
		// The same slice as mode 3, turned a quarter turn: lightness runs
		// along X with black at the left and white at the right, and chroma
		// runs up from the neutral bottom edge to this hue's cusp at the top.
		// The corner tests are the same two gamut edges read the other way, so
		// the region is a triangle standing on the bottom edge with its apex
		// over the cusp's lightness.
		float L = clamp(UV.x, 0.0, 1.0);
		float C = clamp(1.0 - UV.y, 0.0, 1.0) * sara_cusp_chroma(current_hue);
		float reach = sara_gamut_chroma(current_hue, L);
		float alpha = smoothstep(0.0, triangle_edge_softness, reach - C);
		COLOR = vec4(sara_oklch_to_srgb(current_hue, min(C, reach), L), alpha);
	} else if (picker_mode == 3) {
		// The hue's own slice of Oklab: lightness up the Y axis, chroma along
		// X. Black at the bottom, white at the top and the cusp out to the
		// right, which is a triangle because the gamut's two edges between
		// those three points are straight.
		float L = clamp(1.0 - UV.y, 0.0, 1.0);
		float C = clamp(UV.x, 0.0, 1.0) * sara_cusp_chroma(current_hue);
		float reach = sara_gamut_chroma(current_hue, L);
		float alpha = smoothstep(0.0, triangle_edge_softness, reach - C);
		COLOR = vec4(sara_oklch_to_srgb(current_hue, min(C, reach), L), alpha);
	} else if (picker_mode == 2) {
		// The OK-HSL disc: hue around it, saturation out from the middle,
		// and the lightness the slider beside it stands on. The rim is
		// saturation 1 at every hue, because the chroma is normalized to what
		// the hue can reach, so the circle is round rather than the shape of
		// the gamut.
		vec2 d = UV - vec2(0.5);
		float r = length(d) * 2.0;
		float h = hue_at_angle(atan(d.y, d.x) / (2.0 * 3.141592653589793));
		float L = toe_inv(clamp(disc_lightness, 0.0, 1.0));
		float s = clamp(r, 0.0, 1.0);
		float alpha = smoothstep(1.0 + disc_edge_softness, 1.0 - disc_edge_softness, r);
		vec3 col = sara_oklch_to_srgb(h, s * sara_gamut_chroma(h, L), L);
		// The disc does the ring's job on its rim, so the marks stand there.
		float mark = mark_cover(atan(d.y, d.x) / (2.0 * 3.141592653589793), r, 0.9, 1.0);
		COLOR = vec4(mix(col, MARK_GREY, mark), alpha);
	} else if (picker_mode == 0) {
		// Hue Ring
		vec2 d = UV - vec2(0.5);
		float dist = length(d) * 2.0;
		if (dist < inner_radius - 0.01 || dist > outer_radius + 0.01) {
			COLOR = vec4(0.0);
		} else {
			float alpha = smoothstep(inner_radius - 0.01, inner_radius + 0.01, dist) *
			              smoothstep(outer_radius + 0.01, outer_radius - 0.01, dist);
			float turn = atan(d.y, d.x) / (2.0 * 3.141592653589793);
			vec3 col = ring_color(hue_at_angle(turn));
			// The marks stand on the inner half of the ring, so the outer
			// half still shows the colour under them.
			float mark = mark_cover(turn, dist, inner_radius, (inner_radius + outer_radius) * 0.5);
			COLOR = vec4(mix(col, MARK_GREY, mark), alpha);
		}
	} else {
		// Saturation/Value Square
		float s = clamp(UV.x, 0.0, 1.0);
		float v = clamp(1.0 - UV.y, 0.0, 1.0);
		vec3 col = okhsv_to_srgb(current_hue, s, v);
		COLOR = vec4(col, 1.0);
	}
}
