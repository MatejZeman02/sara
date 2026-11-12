## White Point's eyedropper averages the Eyedropper tool's Sample size, and a
## search for "white balance" finds White Point.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A 16 by 16 patch of two tints in a chequer, whose mean in light is a warm
## grey, is painted at the right edge of the first chunk of an sRGB document two
## chunks wide, and the second chunk holds nothing. A click at Sample size 1
## reads one of the two tints, the colour the one texel Levels' sampler reads
## gives, and at 9 the warm grey, which the filter then makes neutral across the
## patch. A square that runs into transparent texels or into the empty chunk
## reads the paint alone, and a click on nothing picks nothing. Last, the rank
## both searches list by finds White Point for "white balance" and not for a
## word it never says.
extends "res://tests/test_framework.gd"

const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")
const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const BASE_MODULE_ID := &"sara-base-modules"

## The two tints as light-linear sRGB, a reddish and a greenish one, whose mean
## is the warm grey [constant WARM_GREY].
const TINT_A := Vector3(0.50, 0.30, 0.20)
const TINT_B := Vector3(0.30, 0.34, 0.24)
const WARM_GREY := Vector3(0.40, 0.32, 0.22)

## The patch, in document pixels, against the right edge of chunk (0, 0).
const PATCH := Rect2i(240, 100, 16, 16)

## How far a mean of float texels may stand from the one worked out by hand.
const MEAN_BOUND := 1e-4
## How far an odd square's mean may stand from the warm grey, one texel of 81.
const GREY_BOUND := 0.002
## How far apart the channels of the corrected patch's mean may stand.
const NEUTRAL_BOUND := 1e-3

## The side the suite picks at above 1.
const WIDE := 9

static var scratch_path: String = SaDataRoot.path("test_white_point_sample_size.cfg")

var _easel: SaEasel = null
var _doc: SaDocument = null
var _saved_path: String = ""
## The base module's context the Eyedropper tool keeps its Sample size in, held
## here because the tool holds it weakly.
var _preferences: SaContext = null


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    SaSettings.config = ConfigFile.new()
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_path)
    SaSettings.load_settings()
    _preferences = Fixtures.make_registries().context.for_module(BASE_MODULE_ID)
    StateEyedropperScript.keep_choice_in(_preferences)


func after_each() -> void:
    StateEyedropperScript.keep_choice_in(null)
    _preferences = null
    if _easel != null:
        _easel.free()
    _easel = null
    _doc = null
    SaSettings.settings_path = _saved_path
    SaSettings.config = ConfigFile.new()
    SaSettings.load_settings()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path) + SaSettings.BACKUP_SUFFIX)


## An sRGB document two chunks wide whose first chunk holds the patch and is
## transparent elsewhere, and whose second holds no chunk at all.
func _open() -> void:
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE * 2, SaChunk.SIZE), null, SaColorSpace.srgb())
    _doc = _easel.document
    var texture := _doc.active_layer.get_or_create_field(Vector2i.ZERO)
    var rd := GlobalShaderCompiler.get_rd()
    var bytes := rd.texture_get_data(texture.rid, 0)
    var curve := SaTransferFunction.srgb()
    for y in range(PATCH.position.y, PATCH.end.y):
        for x in range(PATCH.position.x, PATCH.end.x):
            var light := _tint_at(Vector2i(x, y))
            var stored := [curve.encode(light.x), curve.encode(light.y), curve.encode(light.z), 1.0]
            for channel in 4:
                bytes.encode_float((y * texture.size.x + x) * 16 + channel * 4, stored[channel])
    rd.texture_update(texture.rid, 0, bytes)


## The tint the chequer lays at *place*.
static func _tint_at(place: Vector2i) -> Vector3:
    return TINT_A if (place.x + place.y) % 2 == 0 else TINT_B


## The mean in light of the painted texels in the square of *side* around
## *centre*, worked out by hand. An odd square holds one more of one tint, so it
## stands a little off [constant WARM_GREY].
static func _expected(centre: Vector2i, side: int) -> Vector3:
    @warning_ignore("integer_division")
    var half := side / 2
    var square := Rect2i(centre - Vector2i(half, half), Vector2i(side, side)).intersection(PATCH)
    var sum := Vector3.ZERO
    for y in range(square.position.y, square.end.y):
        for x in range(square.position.x, square.end.x):
            sum += _tint_at(Vector2i(x, y))
    return sum / float(square.get_area())


static func _near(a: Vector3, b: Vector3, bound: float) -> bool:
    return absf(a.x - b.x) <= bound and absf(a.y - b.y) <= bound and absf(a.z - b.z) <= bound


func _set_side(side: int) -> void:
    StateEyedropperScript.new().sample_size = side


## What the panel picks at *at*, NAN when the pick did not land.
func _pick(at: Vector2) -> Vector3:
    var panel := SaWhitePointPanel.new()
    var picked := panel.picked if panel.take_pick(_doc, _doc.active_layer, at) else Vector3(NAN, NAN, NAN)
    panel.free()
    return picked


