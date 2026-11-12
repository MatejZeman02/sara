## The smudge stage: the pickup's arithmetic on the GPU, the stand-in the dab
## reads while the stage is off, and the options that switch it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Numbers here, the stroke in the scenario.**
## `scenarios/the-smudge-stage.json` paints across two colours with the stage
## on and off and dumps the texels, which is what a painter would call a smudge.
## What a stroke cannot say is how much of the carry one dab took and how fast it
## faded, so the pickup kernel is dispatched here over textures this file filled
## and its two texels are read back, which a test may do and the brush never does.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## The snapshot a test fills, larger than the pickup's five-sample grid reaches.
const SNAPSHOT := Vector2i(16, 16)
const CENTRE := Vector2(8.0, 8.0)

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
const NOTHING := Color(0.0, 0.0, 0.0, 0.0)


func _filled(size: Vector2i, colour: Color) -> SaTexture:
    var texture := SaTexture.new(size)
    texture.clear(colour)
    return texture


## The four channels of every texel of *texture*, in row order.
func _read(texture: SaTexture) -> PackedFloat32Array:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0).to_float32_array()


## One pickup of *snapshot* into *carry*, the way `SaSmudgeReservoir.pick_up`
## dispatches it, with the arguments named rather than packed by hand at every
## call. *mode* is the stage's rate and smearing is what every call written
## before that row meant. The buffer comes back because it is where the pickup
## leaves the carry's spread about the paint under the dab.
func _pick(
    snapshot: SaTexture, carry: SaTexture, pickup: float, keep: float, color_rate: float, first: bool, mode: int = 0
) -> SaCompute.Buffer:
    var compute := SaCompute.new("smudge_pickup")
    var variance := SaCompute.Buffer.new(PackedFloat32Array([0.0]).to_byte_array())
    compute.use_storage_format(snapshot.format)
    compute.set_texture(0, snapshot.rid)
    compute.set_texture(1, carry.rid)
    compute.set_buffer(SaSmudgeReservoir.BUFFER_BINDING, variance.rid)
    # The height exchange, empty, so the carry's height stays
    # where it stood and the colour's arithmetic is what this suite reads.
    var exchange := SaCompute.Buffer.new(PackedInt32Array([0, 0]).to_byte_array())
    compute.set_buffer(SaSmudgeReservoir.EXCHANGE_BINDING, exchange.rid)
    compute.set_push_constant_float_array(
        PackedFloat32Array([CENTRE.x, CENTRE.y, 4.0, pickup, keep, color_rate, 1.0 if first else 0.0, float(mode)])
    )
    compute.dispatch_kernel("smudge_pickup", 1, 1, 1)
    return variance


## A snapshot whose texels left of the middle column are *left* and the rest are
## *right*, so the pickup's five by five grid straddles the join and the mean it
## reduces has both colours in it.
func _split(size: Vector2i, left: Color, right: Color) -> SaTexture:
    var texture := SaTexture.new(size)
    var texels := PackedFloat32Array()
    texels.resize(size.x * size.y * 4)
    @warning_ignore("integer_division")
    var middle := size.x / 2
    for y in range(size.y):
        for x in range(size.x):
            var colour := left if x < middle else right
            var at := (y * size.x + x) * 4
            texels[at] = colour.r
            texels[at + 1] = colour.g
            texels[at + 2] = colour.b
            texels[at + 3] = colour.a
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, texels.to_byte_array())
    return texture


## The carry's spread about the paint under the last dab, which the pickup left
## in its own buffer.
func _variance(buffer: SaCompute.Buffer) -> float:
    var bytes := buffer.read()
    return bytes.decode_float(0) if bytes.size() >= 4 else 0.0


## The carried colour, texel 0.
func _colour(carry: SaTexture) -> Color:
    var texels := _read(carry)
    return Color(texels[0], texels[1], texels[2], texels[3])


## The carry's strength, texel 1's red.
func _strength(carry: SaTexture) -> float:
    return _read(carry)[4]


# --- The pickup ----------------------------------------------------------------------


func test_the_first_pickup_starts_the_carry_from_the_paint_under_the_dab() -> void:
    var carry := _filled(SaSmudgeReservoir.SIZE, NOTHING)
    _pick(_filled(SNAPSHOT, RED), carry, 0.3, 0.9, 0.2, true)

    var colour := _colour(carry)
    assert_almost_eq(colour.r, 1.0, 1e-5, "The carry is the red under the first dab, whatever the pickup rate")
    assert_almost_eq(colour.b, 0.0, 1e-5, "and nothing of any other colour")
    assert_almost_eq(_strength(carry), 1.0, 1e-5, "at full strength, because the dab sat wholly on paint")
    assert_almost_eq(colour.a, 0.8, 1e-5, "and the dab is told to lay the carry's share, one less the colour rate")


