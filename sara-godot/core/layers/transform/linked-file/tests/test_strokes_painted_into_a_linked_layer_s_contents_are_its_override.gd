## Strokes painted into a linked layer's contents are its
## override, kept over the file's picture. A brush stroke is painted in the
## contents of a layer linked to a PNG, the PNG is replaced and reloaded, and
## the stroke is read on top of the new picture. A save and an open of a file
## whose picture changed again keep it, a missing file keeps it with the
## picture under it, and Clear Override leaves the file's picture alone, as one
## history step.
##
## The fixtures are two PNGs written by the suite into a folder of its own
## under the data root, a red square with a blue bar and a green one with
## noise in it, as the sibling suite writes them. The layer is linked at no map, so
## a position in its contents is the position on the canvas.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 512)
const PICTURE := Vector2i(300, 200)
## The stroke's path in the contents, a frame a step, across the blue bar.
const FROM := Vector2(60.0, 60.0)
const STEP := Vector2(12.0, 0.0)
const STEPS := 12
## A texel on the stroke's path, and one far from it inside the picture.
const ON := Vector2(132.0, 60.0)
const OFF := Vector2(250.0, 170.0)
## What two readings of one texel may differ by.
const SAME := 1.0e-3

var _folder := ""
var _fixture := ""


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _folder = ProjectSettings.globalize_path(SaDataRoot.path("linked_override"))
    _clear(_folder)
    DirAccess.make_dir_recursive_absolute(_folder)
    _fixture = _folder.path_join("logo.png")
    _write(_fixture, false)


func after_each() -> void:
    _clear(_folder)


static func _clear(folder: String) -> void:
    if not DirAccess.dir_exists_absolute(folder):
        return
    for file in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(file))
    DirAccess.remove_absolute(folder)


## The first picture, or the second when *second*.
static func _write(path: String, second: bool) -> void:
    var image := Image.create_empty(PICTURE.x, PICTURE.y, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.1, 0.7, 0.2, 1.0) if second else Color(0.9, 0.1, 0.1, 1.0))
    if second:
        var noise := RandomNumberGenerator.new()
        noise.seed = 150
        for y in PICTURE.y:
            for x in PICTURE.x:
                image.set_pixel(x, y, Color(0.1, noise.randf(), 0.2, 1.0))
    else:
        image.fill_rect(Rect2i(20, 40, 260, 40), Color(0.1, 0.2, 0.9, 1.0))
    image.save_png(path)


static func _surface() -> SaSurface:
    var surface := Fixtures.make_surface(SIZE)
    surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    (surface.get_document().get_node("Background") as SaLayer).visible = false
    return surface


static func _button(machine: ToolMachine, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = machine.surface.view.mouse_position
    machine.active_tool.handle_input(event)


static func _move(machine: ToolMachine, at: Vector2) -> void:
    machine.surface.view.mouse_position = at
    var motion := InputEventMouseMotion.new()
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    motion.position = at
    motion.pressure = 1.0
    machine.active_tool.handle_input(motion)


static func _frame(surface: SaSurface, machine: ToolMachine) -> void:
    machine._process(1.0 / 60.0)
    (Engine.get_main_loop() as SceneTree).process_frame.emit()
    surface.easel.process_pending_composite()


static func _redraw(surface: SaSurface, machine: ToolMachine) -> void:
    _frame(surface, machine)
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()


## A brush stroke along FROM painted in *layer*'s contents, opened for it and
## closed after, the way the view paints.
static func _paint_in(surface: SaSurface, machine: ToolMachine, layer: SaLayer) -> void:
    var doc := surface.get_document()
    doc.set_active_layer(layer)
    SaLocalView.begin(doc, null, Rect2(), layer)
    _redraw(surface, machine)
    surface.view.mouse_position = FROM
    _button(machine, true)
    for i in range(1, STEPS + 1):
        _move(machine, FROM + STEP * i)
        _frame(surface, machine)
    _button(machine, false)
    _frame(surface, machine)
    SaLocalView.end(doc, null)
    _redraw(surface, machine)


## The colour *layer*'s contents hold at *at*, clear where they hold no chunk.
static func _texel(layer: SaLayer, at: Vector2) -> Color:
    var grid_pos := Vector2i(floori(at.x / SaLayer.CHUNK_SIZE), floori(at.y / SaLayer.CHUNK_SIZE))
    if layer == null or not layer.chunks.has(grid_pos):
        return Color(0, 0, 0, 0)
    var chunk: SaChunk = layer.chunks[grid_pos]
    var texture := chunk.albedo()
    var texel := Vector2i(at - Vector2(grid_pos * chunk.pixel_size()))
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, texel.y * texture.size.x + texel.x)


