extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const OkhsvConversionsScript = preload("res://utils/okhsv_conversions.gd")
const OkhslConversionsScript = preload("res://utils/okhsl_conversions.gd")
const SaColorPickerScript = preload("res://ui/dockers/color/sa_color_picker.gd")


func test_okhsv_shader_compilation() -> void:
    var PickerShader := preload("res://shaders/ui/okhsv_picker.gdshader")
    assert_true(PickerShader != null, "OKHSV shader resource should load successfully")
    var mat := ShaderMaterial.new()
    mat.shader = PickerShader
    mat.set_shader_parameter("picker_mode", 0)
    mat.set_shader_parameter("current_hue", 0.5)
    assert_eq(mat.get_shader_parameter("picker_mode"), 0, "Should set parameter on OKHSV material")


## The ring carries no hue anchors and no lightness factors any more. An
## earlier version put four there, and this asserts they are gone rather than merely unused,
## because a stale uniform still set from GDScript is how a shader keeps
## answering a question nobody asks it.
func test_the_ring_has_no_anchor_parameters_left() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)

    var material: ShaderMaterial = picker.shape._ring_mat
    for gone: String in ["yellow_hue", "blue_hue", "yellow_lightness_factor", "blue_lightness_factor"]:
        assert_null(material.get_shader_parameter(gone), "%s is not a ring parameter any more" % gone)
    assert_eq(material.get_shader_parameter("picker_mode"), 0, "and the ring is still mode 0")
    dummy.free()


## The ring's rule. GDScript cannot call into a `.gdshader`,
## and `test_tonemap_view.gd` beside this one settled the same way: the look is
## proved by a capture and the arithmetic is proved here, against the twin in
## `utils/okhsv_conversions.gd`. The rule: yellow lifted well above
## the base, the hue opposite a little under it, the rest interpolated, and
## equal steps seen from above.
func test_the_ring_peaks_at_yellow_and_dips_opposite() -> void:
    var yellow: float = OkhsvConversionsScript.RING_YELLOW_HUE
    var base: float = OkhsvConversionsScript.RING_BASE_L
    assert_almost_eq(_hue_of(Color(1.0, 1.0, 0.0)), yellow, 0.001, "the peak sits at sRGB yellow's own hue")
    assert_almost_eq(OkhsvConversionsScript.ring_lightness(yellow), 0.85, 0.001, "yellow is lifted a fifth")
    assert_almost_eq(OkhsvConversionsScript.ring_lightness(yellow + 0.5), 0.58, 0.001, "the opposite dips a little")
    assert_almost_eq(
        OkhsvConversionsScript.ring_lightness(yellow + 0.25), base + 0.0325, 0.001, "the quarter points sit a hair over the base"
    )
    var previous: float = OkhsvConversionsScript.ring_lightness(yellow)
    for step: int in range(1, 361):
        var h := yellow + float(step) / 720.0
        var here: float = OkhsvConversionsScript.ring_lightness(h)
        assert_true(here <= previous + 1e-6, "falling all the way from yellow to its opposite, step %d" % step)
        previous = here
    var last: float = OkhsvConversionsScript.ring_lightness(yellow - 0.5)
    assert_almost_eq(last, previous, 1e-6, "and the same profile mirrored on the way back")


## At every hue the most chroma the gamut holds at the profile's lightness,
## which is the shape's own gamut rule, so the ring and the shapes inside it
## cannot disagree about the edge. Cyan is the floor and purple the ceiling,
## the numbers `scripts/ring_profile.py` prints. A circle from above, one
## chroma everywhere, was tried first: the gamut caps it at cyan's 0.11 and
## the pastel ring looked wrong on sight.
func test_the_ring_takes_the_gamuts_chroma_at_every_hue() -> void:
    var floor_chroma := 1.0
    var floor_at := 0.0
    var ceiling_chroma := 0.0
    var ceiling_at := 0.0
    for step: int in range(720):
        var h := float(step) / 720.0
        var lab: Vector3 = OkhslConversionsScript.ring_color_lab(h)
        var chroma := Vector2(lab.y, lab.z).length()
        var held: float = OkhslConversionsScript.gamut_chroma(cos(TAU * h), sin(TAU * h), lab.x)
        assert_almost_eq(chroma, held, 1e-6, "the gamut's own chroma at hue %f" % h)
        var rgb: Vector3 = OkhsvConversionsScript.oklab_to_linear_srgb(lab)
        for channel: float in [rgb.x, rgb.y, rgb.z]:
            assert_true(channel >= -0.005 and channel <= 1.005, "inside the gamut at hue %f: %s" % [h, rgb])
        if chroma < floor_chroma:
            floor_chroma = chroma
            floor_at = h * 360.0
        if chroma > ceiling_chroma:
            ceiling_chroma = chroma
            ceiling_at = h * 360.0
    assert_almost_eq(floor_chroma, 0.114, 0.01, "cyan is the floor")
    assert_true(absf(floor_at - 210.0) < 5.0, "at cyan's hue, not %f" % floor_at)
    assert_almost_eq(ceiling_chroma, 0.298, 0.02, "and purple the ceiling")
    assert_true(absf(ceiling_at - 308.0) < 10.0, "at purple's hue, not %f" % ceiling_at)


