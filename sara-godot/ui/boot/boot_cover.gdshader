shader_type canvas_item;

// The boot cover's picture: the last session's window, or the
// stock one, blurred and fogged so it reads as "Sara is coming" rather than as
// a window that has frozen. The blur is the texture's own mipmaps, read a few
// levels down and averaged over a small ring, which is soft enough at a
// quarter of the window's size and costs nine taps a pixel for the fraction of
// a second the cover is up.

uniform sampler2D picture : filter_linear_mipmap, repeat_disable;
// How many mip levels down the picture is read, the blur's radius.
uniform float blur_lod = 2.5;
// The colour the picture is washed towards, the theme's background.
uniform vec4 fog_colour : source_color = vec4(0.12, 0.12, 0.13, 1.0);
// How far towards the fog, 0 the picture and 1 the fog alone.
uniform float fog_amount = 0.45;

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(picture, 0));
	vec2 step = texel * exp2(blur_lod);
	vec3 sum = vec3(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			sum += textureLod(picture, UV + vec2(float(x), float(y)) * step, blur_lod).rgb;
		}
	}
	vec3 blurred = sum / 9.0;
	COLOR = vec4(mix(blurred, fog_colour.rgb, fog_amount), COLOR.a);
}
