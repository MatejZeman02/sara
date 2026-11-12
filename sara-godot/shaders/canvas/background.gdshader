// The document's background beyond the document rectangle: the
// same flat colour background.gmacs writes inside it, on a rect so large in
// document pixels that it reaches the viewport edges at any zoom. The
// uniforms are what SaGeneratedLayer.apply_view sets, the colours already in
// display space with the layer's opacity in their alpha.
shader_type canvas_item;

uniform vec4 color_a : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 color_b : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float scale = 1.0;
// The rect's place in document pixels, so a pattern could read where it is.
uniform vec2 rect_origin = vec2(0.0);
uniform vec2 rect_size = vec2(1.0);
uniform vec2 canvas_size = vec2(1.0);
// How many document pixels one screen pixel covers, which a flat colour has no
// grain to fade by. paper.gdshader reads it.
uniform float texels_per_pixel = 1.0;

void fragment() {
    // A pattern would read rect_origin + UV * rect_size, the document position.
    COLOR = color_a;
}
