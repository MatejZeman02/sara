shader_type canvas_item;

// The glitter coat over a sweep block, ui/settings/input/tablet_sweep_strip.gd.
//
// TEXTURE is how much coat the pen has scratched off each pixel, and `paint`
// is what Try It laid over the coat. The coat itself is a greyscale salt and
// pepper grain at three sizes, each grain a round fleck of its own size and
// tone rather than a pixel of white noise, and each twinkles slowly on its own
// phase, so the coat glitters without ever crawling.

uniform sampler2D paint : filter_nearest, repeat_disable;

// The block's size in pixels, so the grains keep one size on every block.
uniform vec2 pixels = vec2(360.0, 72.0);

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// One layer of flecks on cells *cell* pixels wide: a signed tone, salt above
// nought and pepper below, and a twinkle on the salt.
vec2 flecks(vec2 at, float cell, float seed, float time) {
    vec2 index = floor(at / cell);
    vec2 within = fract(at / cell) - 0.5;
    float tone = hash(index + seed);
    vec2 offset = (vec2(hash(index + seed + 17.1), hash(index + seed + 31.7)) - 0.5) * 0.4;
    float radius = mix(0.18, 0.48, hash(index + seed + 5.3));
    float fleck = smoothstep(radius, radius - 0.12, length(within - offset));
    float twinkle = 0.5 + 0.5 * sin(time * mix(0.5, 1.6, hash(index + seed + 9.9)) + tone * 40.0);
    float sign_of = tone > 0.5 ? 1.0 : -1.0;
    return vec2(fleck * sign_of * mix(0.55, 1.0, twinkle), fleck * step(0.5, tone) * pow(twinkle, 12.0));
}

void fragment() {
    vec2 at = UV * pixels;
    vec2 fine = flecks(at, 2.5, 0.0, TIME);
    vec2 middle = flecks(at, 5.5, 7.0, TIME * 0.8);
    vec2 coarse = flecks(at, 11.0, 13.0, TIME * 0.6);
    float grey = 0.6 + 0.16 * fine.x + 0.13 * middle.x + 0.1 * coarse.x;
    float shine = max(max(fine.y, middle.y), coarse.y);
    vec3 coat = vec3(clamp(grey + 0.35 * shine, 0.0, 1.0));

    float cover = 1.0 - texture(TEXTURE, UV).r;
    vec4 laid = texture(paint, UV);
    float alpha = laid.a + cover * (1.0 - laid.a);
    vec3 colour = alpha <= 0.0 ? vec3(0.0) : (laid.rgb * laid.a + coat * cover * (1.0 - laid.a)) / alpha;
    COLOR = vec4(colour, alpha);
}