## The shape's chroma axis is the ring's cusp now, not Ottosson's pick, so
## the two ports of that rule have to answer the same number at every hue or the
## picker's cursor and the picker's drawing are working from different scales.
##
## The comparison is both ways round, where the one above it is one way: it says the
## ring is never *under* the axis, and this says the two are the same to a
## millionth. Before the fix they differed by 0.029 at pure blue and the difference
## was the bug.
func test_the_axis_and_the_shader_agree_on_the_cusp_at_every_hue() -> void:
    var worst := 0.0
    var worst_hue := 0.0
    for step: int in range(720):
        var h := float(step) / 720.0
        var apart: float = absf(OkhslConversionsScript.cusp_chroma(h) - _ring_cusp(h).y)
        if apart > worst:
            worst = apart
            worst_hue = h
    assert_true(worst <= 1e-6, "The two ports agree everywhere, worst %f at hue %f" % [worst, worst_hue])


## And the axis reaches the blue vertex, which is the fault fixed: a press
## on the triangle's full-chroma edge at this hue answered a washed-out blue,
## because the axis was 0.284 wide where the colour it had to reach is 0.313.
func test_the_chroma_axis_reaches_the_blue_vertex() -> void:
    var h: float = _hue_of(Color(0.0, 0.0, 1.0))
    var picked: Vector2 = OkhsvConversionsScript.find_cusp(cos(TAU * h), sin(TAU * h))
    assert_almost_eq(picked.y, 0.284, 0.002, "Ottosson's own pick is still short of the vertex")
    assert_almost_eq(OkhslConversionsScript.cusp_chroma(h), 0.313, 0.002, "and the axis the shapes are drawn against is not")

    # Through the same call the cursor and the drawing both make, and at the
    # ring cusp's own lightness rather than at the pick's: the two differ by
    # 0.044 here, and a chroma taken from one and a lightness from the other is
    # a point on neither.
    var reaching: Vector2 = OkhsvConversionsScript.ring_cusp(cos(TAU * h), sin(TAU * h))
    var at_edge: Color = OkhslConversionsScript.oklch_to_srgb(h, reaching.y, reaching.x)
    assert_almost_eq(at_edge.b, 1.0, 0.004, "The edge of the axis is blue at the top")
    assert_almost_eq(at_edge.r, 0.0, 0.006, "with no red")
    assert_almost_eq(at_edge.g, 0.0, 0.02, "and next to no green, where it once carried 0.20")


## The ring reaches pure blue at pure blue's own hue, which is the whole of why
## the ring asks all three candidates rather than taking the one Ottosson's
## half-plane tests pick. That pick answers a colour of chroma 0.284 there,
## while the blue vertex sitting at the same hue holds 0.313.
func test_the_ring_reaches_the_blue_vertex() -> void:
    var h: float = _hue_of(Color(0.0, 0.0, 1.0))
    var picked: Vector2 = OkhsvConversionsScript.find_cusp(cos(TAU * h), sin(TAU * h))
    assert_almost_eq(picked.y, 0.284, 0.002, "Ottosson's own pick is short of the vertex here")
    assert_almost_eq(_ring_cusp(h).y, 0.313, 0.002, "and the ring's rule reaches it")

    var lab := Vector3(_ring_cusp(h).x, _ring_cusp(h).y * cos(TAU * h), _ring_cusp(h).y * sin(TAU * h))
    var rgb: Vector3 = OkhsvConversionsScript.srgb_transfer_function(OkhsvConversionsScript.oklab_to_linear_srgb(lab))
    assert_almost_eq(rgb.x, 0.0, 0.004, "which in sRGB is no red")
    assert_almost_eq(rgb.y, 0.0, 0.004, "no green")
    assert_almost_eq(rgb.z, 1.0, 0.004, "and blue at the top")


