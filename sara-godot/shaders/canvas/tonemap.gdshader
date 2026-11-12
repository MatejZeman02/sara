shader_type canvas_item;

// View-time highlight rolloff for the canvas.
//
// What it is for
// --------------
// Sara's canvas is float and carries values above 1.0 on purpose. The display
// does not: everything above 1.0 clips to the same white, and it clips per
// channel, so a stored (4.0, 1.0, 0.5) reaches the screen as (1.0, 1.0, 0.5)
// and a hot orange arrives as pale yellow. This holds the ratios instead, so
// the hue a painter picked is the hue on screen, and lets the colour go white
// the way an over-bright colour really does.
//
// White stays white. Nothing at or below a stored 1.0 is darkened by any
// setting here. That is the one thing the operator may not do: a painter's
// white is the paper, and a view that dims it is showing a painting nobody
// made. The magnitude of a value above white is therefore not readable in the
// picture at all, and False Colour is where it is read instead.
//
// This runs on the view, never on the pixels. `easel.output` stays exactly as
// the compositor wrote it, so the eyedropper, export and stroke commit all keep
// reading true values and nobody has to remember to bypass a rolled-off buffer.
// It is a CanvasItem shader rather than a compute pass for the same reason: no
// second texture, no extra dispatch, and it costs screen pixels rather than
// document pixels, so a zoomed-out 8K document is no more expensive than a
// small one.
//
// The ceiling
// -----------
// A screen's white is the ceiling, and a stored 1.0 is already standing on it,
// so the peak channel is brought to white and no further:
//
//     f(x) = min(x, 1)
//
// That is the whole magnitude curve, rather than a shoulder asymptotic to white
// such as f(x) = 1 - d^2 / (x + d - k) with d = 1 - k. A shoulder keeps a
// stored 1.0 and a stored 4.0 apart on screen, and pays for it with a painted
// white reaching the screen below white, so a painting whose brightest value is
// white comes up grey.
//
// That price cannot be paid down. Any curve that leaves a stored 1.0 at display
// white and never exceeds it is flat above white, so magnitude above white is
// unreadable in the picture whatever the arithmetic. What the operator can
// still do there is hold the hue, which per-channel clipping does not, and hand
// the magnitude question to False Colour, which answers it directly.
//
// Desaturation and gamut mapping happen in Oklab
// ----------------------------------------------
// Bringing the peak down holds the RGB ratios, which is not the same as holding
// the colour. Pulling toward white in RGB, which is the obvious next step, drags
// perceived hue with it.
//
// So the compressed colour goes to Oklab and loses *chroma* there, on the
// perceptual axis, with the hue angle never touched. Oklab is perceptually
// uniform, so equal chroma reductions look equal, and the hue a painter picked is
// the hue that reaches the screen. Hue is never rotated. Rotation is what makes
// bright blue go purple under ACES, and a colour that changes hue between the
// picker and the canvas is a bug report rather than film emulation.
//
// Lightness moves with the chroma, toward the lightness of the neutral at the
// compressed peak. That is the difference between a highlight going *white* and
// a highlight going *grey*: dropping chroma at constant L leaves a mid grey of
// the same perceived lightness, which is not what a bright light looks like.
// A bright red that should read as a hot highlight stays well below white with
// L held and reaches it with L carried along. Both preserve hue exactly,
// because only a and b are scaled and L is a separate axis.
//
// Reducing chroma can still leave the colour outside what the display can show,
// so the same Oklab axis does the gamut mapping: chroma comes down to where
// the colour first meets the cube's surface, with L and hue held fixed. That is
// the CSS Color 4 compromise, and the place is Ottosson's analytic gamut
// intersection solved exactly, a closed-form cubic root per channel and edge,
// where `composite.gmacs` still bisects for the non-separable blend modes. Clamping RGB instead would drag hue and
// lightness along with it, which is the thing this whole section exists to
// avoid.
//
// One step comes before that map, for a colour that started inside the cube.
// The step towards white can carry a blue or a yellow a hair outside, past a
// fold where the cube's surface dips in by less than the test's slack, so the
// exact first meeting jumps from one side of the fold to the other as the
// stored value grows, and two blues a hair apart in storage are drawn far apart
// on screen. So such a colour first has its chroma brought to the first meeting
// with the cube widened by half the slack, which lies past the fold, and the
// map then accepts it as it is. A colour with a channel below zero is left to
// the map alone.
//
// Below black ----------- The low side of the cube is the same problem at the
// other end. A filter is right to write a negative channel, and the document
// keeps it, but the monitor clips it to zero on its own, per channel, and that
// turns the hue: a stored (0.45, 0.3, -0.4) is a yellow green of Oklab hue 111
// degrees and would reach the screen as an orange of 75. So a texel with any
// channel below zero goes through the same gamut map at its own lightness and
// hue, whatever its peak, and a texel whose lightness is itself below black is
// black, since no chroma makes a negative lightness fit. It is still only a
// view, so the eyedropper and export read the negative number the document
// holds.
//
// The knee, and tuning
// --------------------
// The knee is where a colour starts to be given up to white, and it moves
// chroma alone: no grey and no white is touched at any knee, and no colour
// inside the display's cube below it. At the default of 1.0 every colour the
// display can show reaches the screen as it does with the rolloff off. A knee
// below 1.0 starts the fading on paint the display could show as it is.
// A knee above 1.0, up to 4.0, is where the rolloff starts. Between white and
// the knee a colour moves from what the display would show with the rolloff
// off, each channel clipped at white on its own, to the channels' ratios held
// with the peak brought to white, by a smoothstep of the peak from 1.0 to the
// knee. At the knee and past it the ratios are held whole and chroma goes to
// white as the desaturation asks. So at a knee of 4 a skin stored at 1.28 in
// light is shown within an 8-bit step of the clip, and a red at 4 is held.

// On by default, and the toggle lives in the View menu and in Preferences. At
// the default knee of 1.0 it changes nothing the display can show, only a
// colour past white that the display would otherwise clip channel by channel
// and turn the hue of, so leaving it off protects no painting. A knee below
// 1.0 moves ordinary paint, and a look that does that is never imposed, so it
// can be on by default only because the default knee leaves paint alone. The
// material's default
// is the profile's, so a copy of this shader handed none of the settings shows
// what a fresh profile shows.
uniform bool tonemap_enabled = true;