func test_the_pickup_moves_the_carry_towards_new_paint_at_its_rate() -> void:
    var carry := _filled(SaSmudgeReservoir.SIZE, NOTHING)
    _pick(_filled(SNAPSHOT, RED), carry, 0.25, 1.0, 0.0, true)
    _pick(_filled(SNAPSHOT, BLUE), carry, 0.25, 1.0, 0.0, false)

    var colour := _colour(carry)
    assert_almost_eq(colour.r, 0.75, 1e-5, "A quarter of the way from the red it carried")
    assert_almost_eq(colour.b, 0.25, 1e-5, "towards the blue it crossed")
    assert_almost_eq(_strength(carry), 1.0, 1e-5, "and still strong, because it picked up as much as it lost")


func test_bare_canvas_moves_the_carry_by_nothing() -> void:
    var carry := _filled(SaSmudgeReservoir.SIZE, NOTHING)
    _pick(_filled(SNAPSHOT, BLUE), carry, 1.0, 1.0, 0.0, true)
    _pick(_filled(SNAPSHOT, NOTHING), carry, 1.0, 1.0, 0.0, false)

    var colour := _colour(carry)
    assert_almost_eq(colour.b, 1.0, 1e-5, "A dab over nothing keeps the blue it carried rather than picking up black")
    assert_almost_eq(colour.r, 0.0, 1e-5, "and gains no other colour")


func test_the_smear_length_fades_the_carry_once_it_leaves_the_paint() -> void:
    var carry := _filled(SaSmudgeReservoir.SIZE, NOTHING)
    _pick(_filled(SNAPSHOT, RED), carry, 0.3, 0.5, 0.0, true)
    var bare := _filled(SNAPSHOT, NOTHING)
    for _dab in range(3):
        _pick(bare, carry, 0.3, 0.5, 0.0, false)

    assert_almost_eq(_strength(carry), 0.125, 1e-5, "Half of the strength survives each of three dabs off the paint")
    assert_almost_eq(_colour(carry).a, 0.125, 1e-5, "and the dab lays that share of the carry, no more")


func test_a_long_smear_does_not_fade_at_all() -> void:
    var carry := _filled(SaSmudgeReservoir.SIZE, NOTHING)
    _pick(_filled(SNAPSHOT, RED), carry, 0.3, 1.0, 0.0, true)
    var bare := _filled(SNAPSHOT, NOTHING)
    for _dab in range(10):
        _pick(bare, carry, 0.3, 1.0, 0.0, false)

    assert_almost_eq(_strength(carry), 1.0, 1e-5, "A smear length of one carries the paint as far as the stroke goes")


# --- Dulling, the other rate ------------------------------------------


func test_a_dulling_dab_is_set_to_the_paint_under_it_rather_than_mixed_towards_it() -> void:
    var carry := _filled(SaSmudgeReservoir.SIZE, NOTHING)
    _pick(_filled(SNAPSHOT, RED), carry, 0.25, 1.0, 0.0, true, SettingsScript.SmudgeMode.DULLING)
    _pick(_filled(SNAPSHOT, BLUE), carry, 0.25, 1.0, 0.0, false, SettingsScript.SmudgeMode.DULLING)

    var colour := _colour(carry)
    assert_almost_eq(colour.b, 1.0, 1e-5, "The second dab's paint is the carry outright, whatever the pickup rate")
    assert_almost_eq(colour.r, 0.0, 1e-5, "so none of the red it carried before is dragged along")
    assert_almost_eq(_strength(carry), 1.0, 1e-5, "and the dab lays it at the strength of the paint under it")


func test_the_pickup_reduces_the_region_to_one_mean_colour_weighted_by_coverage() -> void:
    # Red left of the middle column and blue at it, so the five by five grid
    # reads ten red texels and fifteen blue ones and the carry is the blend of
    # the two rather than either of them.
    var carry := _filled(SaSmudgeReservoir.SIZE, NOTHING)
    _pick(_split(SNAPSHOT, RED, BLUE), carry, 1.0, 1.0, 0.0, true, SettingsScript.SmudgeMode.DULLING)

    var colour := _colour(carry)
    assert_almost_eq(colour.r, 0.4, 1e-5, "Two fifths of the region under the dab is red")
    assert_almost_eq(colour.b, 0.6, 1e-5, "and three fifths of it is blue")


