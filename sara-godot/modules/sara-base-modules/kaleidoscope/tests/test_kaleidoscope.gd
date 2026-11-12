## The kaleidoscope folds every texel into one wedge and reads the picture there.
## A canvas of three by three chunks, centred at (384, 384), with one chunk
## painted white, is folded by two mirrors into four quadrants, so a texel of one
## quadrant reads its mirror image in the quadrant that is repeated. The texel is
## read through the chain, on the canvas and after the one-shot, which are the
## two forms one `run` serves.
##
## The dialog's own half is here too, because a filter that cannot be driven is
## not the showcase it claims to be: the Mirrors row holds the count in the
## range 2 to 24, the dial holds the angle and turns a step for the wheel and a
## pan alike, and a preset saved on the dialog's presets row comes back with
## both.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Kaleidoscope = preload("res://modules/sara-base-modules/kaleidoscope/kaleidoscope.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"kaleidoscope"
const KEY: StringName = &"kaleidoscope.kaleidoscope"
const WHITE := Color(1.0, 1.0, 1.0, 1.0)
const CLEAR := Color(0.0, 0.0, 0.0, 0.0)
## The quadrant below and right of the centre, the one two mirrors at no
## rotation repeat.
const PAINTED := Vector2i(2, 2)
## Below and left of the centre, the mirror image of (668, 600) across the
## vertical line through (384, 384).
const MIRRORED := Vector2i(100, 600)
## Below and right of the centre and folded onto itself, where nothing is
## painted.
const UNPAINTED := Vector2i(400, 400)
const TWO_MIRRORS := {"mirrors": 2, "angle": 0.0, "centre_x": 50.0, "centre_y": 50.0}

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _presets_dir: String = ""


func before_each() -> void:
    # First, so the filter made below carries nothing into a painter's store.
    _presets_dir = SaDataRoot.path("test_kaleidoscope_presets_%d" % OS.get_process_id())
    SaFilterPreset.root = _presets_dir
    _easel = Bench.easel(Vector2i(3 * SaChunk.SIZE, 3 * SaChunk.SIZE))
    _doc = _easel.document
    # The kernels' owner is the folder under modules, sara-base-modules, which
    # a filter registered by hand has to tell the loader.
    ModuleLoader.module_dirs[OWNER] = "res://modules/sara-base-modules/kaleidoscope"
    _easel.compositor.filter_chain.registry.register(Kaleidoscope.new(), OWNER)
    _layer = _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null
    _clear_presets()
    SaFilterPreset.root = SaFilterPreset.default_root()


## The directory this suite points the filter's presets at, empty at the end of
## every case, so one case cannot answer for another.
func _clear_presets() -> void:
    var store := SaFilterPreset.store_for(&"kaleidoscope")
    for preset_name in store.list_names():
        store.delete_preset(preset_name)
    DirAccess.remove_absolute(store.dir)
    DirAccess.remove_absolute(_presets_dir)


## Every chunk of the canvas held, *painted* white and the rest transparent.
func _hold_every_chunk(painted: Vector2i) -> void:
    for y in 3:
        for x in 3:
            var grid_pos := Vector2i(x, y)
            _layer.get_or_create_chunk(grid_pos).clear(WHITE if grid_pos == painted else CLEAR)


func _attach(values: Dictionary) -> SaAttachedFilter:
    var record := SaFilterOps.new(_doc).attach(_layer, KEY, values)
    Bench.composite(_easel)
    return record


## The chunk holding the document pixel *at*, which is never negative here.
func _grid_of(at: Vector2i) -> Vector2i:
    return Vector2i(floori(float(at.x) / SaChunk.SIZE), floori(float(at.y) / SaChunk.SIZE))


## What the chain answers at the document pixel *at*.
func _filtered(at: Vector2i) -> Color:
    var grid_pos := _grid_of(at)
    var chain := _easel.compositor.filter_chain
    var answer := chain.filtered(_layer, _layer.get_field(grid_pos), grid_pos, SaDocument.WHOLE_CHUNK)
    return Bench.texel(answer, at - grid_pos * SaChunk.SIZE)


## What the layer holds at the document pixel *at*, transparent where it holds
## no chunk.
func _held(at: Vector2i) -> Color:
    var grid_pos := _grid_of(at)
    if not _layer.chunks.has(grid_pos):
        return CLEAR
    return Bench.texel(_layer.get_field(grid_pos), at - grid_pos * SaChunk.SIZE)