// What happens to a colour the display's cube cannot hold, the
// place of SaSettings.gamut_mapping in SaGamutMapping.MODES. 0 clips, which is
// the display cutting each channel on its own and is what this shader always
// did. 1 is oklab: lightness and hue are held and chroma is given up until the
// colour fits, so a saturated colour with a negative channel keeps its hue. It
// is not the rolloff's switch and does not wait for it.
uniform int gamut_mapping = 0;

uniform float knee : hint_range(0.05, 4.0) = 1.0;
uniform float desaturation : hint_range(0.0, 1.0) = 0.15;

// The document's blend reference white. What the document calls 1.0 is what the
// operator should treat as 1.0, so the two cannot disagree about where the
// highlights start. W = 1.0 makes this division the identity.
uniform float blend_white = 1.0;

// Whether stored values carry the sRGB transfer curve. The operator is only
// meaningful in linear light, so a gamma-encoded document is decoded before the
// rolloff. A scene-referred document already stores linear and skips the
// decode, because each document chooses its own blending space.
uniform bool document_is_srgb = true;

// True when the stored numbers are already what the screen wants, which is every
// sRGB document and therefore almost every document. The colour block is
// skipped entirely in that case with the rolloff off, so disabling the rolloff
// hands the screen the stored numbers exactly rather than merely close, with
// only the half-level dither at the end of the fragment added.
//
// False is what makes Image > Convert Colour Space honest. Godot's 2D pipeline
// writes canvas colours to the screen without any encode of its own, which is
// why the rolloff below re-encodes by hand. Without it a document converted to
// Linear sRGB would have its linear numbers displayed as though they were still
// gamma-encoded, 0.5 grey shown as 0.214, the whole painting dark. Convert
// preserves appearance by definition, and this is the view's half of that
// promise.
uniform bool display_passthrough = true;

// The document's linear RGB into linear sRGB, which is what the display wants,
// white point adapted. Exactly the identity for any sRGB-gamut document.
//
// Three column vectors rather than one mat3 uniform, because columns are the
// convention SaColorSpace already packs for .gmacs push constants and emits from
// _mat3_literal, and one convention is worth more here than one uniform.
uniform vec3 to_display_col0 = vec3(1.0, 0.0, 0.0);
uniform vec3 to_display_col1 = vec3(0.0, 1.0, 0.0);
uniform vec3 to_display_col2 = vec3(0.0, 0.0, 1.0);

// What the view shows instead of the picture. 0 is the picture. 1 is the
// Oklab lightness check: every texel as the grey of its perceptual lightness,
// so values read without their hue. 2 is the HDR heatmap: the canvas banded
// by stored magnitude, which is the blowout cue the rolloff takes away and
// the place a painter reads it back. The stored
// peak channel, decoded and before any exposure, picks the band: grey at its
// lightness up to 1.0, then yellow to 2, orange to 4, red to 8 and magenta
// past that, and blue wherever a channel is negative. 4 is Raw: the stored
// numbers reach the screen untouched, with no decode, no gamut and no encode,
// which is the mode a painter asks what the document actually holds with. The
// registry in core/registry/sa_view_transform_registry.gd hands the value in.
// 5 is the shape check: the composite averaged down to a few dozen blocks
// across, or smoothed inside its masses with their edges kept, and its
// lightness snapped to a handful of steps, in colour or in grey, so a
// silhouette reads without the detail that carries it. See the SHAPE_CHECK
// constants below for the methods.
uniform int view_mode = 0;

// The shape check's options, every one of them a preference on the Display
// page. The method is the place of the painter's choice in
// SaSettingsShapeCheck.SHAPE_METHODS, and what it throws away is described at
// the SHAPE_CHECK constants below. Levels is the lightness quantize further
// down, after the method. Blocks with Levels is what a material handed
// nothing keeps.
uniform int shape_check_method = 0;
uniform bool shape_check_levels = true;
// How many steps of lightness the Levels half snaps to, the painter's count.
// Five is what a material handed nothing keeps.
uniform int shape_check_level_count = 5;
// How many blocks Blocks cuts the long side into, a preference whose default
// is this.
uniform float shape_check_across = 32.0;
// How far Masses reaches, a share of the long side, and the two grey methods
// with it.
uniform float shape_check_reach = 0.015;
// Notan's count of values, two or three, and where it cuts the Oklab lightness:
// the one threshold of two values, and the dark and the light one of three.
uniform int shape_check_notan_values = 2;
uniform float shape_check_notan_threshold = 0.5;
uniform float shape_check_notan_dark = 0.333333;
uniform float shape_check_notan_light = 0.666667;

// A greyscale view of whatever the modes above produce, for a reference-image
// canvas element. The one element with no CPU image
// to convert, so it asks its copy of this material for grey instead: Rec. 709
// luminance on linear light, before the display matrix, so the grey is the
// document's lightness and not the monitor's. Off on the canvas itself, always.
uniform bool greyscale_view = false;

// The display exposure: a scale on linear light before the rolloff
// and the display conversion, so a painter can look into the highlights of an
// HDR document. 1.0 is the identity, and it is the viewer's, never the brush's.
uniform float display_exposure = 1.0;

// The display's own gamut: linear sRGB into the space the monitor
// shows, Bradford adapted, applied last. Identity for an sRGB display, which
// display_identity says outright so the common case keeps its passthrough.
// The encode after it is always the sRGB curve: the monitor is assumed to
// apply sRGB's transfer whatever its primaries.
uniform bool display_identity = true;
uniform vec3 display_col0 = vec3(1.0, 0.0, 0.0);
uniform vec3 display_col1 = vec3(0.0, 1.0, 0.0);
uniform vec3 display_col2 = vec3(0.0, 0.0, 1.0);

// Soft proofing: mode 3 shows the picture as a narrower gamut would
// show it, by taking linear sRGB into the proof space, clipping to its cube,
// and coming back. View only, the way everything here is. proof_col* is
// linear sRGB into the proof space and proof_back_col* the way back, both
// Bradford adapted by SaColorSpace. With the warning on, a texel the proof
// space could not hold is painted flat grey instead of clipped, which is
// the gamut warning every proofing program offers.
uniform vec3 proof_col0 = vec3(1.0, 0.0, 0.0);
uniform vec3 proof_col1 = vec3(0.0, 1.0, 0.0);
uniform vec3 proof_col2 = vec3(0.0, 0.0, 1.0);
uniform vec3 proof_back_col0 = vec3(1.0, 0.0, 0.0);
uniform vec3 proof_back_col1 = vec3(0.0, 1.0, 0.0);
uniform vec3 proof_back_col2 = vec3(0.0, 0.0, 1.0);
uniform bool proof_gamut_warning = false;

