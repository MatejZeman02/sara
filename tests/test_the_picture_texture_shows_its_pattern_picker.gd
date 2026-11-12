## The Picture texture shows its pattern picker.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Changing the Texture mode to Picture must show a way to choose the picture.
## The store lists its four patterns at registration, and the Brush Editor has
## no Advanced gate. Every field's rows carry a condition on the Texture row, which
## sits on the General page, and a page read only its own rows, so the
## condition read null and Picture's rows were never drawn. The Tool Options
## docker read no condition at all and drew all three fields' rows at once.
##
## The Done when, a clause a test: the Pattern row lists the shipped patterns
## and any in the painter's folder, one added while Sara runs among them, a
## choice on it reaches `picture_name` and the stroke, and the row is drawn in
## the docker while Picture is chosen and not while Grain is.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseFieldsScript = preload("res://modules/sara-noise-brush-engine/noise_fields.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")

const RADIUS := 14.0
const INSIDE := RADIUS - 3.0
const SPOT := Vector2(60.0, 60.0)
## The tool id the row's controls are built under.
const TOOL_ID := &"d85_noise"
## The file a painter drops in while Sara runs, and the name the store gives it.
const ADDED_FILE := "scanned_paper.png"
const ADDED_NAME := "Scanned Paper"

var _scratch := ""
var _store: SaPatternStore = null
var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


func before_each() -> void:
    _scratch = SaDataRoot.path("test_d85_patterns")
    ScratchFolder.clear(_scratch)
    DirAccess.make_dir_recursive_absolute(_scratch)
    _store = SaPatternStore.new([SaPatternStore.SHIPPED_DIR, _scratch])
    _surface = Fixtures.make_surface()
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    _brush.settings.pattern_store = _store
    _brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    _brush.settings.opacity = 1.0
    _brush.settings.hardness = 1.0
    _brush.settings.strength = 0.5
    _brush.settings.strength_option.enabled = false
    _brush.settings.radius = RADIUS / 256.0
    _brush.settings.texture_field = NoiseFieldsScript.PICTURE


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null
    _store = null
    ScratchFolder.clear(_scratch)


## The row lists every pattern the store finds, and a picture dropped into the
## painter's folder after the row was built is a row the next time it opens.
func test_the_pattern_row_lists_the_folders_and_a_pattern_added_while_sara_runs() -> void:
    var spec := _pattern_spec()
    assert_eq(spec.kind, SaOptionSpec.Kind.CUSTOM, "The Pattern row is built by the module, so it can list at the open")
    var list := spec.build_control.call(spec, Callable()) as NoiseFieldsScript.PatternList
    assert_not_null(list, "and its control is the pattern list")
    var shipped := Array(SaPatternStore.new([SaPatternStore.SHIPPED_DIR]).names())
    assert_eq(list.choice_values(), shipped, "The list holds the shipped patterns: %s" % [shipped])
    _write_picture(_scratch.path_join(ADDED_FILE))
    assert_false(list.choice_values().has(ADDED_NAME), "A file dropped in is not a row of a list already filled")
    list.relist()
    assert_true(list.choice_values().has(ADDED_NAME), "and is one the next time the list opens: %s" % [list.choice_values()])
    assert_eq(list.choice_values().size(), shipped.size() + 1, "beside every shipped one")
    list.free()


## A name no file carries is shown as it is with no row marked, rather than as
## the first pattern in the list, which the stroke does not paint.
func test_a_name_no_file_carries_is_shown_as_it_is() -> void:
    var spec := _pattern_spec()
    var list := spec.build_control.call(spec, Callable()) as NoiseFieldsScript.PatternList
    spec.bind_value.call(list, "Lienzo 01")
    assert_eq(list.text, "Lienzo 01", "The button reads the name the settings hold")
    assert_null(list.selected_value(), "and marks no row")
    list.relist()
    assert_eq(list.text, "Lienzo 01", "and still reads it after the list is read again")
    spec.bind_value.call(list, "Dot Screen")
    assert_eq(list.selected_value(), "Dot Screen", "A name a file carries marks its row")
    list.free()


