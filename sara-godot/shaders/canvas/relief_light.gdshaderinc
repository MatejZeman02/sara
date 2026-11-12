// The relief's light, shared by the view's tonemap shader, which lights the
// paint inside the document, and by the grounds' view shaders, which light the
// tooth beyond it, so the two sides of the document edge catch the same light.
//
// Art directed. The slope a normal is drawn with, after the strength, is eased
// towards RELIEF_STEEPEST, so a tenth of a millimetre on a soft edge still
// tilts the surface enough to read while a centimetre of stacked paint stops
// at a steep face rather than a wall that is all shadow or all light. The flat
// surface is the reference: a texel facing straight up is shaded 1.0 and
// catches no highlight, so relief only ever moves what a slope changes. A face
// turned to the light brightens by RELIEF_LIFT of the cosine it gains and a
// face turned away darkens by RELIEF_SHADE of the cosine it loses, and the
// specular is a soft Blinn lobe, relief_gloss at its peak over the flat
// surface's own, added as white light.
//
// The gloss is Preferences' Gloss, `SaSettings.relief_gloss`, a uniform rather
// than a constant so a painter can turn the shine down without flattening the
// relief, and the canvas and the grounds' view both set it. Its default here
// is the setting's, so a material nobody has set yet shines as the view does.
const float RELIEF_STEEPEST = 1.5;
const float RELIEF_LIFT = 0.35;
const float RELIEF_SHADE = 0.8;
const float RELIEF_SHININESS = 20.0;
uniform float relief_gloss = 0.055;

// Lights *lin*, linear light, by the surface's *normal* in the canvas's axes,
// with *light* pointing from the surface to the light and *strength* scaling
// the slope. The flat surface answers *lin* unchanged.
vec3 sa_relief_shade(vec3 lin, vec3 normal, vec3 light, float strength) {
    // The slope the normal was built from, dh/dx and dh/dy up to the sign, in
    // millimetres a millimetre, scaled and then eased.
    vec2 slope = normal.xy / max(normal.z, 1e-3) * strength;
    float steep = length(slope) / RELIEF_STEEPEST;
    slope /= sqrt(1.0 + steep * steep);
    vec3 n = normalize(vec3(slope, 1.0));
    vec3 l = normalize(light);
    float gained = dot(n, l) - l.z;
    float shade = 1.0 + gained * (gained > 0.0 ? RELIEF_LIFT : RELIEF_SHADE);
    vec3 h = normalize(l + vec3(0.0, 0.0, 1.0));
    float gloss = pow(max(dot(n, h), 0.0), RELIEF_SHININESS) - pow(h.z, RELIEF_SHININESS);
    return lin * max(shade, 0.0) + vec3(max(gloss, 0.0) * relief_gloss);
}