## The colour an import of the fixture as it stands puts at *at*.
func _imported(at: Vector2) -> Color:
    var other := _surface()
    var colour := _texel(SaImageImport.open_into(other.get_document(), _fixture), at)
    Fixtures.teardown(other)
    return colour


static func _near(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < SAME and absf(a.g - b.g) < SAME and absf(a.b - b.b) < SAME and absf(a.a - b.a) < SAME


## A linked layer named Paint over the first picture with a stroke painted in
## its contents. Answers the surface, the machine and the layer.
func _painted() -> Array:
    var surface := _surface()
    var machine := Fixtures.make_bound_machine(surface)
    var doc := surface.get_document()
    var paint := SaLayerOps.new(doc).add()
    paint.name = "Paint"
    assert_true(SaLinkedFile.link_file(doc, paint, _fixture), "Link to File links the layer")
    machine.set_active_tool(&"brush")
    _redraw(surface, machine)
    var red := _texel(paint, ON)
    _paint_in(surface, machine, paint)
    assert_false(_near(_texel(paint, ON), red), "The stroke is painted into the contents: %s over %s" % [_texel(paint, ON), red])
    return [surface, machine, paint]


## *sad* opened into a surface of its own, answered with its Paint layer.
static func _opened(sad: String) -> Array:
    var loaded := _surface()
    var error := SaExport.load_sad(loaded.get_document(), sad, loaded.easel.compositor)
    return [loaded, loaded.get_document().get_node_or_null("Paint") as SaLayer, error]


## The first clause: the file replaced and reloaded, the new picture is
## underneath and the stroke is still on top, and one undo gives the old
## picture back with the stroke.
func test_a_reload_puts_the_new_picture_under_the_stroke() -> void:
    var made := _painted()
    var surface: SaSurface = made[0]
    var paint: SaLayer = made[2]
    var doc := surface.get_document()
    var stroke := _texel(paint, ON)
    var first := _texel(paint, OFF)
    _write(_fixture, true)
    var second := _imported(OFF)
    assert_false(_near(first, second), "The second picture differs from the first off the stroke")
    assert_true(SaLinkedFile.reload_file(doc, paint), "Reload Linked File reads the new picture")
    assert_true(_near(_texel(paint, OFF), second), "which is underneath: %s, the file %s" % [_texel(paint, OFF), second])
    assert_true(_near(_texel(paint, ON), stroke), "and the stroke is still on top: %s, painted %s" % [_texel(paint, ON), stroke])
    var fresh := _imported(ON)
    assert_false(_near(_texel(paint, ON), fresh), "rather than the new picture there")
    assert_true(doc.undo(), "One undo")
    assert_true(_near(_texel(paint, OFF), first), "gives the old picture back")
    assert_true(_near(_texel(paint, ON), stroke), "with the stroke on it")
    Fixtures.teardown(surface, made[1])


## The second clause: a save and an open read the stroke again, over the
## picture the file holds when it is opened, which changed after the save.
func test_a_save_and_an_open_keep_the_stroke_over_the_file() -> void:
    var made := _painted()
    var surface: SaSurface = made[0]
    var paint: SaLayer = made[2]
    var doc := surface.get_document()
    var stroke := _texel(paint, ON)
    var sad := _folder.path_join("override.sad")
    assert_eq(SaSadFile.save_file(doc, sad, 0), OK, "It saves")
    _write(_fixture, true)
    var second := _imported(OFF)
    var opened := _opened(sad)
    var back: SaLayer = opened[1]
    assert_eq(opened[2], OK, "and opens with the file changed since")
    assert_not_null(SaLinkedFile.link_of(back), "linked")
    assert_true(_near(_texel(back, ON), stroke), "The stroke is read again: %s, painted %s" % [_texel(back, ON), stroke])
    assert_true(_near(_texel(back, OFF), second), "over the picture the file holds now: %s, %s" % [_texel(back, OFF), second])

    var resaved := _folder.path_join("again.sad")
    var reopened_doc := (opened[0] as SaSurface).get_document()
    assert_eq(SaSadFile.save_file(reopened_doc, resaved, 0), OK, "The opened document saves again")
    _write(_fixture, false)
    var first := _imported(OFF)
    var again := _opened(resaved)
    var twice: SaLayer = again[1]
    assert_true(_near(_texel(twice, ON), stroke), "and the stroke survives a second open")
    assert_true(_near(_texel(twice, OFF), first), "over the first picture again")
    Fixtures.teardown(again[0])
    Fixtures.teardown(opened[0])
    Fixtures.teardown(surface, made[1])


## The third clause: Clear Override leaves the file's picture alone, as one
## history step whose undo puts the stroke back, and a second Clear Override
## finds nothing to drop and writes no step.
func test_clear_override_leaves_the_files_picture_alone() -> void:
    var made := _painted()
    var surface: SaSurface = made[0]
    var paint: SaLayer = made[2]
    var doc := surface.get_document()
    var stroke := _texel(paint, ON)
    var under := _imported(ON)
    var steps := doc.history.step_count()
    assert_true(SaLinkedFile.clear_override(doc, paint), "Clear Override runs")
    assert_eq(doc.history.step_count(), steps + 1, "as one history step")
    assert_true(_near(_texel(paint, ON), under), "and the file's picture is alone: %s, the file %s" % [_texel(paint, ON), under])
    assert_false(SaLinkedFile.clear_override(doc, paint), "A second Clear Override drops nothing")
    assert_true(SaProblems.pending_refusals[-1].contains("no strokes"), "and says so: %s" % SaProblems.pending_refusals[-1])
    assert_eq(doc.history.step_count(), steps + 1, "with no step written")
    assert_true(doc.undo(), "One undo")
    assert_true(_near(_texel(paint, ON), stroke), "puts the stroke back")
    Fixtures.teardown(surface, made[1])


## A missing file at open keeps the stroke and the picture under it, so Clear
## Override still gives the picture the file had.
func test_a_missing_file_keeps_the_picture_under_the_stroke() -> void:
    var made := _painted()
    var surface: SaSurface = made[0]
    var paint: SaLayer = made[2]
    var doc := surface.get_document()
    var stroke := _texel(paint, ON)
    var under := _imported(ON)
    var sad := _folder.path_join("missing.sad")
    assert_eq(SaSadFile.save_file(doc, sad, 0), OK, "It saves")
    DirAccess.remove_absolute(_fixture)
    var opened := _opened(sad)
    var back: SaLayer = opened[1]
    var state: String = SaLinkedFile.link_of(back).state if back != null else ""
    assert_eq(state, SaLinkedFile.MISSING, "With the file gone the link is missing")
    assert_true(_near(_texel(back, ON), stroke), "and the stroke is kept")
    var reopened_doc := (opened[0] as SaSurface).get_document()
    assert_true(SaLinkedFile.clear_override(reopened_doc, back), "Clear Override runs on it")
    assert_true(_near(_texel(back, ON), under), "and gives the picture the file had under it: %s, %s" % [_texel(back, ON), under])
    Fixtures.teardown(opened[0])
    Fixtures.teardown(surface, made[1])
