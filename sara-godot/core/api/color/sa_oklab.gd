## Oklab, as coordinates rather than as a colour space.
##
## Oklab is not a colour space in `SaColorSpace`'s sense and never will be. It has
## no primaries and no gamut: it is a *coordinate system*, gamut-independent and
## perceptually uniform, reached from linear sRGB by two fixed matrices with a
## cube root between them. That is why it does not fit the descriptor's four axes
## and why it gets its own file.
##
## Deliberate twin of `shaders/compute/libs/oklab_color_space.gmacs` and of the
## same matrices in `shaders/canvas/tonemap.gdshader`, whose forward half
## `shaders/ui/grey_veil.gdshader` holds as well. GDScript cannot include a
## `.gmacs` and a `.gdshader` cannot either, so this is one copy of four on
## purpose: change one and change all four. The suite compares this against the
## kernel's own answers, which is what keeps the copies honest.
##
## Signs are carried around the cube root and the cube. `pow` of a negative base
## is undefined, and blending and wide-gamut colours produce negative LMS all the
## time, so the magnitude goes through the curve and the sign is put back.
@tool
class_name SaOklab
extends RefCounted


## Linear sRGB to LMS. Columns, which is what a Godot Basis and a GLSL mat3 both
## take, so this is the literal transcription of the kernel's matrix.
static func _srgb_to_lms() -> Basis:
    return Basis(
        Vector3(0.4122214708, 0.2119034982, 0.0883024619),
        Vector3(0.5363325363, 0.6806995451, 0.2817188376),
        Vector3(0.0514459929, 0.1073969566, 0.6299787005)
    )


static func _lms_to_oklab() -> Basis:
    return Basis(
        Vector3(0.2104542553, 1.9779984951, 0.0259040371),
        Vector3(0.7936177850, -2.4285922050, 0.7827717662),
        Vector3(-0.0040720468, 0.4505937099, -0.8086757660)
    )


static func _oklab_to_lms() -> Basis:
    return Basis(
        Vector3(1.0, 1.0, 1.0),
        Vector3(0.3963377774, -0.1055613458, -0.0894841775),
        Vector3(0.2158037573, -0.0638541728, -1.2914855480)
    )


static func _lms_to_srgb() -> Basis:
    return Basis(
        Vector3(4.0767416621, -1.2684380046, -0.0041960863),
        Vector3(-3.3077115913, 2.6097574011, -0.7034186147),
        Vector3(0.2309699292, -0.3413193965, 1.7076147010)
    )


## Cube root that keeps the sign, because negative LMS is ordinary here.
static func _signed_cbrt(v: Vector3) -> Vector3:
    return Vector3(
        signf(v.x) * pow(absf(v.x), 1.0 / 3.0), signf(v.y) * pow(absf(v.y), 1.0 / 3.0), signf(v.z) * pow(absf(v.z), 1.0 / 3.0)
    )


## Light-linear sRGB to Oklab (L, a, b).
static func from_linear_srgb(linear: Vector3) -> Vector3:
    return _lms_to_oklab() * _signed_cbrt(_srgb_to_lms() * linear)


## Oklab (L, a, b) back to light-linear sRGB.
##
## An odd power preserves the sign, so no sign dance is needed on the way back.
static func to_linear_srgb(lab: Vector3) -> Vector3:
    var lms: Vector3 = _oklab_to_lms() * lab
    return _lms_to_srgb() * Vector3(lms.x * lms.x * lms.x, lms.y * lms.y * lms.y, lms.z * lms.z * lms.z)


## Oklab in the polar form the non-separable blend modes use: lightness, chroma
## and hue angle. Hue is what a painter picked and is never rotated, so having it
## as its own number is what lets chroma move without dragging it.
static func to_polar(lab: Vector3) -> Vector3:
    var chroma := Vector2(lab.y, lab.z).length()
    # atan2(0, 0) is undefined, so an achromatic colour gets hue 0.
    var hue := atan2(lab.z, lab.y) if chroma > 1e-6 else 0.0
    return Vector3(lab.x, chroma, hue)


static func from_polar(lch: Vector3) -> Vector3:
    return Vector3(lch.x, lch.y * cos(lch.z), lch.y * sin(lch.z))


