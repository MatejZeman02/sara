## A smart layer's contents open untransformed over a solid
## backdrop that never transfers. Edit Smart Layer Contents shows the layer
## drawn through no map while its map is held, any brush paints into it, a
## perspective map included, and closing it draws the map over the source as
## edited. With it open, an export, the save's preview, a `.sad` and a merge
## take the layer as the file draws it, and none of them holds the grey.
##
## The painting is four chunks across and four down, the grey background
## hidden, with a brush stroke painted along a row by the tool machine a frame
## a step, as `test_a_stroke_on_a_transformed_layer_lands_in_one_place_only`
## paints its own.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const LayersReport = preload("res://harness/report/sa_layers_report.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(1024, 1024)
const MIDDLE := Vector2(512.0, 512.0)
## The turned and scaled map of the first clause.
const MOVE := Vector2(180.0, 260.0)
const TURN := 30.0
const SCALE := Vector2(1.4, 1.4)
## The stroke's path in document pixels, a frame a step.
const FROM := Vector2(200.0, 200.0)
const STEP := Vector2(16.0, 0.0)
const STEPS := 14
const HALF := 7
## Where a stroke painted in the view starts.
const SECOND := Vector2(200.0, 330.0)
## What counts as paint.
const VISIBLE := 0.05
## A place no stroke and no map of this suite reaches.
const EMPTY := Vector2(980.0, 40.0)


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()


static func _surface() -> SaSurface:
    var surface := Fixtures.make_surface(SIZE)
    surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    (surface.get_document().get_node("Background") as SaLayer).visible = false
    return surface


static func _turned() -> Basis:
    return SaLiveTransform.composed(MOVE, TURN, SCALE, MIDDLE)


## A perspective whose corners pull the canvas's top edge in, which no stroke
## is painted through today.
static func _perspective() -> Variant:
    var corners := PackedVector2Array([Vector2(260, 120), Vector2(880, 180), Vector2(1000, 980), Vector2(60, 900)])
    return SaLiveTransform.cornered(Rect2(Vector2.ZERO, Vector2(SIZE)), corners)


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


## The whole canvas composited again, as a frame after a change of the view.
static func _redraw(surface: SaSurface, machine: ToolMachine) -> void:
    _frame(surface, machine)
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()


## A stroke of the active tool from FROM along STEP, a frame a step.
static func _stroke(surface: SaSurface, machine: ToolMachine, from := FROM) -> void:
    surface.view.mouse_position = from
    _button(machine, true)
    for i in range(1, STEPS + 1):
        _move(machine, from + STEP * i)
        _frame(surface, machine)
    _button(machine, false)
    _frame(surface, machine)


## The texel of *texture* at *at*, in its own pixels.
static func _texel(texture: SaTexture, at: Vector2) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var texel := Vector2i(at)
    return SaFieldSpec.decode_texel(bytes, texture.format, texel.y * texture.size.x + texel.x)


## Whether the canvas shows paint at *at*, a document position.
static func _shows(surface: SaSurface, at: Vector2) -> bool:
    return _texel(surface.easel.output, at).a > VISIBLE


## The colour *layer*'s own chunks hold at *at*, a document position, clear
## where it holds no chunk.
static func _held(layer: SaLayer, at: Vector2) -> Color:
    var grid_pos := Vector2i(floori(at.x / SaLayer.CHUNK_SIZE), floori(at.y / SaLayer.CHUNK_SIZE))
    if not layer.chunks.has(grid_pos):
        return Color(0, 0, 0, 0)
    var chunk: SaChunk = layer.chunks[grid_pos]
    return _texel(chunk.albedo(), at - Vector2(grid_pos * chunk.pixel_size()))


static func _report(doc: SaDocument, name: String) -> Dictionary:
    for entry: Dictionary in LayersReport.stack(doc):
        if entry["name"] == name:
            return entry
    return {}


## The middle of the stroke, and where the map shows it.
static func _middle() -> Vector2:
    return FROM + STEP * HALF