// True when the chunks hold Oklab rather than RGB. Such a document reaches linear
// sRGB by the fixed Oklab matrices instead of by a curve and a gamut rotation, so
// document_is_srgb and the matrix above do not apply to it and are not consulted.
// Without this the view reads perceptual coordinates as though they were red,
// green and blue, which is not a wrong colour but noise.
uniform bool document_is_oklab = false;

// The relief: thick paint lit by one directional light, so a
// ridge catches it and a groove falls into shadow. Art directed rather than
// physical, with no cast shadow and no parallax.
//
// relief_texture is `SaRelief.texture`, the resolve of every visible height,
// the surface's normal in rgb and its height in a, canvas sized and in the
// canvas's axes, x right, y down, z to the viewer. The normal is the true
// slope in millimetres, and relief_strength scales the slope before it is
// drawn, so the stored height never has to look right. relief_light points
// from the surface to the light in the same axes, and SaCanvas builds it from
// Preferences. Off, or with no height in the document, the relief is not read
// at all, and a texel whose normal stands straight up is not touched either,
// so a picture without height reaches the screen exactly as it would without
// the relief.
//
// The black default is for a sampler nothing bound: a normal of zero is flat
// to the test below, where the white default would have lit every texel.
uniform bool relief_enabled = false;
uniform sampler2D relief_texture : hint_default_black, filter_nearest, repeat_disable;
uniform vec3 relief_light = vec3(-0.5, -0.5, 0.70710678);
uniform float relief_strength = 2.0;

// Slack on the gamut test, so a colour already on the cube face is not rejected
// by rounding and needlessly stripped of chroma. GAMUT_EPSILON is float's own
// rounding. GAMUT_ROUNDING is an F16 Oklab texel's, a share of the texel's
// largest channel, because F16 keeps eleven significant bits at any magnitude.
// Pure blue stored at F16 decodes to (-8.0e-6, -4.6e-5, 0.99962), and at blue's
// hue the map's first exit is 85 per cent of the vertex's chroma, so under the
// float slack alone a texel nothing but F16 has moved would be drawn far from
// pure blue. Measured in NumPy over every 8-bit colour on the cube's faces,
// edges and vertices and over twenty million float colours in and on the cube,
// dark ones included, F16 put no channel further outside than 0.00138 of the
// largest channel rounding to nearest, or 0.00071 truncating as Godot's own
// narrowing does, wherever it was more than 1e-6 out. So 0.002 holds them all,
// and over those 8-bit colours the map then moves none past what F16 already
// did. A colour a hundredth of its largest channel outside a face is still
// mapped.
const float GAMUT_EPSILON = 1e-5;
const float GAMUT_ROUNDING = 2e-3;

// The mirrored sRGB pair and the Oklab matrices below are deliberate twins of
// shaders/compute/libs/linear_srgb_color_space.gmacs and
// shaders/compute/libs/oklab_color_space.gmacs. A .gdshader cannot include a
// .gmacs, so this is duplication on purpose: change one and change the other.
//
// Mirrored rather than plain pow(), because pow() of a negative base is
// undefined and a negative channel reaches the view unclamped by design, and a
// NaN survives even a multiplication by zero.
vec3 srgb_to_linear_mirrored(vec3 c) {
    vec3 m = abs(c);
    vec3 lo = m / 12.92;
    vec3 hi = pow((m + 0.055) / 1.055, vec3(2.4));
    return sign(c) * mix(lo, hi, step(vec3(0.04045), m));
}

vec3 linear_to_srgb_mirrored(vec3 c) {
    vec3 m = abs(c);
    vec3 lo = 12.92 * m;
    vec3 hi = 1.055 * pow(m, vec3(1.0 / 2.4)) - 0.055;
    return sign(c) * mix(lo, hi, step(vec3(0.0031308), m));
}

vec3 linear_srgb_to_oklab(vec3 c) {
    mat3 srgb_to_lms = mat3(
        vec3(0.4122214708, 0.2119034982, 0.0883024619),
        vec3(0.5363325363, 0.6806995451, 0.2817188376),
        vec3(0.0514459929, 0.1073969566, 0.6299787005)
    );
    vec3 lms = srgb_to_lms * c;
    // Blending and wide-gamut colours produce negative LMS, and pow() of a
    // negative base is undefined, so the sign is carried separately.
    lms = sign(lms) * pow(abs(lms), vec3(1.0 / 3.0));
    mat3 lms_to_oklab = mat3(
        vec3(0.2104542553, 1.9779984951, 0.0259040371),
        vec3(0.7936177850, -2.4285922050, 0.7827717662),
        vec3(-0.0040720468, 0.4505937099, -0.8086757660)
    );
    return lms_to_oklab * lms;
}

vec3 oklab_to_linear_srgb(vec3 c) {
    mat3 oklab_to_lms = mat3(
        vec3(1.0, 1.0, 1.0),
        vec3(0.3963377774, -0.1055613458, -0.0894841775),
        vec3(0.2158037573, -0.0638541728, -1.2914855480)
    );
    vec3 lms = oklab_to_lms * c;
    // An odd power preserves sign, so no abs()/sign() dance is needed here.
    lms = lms * lms * lms;
    mat3 lms_to_srgb = mat3(
        vec3(4.0767416621, -1.2684380046, -0.0041960863),
        vec3(-3.3077115913, 2.6097574011, -0.7034186147),
        vec3(0.2309699292, -0.3413193965, 1.7076147010)
    );
    return lms_to_srgb * lms;
}

bool in_display_gamut(vec3 linear) {
    float slack = max(GAMUT_EPSILON, GAMUT_ROUNDING * max(abs(linear.x), max(abs(linear.y), abs(linear.z))));
    return all(greaterThanEqual(linear, vec3(-slack)))
        && all(lessThanEqual(linear, vec3(1.0 + slack)));
}

// Scales Oklab's a and b together, which is a chroma change at constant hue:
// the (a, b) angle is what hue is, and scaling both leaves the angle alone.
vec3 with_chroma_scale(vec3 lab, float factor) {
    return vec3(lab.x, lab.yz * factor);
}

// The real cube root with the sign carried, since pow() of a negative base is
// undefined.
float signed_cbrt(float x) {
    return sign(x) * pow(abs(x), 1.0 / 3.0);
}