func test_dulling_leaves_no_spread_about_the_paint_and_smearing_leaves_the_lag() -> void:
    var dull := _filled(SaSmudgeReservoir.SIZE, NOTHING)
    _pick(_filled(SNAPSHOT, RED), dull, 0.3, 0.9, 0.2, true, SettingsScript.SmudgeMode.DULLING)
    var dull_variance := _pick(_filled(SNAPSHOT, BLUE), dull, 0.3, 0.9, 0.2, false, SettingsScript.SmudgeMode.DULLING)

    assert_almost_eq(
        _variance(dull_variance), 0.0, 1e-5, "A dulling dab is the paint under it, so the carry has no spread about it"
    )

    var smear := _filled(SaSmudgeReservoir.SIZE, NOTHING)
    _pick(_filled(SNAPSHOT, RED), smear, 0.3, 0.9, 0.2, true, SettingsScript.SmudgeMode.SMEARING)
    var smear_variance := _pick(_filled(SNAPSHOT, BLUE), smear, 0.3, 0.9, 0.2, false, SettingsScript.SmudgeMode.SMEARING)

    # The carry is seven tenths red over paint that is blue: the squared
    # distance between the two is 0.49 twice over.
    assert_almost_eq(_variance(smear_variance), 0.98, 1e-5, "A smearing dab lags the paint under it by the red it crossed")


func test_a_dulling_dab_over_bare_canvas_lays_nothing() -> void:
    var carry := _filled(SaSmudgeReservoir.SIZE, NOTHING)
    _pick(_filled(SNAPSHOT, RED), carry, 1.0, 1.0, 0.0, true, SettingsScript.SmudgeMode.DULLING)
    _pick(_filled(SNAPSHOT, NOTHING), carry, 1.0, 1.0, 0.0, false, SettingsScript.SmudgeMode.DULLING)

    # Nothing by the load, which the dab reads where the layer is
    # empty. The carry keeps the red and its strength, so the texels the
    # stroke laid itself, which the snapshot reads as empty, get that red
    # rather than the swatch's colour.
    var held: float = _read(carry)[SaSmudgeReservoir.LOAD * 4]
    assert_almost_eq(held, 0.0, 1e-5, "Nothing stands where the dab is, so a dulling dab lays nothing")
    assert_almost_eq(_colour(carry).r, 1.0, 1e-5, "and what it carries is the red the stroke met rather than the swatch")


# --- The stage off -------------------------------------------------------------------


func test_the_stand_in_is_one_texel_of_nothing() -> void:
    var stand_in := SaSmudgeReservoir.stand_in()

    assert_not_null(stand_in, "There is a stand-in to bind")
    assert_eq(stand_in.size, Vector2i.ONE, "one texel of it")
    var texels := _read(stand_in)
    for channel in range(4):
        assert_almost_eq(texels[channel], 0.0, 1e-6, "and every channel is nought, so the dab mixes nothing in")


func test_a_fresh_brush_has_the_stage_off() -> void:
    var settings: Resource = SettingsScript.new()

    assert_false(settings.smudge_pickup_option.enabled, "A new brush does not smudge")
    assert_true(settings.smudge_color_rate_option.enabled, "its colour rate is ticked, so ticking the pickup paints too")
    assert_false(settings.smudge_length_option.enabled, "nor smear")
    assert_almost_eq(settings.smudge_pickup_option.strength, 0.3, 1e-6, "and the pickup waits at some rather than all")
    assert_almost_eq(settings.smudge_color_rate_option.strength, 0.5, 1e-6, "the colour rate at half the brush's colour")
    assert_almost_eq(settings.smudge_length_option.strength, 0.9, 1e-6, "and the smear at a long one")
    assert_almost_eq(settings.smudge_radius, 1.0, 1e-6, "and the pickup reads no wider than the dab it is under")
    assert_eq(settings.smudge_mode, SettingsScript.SmudgeMode.SMEARING, "and the stage drags rather than averages")


func test_the_dynamics_read_the_stage_only_while_pickup_is_ticked() -> void:
    var settings: Resource = SettingsScript.new()
    var dynamics := SaDynamics.new()
    dynamics.settings = settings
    dynamics.begin_stroke()
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 12345)

    assert_false(dynamics.evaluate(info, 20.0).smudge, "With pickup unticked the dab has no smudge")

    settings.smudge_pickup_option.enabled = true
    dynamics.begin_stroke()
    var dab := dynamics.evaluate(info, 20.0)
    assert_true(dab.smudge, "Ticked, the dab smudges")
    assert_almost_eq(dab.smudge_pickup, 0.3, 1e-5, "at the pickup option's strength")
    assert_almost_eq(dab.smudge_color_rate, 0.5, 1e-5, "and the fresh colour rate lays half the brush's colour")
    settings.smudge_color_rate_option.enabled = false
    dynamics.begin_stroke()
    dab = dynamics.evaluate(info, 20.0)
    assert_almost_eq(dab.smudge_color_rate, 0.0, 1e-5, "and an unticked colour rate lays the carry in full")
    assert_almost_eq(dab.smudge_length, 1.0, 1e-5, "and an unticked length never fades it")