func test_the_record_reads_the_whole_node_and_writes_the_canvas() -> void:
    _hold_every_chunk(PAINTED)
    var record := _attach(TWO_MIRRORS)
    assert_true(record.cached_pass is SaNeighbourhoodPass, "The run recorded a neighbourhood pass")
    if record.cached_pass is SaNeighbourhoodPass:
        var recorded := record.cached_pass as SaNeighbourhoodPass
        assert_true(recorded.whole(), "that reads the whole node, since a wedge may fold from across the canvas")
        assert_eq(recorded.writes, SaNeighbourhoodPass.WRITES_CANVAS, "and writes where the layer holds nothing yet")


func test_attached_a_mirrored_texel_reads_the_texel_it_was_folded_from() -> void:
    _hold_every_chunk(PAINTED)
    _attach(TWO_MIRRORS)
    assert_eq(_filtered(MIRRORED), WHITE, "A texel left of the vertical mirror reads its image in the painted quadrant")
    assert_eq(
        _filtered(Vector2i(100, 100)), WHITE, "and one up and left of the centre reads the painted quadrant through both mirrors"
    )
    assert_eq(Bench.texel(_easel.output, MIRRORED), WHITE, "The canvas shows the mirrored paint")


func test_attached_a_texel_folded_onto_nothing_is_transparent() -> void:
    _hold_every_chunk(PAINTED)
    _attach(TWO_MIRRORS)
    assert_eq(_filtered(UNPAINTED), CLEAR, "A texel whose wedge holds no paint reads transparent")


func test_the_angle_turns_the_wedge_that_is_repeated() -> void:
    _hold_every_chunk(Vector2i(0, 2))
    _attach({"mirrors": 2, "angle": 90.0, "centre_x": 50.0, "centre_y": 50.0})
    assert_eq(_filtered(Vector2i(668, 600)), WHITE, "Turned by a quarter, the quadrant below and left is the one repeated")
    assert_eq(_filtered(Vector2i(100, 100)), WHITE, "and read across the horizontal mirror too")


func test_the_one_shot_writes_what_the_attached_form_shows() -> void:
    _layer.get_or_create_chunk(PAINTED).clear(WHITE)
    var filter := Kaleidoscope.new()
    filter.set_parameters(TWO_MIRRORS)
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, filter.title(), false)
    assert_true(SaFilterApply.call_run(filter, ctx), "The run records a pass")
    assert_true(SaFilterApply.apply(ctx, "Kaleidoscope"), "Apply writes it")
    assert_eq(_held(MIRRORED), WHITE, "The one-shot wrote the mirrored paint on a chunk the layer did not hold")
    assert_eq(_held(Vector2i(100, 100)), WHITE, "and on the quadrant diagonally across")
    assert_eq(_held(UNPAINTED), CLEAR, "and nothing where the fold holds no paint")


func test_the_dial_moves_through_its_door_and_one_rerun_follows() -> void:
    var host := VBoxContainer.new()
    var filter := Kaleidoscope.new()
    var dialog := SaDialog.for_filter(filter)
    dialog.realize(host)
    var said := SaFilterDialogWindow._drive(dialog.row(&"angle"), {"widget": "angle", "value": 30})
    assert_true(said.contains("KaleidoscopeDial holds 30"), "The step was answered by the base class's door")
    assert_true(dialog.rerun_pending, "Moving the dial asks for a rerun")
    dialog.flush_rerun()
    assert_eq(dialog.runs, 1, "and one run follows")
    assert_almost_eq(float(filter.parameters()["angle"]), 30.0, 0.001, "The record keeps the dial's angle")
    host.free()


## The Mirrors row is the count's one door and the dial draws what it holds,
## while the wheel over the dial turns the wedge and leaves the count alone.
func test_the_mirrors_row_holds_the_count_and_the_wheel_turns_the_dial() -> void:
    var host := VBoxContainer.new()
    var filter := Kaleidoscope.new()
    var dialog := SaDialog.for_filter(filter)
    dialog.realize(host)
    SaFilterDialogWindow._drive(dialog.row(&"mirrors"), {"widget": "mirrors", "value": 12})
    assert_eq(int(filter.parameters()["mirrors"]), 12, "The row writes the count the record keeps")
    assert_eq(filter.dial.mirrors, 12, "and the dial shows what the row wrote")
    SaFilterDialogWindow._drive(dialog.row(&"angle"), {"widget": "angle", "wheel": 2})
    assert_almost_eq(
        float(filter.parameters()["angle"]), 2.0 * Kaleidoscope.WedgeDial.TURN_STEP, 0.001, "Two notches turn the wedge two steps"
    )
    assert_eq(int(filter.parameters()["mirrors"]), 12, "and the count stays the row's")
    host.free()


