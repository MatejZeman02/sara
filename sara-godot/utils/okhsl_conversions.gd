## Sara's own OKHSL and OKLCh conversions, for the two picker shapes that read
## them.
##
## Beside [OkhsvConversions] rather than in it, because that file is Björn
## Ottosson's OKHSV translated line for line and this one is not a translation:
## the saturation here is the plain fraction of the chroma the hue can reach at
## that lightness, without the mid-chroma curve Ottosson's `okhsl` bends the
## scale with. The note asked for a custom ok-hsl rather than a built-in one,
## and a definition that can be stated in a sentence is worth more in a picker
## than one that matches a reference implementation nobody reads.
##
## Two models live here, and the pickers use one each:
##
## - **OKHSL**, hue and a saturation normalized to the gamut, so the square is
##   full at every lightness. `l` is the toe-mapped lightness, which is what
##   makes the vertical axis look evenly spaced.
## - **OKLCh**, hue and the chroma itself, so the region a hue can reach is the
##   triangle it actually is in Oklab: black at the bottom, white at the top and
##   the cusp out to the right. `lightness` here is Oklab's own L, untoed,
##   because toeing it bends the two straight gamut edges into curves and the
##   shape stops being a triangle.
##
## Everything below the two entry points is shared with the shader that draws
## the same shapes, `shaders/ui/okhsv_picker.gdshader`, which carries the same
## functions in GLSL. A number changed here has to change there too, which
## `utils/tests/test_okhsl_conversions.gd` is not able to check, so the shader's
## modes are proved by a capture instead.
class_name OkhslConversions

const OkhsvConversionsScript = preload("res://utils/okhsv_conversions.gd")

## The widest chroma sRGB reaches in Oklab, at any hue and any lightness, with
## a little room over it. `test_okhsl_conversions.gd` sweeps the hues and fails
## if one ever exceeds it.
##
## It is not the triangle's right edge, though one scale for every hue would
## let the shapes be compared between hues: swept over 360 hues the cusp runs
## from 0.145 at hue 0.594 to 0.322 at hue 0.911, so a cyan triangle would be
## drawn across 44 per cent of its frame and a magenta one across 98. The
## triangle uses [method cusp_chroma], and this is the ceiling, which is the
## number a shape that does want one scale for every hue would take.
const SRGB_MAX_CHROMA: float = 0.33


## The largest chroma the sRGB gamut holds at *h* turns anywhere on its
## lightness axis, which is the chroma at its cusp.
##
## The triangle is normalized by this rather than by [constant SRGB_MAX_CHROMA]:
## one constant for every hue would draw a magenta triangle across 98 per cent
## of its frame and a cyan one across 44, a triangle too small to work in. The
## cost is that the horizontal axis means a different chroma at each hue, so a
## colour has to be read back through the same call or the cursor lands
## somewhere else. Through
## [method OkhsvConversions.ring_cusp] rather than
## [method OkhsvConversions.find_cusp]: the half-plane tests pick the wrong
## coefficient set at pure blue's own hue and answer 0.284 where the vertex
## holds 0.313, so the triangle's full-chroma edge stopped a ninth short there
## and pure blue was not reachable from any shape by gesture.
static func cusp_chroma(h: float) -> float:
    var angle := 2.0 * PI * fposmod(h, 1.0)
    return OkhsvConversionsScript.ring_cusp(cos(angle), sin(angle)).y


## The largest chroma the sRGB gamut holds at Oklab lightness *lightness*, for
## the hue the unit vector (*a*, *b*) points at.
##
## Ottosson's `find_gamut_intersection` with the lightness fixed: a first guess
## from the two straight lines through the cusp, then one Halley step per
## channel when the guess is above the cusp, where the gamut's edge is not
## quite straight. The hue ring's colour at *h* as Oklab: the profile's
## lightness and the most chroma this gamut rule holds there, the twin of the
## shader's `ring_color`, which a suite reads to say the ring is inside the
## gamut at every hue and which hues sit at its floor and its ceiling.
static func ring_color_lab(h: float) -> Vector3:
    var angle := TAU * fposmod(h, 1.0)
    var lightness: float = OkhsvConversionsScript.ring_lightness(h)
    var chroma := gamut_chroma(cos(angle), sin(angle), lightness)
    return Vector3(lightness, chroma * cos(angle), chroma * sin(angle))