## A press on a row of the list, through the controls both surfaces build,
## writes `picture_name`, makes the settings' picture of it, and the stroke
## paints through it rather than through the pattern it held before.
func test_a_choice_reaches_picture_name_and_the_stroke() -> void:
    _brush.settings.picture_name = "Paper Grain"
    var before := _painted()
    var host := Control.new()
    var controls := ToolOptionControls.new(host)
    var descriptor := SaToolDescriptor.new()
    descriptor.id = TOOL_ID
    descriptor.options.assign(NoiseFieldsScript.shipped(_store)[2].rows)
    controls.build_for(descriptor)
    controls.sync(_brush, TOOL_ID, 1.0)
    var list := controls.control(&"picture_name") as SaChoiceButton
    assert_not_null(list, "The controls build the Pattern row")
    assert_eq(list.selected_value(), "Paper Grain", "showing the pattern the settings hold")
    assert_true(list.pick_row("Dot Screen"), "A press on Dot Screen's row is taken")
    assert_eq(_brush.settings.picture_name, "Dot Screen", "and writes picture_name")
    assert_true(
        _brush.settings.chosen_picture.holds("Dot Screen"),
        "and the settings make its picture (%s)" % _brush.settings.chosen_picture.error
    )
    var after := _painted()
    var painted := after.count(true)
    assert_true(
        painted > 0 and painted < after.size(),
        "The stroke paints through it and leaves holes, %d of %d" % [painted, after.size()]
    )
    assert_true(after != before, "in another pattern than Paper Grain's")
    host.free()


## The docker draws a field's rows only while that field is chosen: Picture's
## Pattern row while Picture is, and Grain's rows in its place once Grain is.
## The noise brush is registered as a tool of its own here, because the
## fixture's registry carries the stamp and the base module and no engine.
func test_the_docker_draws_the_pattern_row_only_while_picture_is_chosen() -> void:
    var advanced := SaSettings.advanced_options
    SaSettings.advanced_options = true
    var fields: RefCounted = NoiseFieldsScript.new()
    fields.register_shipped(_store)
    var descriptor := SaToolDescriptor.create(TOOL_ID, StateNoiseBrushScript)
    descriptor.options = NoiseModuleScript.options(fields)
    var registry := Fixtures.make_tool_registry()
    assert_true(registry.register(descriptor), "The noise brush registers as a tool")
    var machine := ToolMachine.new()
    machine.name = "ToolMachine"
    machine._ready()
    machine.bind(_surface, registry)
    var host := Node.new()
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)
    docker.target_tool_machine = machine
    machine.set_active_tool(TOOL_ID)
    var settings: Resource = machine.get_tool(TOOL_ID).settings
    settings.texture_field = NoiseFieldsScript.PICTURE
    docker.sync_from_tool()
    var shown := docker.shown_keys()
    assert_true(shown.has(&"picture_name"), "With Picture chosen the docker draws the Pattern row: %s" % [shown])
    assert_false(shown.has(&"grain_scale"), "and not Grain's Scale")
    settings.texture_field = NoiseFieldsScript.GRAIN
    docker.sync_from_tool()
    shown = docker.shown_keys()
    assert_false(shown.has(&"picture_name"), "With Grain chosen the Pattern row leaves the docker")
    assert_true(shown.has(&"grain_scale"), "and Grain's Scale is drawn")
    host.free()
    Fixtures.teardown(null, machine)
    SaSettings.advanced_options = advanced


func _pattern_spec() -> SaOptionSpec:
    for spec: SaOptionSpec in NoiseFieldsScript.shipped(_store)[2].rows:
        if spec.key == &"picture_name":
            return spec
    return null


## A grey picture of stripes, a pattern the store reads as an image.
func _write_picture(path: String) -> void:
    var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
    for y in 16:
        for x in 16:
            var grey := 1.0 if posmod(floori(x / 4.0), 2) == 0 else 0.2
            image.set_pixel(x, y, Color(grey, grey, grey, 1.0))
    image.save_png(path)


## Whether each texel well inside the tip is painted by a press at [constant
## SPOT], on a fresh surface.
func _painted() -> Array[bool]:
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface()
    _brush.surface = _surface
    _brush.begin_stroke(SPOT, 1.0)
    _brush.end_stroke()
    var layer := _surface.easel.document.active_layer
    var images := {}
    var out: Array[bool] = []
    var reach := int(INSIDE)
    for y in range(-reach, reach + 1):
        for x in range(-reach, reach + 1):
            if Vector2(x, y).length() > INSIDE:
                continue
            out.append(_alpha(layer, Vector2i(SPOT) + Vector2i(x, y), images) > 0.5)
    return out


func _alpha(layer: SaLayer, pixel: Vector2i, images: Dictionary) -> float:
    for grid: Vector2i in layer.chunks:
        var side := (layer.chunks[grid] as SaChunk).pixel_size()
        var here := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
        if not layer.chunks.has(here):
            return 0.0
        if not images.has(here):
            @warning_ignore("static_called_on_instance")
            images[here] = SaExport.get_texture_image_float(layer.get_field(here))
        return (images[here] as Image).get_pixelv(pixel - here * side).a
    return 0.0