// The largest real root of d3 u^3 + d2 u^2 + d1 u + d0, in closed form:
// Cardano's formula when there is one real root and the trigonometric form
// when there are three, whose first is the largest.
float largest_cubic_root(float d3, float d2, float d1, float d0) {
    float a = d2 / d3;
    float b = d1 / d3;
    float c = d0 / d3;
    float p = b - a * a / 3.0;
    float q = 2.0 * a * a * a / 27.0 - a * b / 3.0 + c;
    float disc = 0.25 * q * q + p * p * p / 27.0;
    if (disc > 0.0) {
        float root = sqrt(disc);
        return signed_cbrt(-0.5 * q + root) + signed_cbrt(-0.5 * q - root) - a / 3.0;
    }
    // Three real roots need p below zero, and p at zero here is a triple root.
    if (p >= 0.0) {
        return -a / 3.0;
    }
    float r = sqrt(-p / 3.0);
    float angle = acos(clamp(1.5 * q / (p * r), -1.0, 1.0));
    return 2.0 * r * cos(angle / 3.0) - a / 3.0;
}

// Ottosson's analytic gamut intersection, solved exactly. Along a hue whose
// Oklab to LMS slopes are `k`, one channel of linear sRGB, weighted by the row
// `w` of the LMS to sRGB matrix, is L^3 times a cubic in the saturation
// s = C / L. Put u = 1 / s and the cubic reaching a level T reads
// (1 - T / L^3) u^3 + 3 w.k u^2 + 3 w.k^2 u + w.k^3 = 0, so the first s at
// which the channel leaves the cube is one over that cubic's largest root.
// T = 0 is Ottosson's lower edge, a straight line from black whatever L is,
// and `to_white` carries T = 1, the curved upper edge. A cubic whose largest
// root is not positive never leaves on that side.
float channel_exit(vec3 w, vec3 k, float to_white) {
    float d2 = 3.0 * dot(w, k);
    float d1 = 3.0 * dot(w, k * k);
    float d0 = dot(w, k * k * k);
    float s = 1e30;
    float to_black = largest_cubic_root(1.0, d2, d1, d0);
    if (to_black > 0.0) {
        s = 1.0 / to_black;
    }
    float to_one = largest_cubic_root(to_white, d2, d1, d0);
    if (to_one > 0.0) {
        s = min(s, 1.0 / to_one);
    }
    return s;
}

// Reduces chroma until the colour fits the display cube, holding L and hue.
// Where the colour first leaves the cube on its way out from the neutral axis
// is solved per channel rather than searched for, so it is exact to float
// where twelve bisection steps stopped within 1/4096 of the source chroma, and
// at the fold by blue the answer is the first exit along the chroma axis.
vec3 gamut_map(vec3 lab) {
    vec3 linear = oklab_to_linear_srgb(lab);
    if (in_display_gamut(linear)) {
        return linear;
    }
    // A lightness at or below black has no chroma that fits, because even its
    // neutral is negative, and the monitor would clip that neutral anyway.
    // Black is what that clip was.
    if (lab.x <= 0.0) {
        return vec3(0.0);
    }
    // A lightness at or above white holds no chroma either, and its neutral is
    // the answer the display clips.
    float chroma = length(lab.yz);
    if (lab.x >= 1.0 || chroma <= 0.0) {
        return oklab_to_linear_srgb(with_chroma_scale(lab, 0.0));
    }
    vec2 hue = lab.yz / chroma;
    vec3 k = vec3(0.3963377774 * hue.x + 0.2158037573 * hue.y, -0.1055613458 * hue.x - 0.0638541728 * hue.y, -0.0894841775 * hue.x - 1.2914855480 * hue.y);
    // Held below zero, so a lightness a float step under white is not divided
    // by zero. The chroma it allows there is far below a display step.
    float to_white = min(1.0 - 1.0 / (lab.x * lab.x * lab.x), -1e-6);
    float s = chroma / lab.x;
    s = min(s, channel_exit(vec3(4.0767416621, -3.3077115913, 0.2309699292), k, to_white));
    s = min(s, channel_exit(vec3(-1.2684380046, 2.6097574011, -0.3413193965), k, to_white));
    s = min(s, channel_exit(vec3(-0.0041960863, -0.7034186147, 1.7076147010), k, to_white));
    return oklab_to_linear_srgb(with_chroma_scale(lab, s * lab.x / chroma));
}

// The band a texel falls in, as a display-ready linear colour. `stored` is
// the number in the document, which is what the picker showed and what the
// painter reasons in: a painted 3.0 is stored 3.0 whatever linear light it
// decodes to. `lin` is the same texel in linear sRGB, for the grey band's
// lightness, so the picture stays readable under the bands.
vec3 heatmap_band(vec3 stored, vec3 lin) {
    float peak = max(stored.r, max(stored.g, stored.b));
    float low = min(stored.r, min(stored.g, stored.b));
    if (low < 0.0) {
        return vec3(0.1, 0.3, 1.0);
    }
    if (peak <= 1.0) {
        float l = linear_srgb_to_oklab(lin).x;
        return oklab_to_linear_srgb(vec3(l, 0.0, 0.0));
    }
    if (peak <= 2.0) {
        return vec3(1.0, 0.85, 0.0);
    }
    if (peak <= 4.0) {
        return vec3(1.0, 0.4, 0.0);
    }
    if (peak <= 8.0) {
        return vec3(1.0, 0.0, 0.0);
    }
    return vec3(1.0, 0.0, 1.0);
}

// The width of Khronos PBR Neutral's shoulder, one minus its startCompression
// of 0.76. Sara's magnitude has no shoulder, and this is the one Khronos would
// have pulled the peak down by, which is what the chroma loss is measured by.
// The knee section of the header says why.
const float KHRONOS_SHOULDER = 0.24;

// The first saturation at which the channel of row `w` leaves the cube widened
// by `slack` on both sides, below zero and above one, at a lightness whose cube
// is `l3`. It is `channel_exit` with the two levels moved out, the same cubic in
// u = 1 / s with T = -slack and T = 1 + slack.
float widened_exit(vec3 w, vec3 k, float l3, float slack) {
    float d2 = 3.0 * dot(w, k);
    float d1 = 3.0 * dot(w, k * k);
    float d0 = dot(w, k * k * k);
    float s = 1e30;
    float to_below = largest_cubic_root(1.0 + slack / l3, d2, d1, d0);
    if (to_below > 0.0) {
        s = 1.0 / to_below;
    }
    float to_above = largest_cubic_root(min(1.0 - (1.0 + slack) / l3, -1e-6), d2, d1, d0);
    if (to_above > 0.0) {
        s = min(s, 1.0 / to_above);
    }
    return s;
}