## The slack on the cube's faces, the same 1e-9 `scripts/gen_gamut_images.py`
## uses, so the two agree on where the boundary is.
const GAMUT_TOLERANCE := 1e-9


## How far outside the unit cube *linear* sits, as the largest single overshoot,
## and at most zero for a colour the display can show.
static func gamut_overshoot(linear: Vector3) -> float:
    var over := maxf(maxf(linear.x, linear.y), linear.z) - 1.0
    var under := -minf(minf(linear.x, linear.y), linear.z)
    return maxf(over, under) - GAMUT_TOLERANCE


## The six edges of the RGB cube, in the order red, yellow, green, cyan, blue,
## magenta. Each is the edge where one channel is pinned at 1 and another at 0,
## and between them they carry every maximally saturated colour there is.
const _CUBE_EDGES: Array = [
    [Vector3(1, 0, 0), Vector3(0, 1, 0)],
    [Vector3(1, 1, 0), Vector3(-1, 0, 0)],
    [Vector3(0, 1, 0), Vector3(0, 0, 1)],
    [Vector3(0, 1, 1), Vector3(0, -1, 0)],
    [Vector3(0, 0, 1), Vector3(1, 0, 0)],
    [Vector3(1, 0, 1), Vector3(0, 0, -1)],
]


## Each hue column's cusp, its highest-chroma colour, as (lightness, chroma, hue).
##
## The hue rides along rather than being implied by the column, because a cusp
## is the maximum over a column and sits at whatever hue inside it the cube's
## edge reached. Reading the column's own left edge back instead overstates the
## chroma by up to a column's width of hue, which near blue is 0.028 of chroma
## and comes out of a picture as one clamped stripe.
##
## The loop method, ported from `scripts/gen_gamut_images.py`. Never bisect
## chroma in Oklab to find this: a ray of constant lightness towards blue leaves
## the cube by 0.0007 and comes back, so a search stops early and cuts pure blue
## out of whatever is being drawn. Walking the cube's own saturated edges is
## exact instead, and there is nothing to converge.
##
## Nor is it an interpolation of the loop sorted by hue. Two cube edges reach the
## same Oklab hue near blue, so the loop doubles back there and a sorted list
## interleaves a 0.313 chroma branch with a 0.287 one. A maximum per column picks
## the larger, which is the cusp, and an interpolation averages the two away.
##
## Public here rather than private to a caller because `gamut_map` in
## `shaders/canvas/tonemap.gdshader` solves for the same boundary per texel and
## the Oklab blend modes bisect for it, so the cusp wants one home.
static func gamut_cusps(columns: int, per_edge: int = 1200) -> PackedVector3Array:
    var out := PackedVector3Array()
    out.resize(columns)
    for edge: Array in _CUBE_EDGES:
        var start: Vector3 = edge[0]
        var direction: Vector3 = edge[1]
        for step in per_edge:
            var lab := from_linear_srgb(start + direction * (float(step) / float(per_edge)))
            var polar := to_polar(lab)
            var hue := fposmod(polar.z, TAU)
            var column := int(hue * float(columns) / TAU) % columns
            if polar.y > out[column].y:
                out[column] = Vector3(polar.x, polar.y, hue)
    for column in columns:
        if out[column].y <= 0.0:
            push_error("SaOklab: hue column %d holds no cube-edge sample, raise per_edge" % column)
    return out


## The lightest in-gamut lightness at *chroma* and *hue*, so a picture of a hue
## can ride the real gamut boundary rather than a straight line towards white.
##
## Bisecting lightness is sound where bisecting chroma is not: the in-gamut set
## along this ray is an interval with the cusp's lightness at one end, so the
## floor is in gamut for every chroma the cusp reaches and 1.0 is out for every
## chroma above zero.
static func max_lightness(chroma: float, hue: float, floor_lightness: float, steps: int = 12) -> float:
    var low := floor_lightness
    var high := 1.0
    var cos_hue := cos(hue)
    var sin_hue := sin(hue)
    for _step in steps:
        var mid := 0.5 * (low + high)
        if gamut_overshoot(to_linear_srgb(Vector3(mid, chroma * cos_hue, chroma * sin_hue))) <= 0.0:
            low = mid
        else:
            high = mid
    return low