## The patch's mean in light, as the document stores it now.
func _patch_mean() -> Vector3:
    var texture := _doc.active_layer.get_field(Vector2i.ZERO)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var sum := Vector3.ZERO
    for y in range(PATCH.position.y, PATCH.end.y):
        for x in range(PATCH.position.x, PATCH.end.x):
            var stored := SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)
            sum += SaWhitePointFilter.linear_of(stored, _doc.color_space)
    return sum / float(PATCH.size.x * PATCH.size.y)


func test_the_sample_size_is_the_eyedropper_tool_s_own() -> void:
    _set_side(WIDE)
    assert_eq(SaWhitePointSquare.side(), WIDE, "White Point reads the side the Eyedropper tool keeps")
    _set_side(1)
    assert_eq(SaWhitePointSquare.side(), 1, "and follows it back to one texel")


func test_a_click_at_one_reads_one_tint_and_at_nine_the_warm_grey_which_the_filter_makes_neutral() -> void:
    _open()
    var at := Vector2(250.5, 108.5)
    _set_side(1)
    var one := _pick(at)
    assert_true(_near(one, _tint_at(Vector2i(250, 108)), MEAN_BOUND), "at Sample size 1 the pick is one tint, read %s" % one)
    var before := SaLevelsSampler.new().read_texel(SaNodeInput.new(_doc, _doc.active_layer), at, _doc.canvas_size)
    var old := SaWhitePointFilter.linear_of(before, _doc.color_space)
    assert_true(
        _near(one, old, 1e-6), "and the same colour the one texel read gave before sampling averaged, %s against %s" % [one, old]
    )
    _set_side(WIDE)
    var wide := _pick(at)
    var wanted := _expected(Vector2i(250, 108), WIDE)
    assert_true(
        _near(wide, wanted, MEAN_BOUND),
        "at Sample size %d the pick is the light mean of the square, %s, read %s" % [WIDE, wanted, wide]
    )
    assert_true(_near(wide, WARM_GREY, GREY_BOUND), "which is the warm grey %s within %.3f" % [WARM_GREY, GREY_BOUND])
    assert_true(wide.x > wide.y and wide.y > wide.z, "a warm grey, red over green over blue")
    assert_true(SaWhitePointFilter.new().capture_apply(_doc, {"picked": SaWhitePointFilter.as_list(wide)}), "the filter ran")
    var mean := _patch_mean()
    var grey := (mean.x + mean.y + mean.z) / 3.0
    assert_true(_near(mean, Vector3.ONE * grey, NEUTRAL_BOUND), "and the patch's mean comes out neutral, read %s" % mean)


func test_a_square_that_runs_off_the_paint_reads_the_paint_alone() -> void:
    _open()
    _set_side(WIDE)
    # Columns 250 to 255 of the patch, then three of the chunk nobody painted.
    var into_empty_chunk := _pick(Vector2(254.5, 108.5))
    var wanted := _expected(Vector2i(254, 108), WIDE)
    assert_true(
        _near(into_empty_chunk, wanted, MEAN_BOUND),
        "a square into an empty chunk reads the paint's mean %s, read %s" % [wanted, into_empty_chunk]
    )
    # Its top left runs into the transparent texels of the patch's own chunk.
    var into_transparent := _pick(Vector2(243.5, 100.5))
    wanted = _expected(Vector2i(243, 100), WIDE)
    assert_true(
        _near(into_transparent, wanted, MEAN_BOUND),
        "a square into transparent texels reads the paint's mean %s, read %s" % [wanted, into_transparent]
    )


func test_a_click_on_nothing_picks_nothing_and_keeps_the_colour() -> void:
    _open()
    _set_side(WIDE)
    var panel := SaWhitePointPanel.new()
    assert_true(panel.take_pick(_doc, _doc.active_layer, Vector2(250.5, 108.5)), "a pick on the patch lands")
    var kept := panel.picked
    assert_false(panel.take_pick(_doc, _doc.active_layer, Vector2(100.5, 30.5)), "a pick on transparent paint does not")
    assert_false(panel.take_pick(_doc, _doc.active_layer, Vector2(400.5, 30.5)), "nor one where no chunk is")
    assert_false(panel.take_pick(_doc, _doc.active_layer, Vector2(-5.0, 30.5)), "nor one off the canvas")
    assert_eq(panel.picked, kept, "and the colour is the one picked before")
    panel.free()


func test_a_search_for_white_balance_finds_white_point() -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    var mod := BaseModule.new()
    mod.register(registries.context.for_module(mod.get_id()))
    assert_true(registries.filters.list_keys().size() > 1, "the base module's filters are registered")
    var found := _found(registries.filters, "white balance")
    assert_true(found.has("White Point"), "a search for white balance finds White Point, found %s" % [found])
    var other := _found(registries.filters, "sharpen")
    assert_false(other.has("White Point"), "and one for a word it never says does not, found %s" % [other])
    mod.unregister(registries.context.for_module(mod.get_id()))


## The titles of the filters of *filters* the rank both searches list by finds
## for *needle*.
static func _found(filters: SaFilterRegistry, needle: String) -> Array[String]:
    var titles: Array[String] = []
    for key: StringName in filters.list_keys():
        var filter := filters.get_filter(key)
        var said := SaFilterMenu.sentence_of(key, filter, null)
        if SaFilterMenu.rank(filter, needle, "", said) > SaFilterMenu.RANK_NONE:
            titles.append(filter.title())
    return titles