// The rolloff's step towards white carries a colour from the cube's face a hair
// out of the cube, and by blue and by yellow a hair out on one channel is far
// out in chroma. There one channel dips under zero by less than the gamut
// test's slack and comes back, so the exact cube's first exit is 85 per cent of
// the way out while the test lets a colour just short of the slack through as
// it is, so two stored blues a hair apart would be drawn far apart. So a colour
// outside half the slack has its chroma brought down to where it first leaves
// the cube widened by half the slack, which is where one just inside that half
// would be drawn, and `gamut_map` then takes it as it stands. Half, so the
// slack the test reads off the colour that comes out still holds it. Its
// lightness and hue are held as `gamut_map` holds them.
vec3 within_half_the_slack(vec3 lab) {
    float chroma = length(lab.yz);
    if (lab.x <= 0.0 || lab.x >= 1.0 || chroma <= 0.0) {
        return lab;
    }
    vec3 linear = oklab_to_linear_srgb(lab);
    float slack = 0.5 * max(GAMUT_EPSILON, GAMUT_ROUNDING * max(abs(linear.x), max(abs(linear.y), abs(linear.z))));
    if (all(greaterThanEqual(linear, vec3(-slack))) && all(lessThanEqual(linear, vec3(1.0 + slack)))) {
        return lab;
    }
    vec2 hue = lab.yz / chroma;
    vec3 k = vec3(0.3963377774 * hue.x + 0.2158037573 * hue.y, -0.1055613458 * hue.x - 0.0638541728 * hue.y, -0.0894841775 * hue.x - 1.2914855480 * hue.y);
    float l3 = lab.x * lab.x * lab.x;
    float s = chroma / lab.x;
    s = min(s, widened_exit(vec3(4.0767416621, -3.3077115913, 0.2309699292), k, l3, slack));
    s = min(s, widened_exit(vec3(-1.2684380046, 2.6097574011, -0.3413193965), k, l3, slack));
    s = min(s, widened_exit(vec3(-0.0041960863, -0.7034186147, 1.7076147010), k, l3, slack));
    return with_chroma_scale(lab, s * lab.x / chroma);
}

// The rolloff past white with the channels' ratios held, the peak brought to
// white and chroma given up past the knee. `highlight_rolloff` says when.
vec3 held_ratios(vec3 c, float peak, float low, float k, float desat) {
    // White is the ceiling, and a stored white is already on it, so this is the
    // identity for everything up to white as well.
    float new_peak = min(peak, 1.0);
    // Hold the RGB ratios while bringing the peak down. Everything after this is
    // about the colour rather than the magnitude.
    c *= new_peak / peak;

    vec3 lab = linear_srgb_to_oklab(c);
    // Lose chroma with how far Khronos's shoulder, started at the knee, would
    // have pulled the peak down: the brighter a colour is, the closer to neutral
    // it reads. The distance starts from nothing as the square of how far past
    // the knee the peak stands, so a colour a hair past white keeps its chroma
    // to the last 8-bit step, and past a stop or so it is that distance less
    // the shoulder's width. This is the "bright colours go white" behaviour,
    // done on the perceptual axis so equal reductions look equal, and it is the
    // only thing left that tells a stored 4.0 from a stored 1.0 once both
    // magnitudes have landed on white.
    float past = max(peak - k, 0.0);
    float pulled = past * past / (past + KHRONOS_SHOULDER);
    float g = 1.0 - 1.0 / (desat * pulled + 1.0);
    // Lightness travels to the neutral at the compressed peak, so full
    // desaturation lands on white rather than on a grey of the original
    // lightness. Only a and b are scaled, so the hue angle is untouched whatever
    // L does.
    float neutral_l = linear_srgb_to_oklab(vec3(new_peak)).x;
    lab = vec3(mix(lab.x, neutral_l, g), lab.yz * (1.0 - g));
    // A colour that started inside the cube is never carried across blue's or
    // yellow's fold by that step. One with a channel below zero keeps the map
    // it had.
    if (low >= -GAMUT_EPSILON) {
        lab = within_half_the_slack(lab);
    }
    return gamut_map(lab);
}

vec3 highlight_rolloff(vec3 c, float k, float desat) {
    float peak = max(c.r, max(c.g, c.b));
    float low = min(c.r, min(c.g, c.b));
    // The identity region. An ordinary SDR texel leaves here untouched, which is
    // the property the whole operator is chosen for, and at the default knee of
    // 1.0 that is every colour the display can show, a stored white included.
    // A knee above 1.0 ends this region at white all the same, and what stands
    // between white and the knee is blended towards the clip below.
    float flat_to = min(k, 1.0);
    if (peak <= flat_to && low >= -GAMUT_EPSILON) {
        return c;
    }
    // Under the knee with a channel below zero: nothing to give up to white,
    // only a colour the monitor would clip per channel and turn the hue of, so
    // it keeps its lightness and hue and loses the chroma that does not fit.
    if (peak <= flat_to) {
        return gamut_map(linear_srgb_to_oklab(c));
    }
    vec3 held = held_ratios(c, peak, low, k, desat);
    // Under a knee above white the colour starts at what the display shows with
    // the rolloff off and reaches the held ratios at the knee, the header's
    // knee section. The clip of a colour with a channel below zero is the map
    // the rolloff gives it under white, so the two meet at white.
    if (k <= 1.0 || peak >= k) {
        return held;
    }
    vec3 clipped = min(c, vec3(1.0));
    if (low < -GAMUT_EPSILON) {
        clipped = gamut_map(linear_srgb_to_oklab(clipped));
    }
    return mix(clipped, held, smoothstep(1.0, k, peak));
}

// Sampling below 100 percent
// --------------------------
// The output has one mip level, so one bilinear tap reads at most four texels
// of a footprint that covers more, and the picture shimmers as the zoom moves.
// So the view filters below 100 percent itself, with taps one texel apart over
// the footprint less the two texels a linear tap already covers, at most
// MAX_TAPS a side. From 50 percent up one tap is the kernel and the block is
// skipped, so the passthrough stays exact.
const int MAX_TAPS = 6;
const float TENT_WIDTH = 2.0;

