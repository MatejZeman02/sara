## A preset thumbnail is the same picture on every launch.
##
## Filed as a curve on the Tool Options docker, it is the Grainy Pencil's cell
## in the Brush Presets docker, which sits over that docker in the default
## layout. The chooser renders a thumbnail once per launch where the cache is
## empty, and the pencil jumps its paper by a phase drawn per stroke from a seed
## the brush took off the wall clock, so each launch drew the grain in another
## place and the cell differed by a level or two. `SaPresetThumbs` now hands the
## tool a fixed `ToolState.stroke_seed`, and the brush starts from it.
##
## Two renders in one process are two strokes pressed microseconds apart, which
## is the two launches in small: without the seed they draw the grain at two
## phases and the first case fails. The running-app proof is
## `scenarios/a-curve-on-the-tool-options-docker-differs-by-a-level-between-two-runs.json`
## shot four times and compared at a tolerance of 0.
extends "res://tests/test_framework.gd"

## A thumbnail is a stroke through the real paint path, and the brush loads its
## dab kernel when it is built.
const REQUIRES_GPU := true

const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

static var scratch_dir: String = SaDataRoot.path("test_d2_preset_thumb_seed")

## The shipped preset whose cell the filing's box was on.
const GRAINY: String = "Grainy Pencil"


func after_each() -> void:
    var thumbs := SaPresetThumbs.thumbs_dir(scratch_dir)
    for folder: String in [thumbs, scratch_dir]:
        if not DirAccess.dir_exists_absolute(folder):
            continue
        for file_name: String in DirAccess.get_files_at(folder):
            DirAccess.remove_absolute(folder.path_join(file_name))
        DirAccess.remove_absolute(folder)


func _grainy() -> Resource:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    return store.load_preset(GRAINY)


## A brush on a throwaway easel with *seed* as its stroke seed, pressed once,
## answered with its stroke info. The easel is freed before the answer.
func _pressed(seed_value: int) -> SaStrokeInfo:
    var easel := SaEasel.create_default(Vector2i(64, 64), SaPresetThumbs.shared_compositor())
    var view := SaPresetThumbs.ThumbView.new()
    view.at = Vector2(32.0, 32.0)
    var brush := StateBrushScript.new() as ToolState
    brush.surface = SaSurface.create(&"d2_seed", easel, view)
    brush.stroke_seed = seed_value
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = view.at
    brush.handle_input(press)
    var info := brush.get("stroke_info") as SaStrokeInfo
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)
    if easel.document != null:
        easel.document.free()
    easel.free()
    return info


## The clause the filing grades: the same preset drawn twice is the same picture
## to the byte, the stroke strip and the tip both.
func test_the_grainy_pencil_draws_the_same_thumbnail_twice() -> void:
    var settings := _grainy()
    assert_not_null(settings, "%s is in a store of the shipped presets" % GRAINY)
    if settings == null:
        return
    assert_true(SaDabPattern.random_amount_of(settings) != Vector2.ZERO, "and jumps its paper per stroke, which is the case")
    var first := SaPresetThumbs.render(StateBrushScript, settings)
    var second := SaPresetThumbs.render(StateBrushScript, settings)
    assert_not_null(first, "The stroke renders")
    if first == null or second == null:
        return
    assert_eq(first.get_data(), second.get_data(), "and a second render is the same picture to the byte")
    var tip := SaPresetThumbs.render_tip(StateBrushScript, settings)
    var tip_again := SaPresetThumbs.render_tip(StateBrushScript, settings)
    assert_not_null(tip, "The tip renders")
    if tip == null or tip_again == null:
        return
    assert_eq(tip.get_data(), tip_again.get_data(), "and so is the tip")


## The seed is what the brush starts from, and the phase the paper jumps by is
## drawn from it, so two seeds are two phases and one seed is one.
func test_the_brush_starts_its_stroke_from_the_seed_it_was_handed() -> void:
    var settings := _grainy()
    if settings == null:
        return
    var seven := _pressed(7)
    var seven_again := _pressed(7)
    var eight := _pressed(8)
    assert_eq(
        SaDabPattern.random_phase(settings, seven),
        SaDabPattern.random_phase(settings, seven_again),
        "One seed jumps the paper by one phase"
    )
    assert_true(SaDabPattern.random_phase(settings, seven) != SaDabPattern.random_phase(settings, eight), "and two seeds by two")


## Zero is the painter's case, the clock, so the default tool is unchanged and
## two strokes side by side still lay different grain.
func test_a_tool_with_no_seed_draws_one_off_the_clock() -> void:
    assert_eq(ToolState.new().stroke_seed, 0, "A tool is built with no seed")
    var settings := _grainy()
    if settings == null:
        return
    var first := _pressed(0)
    OS.delay_usec(10)
    var second := _pressed(0)
    assert_true(
        SaDabPattern.random_phase(settings, first) != SaDabPattern.random_phase(settings, second),
        "and two of its strokes jump the paper by two phases"
    )
