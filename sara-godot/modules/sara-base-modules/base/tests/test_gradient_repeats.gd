## The gradient's repeat modes and its wobble.
##
## The repeat options come with more wobbles, like playing with Voronoi or noise
## textures in Blender shaders.
##
## Every one of these reads texels back off the canvas rather than checking that
## an enum reached a push constant, because the whole of a repeat mode is what
## the picture does past the release point.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## Wide enough that a ramp over the left half repeats twice across the right,
## and one chunk tall, which is all these read.
const CANVAS := Vector2i(512, 256)
## The drag: the ramp runs across the first half of the canvas, so everything
## past x = 256 is the repeat mode's doing.
const DRAG_FROM := Vector2(0.5, 0.0)
const DRAG_TO := Vector2(256.5, 0.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _pass: SaGradient = null


func before_each() -> void:
    _easel = SaEasel.create_default(CANVAS)
    _doc = _easel.document
    _pass = SaGradient.new(_doc)


func after_each() -> void:
    _pass = null
    _easel.free()
    _easel = null


func _texel(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := _doc.active_layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(
        bytes, texture.format, (y - grid.y * SaChunk.SIZE) * texture.size.x + (x - grid.x * SaChunk.SIZE)
    )


## Lays a black to white ramp with *repeat* and *wobble*, and answers whether
## anything landed.
func _lay(repeat: int, wobble: Dictionary = {}) -> bool:
    _doc.active_layer.release_chunks()
    return _pass.apply(
        _doc.active_layer,
        DRAG_FROM,
        DRAG_TO,
        SaColorRamp.from_pair(Color.BLACK, Color.WHITE),
        SaGradient.Shape.LINEAR,
        repeat,
        true,
        wobble
    )


## The row of texels this suite reads, one per eighth of the canvas.
func _row() -> Array[float]:
    var out: Array[float] = []
    for i in 8:
        out.append(_texel(i * 64 + 32, 100).r)
    return out


func test_none_holds_the_far_colour_past_the_release() -> void:
    assert_true(_lay(SaGradient.Repeat.NONE), "A drag lays a ramp")
    var row := _row()

    assert_true(row[0] < row[3], "The ramp rises across the drag")
    # Eighth 3 is at seven eighths of the drag rather than at its end, so it is
    # not white yet. Everything past the release is.
    for i in range(4, 8):
        assert_almost_eq(row[i], 1.0, 0.02, "and holds the far colour from the release onwards, at eighth %d" % i)


func test_mirror_runs_the_ramp_back() -> void:
    assert_true(_lay(SaGradient.Repeat.MIRROR), "A drag lays a ramp")
    var row := _row()

    # Eighth 3 is just before the release and eighth 4 just after, so the mirror
    # turns between them and the pairs either side match.
    assert_almost_eq(row[4], row[3], 0.05, "The ramp turns at the release")
    assert_almost_eq(row[5], row[2], 0.05, "and comes back through the values it went out on")
    assert_almost_eq(row[7], row[0], 0.05, "reaching the near colour again at the far edge")


## The mode every other program calls Repeat, and the one Sara did not have: the
## ramp starts again, with a hard edge where the far colour meets the near one.
func test_repeat_starts_the_ramp_again() -> void:
    assert_true(_lay(SaGradient.Repeat.REPEAT), "A drag lays a ramp")
    var row := _row()

    assert_almost_eq(row[4], row[0], 0.05, "The second run begins where the first did")
    assert_almost_eq(row[5], row[1], 0.05, "and goes up the same way")
    assert_true(row[7] > row[4], "reaching the far colour again at the far edge")
    assert_true(row[3] > row[4], "with a hard edge at the seam rather than a blend through it")


## Steps is the one that is not a tiling: it cuts the ramp into bands. Two bands
## are the fewest a gradient can have, and the picture then holds two values.
func test_steps_cuts_the_ramp_into_bands() -> void:
    assert_true(_lay(SaGradient.Repeat.STEPS, {"steps": 2}), "A drag lays a ramp")
    for value: float in _row():
        var is_near := absf(value - 0.0) < 0.02
        var is_far := absf(value - 1.0) < 0.02
        assert_true(is_near or is_far, "every texel is one end or the other, not %f" % value)

    assert_true(_lay(SaGradient.Repeat.STEPS, {"steps": 4}), "and again in four")
    var seen: Array[float] = []
    for value: float in _row():
        var known := false
        for other: float in seen:
            known = known or absf(other - value) < 0.02
        if not known:
            seen.append(value)
    assert_eq(seen.size(), 4, "four bands means four values across the drag")


func test_the_band_count_cannot_go_below_two() -> void:
    assert_true(_lay(SaGradient.Repeat.STEPS, {"steps": 1}), "One band is asked for")
    var row := _row()
    assert_true(absf(row[0] - row[3]) > 0.5, "and two are drawn, because one band is a fill")


# --- The wobble ----------------------------------------------------------------


## A vertical slice, which is where a wobble shows: without one the ramp is the
## same all the way down a column.
func _column(x: int) -> Array[float]:
    var out: Array[float] = []
    for i in 8:
        out.append(_texel(x, i * 32 + 16).r)
    return out


func _spread(values: Array[float]) -> float:
    var lowest := values[0]
    var highest := values[0]
    for value: float in values:
        lowest = minf(lowest, value)
        highest = maxf(highest, value)
    return highest - lowest


func test_a_ramp_with_no_wobble_is_flat_down_a_column() -> void:
    assert_true(_lay(SaGradient.Repeat.NONE), "A drag lays a ramp")

    assert_almost_eq(_spread(_column(128)), 0.0, 1e-4, "A linear ramp does not vary down its own column")


func test_the_noise_wobble_pushes_the_ramp_off_its_axis() -> void:
    assert_true(_lay(SaGradient.Repeat.NONE, {"kind": SaGradient.Wobble.NOISE, "amount": 0.6}), "A drag lays a ramp")

    assert_true(_spread(_column(128)) > 0.02, "and the column varies now, which is the wobble")


func test_the_voronoi_wobble_does_too_and_is_not_the_noise_one() -> void:
    assert_true(_lay(SaGradient.Repeat.NONE, {"kind": SaGradient.Wobble.NOISE, "amount": 0.6}), "Noise first")
    var noise := _column(128)

    assert_true(_lay(SaGradient.Repeat.NONE, {"kind": SaGradient.Wobble.VORONOI, "amount": 0.6}), "then Voronoi")
    var voronoi := _column(128)

    assert_true(_spread(voronoi) > 0.02, "Voronoi wobbles too")
    var same := true
    for i in 8:
        same = same and absf(noise[i] - voronoi[i]) < 1e-4
    assert_false(same, "and it is a different field, not the same one under another name")


## A wobble of nothing is no wobble, so the option is off at zero rather than
## needing the dropdown as well.
func test_a_wobble_amount_of_zero_changes_nothing() -> void:
    assert_true(_lay(SaGradient.Repeat.NONE), "The plain ramp")
    var plain := _column(128)

    assert_true(_lay(SaGradient.Repeat.NONE, {"kind": SaGradient.Wobble.VORONOI, "amount": 0.0}), "and one at zero")
    var zero := _column(128)

    for i in 8:
        assert_almost_eq(zero[i], plain[i], 1e-5, "texel %d is where it was" % i)


## The hash behind both fields is sine-free, so the same drag gives the same
## picture. A wobble that came out differently every run would be unphotographable
## and would make a capture's before-and-after meaningless.
func test_the_wobble_is_the_same_every_time() -> void:
    assert_true(_lay(SaGradient.Repeat.NONE, {"kind": SaGradient.Wobble.NOISE, "amount": 0.6}), "Once")
    var first := _column(200)

    assert_true(_lay(SaGradient.Repeat.NONE, {"kind": SaGradient.Wobble.NOISE, "amount": 0.6}), "and again")
    var second := _column(200)

    for i in 8:
        assert_eq(second[i], first[i], "texel %d came out the same" % i)


## The wobble is sampled relative to the press rather than to the chunk, so it
## runs on across a chunk boundary instead of restarting every 256 pixels.
func test_the_wobble_does_not_restart_at_a_chunk_boundary() -> void:
    assert_true(_lay(SaGradient.Repeat.REPEAT, {"kind": SaGradient.Wobble.NOISE, "amount": 0.6}), "A wobbly ramp")

    # The two texels either side of the boundary between chunk 0 and chunk 1.
    # A field that restarted there would put an unrelated value on each side.
    var left := _texel(SaChunk.SIZE - 1, 100).r
    var right := _texel(SaChunk.SIZE, 100).r
    assert_almost_eq(right, left, 0.05, "the field runs on across the seam")