## The first clause: the view draws the layer through no map, its paint at its
## own place, while `SaLiveTransform.of` holds the real map, the layers report
## says the layer is open, and the Transform tool refuses with its corner line.
func test_the_view_draws_the_layer_through_no_map_and_the_transform_tool_refuses() -> void:
    var surface := _surface()
    var machine := Fixtures.make_bound_machine(surface)
    var doc := surface.get_document()
    var layer := doc.active_layer
    layer.name = "Paint"
    machine.set_active_tool(&"brush")
    _stroke(surface, machine)
    assert_true(SaLiveTransform.make_smart(doc, layer), "Make Smart Layer runs")
    assert_true(SaLiveTransform.put(doc, layer, _turned()), "and the turned and scaled map is put on")
    _redraw(surface, machine)
    var live := SaLiveTransform.of(layer)
    var shown := live.map_point(_middle())
    assert_true(_shows(surface, shown), "The canvas shows the stroke where the map takes it")
    assert_false(_shows(surface, _middle()), "and not where it was painted")

    assert_true(SaLocalView.begin(doc, null, Rect2(), layer), "Edit Smart Layer Contents opens")
    _redraw(surface, machine)
    assert_eq(SaLocalView.contents_of(doc), layer, "on the smart layer")
    assert_eq(SaLiveTransform.paint_of(layer), layer, "which is drawn through no map, its own chunks")
    assert_true(_shows(surface, _middle()), "The canvas shows the stroke where it was painted")
    assert_false(_shows(surface, shown), "and not where the map takes it")
    assert_eq(SaLiveTransform.of(layer), live, "SaLiveTransform.of still holds the real transform")
    assert_true(live.matrix.is_equal_approx(_turned()), "under the turned and scaled map")
    assert_true(_report(doc, "Paint").get("open", false), "The layers report says the layer is open")
    assert_true(_report(doc, "Paint").get("smart", false), "and smart")

    _stroke(surface, machine, SECOND)
    assert_true(_held(layer, SECOND + STEP * 3).a > VISIBLE, "A stroke painted in the view lands in the layer under the pointer")
    var heard: Array[String] = []
    var hear := func(said: String) -> void: heard.append(said)
    EventBus.paint_refused.connect(hear)
    var steps := doc.history.step_count()
    var chunks := layer.chunks.keys()
    machine.set_active_tool(&"transform")
    _frame(surface, machine)
    # The press lands inside the box the tool draws, which stands on the map.
    var quad: PackedVector2Array = machine.active_tool.pending_quad()
    var inside := (quad[0] + quad[1] + quad[2] + quad[3]) / 4.0
    surface.view.mouse_position = inside
    _button(machine, true)
    _move(machine, inside + Vector2(60, 40))
    _frame(surface, machine)
    _button(machine, false)
    _frame(surface, machine)
    machine.set_active_tool(&"brush")
    EventBus.paint_refused.disconnect(hear)
    assert_false(heard.is_empty(), "The Transform tool says in the corner why it did nothing")
    if not heard.is_empty():
        assert_true(heard[0].contains("open for painting"), "that the layer is open for painting: %s" % heard[0])
    assert_eq(doc.history.step_count(), steps, "and writes no step")
    assert_eq(SaLiveTransform.of(layer), live, "The transform is the one it was")
    assert_eq(layer.chunks.keys(), chunks, "and the layer's chunks are where they were")
    assert_true(_held(layer, SECOND + STEP * 3).a > VISIBLE, "and the stroke painted in the view is still in them")
    var line := SaContext.contents_refusal_line(layer, TranslationServer.translate(SaContext.TRANSFORM_GESTURE))
    assert_false(line.is_empty(), "The sentence is the door's own")
    assert_false(SaContext.refuse_paint(layer, "stroke"), "Every other tool paints")
    assert_false(layer.refuses_paint(), "a fill and a smudge among them")

    SaLocalView.end(doc, null)
    _redraw(surface, machine)
    assert_null(SaLocalView.contents_of(doc), "The same command closes it")
    assert_false(_report(doc, "Paint").get("open", true), "and the report says so")
    assert_true(_shows(surface, shown), "The map is drawn again")
    assert_false(_shows(surface, _middle()), "and the source's place is clear")
    var second := SECOND + STEP * 3
    assert_true(_shows(surface, live.map_point(second)), "and the stroke painted in the view shows through the map")
    assert_false(_shows(surface, second), "and not at its own place")
    Fixtures.teardown(surface, machine)


## The second clause: a stroke painted in the view onto a layer whose map is a
## perspective, which is refused today, shows through the map once the view
## closes, at the place the map gives and none at its own place.
func test_a_stroke_in_the_view_lands_through_a_perspective_once_it_closes() -> void:
    var surface := _surface()
    var machine := Fixtures.make_bound_machine(surface)
    var doc := surface.get_document()
    var layer := doc.active_layer
    assert_true(SaLiveTransform.make_smart(doc, layer), "Make Smart Layer runs")
    assert_true(SaLiveTransform.put(doc, layer, _perspective()), "and a perspective is put on")
    var live := SaLiveTransform.of(layer)
    assert_false(live.affine(), "which is no affine map")
    assert_true(layer.refuses_paint(true), "A brush is refused on it today")

    doc.selection.select_rect(Rect2i(Vector2i.ZERO, SIZE))
    assert_true(layer.refuses_paint(true), "and so is one inside a selection")

    assert_true(SaLocalView.begin(doc, null, Rect2(), layer), "The contents open")
    assert_false(layer.refuses_paint(true), "and a brush is taken, with the selection still on")
    assert_false(layer.refuses_paint(), "and every other tool")
    machine.set_active_tool(&"brush")
    _frame(surface, machine)
    _stroke(surface, machine)
    doc.selection.deselect()
    assert_true(_held(layer, _middle()).a > VISIBLE, "The stroke is in the layer's own pixels under the pointer")
    assert_true(_shows(surface, _middle()), "and on the canvas there")

    SaLocalView.end(doc, null)
    _redraw(surface, machine)
    var shown := live.map_point(_middle())
    assert_true(shown.distance_to(_middle()) > 64.0, "The map takes the stroke elsewhere, to %s" % shown)
    assert_true(_shows(surface, shown), "and the canvas shows it there once the view closes")
    assert_false(_shows(surface, _middle()), "and none at its untransformed place")
    for i: int in [2, STEPS - 2]:
        assert_true(_shows(surface, live.map_point(FROM + STEP * i)), "The stroke runs through the map at its step %d" % i)
    Fixtures.teardown(surface, machine)


