## The view maps into gamut by an analytic intersection. The ask:
## "The analytic gamut intersection, Ottosson's, in place of `gamut_map`'s
## twelve bisection steps in `tonemap.gdshader`."
##
## A grid of Oklab colours outside the sRGB cube is written into a texture and
## run through `map_into_gamut.gmacs`, the export's pass, whose `gamut_map` the
## drift suite holds to the view's body line for line. Every mapped texel is
## compared with a bisection of chroma at the same lightness and hue, run here
## on the CPU in doubles to 30 steps, so the reference is the boundary itself
## rather than the shader's old twelve steps, which stopped within 1/4096 of the
## source chroma and near black missed by more than a display step on their
## own. The analytic answer has to sit within one 8-bit display step of the
## reference on every channel, and inside the cube.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: the mapping is the export kernel's.
const REQUIRES_GPU := true

const CHUNK := SaChunk.SIZE

## The grid: lightness from near black to near white, a hue every five degrees,
## and chroma from a little past the cube to twice the most it holds. Beyond
## that the kernel's own float32 decode loses the colour before any mapping:
## at chroma 1.5 a stored channel reaches 22, the LMS sum cancels, and the
## lightness the kernel reads is a thousandth off the one written, which moved
## the answer 2.6 display steps on its own.
const LIGHTNESSES: Array[float] = [0.01, 0.05, 0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85, 0.95, 0.99]
const HUE_STEP_DEGREES := 5
const CHROMAS: Array[float] = [0.1, 0.2, 0.3, 0.45, 0.65]

## Steps of the reference bisection, far past float's own resolution of chroma.
const REFERENCE_STEPS := 30

## The float slack of `in_display_gamut` in the shader, which the reference
## bisects to.
const GAMUT_EPSILON := 1e-5

## Its F16 slack, a share of the texel's largest channel. A
## colour inside it is never written by the kernel, so the grid leaves it out.
const GAMUT_ROUNDING := 2e-3

## One 8-bit step of the sRGB-encoded display value.
const DISPLAY_STEP := 1.0 / 255.0

## Float rounding through the kernel's decode, map and encode, well under a
## display step.
const CUBE_SLACK := 1e-4


func _grid() -> Array[Vector3]:
    var out: Array[Vector3] = []
    for lightness: float in LIGHTNESSES:
        for degrees in range(0, 360, HUE_STEP_DEGREES):
            var angle := deg_to_rad(float(degrees))
            for chroma: float in CHROMAS:
                var lab := Vector3(lightness, chroma * cos(angle), chroma * sin(angle))
                if not _left_alone(SaOklab.to_linear_srgb(lab)):
                    out.append(lab)
    return out


## Whether the shader's `in_display_gamut` passes *linear* as it is.
static func _left_alone(linear: Vector3) -> bool:
    var slack := maxf(GAMUT_EPSILON, GAMUT_ROUNDING * maxf(absf(linear.x), maxf(absf(linear.y), absf(linear.z))))
    for i in 3:
        if linear[i] < -slack or linear[i] > 1.0 + slack:
            return false
    return true


static func _in_gamut(linear: Vector3) -> bool:
    for i in 3:
        if linear[i] < -GAMUT_EPSILON or linear[i] > 1.0 + GAMUT_EPSILON:
            return false
    return true


## Chroma bisected down at *lab*'s lightness and hue, the shader's old search
## run to the boundary.
static func _bisected(lab: Vector3) -> Vector3:
    var lo := 0.0
    var hi := 1.0
    var linear := SaOklab.to_linear_srgb(Vector3(lab.x, 0.0, 0.0))
    for i in REFERENCE_STEPS:
        var mid := 0.5 * (lo + hi)
        var probe := SaOklab.to_linear_srgb(Vector3(lab.x, lab.y * mid, lab.z * mid))
        if _in_gamut(probe):
            lo = mid
            linear = probe
        else:
            hi = mid
    return linear


static func _encode(linear: float) -> float:
    var magnitude := absf(linear)
    var encoded := 12.92 * magnitude if magnitude <= 0.0031308 else 1.055 * pow(magnitude, 1.0 / 2.4) - 0.055
    return signf(linear) * encoded


static func _decode(encoded: float) -> float:
    var magnitude := absf(encoded)
    var linear := magnitude / 12.92 if magnitude < 0.04045 else pow((magnitude + 0.055) / 1.055, 2.4)
    return signf(encoded) * linear


## The grid as the sRGB-curve numbers an sRGB document stores, one colour a
## texel from the top left, and grey after the last.
func _texture(grid: Array[Vector3]) -> SaTexture:
    var texture := SaTexture.new(Vector2i(CHUNK, CHUNK))
    var texels := PackedFloat32Array()
    texels.resize(CHUNK * CHUNK * 4)
    texels.fill(0.5)
    for i in grid.size():
        var linear := SaOklab.to_linear_srgb(grid[i])
        for channel in 3:
            texels[i * 4 + channel] = _encode(linear[channel])
        texels[i * 4 + 3] = 1.0
    texture.rd.texture_update(texture.rid, 0, texels.to_byte_array())
    return texture


func test_the_grid_is_out_of_gamut_and_fits_one_texture() -> void:
    var grid := _grid()
    assert_true(grid.size() > 2000, "The grid holds %d colours outside the cube" % grid.size())
    assert_true(grid.size() <= CHUNK * CHUNK, "and they fit one texture")


func test_the_analytic_answer_is_the_bisections_within_a_display_step_and_in_gamut() -> void:
    var grid := _grid()
    var mapped := SaExportGamut.encoded_image(_texture(grid), SaColorSpace.srgb(), PackedFloat32Array(), SaGamutMapping.OKLAB)
    assert_not_null(mapped, "The export pass ran")
    if mapped == null:
        return
    var worst_step := 0.0
    var worst_at := Vector3.ZERO
    var outside := 0
    var furthest := 0.0
    for i in grid.size():
        var texel := mapped.get_pixel(i % CHUNK, floori(float(i) / CHUNK))
        var bisected := _bisected(grid[i])
        for channel in 3:
            var encoded: float = [texel.r, texel.g, texel.b][channel]
            var linear := _decode(encoded)
            var beyond := maxf(-linear, linear - 1.0)
            if beyond > CUBE_SLACK:
                outside += 1
            furthest = maxf(furthest, beyond)
            var shown := clampf(encoded, 0.0, 1.0)
            var wanted := _encode(clampf(bisected[channel], 0.0, 1.0))
            var steps := absf(shown - wanted) / DISPLAY_STEP
            if steps > worst_step:
                worst_step = steps
                worst_at = grid[i]
    assert_true(
        worst_step <= 1.0,
        (
            "Every texel is within a display step of the bisection, the worst %.3f steps at L %.2f a %.3f b %.3f"
            % [worst_step, worst_at.x, worst_at.y, worst_at.z]
        )
    )
    assert_eq(outside, 0, "and every channel is inside the cube, the furthest out by %f" % furthest)
