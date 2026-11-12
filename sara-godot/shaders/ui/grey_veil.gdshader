shader_type canvas_item;

// The cover a picker wears while a mask is the paint target: every pixel under
// it drawn as the grey a brush would paint for the colour that is there.
//
// Each number below comes from SaColorStore.mask_grey, which reads the
// document's own colour space, and `ramp` is that store's own answer for a
// coverage rather than a second inverse worked out here, so what the cover
// shows and what a pick through it paints cannot part. The three rules are
// MaskGrey.PEAK, OKLAB and LUMINANCE of core/colors/sa_color_store.gd, and
// ui/widgets/picker/tests/test_the_colour_picker_greyed_for_a_mask_shows_each_colour_at_the_lightness_it_paints.gd
// reads this shader's own pixels back against the store.
//
// The cone matrix and the weights of Oklab's L are deliberate twins of
// core/api/color/sa_oklab.gd, shaders/canvas/tonemap.gdshader and
// shaders/compute/libs/oklab_color_space.gmacs. A .gdshader can include
// neither a .gd nor a .gmacs, so this is duplication on purpose: change one
// and change all four. SaColorSpace hands a shader its gamut and its curve as
// numbers, and has nowhere to hand it these, which is why they are here and
// not a uniform.

uniform sampler2D screen : hint_screen_texture, filter_nearest;

// The display grey of each coverage from 0 to 1, `steps` of them.
uniform sampler2D ramp : filter_linear, repeat_disable;
uniform float steps = 256.0;

// Which coverage the document asks for.
uniform int rule = 0;

// What a decoded display colour is carried by before the shape, and what the
// shape's three numbers are weighed by.
uniform mat3 carry = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0));
uniform vec3 weights = vec3(1.0, 1.0, 1.0);

// The curves, each the four numbers an SaTransferFunction is: slope, where its
// toe ends, gain and exponent, the offset gain - 1 being fixed by
// encode(1) == 1. `display` is undone and its toe is in display values,
// `shape` is applied and its toe is in linear ones.
uniform vec4 display = vec4(12.92, 0.04045, 1.055, 2.4);
uniform vec4 shape = vec4(1.0, 0.0, 1.0, 1.0);

const int RULE_PEAK = 0;
const int RULE_OKLAB = 1;

const mat3 SRGB_TO_LMS = mat3(
		vec3(0.4122214708, 0.2119034982, 0.0883024619),
		vec3(0.5363325363, 0.6806995451, 0.2817188376),
		vec3(0.0514459929, 0.1073969566, 0.6299787005)
	);
const vec3 OKLAB_L = vec3(0.2104542553, 0.7936177850, -0.0040720468);

// Mirrored through the origin, because pow() of a negative base is undefined
// and a wide gamut carried into linear sRGB has negative channels.
vec3 decode(vec3 c, vec4 curve) {
	vec3 m = abs(c);
	vec3 straight = m / curve.x;
	vec3 power = pow((m + curve.z - 1.0) / curve.z, vec3(curve.w));
	return sign(c) * mix(straight, power, step(vec3(curve.y), m));
}

vec3 encode(vec3 c, vec4 curve) {
	vec3 m = abs(c);
	vec3 straight = curve.x * m;
	vec3 power = curve.z * pow(m, vec3(1.0 / curve.w)) - (curve.z - 1.0);
	return sign(c) * mix(straight, power, step(vec3(curve.y), m));
}

// What a brush would paint for the display colour *shown*, 0 to 1.
float coverage(vec3 shown) {
	if (rule == RULE_PEAK) {
		return max(max(shown.r, shown.g), shown.b);
	}
	vec3 light = decode(shown, display);
	if (rule == RULE_OKLAB) {
		return dot(OKLAB_L, encode(SRGB_TO_LMS * (carry * light), shape));
	}
	return dot(weights, encode(carry * light, shape));
}

void fragment() {
	float cover = clamp(coverage(texture(screen, SCREEN_UV).rgb), 0.0, 1.0);
	// The table holds its first grey at coverage 0 and its last at 1, so a
	// coverage lands on the entry's own texel centre rather than half a step
	// off it.
	float at = (cover * (steps - 1.0) + 0.5) / steps;
	COLOR = vec4(vec3(texture(ramp, vec2(at, 0.5)).r), 1.0);
}
