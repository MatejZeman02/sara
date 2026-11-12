## Utility class for exact OKHSV <-> sRGB colour conversions.
## Translated from color_conversions.py (Björn Ottosson's Oklab/Okhsv algorithms).
class_name OkhsvConversions

## Below this Oklab chroma a colour carries no direction, so the angle
## `srgb_to_okhsv` would compute from it is arithmetic noise rather than a hue.
## An exact grey measures 1e-8 here, purely from the rounding in the matrices,
## and the smallest difference a 16-bit channel can hold measures 6e-6, so this
## threshold catches every grey and no colour anyone can distinguish.
const ACHROMATIC_CHROMA: float = 1e-6

## The golden angle, 137.5 degrees, as a fraction of a turn. Repeated steps of
## it never revisit a hue and never land next to the one before, which is why
## the picker walks it when it is handed a colour with no hue of its own.
const GOLDEN_ANGLE_TURNS: float = 0.3819660112501051


## True when *color* is a grey, so nothing about it says which hue it is.
## Callers that must show a hue anyway pick one themselves rather than reading
## the zero `srgb_to_okhsv` reports.
static func is_achromatic(color: Color) -> bool:
    var lab := linear_srgb_to_oklab(srgb_transfer_function_inv(Vector3(color.r, color.g, color.b)))
    return sqrt(lab.y * lab.y + lab.z * lab.z) < ACHROMATIC_CHROMA


## The next hue after *h* in the golden-angle walk, wrapped into one turn.
static func step_hue(h: float) -> float:
    return fposmod(h + GOLDEN_ANGLE_TURNS, 1.0)


static func _cbrt(x: float) -> float:
    if x == 0.0:
        return 0.0
    if x > 0.0:
        return pow(x, 1.0 / 3.0)
    return -pow(-x, 1.0 / 3.0)


static func channel_rgb_to_srgb(c: float) -> float:
    if c <= 0.0031308:
        return 12.92 * c
    return 1.055 * pow(c, 1.0 / 2.4) - 0.055


static func srgb_transfer_function(rgb: Vector3) -> Vector3:
    return Vector3(channel_rgb_to_srgb(rgb.x), channel_rgb_to_srgb(rgb.y), channel_rgb_to_srgb(rgb.z))


static func channel_srgb_to_rgb(c: float) -> float:
    if c > 0.04045:
        return pow((c + 0.055) / 1.055, 2.4)
    return c / 12.92


static func srgb_transfer_function_inv(srgb: Vector3) -> Vector3:
    return Vector3(channel_srgb_to_rgb(srgb.x), channel_srgb_to_rgb(srgb.y), channel_srgb_to_rgb(srgb.z))


static func linear_srgb_to_oklab(rgb: Vector3) -> Vector3:
    if rgb.x == 0.0 and rgb.y == 0.0 and rgb.z == 0.0:
        return Vector3.ZERO

    var lms_l := 0.4122214708 * rgb.x + 0.5363325363 * rgb.y + 0.0514459929 * rgb.z
    var lms_m := 0.2119034982 * rgb.x + 0.6806995451 * rgb.y + 0.1073969566 * rgb.z
    var lms_s := 0.0883024619 * rgb.x + 0.2817188376 * rgb.y + 0.6299787005 * rgb.z

    var l_val := _cbrt(lms_l)
    var m_val := _cbrt(lms_m)
    var s_val := _cbrt(lms_s)

    var lightness := 0.2104542553 * l_val + 0.793617785 * m_val - 0.0040720468 * s_val
    var a := 1.9779984951 * l_val - 2.428592205 * m_val + 0.4505937099 * s_val
    var b := 0.0259040371 * l_val + 0.7827717662 * m_val - 0.808675766 * s_val

    return Vector3(lightness, a, b)