## The one place the ring could not be drawn honestly. Oklab's hue folds at the
## blue vertex: the saturated edge from cyan to blue passes hue 264 degrees
## twice, so the greatest chroma that hue owns jumps. The gamut images
## record the same fold, from Ottosson's own Python, at the
## same hue. Drawn as it stands it was a hard vertical seam across the ring, so
## the ring crosses to the far candidate over the few degrees where that
## candidate is still nearly in the cube.
func test_the_ring_crosses_the_blue_fold_without_a_step() -> void:
    var raw_step := 0.0
    var raw_at := 0.0
    var ring_step := 0.0
    var ring_at := 0.0
    var previous_raw: Vector2 = _raw_cusp(0.0)
    var previous_ring: Vector2 = _ring_cusp(0.0)
    for step: int in range(1, 721):
        var h := float(step) / 720.0
        var raw: Vector2 = _raw_cusp(h)
        var ring: Vector2 = _ring_cusp(h)
        if absf(raw.y - previous_raw.y) > raw_step:
            raw_step = absf(raw.y - previous_raw.y)
            raw_at = h * 360.0
        if absf(ring.y - previous_ring.y) > ring_step:
            ring_step = absf(ring.y - previous_ring.y)
            ring_at = h * 360.0
        previous_raw = raw
        previous_ring = ring
    assert_almost_eq(raw_at, 264.0, 1.0, "The fold is at the blue vertex")
    assert_almost_eq(raw_step, 0.041, 0.005, "and the greatest chroma jumps by this much across it")
    assert_true(ring_step < 0.015, "The ring itself never steps, worst was %f at %f degrees" % [ring_step, ring_at])
    assert_almost_eq(ring_at, 262.0, 3.0, "and its steepest half degree is inside the crossing")


## The port has not drifted. Away from the fold, where Ottosson's half-plane
## tests pick the same candidate the ring keeps, the two agree to within the
## polynomial's own error. They are not identical: around hue 142 the ring
## finds a thousandth more chroma on a neighbouring candidate, which is the
## rule doing its job on a scale nobody can see.
func test_the_port_agrees_with_ottosson_away_from_the_fold() -> void:
    var worst := 0.0
    for step: int in range(720):
        var h := float(step) / 720.0
        if absf(h * 360.0 - 264.0) <= 2.0:
            continue
        var theirs: Vector2 = OkhsvConversionsScript.find_cusp(cos(TAU * h), sin(TAU * h))
        worst = maxf(worst, absf(_raw_cusp(h).y - theirs.y))
    assert_true(worst < 1e-3, "The raw locus is Ottosson's own answer away from the fold, worst was %f" % worst)


## And the crossing is spent at the fold rather than sprinkled round the wheel.
## `RING_GAIN` is what holds it there: a candidate has to reach two hundredths
## further before the ring gives up any gamut for it. Between 260 and 265
## degrees the ring gives up as much as 0.046 of chroma, which is the crossing.
## The only other place it gives up anything at all is the corner at pure red,
## 31 degrees, where the locus turns rather than folds and the ring rounds the
## turn by 0.004. Everywhere else it is the locus to a thousandth.
func test_the_crossing_is_spent_only_at_the_fold() -> void:
    var at_red := 0.0
    var elsewhere := 0.0
    for step: int in range(1440):
        var h := float(step) / 1440.0
        var degrees := h * 360.0
        if absf(degrees - 262.5) <= 3.0:
            continue
        var gap: float = absf(_ring_cusp(h).y - _raw_cusp(h).y)
        if absf(degrees - 31.0) <= 3.0:
            at_red = maxf(at_red, gap)
        else:
            elsewhere = maxf(elsewhere, gap)
    assert_almost_eq(at_red, 0.004, 0.001, "The red corner is rounded by this much")
    assert_true(elsewhere < 0.002, "and nowhere else moves, worst gap %f" % elsewhere)


static func _hue_of(color: Color) -> float:
    return OkhsvConversionsScript.srgb_to_okhsv(color).x