// The shape check, mode 5: the canvas downscaled and upscaled, or quantized,
// so a silhouette reads without its detail.
//
// The downscale is across the document rather than in pixels, because a block
// of a fixed number of texels loses everything on a small canvas and nothing on
// a large one, and the question a painter asks the shape check is about the
// picture and not about its resolution. So the long side is cut into
// shape_check_across blocks whatever the document measures, and every block is
// drawn flat at its own average.
//
// The average is SHAPE_CHECK_TAPS squared samples over the block rather than one
// per texel, so a block of four texels and a block of four hundred cost the same
// sixteen taps. That is a downscale by sampling and not by summing, which is
// visible only where a block holds detail finer than four of its own quarters,
// and that detail is what the mode exists to throw away.
const int SHAPE_CHECK_TAPS = 4;
// Blocks and Masses by their place in SaSettingsShapeCheck.SHAPE_METHODS. The
// third, None, runs neither, and leaves the picture whole for Levels alone. The
// fourth and fifth are the grey methods, with monochrome output. Both run the
// Masses filter at its reach, so they hold at any canvas size as Masses does,
// and then drop the hue and chroma further down. Grey masses snaps the
// lightness as Levels does, and Notan cuts it into two or three values at the
// thresholds the painter sets.
const int SHAPE_CHECK_BLOCKS = 0;
const int SHAPE_CHECK_MASSES = 1;
const int SHAPE_CHECK_GREY_MASSES = 3;
const int SHAPE_CHECK_NOTAN = 4;
// Masses checks that the shapes hold, where Blocks only pixelates, and it is
// a Kuwahara filter: the four squares that meet at a texel, each reaching
// shape_check_reach of the long side up and left, up and right, down and left
// and down and right, and the texel drawn at their means weighted towards the
// flattest. A texel beside an edge has one square on its own side of it, which
// is flat and wins, so the edge stays where it was while everything inside a
// mass smooths away. The weight is the generalised filter's of Papari and
// Kyprianidis, one over one plus the square's variance, summed over the three
// channels and scaled, to the power four, so a texel with no flat square near
// it blends the four rather than flickering between them.
//
// Each square is SHAPE_CHECK_MASS_STEPS plus one taps a side, and the four share
// their middle row and column, so the cost is (2 * 4 + 1) squared, 81 taps,
// whatever the canvas measures and whatever the zoom. The taps are spread over
// the reach rather than one a texel, which is the same sampling Blocks does and
// for the same reason. SHAPE_CHECK_MASS_SCALE is the 255 the generalised filter
// reads a variance on, the levels of an eight-bit channel, so a square whose
// texels stray by a level or two weighs as flat.
const int SHAPE_CHECK_MASS_STEPS = 4;
const float SHAPE_CHECK_MASS_SCALE = 255.0;
// The quantize half of the note has no constant here: its count of steps is
// the uniform shape_check_level_count, five unless the painter sets another.
// The chroma is left alone: the mode answers where the shape is, not what
// colour it is, and a painter who wants the hue gone has the Lightness Check
// one row above. Two is the floor the shader holds whatever it is handed,
// because one step would divide by nothing below.
const int SHAPE_CHECK_FEWEST_LEVELS = 2;

// The relief's light is relief_light.gdshaderinc, which the grounds beyond
// the document light their tooth by too.
#include "res://shaders/canvas/relief_light.gdshaderinc"

// The relief over the same footprint the colour was averaged over, so a view
// zoomed out lights the average slope of the texels a pixel covers instead of
// one of them chosen by where the pixel falls. One tap is one texel, nearest,
// which is the colour's own rule at and above one texel a pixel.
vec3 relief_normal_at(vec2 uv, vec2 dx, vec2 dy, vec2 footprint, vec2 spread, int taps) {
    if (taps <= 1) {
        return textureLod(relief_texture, uv, 0.0).rgb;
    }
    vec3 sum = vec3(0.0);
    for (int j = 0; j < MAX_TAPS; ++j) {
        for (int i = 0; i < MAX_TAPS; ++i) {
            if (i < taps && j < taps) {
                vec2 texels = (vec2(float(i), float(j)) / float(taps - 1) - 0.5) * spread;
                vec2 offset = dx * (texels.x / footprint.x) + dy * (texels.y / footprint.y);
                sum += textureLod(relief_texture, uv + offset, 0.0).rgb;
            }
        }
    }
    return sum / float(taps * taps);
}

// Lights *lin*, linear light in the view's working space, by the stored
// *normal*. The flat surface answers *lin* unchanged.
vec3 relief_shade(vec3 lin, vec3 normal) {
    return sa_relief_shade(lin, normal, relief_light, relief_strength);
}

// The screen's rounding, met halfway
// ----------------------------------
// An eight-bit screen rounds every channel to its nearest step, and the default
// background stands exactly between two, so the faintest paint shows as a hard
// line one level off. An ordered Bayer dither of eight pixels square, read off
// the pixel's place on the screen and spanning three quarters of a level, is
// added before the rounding, so a patch averages the stored number and a still
// canvas does not crawl.
const float DISPLAY_LEVELS = 255.0;
const float DITHER_REACH = 0.75;

// On for every view. Off only for a suite that reads the step the dither hides,
// and the view then rounds to the nearest step with nothing added.
uniform bool display_dither = true;

// The threshold at *pixel*, in levels, between -0.3691 and 0.3691. Bit i of x
// and of y, lowest first, weighs 16, 4 and 1.
float dither_threshold(vec2 pixel) {
    vec2 at = floor(pixel);
    float rank = 0.0;
    for (int i = 0; i < 3; ++i) {
        vec2 bit = mod(floor(at / exp2(float(i))), 2.0);
        rank += (2.0 * abs(bit.x - bit.y) + bit.y) * exp2(float(4 - 2 * i));
    }
    return ((rank + 0.5) / 64.0 - 0.5) * DITHER_REACH;
}