static func oklab_to_linear_srgb(lab: Vector3) -> Vector3:
    if lab.x == 0.0 and lab.y == 0.0 and lab.z == 0.0:
        return Vector3.ZERO

    var l_val := 1.0 * lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
    var m_val := 1.0 * lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
    var s_val := 1.0 * lab.x - 0.0894841775 * lab.y - 1.291485548 * lab.z

    var l := l_val * l_val * l_val
    var m := m_val * m_val * m_val
    var s := s_val * s_val * s_val

    var r := 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    var g := -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    var b := -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s

    return Vector3(r, g, b)


static func toe(x: float) -> float:
    var k_1 := 0.206
    var k_2 := 0.03
    var k_3 := (1.0 + k_1) / (1.0 + k_2)
    return 0.5 * (k_3 * x - k_1 + sqrt((k_3 * x - k_1) * (k_3 * x - k_1) + 4.0 * k_2 * k_3 * x))


static func toe_inv(x: float) -> float:
    var k_1 := 0.206
    var k_2 := 0.03
    var k_3 := (1.0 + k_1) / (1.0 + k_2)
    return (x * x + k_1 * x) / (k_3 * (x + k_2))


static func compute_max_saturation(a: float, b: float) -> float:
    var k0: float
    var k1: float
    var k2: float
    var k3: float
    var k4: float
    var wl: float
    var wm: float
    var ws: float

    if -1.88170328 * a - 0.80936493 * b > 1.0:
        k0 = 1.19086277
        k1 = 1.76576728
        k2 = 0.59662641
        k3 = 0.75515197
        k4 = 0.56771245
        wl = 4.0767416621
        wm = -3.3077115913
        ws = 0.2309699292
    elif 1.81444104 * a - 1.19445276 * b > 1.0:
        k0 = 0.73956515
        k1 = -0.45954404
        k2 = 0.08285427
        k3 = 0.1254107
        k4 = 0.14503204
        wl = -1.2684380046
        wm = 2.6097574011
        ws = -0.3413193965
    else:
        k0 = 1.35733652
        k1 = -0.00915799
        k2 = -1.1513021
        k3 = -0.50559606
        k4 = 0.00692167
        wl = -0.0041960863
        wm = -0.7034186147
        ws = 1.707614701

    var saturation := k0 + k1 * a + k2 * b + k3 * a * a + k4 * a * b

    var k_l := 0.3963377774 * a + 0.2158037573 * b
    var k_m := -0.1055613458 * a - 0.0638541728 * b
    var k_s := -0.0894841775 * a - 1.291485548 * b

    var l_val := 1.0 + saturation * k_l
    var m_val := 1.0 + saturation * k_m
    var s_val := 1.0 + saturation * k_s

    var l := l_val * l_val * l_val
    var m := m_val * m_val * m_val
    var s := s_val * s_val * s_val

    var l_ds := 3.0 * k_l * l_val * l_val
    var m_ds := 3.0 * k_m * m_val * m_val
    var s_ds := 3.0 * k_s * s_val * s_val

    var l_ds2 := 6.0 * k_l * k_l * l_val
    var m_ds2 := 6.0 * k_m * k_m * m_val
    var s_ds2 := 6.0 * k_s * k_s * s_val

    var f := wl * l + wm * m + ws * s
    var f1 := wl * l_ds + wm * m_ds + ws * s_ds
    var f2 := wl * l_ds2 + wm * m_ds2 + ws * s_ds2

    if f1 == 0.0:
        f1 = 1e-10
    if f1 * f1 - 0.5 * f * f2 == 0.0:
        f2 = 1e-10

    saturation = saturation - (f * f1) / (f1 * f1 - 0.5 * f * f2)
    return saturation


static func find_cusp(a: float, b: float) -> Vector2:
    var s_cusp := compute_max_saturation(a, b)
    var rgb_at_max := oklab_to_linear_srgb(Vector3(1.0, s_cusp * a, s_cusp * b))
    var max_rgb := maxf(maxf(rgb_at_max.x, rgb_at_max.y), rgb_at_max.z)
    if max_rgb <= 0.0:
        max_rgb = 1e-10
    var l_cusp := _cbrt(1.0 / max_rgb)
    var c_cusp := l_cusp * s_cusp
    return Vector2(l_cusp, c_cusp)