## The three coefficient rows of Ottosson's max-saturation polynomial, one per
## channel, each followed by the Halley step that lands it on the gamut. Red,
## then green, then blue. The shader carries the same numbers in
## `max_saturation_with`.
const SATURATION_ROWS: Array[Array] = [
    [1.19086277, 1.76576728, 0.59662641, 0.75515197, 0.56771245, 4.0767416621, -3.3077115913, 0.2309699292],
    [0.73956515, -0.45954404, 0.08285427, 0.1254107, 0.14503204, -1.2684380046, 2.6097574011, -0.3413193965],
    [1.35733652, -0.00915799, -1.1513021, -0.50559606, 0.00692167, -0.0041960863, -0.7034186147, 1.707614701],
]


static func _max_saturation_with(a: float, b: float, row: Array) -> float:
    var s: float = row[0] + row[1] * a + row[2] * b + row[3] * a * a + row[4] * a * b
    var k_l := 0.3963377774 * a + 0.2158037573 * b
    var k_m := -0.1055613458 * a - 0.0638541728 * b
    var k_s := -0.0894841775 * a - 1.291485548 * b
    var long := 1.0 + s * k_l
    var medium := 1.0 + s * k_m
    var short := 1.0 + s * k_s
    var f: float = row[5] * (long * long * long) + row[6] * (medium * medium * medium) + row[7] * (short * short * short)
    var f1: float = (
        row[5] * (3.0 * k_l * long * long) + row[6] * (3.0 * k_m * medium * medium) + row[7] * (3.0 * k_s * short * short)
    )
    var f2: float = row[5] * (6.0 * k_l * k_l * long) + row[6] * (6.0 * k_m * k_m * medium) + row[7] * (6.0 * k_s * k_s * short)
    if f1 == 0.0:
        f1 = 1e-10
    if f1 * f1 - 0.5 * f * f2 == 0.0:
        f2 = 1e-10
    return s - (f * f1) / (f1 * f1 - 0.5 * f * f2)


## The shader's two tolerances: how far outside the cube a candidate may sit and
## still be the answer, and how far outside it may sit and still be blended
## towards.
const RING_INSIDE := 0.001
const RING_REACH := 0.02
const RING_GAIN := 0.02


## One candidate, as `ring_cusp_candidate` returns it: lightness, chroma, and
## the darkest channel as a fraction of the brightest, which is negative for a
## candidate that fell outside the cube.
static func _candidate(a: float, b: float, row: Array) -> Vector3:
    var s := _max_saturation_with(a, b, row)
    var rgb: Vector3 = OkhsvConversionsScript.oklab_to_linear_srgb(Vector3(1.0, s * a, s * b))
    var brightest: float = maxf(maxf(rgb.x, rgb.y), rgb.z)
    if s <= 0.0 or brightest <= 0.0:
        return Vector3(0.0, 0.0, -1.0)
    var lightness: float = pow(1.0 / brightest, 1.0 / 3.0)
    return Vector3(lightness, lightness * s, minf(minf(rgb.x, rgb.y), rgb.z) / brightest)


## The greatest chroma any candidate reaches without leaving the cube, with no
## blending: the locus the ring would draw if the fold were drawn honestly.
static func _raw_cusp(h: float) -> Vector2:
    var a := cos(TAU * fposmod(h, 1.0))
    var b := sin(TAU * fposmod(h, 1.0))
    var best := Vector2.ZERO
    for row: Array in SATURATION_ROWS:
        var candidate := _candidate(a, b, row)
        if candidate.z >= -RING_INSIDE and candidate.y > best.y:
            best = Vector2(candidate.x, candidate.y)
    if best.y <= 0.0:
        return OkhsvConversionsScript.find_cusp(a, b)
    return best


## The port of the shader's `ring_cusp`: the raw locus, crossed towards a
## candidate that reaches further and is only just outside.
static func _ring_cusp(h: float) -> Vector2:
    var a := cos(TAU * fposmod(h, 1.0))
    var b := sin(TAU * fposmod(h, 1.0))
    var inside := _raw_cusp(h)
    var reaching := Vector3(0.0, 0.0, -1.0)
    for row: Array in SATURATION_ROWS:
        var candidate := _candidate(a, b, row)
        if candidate.z < -RING_INSIDE and candidate.z > -RING_REACH and candidate.y > reaching.y:
            reaching = candidate
    if reaching.y <= inside.y:
        return inside
    var crossing := smoothstep(-RING_REACH, -RING_INSIDE, reaching.z) * smoothstep(0.0, RING_GAIN, reaching.y - inside.y)
    return inside.lerp(Vector2(reaching.x, reaching.y), crossing)