void fragment() {
    // COLOR already holds texture(TEXTURE, UV) * modulate. An ordinary sRGB
    // document does nothing here at all wherever its texels are inside the
    // display's cube, with the rolloff off or on at the default knee, which is
    // almost every texel of every document Sara opens by default.
    //
    vec2 dx = dFdx(UV);
    vec2 dy = dFdy(UV);
    vec2 footprint = vec2(length(dx), length(dy)) / TEXTURE_PIXEL_SIZE;
    // What one tent does not already cover, per screen axis, in texels.
    vec2 spread = max(footprint - vec2(TENT_WIDTH), vec2(0.0));
    int taps = int(clamp(ceil(max(spread.x, spread.y)), 0.0, float(MAX_TAPS - 1))) + 1;
    if (view_mode == 5) {
        // The shape check reads its own taps instead of the pixel's footprint,
        // and the two filters do not compose: a block or a reach is already
        // wider than any footprint the tent block would answer, so running both
        // would smear one block into the next and take the hard edge away,
        // which is the edge a silhouette is read off. The quantize below is the
        // same story and is guarded the same way, so None shows Godot's own
        // sample and nothing of either method.
        vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
        if (shape_check_method == SHAPE_CHECK_BLOCKS) {
            float block = max(1.0, floor(max(size.x, size.y) / max(shape_check_across, 1.0)));
            vec2 corner = floor(UV * size / block) * block;
            vec4 sum = vec4(0.0);
            for (int j = 0; j < SHAPE_CHECK_TAPS; ++j) {
                for (int i = 0; i < SHAPE_CHECK_TAPS; ++i) {
                    vec2 at = corner + (vec2(float(i), float(j)) + 0.5) * block / float(SHAPE_CHECK_TAPS);
                    sum += textureLod(TEXTURE, at * TEXTURE_PIXEL_SIZE, 0.0);
                }
            }
            COLOR = sum / float(SHAPE_CHECK_TAPS * SHAPE_CHECK_TAPS);
        } else if (shape_check_method == SHAPE_CHECK_MASSES || shape_check_method == SHAPE_CHECK_GREY_MASSES || shape_check_method == SHAPE_CHECK_NOTAN) {
            vec2 at = UV * size;
            float stride = max(size.x, size.y) * shape_check_reach / float(SHAPE_CHECK_MASS_STEPS);
            // Each square's sum and sum of squares, up and left first, then up
            // and right, down and left and down and right. A tap on the middle
            // row or column belongs to the two squares either side of it.
            vec4 sums[4] = vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));
            vec3 squares[4] = vec3[4](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0));
            for (int j = -SHAPE_CHECK_MASS_STEPS; j <= SHAPE_CHECK_MASS_STEPS; ++j) {
                for (int i = -SHAPE_CHECK_MASS_STEPS; i <= SHAPE_CHECK_MASS_STEPS; ++i) {
                    vec4 tap = textureLod(TEXTURE, (at + vec2(float(i), float(j)) * stride) * TEXTURE_PIXEL_SIZE, 0.0);
                    vec3 squared = tap.rgb * tap.rgb;
                    if (j <= 0 && i <= 0) {
                        sums[0] += tap;
                        squares[0] += squared;
                    }
                    if (j <= 0 && i >= 0) {
                        sums[1] += tap;
                        squares[1] += squared;
                    }
                    if (j >= 0 && i <= 0) {
                        sums[2] += tap;
                        squares[2] += squared;
                    }
                    if (j >= 0 && i >= 0) {
                        sums[3] += tap;
                        squares[3] += squared;
                    }
                }
            }
            float count = float((SHAPE_CHECK_MASS_STEPS + 1) * (SHAPE_CHECK_MASS_STEPS + 1));
            vec4 weighted = vec4(0.0);
            float weights = 0.0;
            for (int k = 0; k < 4; ++k) {
                vec4 mean = sums[k] / count;
                vec3 variance = abs(squares[k] / count - mean.rgb * mean.rgb);
                float weight = 1.0 / (1.0 + pow(SHAPE_CHECK_MASS_SCALE * (variance.r + variance.g + variance.b), 4.0));
                weighted += weight * mean;
                weights += weight;
            }
            // Four weights that all fell under what a float holds are a canvas
            // of numbers far past any paint, and it is drawn at the plain mean
            // rather than divided by nothing.
            COLOR = weights > 0.0 ? weighted / weights : (sums[0] + sums[1] + sums[2] + sums[3]) / (4.0 * count);
        }
    } else if (taps > 1) {
        vec4 sum = vec4(0.0);
        for (int j = 0; j < MAX_TAPS; ++j) {
            for (int i = 0; i < MAX_TAPS; ++i) {
                if (i < taps && j < taps) {
                    // Tap centres from one edge of the spread to the other,
                    // in texels, then back into UV along each screen axis.
                    // textureLod, because texture() inside a loop has no
                    // well-defined derivative to pick a level with, and there
                    // is only the one level anyway.
                    vec2 texels = (vec2(float(i), float(j)) / float(taps - 1) - 0.5) * spread;
                    vec2 offset = dx * (texels.x / footprint.x) + dy * (texels.y / footprint.y);
                    sum += textureLod(TEXTURE, UV + offset, 0.0);
                }
            }
        }
        // The canvas has no modulate of its own, so the average is COLOR.
        COLOR = sum / float(taps * taps);
    }
    // Written as one guarded block rather than an early return: Godot's shading
    // language rejects `return` inside fragment(), and it rejects it as a shader
    // compile error at load time, which substitutes a fallback shader rather
    // than failing loudly.
    bool exposed = display_exposure != 1.0;
    // Under oklab a texel outside the cube has to come through the block below
    // to be mapped, even on a document the screen could otherwise show as it
    // is stored. Asked of the stored number, because on such a
    // document the curve keeps zero and one where they are, so a texel inside
    // the cube still skips the block and reaches the screen bit for bit.
    bool unheld = gamut_mapping == 1 && !in_display_gamut(COLOR.rgb);
    // The relief is read only when it is on, and a texel whose normal stands
    // straight up has nothing to light, so it skips the block.
    vec3 relief = relief_enabled && relief_strength > 0.0 ? relief_normal_at(fract(UV), dx, dy, footprint, spread, taps) : vec3(0.0, 0.0, 1.0);
    bool lit = relief.x != 0.0 || relief.y != 0.0;
    // The rolloff is the identity on a texel at or under the knee and white,
    // the lower of the two, with no channel below zero, so on a document the screen shows as it is stored
    // such a texel skips the block as it does with the rolloff off and reaches
    // the screen bit for bit. At the default knee of 1.0 that is every colour
    // the display can show. Asked of the stored number decoded, because the
    // knee is in linear light, and with the reference white at one, because
    // any other white rescales every texel.
    float stored_peak = max(COLOR.r, max(COLOR.g, COLOR.b));
    float stored_low = min(COLOR.r, min(COLOR.g, COLOR.b));
    bool left_alone = display_passthrough && blend_white == 1.0 && stored_low >= 0.0 && srgb_to_linear_mirrored(vec3(stored_peak)).x <= min(knee, 1.0);
    bool rolls = tonemap_enabled && !left_alone;
    if (rolls || !display_passthrough || view_mode != 0 || exposed || lit || !display_identity || unheld) {
        // Out of whatever the document stores and into linear sRGB, the one
        // space both the operator and the screen agree about.
        vec3 lin;
        if (document_is_oklab) {
            lin = oklab_to_linear_srgb(COLOR.rgb);
        } else {
            lin = document_is_srgb ? srgb_to_linear_mirrored(COLOR.rgb) : COLOR.rgb;
            lin = mat3(to_display_col0, to_display_col1, to_display_col2) * lin;
        }

        if (view_mode == 2) {
            // Bands come from what is stored, before the exposure, because
            // the question is what the document holds and not how it is lit.
            // An Oklab document has no stored RGB to band, so its RGB view
            // stands in.
            vec3 stored = document_is_oklab ? lin : COLOR.rgb;
            lin = heatmap_band(stored / max(blend_white, 1e-6), lin);
        } else {
            // Light falls on the paint before anything looks at it, in the
            // working space and ahead of the exposure, the checks and the
            // display transform, so the colour management downstream sees a
            // lit picture and stays whole. False Colour, above, is left
            // unlit, because it bands what is stored.
            if (lit) {
                lin = relief_shade(lin, relief);
            }
            lin *= display_exposure;
            if (view_mode == 1) {
                float l = linear_srgb_to_oklab(lin).x;
                lin = oklab_to_linear_srgb(vec3(l, 0.0, 0.0));
            } else if (view_mode == 5) {
                // This throws the gradient away where the method above throws
                // the detail away: the lightness lands on one of
                // shape_check_level_count steps and the hue and chroma ride along
                // unchanged. Either half reads a silhouette alone, so whether
                // this runs is a switch of its own on the Display page, on by
                // default.
                //
                // Notan cuts the lightness at its own thresholds instead, into
                // black and white, or black, the middle of the scale and white.
                // The grey methods then keep the lightness alone and draw it as
                // the grey of exactly that lightness, the cube of it in linear
                // light, because Oklab's grey axis is the one where the three
                // channels are equal and the cube is what its inverse comes to
                // there. Written straight rather than through the inverse, so
                // the three channels are equal to the last bit and a, b read
                // nought rather than a rounding away from it.
                bool notan = shape_check_method == SHAPE_CHECK_NOTAN;
                bool grey = notan || shape_check_method == SHAPE_CHECK_GREY_MASSES;
                if (shape_check_levels || grey) {
                    vec3 lab = linear_srgb_to_oklab(lin);
                    if (notan) {
                        float lightness = lab.x;
                        if (shape_check_notan_values >= 3) {
                            float dark = min(shape_check_notan_dark, shape_check_notan_light);
                            float light = max(shape_check_notan_dark, shape_check_notan_light);
                            lab.x = lightness < dark ? 0.0 : (lightness < light ? 0.5 : 1.0);
                        } else {
                            lab.x = lightness < shape_check_notan_threshold ? 0.0 : 1.0;
                        }
                    } else if (shape_check_levels) {
                        float steps = float(max(shape_check_level_count, SHAPE_CHECK_FEWEST_LEVELS));
                        float band = min(floor(clamp(lab.x, 0.0, 1.0) * steps), steps - 1.0);
                        lab.x = band / (steps - 1.0);
                    }
                    lin = grey ? vec3(lab.x * lab.x * lab.x) : oklab_to_linear_srgb(lab);
                }
            } else if (view_mode == 3) {
                vec3 proofed = mat3(proof_col0, proof_col1, proof_col2) * lin;
                vec3 held = clamp(proofed, vec3(0.0), vec3(1.0));
                bool outside = any(notEqual(proofed, held));
                lin = mat3(proof_back_col0, proof_back_col1, proof_back_col2) * held;
                if (proof_gamut_warning && outside) {
                    lin = vec3(0.5);
                }
            }
            if (tonemap_enabled) {
                lin /= max(blend_white, 1e-6);
                lin = highlight_rolloff(lin, knee, desaturation);
            }
        }

        if (greyscale_view) {
            lin = vec3(dot(lin, vec3(0.2126, 0.7152, 0.0722)));
        }

        if (!display_identity) {
            lin = mat3(display_col0, display_col1, display_col2) * lin;
        }

        // The last thing before the encode, and outside the rolloff's branch:
        // under oklab a colour the display's cube cannot hold gives up chroma
        // with its lightness and hue held. It runs after the display matrix
        // because the cube is the display's, so on a wide display the hue held
        // is Oklab's read off the display's own primaries, which is what the
        // export does with the file's. With the rolloff on, everything is
        // already inside and this costs the one test. The heat map and the
        // unencoded mode show numbers rather than colours and are left alone.
        if (gamut_mapping == 1 && view_mode != 2 && view_mode != 4 && !in_display_gamut(lin)) {
            lin = gamut_map(linear_srgb_to_oklab(lin));
        }

        // Nothing clamps. Under clip a wide-gamut colour outside sRGB leaves
        // the matrix negative and stays negative through the mirrored encode,
        // so with the rolloff off the display clips it exactly like every
        // other out-of-range value Sara stores. With the rolloff on, gamut_map
        // already brought it inside, on the low side as well as the high.
        //
        // Mode 4 is the one that stops here. It is the display encoding
        // switched off and nothing else: everything above has run, the decode
        // out of the document's space included, so a Lab document is shown as
        // RGB like every other mode shows it and the linear number goes to the
        // screen unencoded, rather than skipping the decode as well, which
        // would put an Oklab document's L, a and b straight into R, G and B and
        // turn a blue sea red. Blender's Raw means this and not that.
        COLOR.rgb = view_mode == 4 ? lin : linear_to_srgb_mirrored(lin);
    }
    // Last and outside the block, since the screen rounds whatever reaches it,
    // the passthrough included. See dither_threshold. The heat map's bands, the
    // unencoded numbers and the shape check's blocks are flat on purpose and are
    // left to the device.
    if (view_mode != 2 && view_mode != 4 && view_mode != 5) {
        float lift = display_dither ? dither_threshold(FRAGCOORD.xy) : 0.0;
        COLOR.rgb = floor(COLOR.rgb * DISPLAY_LEVELS + 0.5 + lift) / DISPLAY_LEVELS;
    }
}