## How far outside the sRGB cube a candidate cusp may sit and still count as
## being on the boundary. Ottosson's solve lands a hair either side of it, so a
## candidate that is exactly the cusp reports a thousandth of a channel outside
## as often as it reports zero.
const RING_INSIDE: float = 0.001

## And how far outside one may sit and still be blended towards, which is what
## carries the answer across the fold at blue.
const RING_REACH: float = 0.02

## How much more chroma an outside candidate has to reach before the blend
## starts at all, so it does not fire where there is no fold to cross.
const RING_GAIN: float = 0.02

## The three coefficient sets [method compute_max_saturation] chooses between,
## each with the weights of the channel it is the limit for. Written out because
## the cusp has to ask all three rather than take the one a pair of half-plane
## tests picks.
const SATURATION_ROWS: Array = [
    [1.19086277, 1.76576728, 0.59662641, 0.75515197, 0.56771245, 4.0767416621, -3.3077115913, 0.2309699292],
    [0.73956515, -0.45954404, 0.08285427, 0.1254107, 0.14503204, -1.2684380046, 2.6097574011, -0.3413193965],
    [1.35733652, -0.00915799, -1.1513021, -0.50559606, 0.00692167, -0.0041960863, -0.7034186147, 1.707614701],
]


## The cusp at the hue the unit vector (*a*, *b*) points at, asking every
## candidate rather than the one Ottosson's half-plane tests pick.
##
## This is the GDScript twin of `ring_cusp` in
## `shaders/ui/okhsv_picker.gdshader`, and `ui/dockers/color/tests/test_okhsv_shader.gd` holds a
## third port that checks the two have not drifted. Two things happen here that
## [method find_cusp] does not do, both about the same place on the wheel.
##
## **The pick is wrong at blue.** `compute_max_saturation`'s two tests both land
## within two millionths of their threshold at pure blue's own hue, so a hair
## either side of 264.05 degrees decides which channel is taken as the limit:
## the red-limited set answers a chroma of 0.284 where the blue-limited one
## answers 0.313, and the vertex holds 0.313. The wrong pick is what drew
## (2, 60, 255) where the gamut has (0, 0, 255), and on the picker's own shapes
## it made the chroma axis jump by a ninth over a thousandth of a hue.
##
## **And the maximum genuinely jumps.** Oklab's hue is not monotonic along the
## saturated edge from cyan to blue: that edge passes 264 degrees twice, so two
## points of the locus share a hue and the greater of them jumps by 0.041 across
## a hundredth of a degree. Drawn honestly that is a seam. So the answer crosses
## to the far candidate over the few degrees where it is still nearly inside the
## cube, which costs at most 0.046 of chroma between 260 and 265 degrees and
## nothing anywhere else.
static func ring_cusp(a: float, b: float) -> Vector2:
    var inside := Vector2.ZERO
    var reaching := Vector3(0.0, 0.0, -1.0)
    for row: Array in SATURATION_ROWS:
        var candidate := _cusp_candidate(a, b, _saturation_with(a, b, row))
        if candidate.z >= -RING_INSIDE:
            if candidate.y > inside.y:
                inside = Vector2(candidate.x, candidate.y)
        elif candidate.z > -RING_REACH and candidate.y > reaching.y:
            reaching = candidate
    if inside.y <= 0.0:
        inside = find_cusp(a, b)
    if reaching.y <= inside.y:
        return inside
    var crossing := smoothstep(-RING_REACH, -RING_INSIDE, reaching.z) * smoothstep(0.0, RING_GAIN, reaching.y - inside.y)
    return inside.lerp(Vector2(reaching.x, reaching.y), crossing)