static func gamut_chroma(a: float, b: float, lightness: float) -> float:
    # The same cusp the axis is normalized by. A reach measured against one cusp
    # and an axis scaled by another disagree at blue, and the cursor then rides
    # an edge the drawing does not have.
    var cusp := OkhsvConversionsScript.ring_cusp(a, b)
    if lightness <= 0.0 or lightness >= 1.0:
        return 0.0
    if lightness <= cusp.x:
        return lightness * (cusp.y / cusp.x) if cusp.x > 0.0 else 0.0

    var t := cusp.y * (1.0 - lightness) / (1.0 - cusp.x)
    var k_l := 0.3963377774 * a + 0.2158037573 * b
    var k_m := -0.1055613458 * a - 0.0638541728 * b
    var k_s := -0.0894841775 * a - 1.291485548 * b
    var l_root := lightness + t * k_l
    var m_root := lightness + t * k_m
    var s_root := lightness + t * k_s
    var l := l_root * l_root * l_root
    var m := m_root * m_root * m_root
    var s := s_root * s_root * s_root
    var ldt := 3.0 * k_l * l_root * l_root
    var mdt := 3.0 * k_m * m_root * m_root
    var sdt := 3.0 * k_s * s_root * s_root
    var ldt2 := 6.0 * k_l * k_l * l_root
    var mdt2 := 6.0 * k_m * k_m * m_root
    var sdt2 := 6.0 * k_s * k_s * s_root

    var red := _halley_step(
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s - 1.0,
        4.0767416621 * ldt - 3.3077115913 * mdt + 0.2309699292 * sdt,
        4.0767416621 * ldt2 - 3.3077115913 * mdt2 + 0.2309699292 * sdt2
    )
    var green := _halley_step(
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s - 1.0,
        -1.2684380046 * ldt + 2.6097574011 * mdt - 0.3413193965 * sdt,
        -1.2684380046 * ldt2 + 2.6097574011 * mdt2 - 0.3413193965 * sdt2
    )
    var blue := _halley_step(
        -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s - 1.0,
        -0.0041960863 * ldt - 0.7034186147 * mdt + 1.707614701 * sdt,
        -0.0041960863 * ldt2 - 0.7034186147 * mdt2 + 1.707614701 * sdt2
    )
    return maxf(t + minf(red, minf(green, blue)), 0.0)


## One channel's Halley correction, or a number no `min` will pick when the
## channel is already inside the gamut and the step would point backwards.
static func _halley_step(value: float, first: float, second: float) -> float:
    var denominator := first * first - 0.5 * value * second
    if denominator == 0.0:
        return 1e5
    var u := first / denominator
    if u < 0.0:
        return 1e5
    return -value * u


## The sRGB colour at hue *h* turns, saturation *s* and lightness *l*, all
## 0 to 1. Saturation is the fraction of the chroma this hue reaches at this
## lightness, so the whole square is in gamut at every lightness.
static func okhsl_to_srgb(h: float, s: float, l: float) -> Color:
    l = clampf(l, 0.0, 1.0)
    s = clampf(s, 0.0, 1.0)
    var lightness := OkhsvConversionsScript.toe_inv(l)
    var angle := 2.0 * PI * fposmod(h, 1.0)
    var a := cos(angle)
    var b := sin(angle)
    return _oklab_to_color(lightness, s * gamut_chroma(a, b, lightness), a, b)


## What *color* is in the model above: hue, saturation, lightness, each 0 to 1.
## A grey reports hue zero, the way [method OkhsvConversions.srgb_to_okhsv]
## does, and the caller decides what hue to show for it.
static func srgb_to_okhsl(color: Color) -> Vector3:
    var lch := srgb_to_oklch(color)
    var angle := 2.0 * PI * lch.x
    var reachable := gamut_chroma(cos(angle), sin(angle), lch.z)
    var s := clampf(lch.y / reachable, 0.0, 1.0) if reachable > 0.0 else 0.0
    return Vector3(lch.x, s, OkhsvConversionsScript.toe(lch.z))


## The sRGB colour at hue *h* turns, Oklab chroma *chroma* and Oklab lightness
## *lightness*. Out-of-gamut chroma is pulled back to the edge rather than
## clipped per channel, so a press outside the triangle lands on the nearest
## colour of the same lightness rather than on a hue the ring is not showing.
static func oklch_to_srgb(h: float, chroma: float, lightness: float) -> Color:
    lightness = clampf(lightness, 0.0, 1.0)
    var angle := 2.0 * PI * fposmod(h, 1.0)
    var a := cos(angle)
    var b := sin(angle)
    return _oklab_to_color(lightness, minf(maxf(chroma, 0.0), gamut_chroma(a, b, lightness)), a, b)


## What *color* is in the model above: hue in turns, Oklab chroma, Oklab
## lightness. Unclamped chroma, because what a caller divides it by is the
## caller's business: the triangle uses [method cusp_chroma] and a shape that
## wanted one scale for every hue would use [constant SRGB_MAX_CHROMA].
static func srgb_to_oklch(color: Color) -> Vector3:
    var lab := OkhsvConversionsScript.linear_srgb_to_oklab(
        OkhsvConversionsScript.srgb_transfer_function_inv(Vector3(color.r, color.g, color.b))
    )
    var chroma := sqrt(lab.y * lab.y + lab.z * lab.z)
    var h := 0.0 if chroma < OkhsvConversionsScript.ACHROMATIC_CHROMA else fposmod(atan2(lab.z, lab.y) / (2.0 * PI), 1.0)
    return Vector3(h, chroma, lab.x)


static func _oklab_to_color(lightness: float, chroma: float, a: float, b: float) -> Color:
    var srgb := OkhsvConversionsScript.srgb_transfer_function(
        OkhsvConversionsScript.oklab_to_linear_srgb(Vector3(lightness, chroma * a, chroma * b))
    )
    return Color(clampf(srgb.x, 0.0, 1.0), clampf(srgb.y, 0.0, 1.0), clampf(srgb.z, 0.0, 1.0), 1.0)