## A touchpad's two finger scroll arrives as a pan rather than as the two wheel
## buttons, and the dial reads both through the step helper, so a hand on one
## turns the wedge as far as a hand on the other. The sign is the first thing to
## check against a hand, which is done on a tablet.
func test_the_dial_reads_a_touchpads_scroll_as_well_as_a_wheel() -> void:
    var host := VBoxContainer.new()
    var filter := Kaleidoscope.new()
    var dialog := SaDialog.for_filter(filter)
    dialog.realize(host)
    var up := InputEventPanGesture.new()
    up.delta = Vector2(0.0, -SaStep.PAN_PER_NOTCH)
    filter.dial._gui_input(up)
    assert_almost_eq(filter.dial.value, Kaleidoscope.WedgeDial.TURN_STEP, 0.001, "A pan up turns the wedge one step on")
    assert_almost_eq(float(dialog.row(&"angle").read()), filter.dial.value, 0.001, "and the filter keeps what the dial shows")
    var down := InputEventPanGesture.new()
    down.delta = Vector2(0.0, SaStep.PAN_PER_NOTCH)
    filter.dial._gui_input(down)
    assert_almost_eq(float(filter.parameters()["angle"]), 0.0, 0.001, "A pan down turns it back")
    host.free()


## Whichever door a number comes through, the range is the count's.
func test_the_mirrors_control_holds_the_count_between_two_and_twenty_four() -> void:
    var host := VBoxContainer.new()
    var filter := Kaleidoscope.new()
    var dialog := SaDialog.for_filter(filter)
    dialog.realize(host)
    SaFilterDialogWindow._drive(dialog.row(&"mirrors"), {"widget": "mirrors", "value": 99})
    assert_eq(int(filter.parameters()["mirrors"]), Kaleidoscope.MAX_MIRRORS, "A count past the ceiling is held to it")
    assert_almost_eq(
        float(dialog.row(&"mirrors").read()),
        float(Kaleidoscope.MAX_MIRRORS),
        0.001,
        "and the row is shown the count the record holds"
    )
    SaFilterDialogWindow._drive(dialog.row(&"mirrors"), {"widget": "mirrors", "value": 1})
    assert_eq(int(filter.parameters()["mirrors"]), Kaleidoscope.MIN_MIRRORS, "and one under the floor is held to that")
    assert_eq(filter.dial.mirrors, Kaleidoscope.MIN_MIRRORS, "with the dial following it")
    host.free()


## A preset goes through the store both ways: saved as a resource under the
## filter's own directory, and read back with the count a painter kept.
func test_a_preset_saved_through_the_store_comes_back_with_its_count() -> void:
    var host := VBoxContainer.new()
    var filter := Kaleidoscope.new()
    var dialog := SaDialog.for_filter(filter)
    dialog.realize(host)
    SaFilterDialogWindow._drive(dialog.row(&"mirrors"), {"widget": "mirrors", "value": 12})
    SaFilterDialogWindow._drive(dialog.row(&"angle"), {"widget": "angle", "value": -45})
    var said := SaFilterDialogWindow._drive(dialog.row(&"preset"), {"widget": "preset", "name": "Twelve", "save": true})
    assert_true(said.contains("Twelve"), "Save keeps the values under the name typed")
    var store := SaFilterPreset.store_for(&"kaleidoscope")
    assert_true(store.list_names().has("Twelve"), "and the file is one the store can list")
    assert_eq(int(SaFilterPreset.values_in(store, "Twelve").get("mirrors", 0)), 12, "carrying the count")
    SaFilterDialogWindow._drive(dialog.row(&"mirrors"), {"widget": "mirrors", "value": 4})
    SaFilterDialogWindow._drive(dialog.row(&"preset"), {"widget": "preset", "preset": "Twelve"})
    var values := filter.parameters()
    assert_eq(int(values["mirrors"]), 12, "and putting it back restores the count on the controls")
    assert_almost_eq(float(values["angle"]), -45.0, 0.001, "and its angle")
    assert_eq(filter.dial.mirrors, 12, "the dial included")
    assert_almost_eq(filter.dial.value, -45.0, 0.001, "at the angle kept")
    SaFilterDialogWindow._drive(dialog.row(&"preset"), {"widget": "preset", "preset": ""})
    assert_eq(int(filter.parameters()["mirrors"]), 6, "The defaults put six mirrors back")
    assert_eq(filter.dial.mirrors, 6, "on the dial as well")
    host.free()


func test_the_parameters_survive_without_a_dialog() -> void:
    var filter := Kaleidoscope.new()
    filter.set_parameters({"mirrors": 40, "angle": 10.0, "centre_x": 25.0})
    var values := filter.parameters()
    assert_eq(int(values["mirrors"]), Kaleidoscope.MAX_MIRRORS, "A mirror count past the range is held to it")
    assert_almost_eq(float(values["centre_x"]), 25.0, 0.001, "and a key the record carries is kept")
    assert_almost_eq(float(values["centre_y"]), 50.0, 0.001, "while one it does not keeps its default")