## The ring's lightness, the twin of `ring_lightness` in
## `shaders/ui/okhsv_picker.gdshader`: a profile that peaks at yellow, dips at
## the hue opposite and sits a hair over `RING_BASE_L` at the quarter points, the
## two bumps squared cosines. The chroma at each hue is the most the gamut
## holds at that lightness, [method OkhslConversions.ring_color_lab], from
## 0.11 at cyan to 0.30 at purple by `scripts/ring_profile.py`.
const RING_BASE_L: float = 0.65
const RING_LIFT_AT_YELLOW: float = 0.20
const RING_DIP_OPPOSITE: float = 0.07
## sRGB yellow's own Oklab hue, 109.8 degrees, as a fraction of the turn.
const RING_YELLOW_HUE: float = 0.30494


static func ring_lightness(h: float) -> float:
    var c := cos(TAU * (fposmod(h, 1.0) - RING_YELLOW_HUE))
    var towards_yellow := (1.0 + c) * 0.5
    var away := (1.0 - c) * 0.5
    return RING_BASE_L + RING_LIFT_AT_YELLOW * towards_yellow * towards_yellow - RING_DIP_OPPOSITE * away * away


## One candidate cusp from one coefficient set: the point that saturation
## reaches, scaled so the brightest channel sits exactly at 1. `z` is the
## darkest channel as a fraction of the brightest, which is how far outside the
## cube the candidate fell and is negative when it fell outside at all.
static func _cusp_candidate(a: float, b: float, saturation: float) -> Vector3:
    var rgb := oklab_to_linear_srgb(Vector3(1.0, saturation * a, saturation * b))
    var max_rgb := maxf(maxf(rgb.x, rgb.y), rgb.z)
    if saturation <= 0.0 or max_rgb <= 0.0:
        return Vector3(0.0, 0.0, -1.0)
    var lightness := _cbrt(1.0 / max_rgb)
    return Vector3(lightness, lightness * saturation, minf(minf(rgb.x, rgb.y), rgb.z) / max_rgb)


## [method compute_max_saturation] with the coefficient set handed in rather
## than chosen, so all three can be asked.
static func _saturation_with(a: float, b: float, row: Array) -> float:
    var saturation: float = row[0] + row[1] * a + row[2] * b + row[3] * a * a + row[4] * a * b
    var k_l := 0.3963377774 * a + 0.2158037573 * b
    var k_m := -0.1055613458 * a - 0.0638541728 * b
    var k_s := -0.0894841775 * a - 1.291485548 * b
    var l_val := 1.0 + saturation * k_l
    var m_val := 1.0 + saturation * k_m
    var s_val := 1.0 + saturation * k_s
    var l := l_val * l_val * l_val
    var m := m_val * m_val * m_val
    var s := s_val * s_val * s_val
    var wl: float = row[5]
    var wm: float = row[6]
    var ws: float = row[7]
    var f := wl * l + wm * m + ws * s
    var f1 := wl * 3.0 * k_l * l_val * l_val + wm * 3.0 * k_m * m_val * m_val + ws * 3.0 * k_s * s_val * s_val
    var f2 := wl * 6.0 * k_l * k_l * l_val + wm * 6.0 * k_m * k_m * m_val + ws * 6.0 * k_s * k_s * s_val
    if f1 == 0.0:
        f1 = 1e-10
    var divisor := f1 * f1 - 0.5 * f * f2
    if divisor == 0.0:
        divisor = 1e-10
    return saturation - (f * f1) / divisor


static func get_st_max(a: float, b: float) -> Vector2:
    var cusp := find_cusp(a, b)
    var lightness := cusp.x
    if lightness >= 1.0:
        lightness = 1.0 - 1e-10
    if lightness <= 0.0:
        lightness = 1e-10
    var chroma := cusp.y
    return Vector2(chroma / lightness, chroma / (1.0 - lightness))