## The third clause: with the view open, the export's flatten, the save's
## preview, a `.sad` and a merge of the smart layer down hold no grey and
## nothing where nothing was painted, and take the layer through its map.
func test_with_the_view_open_an_export_a_save_and_a_merge_hold_no_backdrop() -> void:
    var surface := _surface()
    var machine := Fixtures.make_bound_machine(surface)
    var doc := surface.get_document()
    var below := doc.active_layer
    below.name = "Below"
    var layer := SaLayerOps.new(doc).add()
    layer.name = "Paint"
    doc.set_active_layer(layer)
    machine.set_active_tool(&"brush")
    _frame(surface, machine)
    _stroke(surface, machine)
    assert_true(SaLiveTransform.make_smart(doc, layer), "Make Smart Layer runs")
    assert_true(SaLiveTransform.put(doc, layer, _turned()), "and the map is put on")
    var shown := SaLiveTransform.of(layer).map_point(_middle())
    assert_true(SaLocalView.begin(doc, null, Rect2(), layer), "The contents open")
    _redraw(surface, machine)
    assert_true(_shows(surface, _middle()), "The view draws the stroke untransformed")

    for kind: String in ["export", "preview"]:
        var image := SaExport.get_canvas_image(surface.easel) if kind == "export" else SaExport.get_preview_image(surface.easel)
        SaLocalView.resume(surface.easel)
        assert_not_null(image, "The %s reads the picture" % kind)
        if image == null:
            continue
        assert_eq(image.get_pixelv(Vector2i(EMPTY)).a, 0.0, "The %s is clear where nothing was painted, no grey" % kind)
        assert_true(image.get_pixelv(Vector2i(shown)).a > VISIBLE, "and holds the stroke through the map")
        assert_eq(image.get_pixelv(Vector2i(_middle())).a, 0.0, "and none at the untransformed place")
        assert_eq(_opaque_grey(image), 0, "and no texel of the backdrop's grey anywhere in the %s" % kind)
    assert_eq(SaLocalView.contents_of(doc), layer, "The view is still open after the reads")

    var path := ProjectSettings.globalize_path(SaDataRoot.path("contents_open.sad"))
    assert_eq(SaExport.save_sad(doc, path), OK, "It saves with the view open")
    var opened_surface := Fixtures.make_surface(SIZE)
    var opened_easel := opened_surface.easel
    assert_eq(SaExport.load_sad(opened_easel.document, path, opened_easel.compositor), OK, "and opens")
    DirAccess.remove_absolute(path)
    var opened := opened_easel.document.get_node_or_null("Paint") as SaLayer
    assert_not_null(opened, "with its smart layer")
    if opened != null:
        assert_true(SaLiveTransform.of(opened).matrix.is_equal_approx(_turned()), "under its map")
        assert_eq(_held(opened, EMPTY).a, 0.0, "its chunks clear where nothing was painted")
        assert_true(_held(opened, _middle()).a > VISIBLE, "and the source as painted")
        assert_eq(opened.chunks.keys().size(), layer.chunks.keys().size(), "no chunk more than the layer held")
    # The opened document is torn down too, or its easel, its compositor and
    # every texture they hold outlive the run and fail it as a leak.
    Fixtures.teardown(opened_surface)

    assert_true(SaLayerOps.new(doc).merge_down(layer), "The smart layer merges down with the view open")
    _redraw(surface, machine)
    assert_null(SaLocalView.contents_of(doc), "which ends the view, its layer gone")
    assert_eq(_held(below, EMPTY).a, 0.0, "The layer below is clear where nothing was painted")
    assert_eq(_held(below, _middle()).a, 0.0, "and at the untransformed place")
    assert_true(_held(below, shown).a > VISIBLE, "and holds the stroke where the map showed it")
    for grid_pos: Vector2i in below.chunks:
        var texture := (below.chunks[grid_pos] as SaChunk).albedo()
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var grey := 0
        for i in texture.size.x * texture.size.y:
            var texel := SaFieldSpec.decode_texel(bytes, texture.format, i)
            if _grey(texel):
                grey += 1
        assert_eq(grey, 0, "and no grey texel at %s" % grid_pos)
    Fixtures.teardown(surface, machine)


## How many texels of *image* are the backdrop's opaque grey.
static func _opaque_grey(image: Image) -> int:
    var count := 0
    for y in image.get_height():
        for x in image.get_width():
            if _grey(image.get_pixel(x, y)):
                count += 1
    return count


## Whether *c* is the backdrop's opaque grey.
static func _grey(c: Color) -> bool:
    return c.a > 0.99 and absf(c.r - c.g) < 0.01 and absf(c.g - c.b) < 0.01 and absf(c.r - 0.5) < 0.05
