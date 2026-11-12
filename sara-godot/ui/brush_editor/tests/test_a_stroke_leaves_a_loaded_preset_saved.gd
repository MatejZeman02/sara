## A stroke leaves a loaded preset saved.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The brush editor's bottom line compares every stored field of the live brush
## with the preset as loaded. Every dab copied the size, the hardness and the
## spacing onto the tip, which is one of those fields, so a stroke would read
## as a change to the brush. The dab writes on the stroke's own copy of
## the tip and of the masking block, and these walk the painter's path through
## the brush state: load, paint, read the line.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")

## Never the real `user://brush_presets`, which is the painter's own folder.
static var scratch_dir: String = SaDataRoot.path("test_d7_presets")

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _store: SaPresetStore = null


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _store = SaPresetStore.new()
    _store.dir = scratch_dir
    _store.install_shipped(_brush().settings, ShippedPresetsScript)


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _store = null
    ScratchFolder.clear(scratch_dir)


func _brush() -> Object:
    return _machine.active_tool


func _button(pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    _brush().handle_input(event)


## One stroke through the brush state, a press, two motions under a light hand
## so the size option has something to scale, and the lift.
func _stroke() -> int:
    var history_before: int = _surface.easel.document.undo_redo.get_history_count()
    _surface.view.mouse_position = Vector2(40, 40)
    _button(true)
    for at: Vector2 in [Vector2(90, 70), Vector2(150, 110)]:
        var motion := InputEventMouseMotion.new()
        motion.pressure = 0.6
        _surface.view.mouse_position = at
        _brush().handle_input(motion)
    _button(false)
    return _surface.easel.document.undo_redo.get_history_count() - history_before


func _loaded(preset_name: String) -> SaBrushEditorSession:
    assert_true(_store.apply_preset(preset_name, _brush().settings), "%s loads" % preset_name)
    return SaBrushEditorSession.new(_brush().settings, _store, preset_name)


func test_a_stroke_with_blender_leaves_it_saved() -> void:
    var session := _loaded("Blender")
    assert_false(session.is_dirty(), "Blender reads saved once it is loaded")

    assert_eq(_stroke(), 1, "A stroke lands, one step of history")

    assert_false(session.is_dirty(), "and after it the brush still matches the preset")
    assert_eq(session.dirty_text(), SaBrushEditorSession.CLEAN_TEXT, "so the line reads Saved")


func test_a_change_to_size_after_the_stroke_still_reads_as_one() -> void:
    var session := _loaded("Blender")
    _stroke()

    _brush().settings.radius *= 1.5

    assert_true(session.is_dirty(), "Size is a change to the brush, stroke or no stroke")
    assert_eq(session.dirty_text(), SaBrushEditorSession.DIRTY_TEXT, "and the line says so")


func test_the_stored_tip_keeps_what_the_preset_gave_it() -> void:
    _loaded("Blender")
    var tip: Resource = _brush().settings.tip
    var diameter: float = tip.diameter
    var fade: float = tip.horizontal_fade
    var spacing: float = tip.spacing

    _stroke()

    assert_true(_brush().settings.tip == tip, "The brush holds the tip it was loaded with")
    assert_eq(tip.diameter, diameter, "whose diameter no dab wrote over")
    assert_eq(tip.horizontal_fade, fade, "nor its fade")
    assert_eq(tip.spacing, spacing, "nor its spacing")


## The masking block carries a tip of its own that every dab shapes, the same
## write one level down, so a brush with a mask on is saved and loaded and
## painted with the same way.
func test_a_stroke_with_a_mask_on_leaves_the_preset_saved() -> void:
    var settings: Resource = _brush().settings
    _store.apply_preset("Blender", settings)
    settings.masking.enabled = true
    settings.masking.size = 0.5
    assert_false(_store.save_preset("Masked", settings).is_empty(), "A masked brush saves")
    var session := _loaded("Masked")
    var mask_diameter: float = settings.masking.tip.diameter
    assert_true(settings.masking.active(), "and its mask is on after the load")

    assert_eq(_stroke(), 1, "A masked stroke lands")

    assert_eq(settings.masking.tip.diameter, mask_diameter, "The stored mask tip keeps its diameter")
    assert_false(session.is_dirty(), "and the brush still matches the preset")