static func okhsv_to_srgb(h: float, s: float, v: float) -> Color:
    h = fmod(h, 1.0)
    if h < 0.0:
        h += 1.0
    s = clampf(s, 0.0, 1.0)
    v = clampf(v, 0.0, 1.0)

    var a_val := cos(2.0 * PI * h)
    var b_val := sin(2.0 * PI * h)

    var st_max := get_st_max(a_val, b_val)
    var s_max := st_max.x
    var s_0 := 0.5
    var temperature := st_max.y
    var k := 1.0 - s_0 / s_max

    var l_v := 1.0 - (s * s_0) / (s_0 + temperature - temperature * k * s)
    var c_v := (s * temperature * s_0) / (s_0 + temperature - temperature * k * s)

    var lightness := v * l_v
    var chroma := v * c_v

    var l_vt := toe_inv(l_v)
    if l_v == 0.0:
        l_v = 1e-10
    var c_vt := (c_v * l_vt) / l_v

    var l_new := toe_inv(lightness)
    if lightness == 0.0:
        lightness = 1e-10
    chroma = (chroma * l_new) / lightness
    lightness = l_new

    var rgb_scale := oklab_to_linear_srgb(Vector3(l_vt, a_val * c_vt, b_val * c_vt))
    var max_scale := maxf(maxf(rgb_scale.x, rgb_scale.y), maxf(rgb_scale.z, 0.0))
    if max_scale <= 0.0:
        max_scale = 1e-10
    var scale_l := _cbrt(1.0 / max_scale)

    lightness = lightness * scale_l
    chroma = chroma * scale_l

    var rgb_lin := oklab_to_linear_srgb(Vector3(lightness, chroma * a_val, chroma * b_val))
    var srgb := srgb_transfer_function(rgb_lin)
    return Color(clampf(srgb.x, 0.0, 1.0), clampf(srgb.y, 0.0, 1.0), clampf(srgb.z, 0.0, 1.0), 1.0)


static func srgb_to_okhsv(color: Color) -> Vector3:
    var rgb := Vector3(color.r, color.g, color.b)
    if rgb.x == 0.0 and rgb.y == 0.0 and rgb.z == 0.0:
        return Vector3(0.0, 0.0, 0.0)

    var rgb_lin := srgb_transfer_function_inv(rgb)
    var lab := linear_srgb_to_oklab(rgb_lin)

    var chroma := sqrt(lab.y * lab.y + lab.z * lab.z)
    var achromatic := chroma < ACHROMATIC_CHROMA
    if chroma == 0.0:
        chroma = 1e-10
    var a_val := lab.y / chroma
    var b_val := lab.z / chroma

    var lightness := lab.x
    # A grey is reported as hue zero rather than as the angle of its rounding
    # error. The two normalized components above stay as they are, because the
    # saturation and value below are computed through them and a grey drives
    # them to a degenerate cusp when they are forced to zero.
    var h := 0.0 if achromatic else 0.5 + (0.5 * atan2(-lab.z, -lab.y)) / PI

    var st_max := get_st_max(a_val, b_val)
    var s_max := st_max.x
    var s_0 := 0.5
    var temperature := st_max.y
    var k := 1.0 - s_0 / s_max

    var t := temperature / (chroma + lightness * temperature)
    var l_v := t * lightness
    var c_v := t * chroma

    var l_vt := toe_inv(l_v)
    if l_v == 0.0:
        l_v = 1e-10
    var c_vt := (c_v * l_vt) / l_v

    var rgb_scale := oklab_to_linear_srgb(Vector3(l_vt, a_val * c_vt, b_val * c_vt))
    var max_scale := maxf(maxf(rgb_scale.x, rgb_scale.y), maxf(rgb_scale.z, 0.0))
    if max_scale <= 0.0:
        max_scale = 1e-10
    var scale_l := pow(1.0 / max_scale, 1.0 / 3.0)

    lightness /= scale_l
    chroma /= scale_l

    if lightness == 0.0:
        lightness = 1e-10
    chroma = (chroma * toe(lightness)) / lightness
    lightness = toe(lightness)

    var v := lightness / l_v if l_v != 0.0 else 0.0
    var denom := temperature * s_0 + temperature * k * c_v
    var s := ((s_0 + temperature) * c_v) / denom if denom != 0.0 else 0.0

    return Vector3(fmod(h, 1.0), clampf(s, 0.0, 1.0), clampf(v, 0.0, 1.0))
