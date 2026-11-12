## The Crop tool's box sets a live crop on the active layer.
## The crop is a rectangle of the layer's own pixels kept with its live
## transform, the layer draws nothing outside it, its chunks keep every pixel
## they were painted with, the crop is saved with the layer, and the document
## keeps its size. The tool writes the crop as the drag goes, Enter makes it
## one history step and Escape puts the layer back.
##
## That is a smart layer's crop, a layer that carries a
## live transform, so the painting here is made smart by an identity map. On an
## ordinary layer Enter writes the crop into the chunks, which the tool's own
## test below reads.
##
## The painting: two chunks across and two down, the grey background showing,
## and one layer named Paint holding PAINT over the whole of its top two
## chunks. BOX straddles the seam between them, so the crop is read on both
## sides of a chunk edge.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 512)
const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const PAINTED: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
const BOX := Rect2i(200, 40, 120, 100)
## BOX grown by ten columns on its right, all of them in the chunk at (1, 0).
const WIDER := Rect2i(200, 40, 130, 100)
## A place the paint never reached, where the composite is the background's.
const GROUND_AT := Vector2i(100, 400)
const TOLERANCE := 1.0e-4
## The Crop option's Layer, the first of the tool's `Mode`, set by name since
## the tool is the base module's and Canvas is its default now.
const LAYER_MODE := 0


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()


## The painting of the header, with Paint active and smart, composited once.
func _painting() -> SaEasel:
    var easel := Bench.easel(SIZE)
    var doc := easel.document
    var paint := doc.get_node("Layer 1") as SaLayer
    paint.name = "Paint"
    doc.set_active_layer(paint)
    _paint(paint)
    SaLiveTransform.put(doc, paint, Basis.IDENTITY)
    Bench.composite(easel)
    return easel


## Fills PAINTED of *layer* with PAINT, uploaded whole, since the brush is not
## what this suite is about.
static func _paint(layer: SaLayer) -> void:
    for at: Vector2i in PAINTED:
        var texture := layer.get_or_create_chunk(at).albedo()
        var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAF)
        image.fill(PAINT)
        if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
            image.convert(Image.FORMAT_RGBAH)
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
        layer.mark_unresolved(at)


## The bytes of every chunk *layer* holds, by position.
static func _chunks_of(layer: SaLayer) -> Dictionary:
    var found := {}
    for at: Vector2i in layer.chunks:
        found[at] = GlobalShaderCompiler.get_rd().texture_get_data(layer.get_field(at).rid, 0)
    return found


static func _near(a: Color, b: Color) -> bool:
    return (
        absf(a.r - b.r) <= TOLERANCE
        and absf(a.g - b.g) <= TOLERANCE
        and absf(a.b - b.b) <= TOLERANCE
        and absf(a.a - b.a) <= TOLERANCE
    )


## Reads PAINT on the four corner texels of *box* and its middle, and the
## background on the texel just outside each of its four sides, where the
## layer holds paint too.
func _shows_inside_only(easel: SaEasel, box: Rect2i, ground: Color, what: String) -> void:
    var last := box.end - Vector2i.ONE
    var inside: Array[Vector2i] = [
        box.position, last, Vector2i(last.x, box.position.y), Vector2i(box.position.x, last.y), box.get_center()
    ]
    for at in inside:
        var shown := Bench.texel(easel.output, at)
        assert_true(_near(shown, PAINT), "%s: the paint inside at %s, %s" % [what, at, shown])
    var middle := box.get_center()
    for at: Vector2i in [
        Vector2i(box.position.x - 1, middle.y),
        Vector2i(box.end.x, middle.y),
        Vector2i(middle.x, box.position.y - 1),
        Vector2i(middle.x, box.end.y),
    ]:
        var shown := Bench.texel(easel.output, at)
        assert_true(_near(shown, ground), "%s: the background just outside at %s, %s" % [what, at, shown])


## Reads PAINT across the whole of what was painted, the texels BOX left out
## included.
func _shows_whole(easel: SaEasel, what: String) -> void:
    for at: Vector2i in [Vector2i(0, 0), Vector2i(511, 255), Vector2i(BOX.position.x - 1, 90), Vector2i(BOX.end.x, 90)]:
        var shown := Bench.texel(easel.output, at)
        assert_true(_near(shown, PAINT), "%s: the paint at %s, %s" % [what, at, shown])


## Composites what the document says changed, as a frame of the app does.
static func _redraw(easel: SaEasel) -> void:
    easel.document.update_caches()
    easel.process_pending_composite()


static func _crop(doc: SaDocument, layer: SaLayer, box: Rect2i) -> bool:
    var before := SaLiveTransform.of(layer)
    return SaLiveTransform.crop_to(doc, layer, box) and SaLiveTransform.commit(doc, layer, before)


## Whether *layer* draws all its paint, with no crop or no transform.
static func _uncropped(layer: SaLayer) -> bool:
    return SaLiveTransform.of(layer) == null or not SaLiveTransform.of(layer).crop.any()


func test_a_crop_shows_the_paint_only_inside_and_the_layer_keeps_its_chunks() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var ground := Bench.texel(easel.output, GROUND_AT)
    var painted := _chunks_of(paint)
    _shows_whole(easel, "Before the crop")
    var steps := doc.history.step_count()
    assert_true(_crop(doc, paint, BOX), "The crop is set and written")
    assert_eq(doc.history.step_count(), steps + 1, "as one step")
    Bench.composite(easel)
    _shows_inside_only(easel, BOX, ground, "Cropped, the layer active")
    assert_eq(SaLiveTransform.of(paint).crop.rect, BOX, "The crop is the box, in the layer's own pixels under no map")
    assert_eq(_chunks_of(paint), painted, "The layer's chunks hold every byte painted, outside the box too")
    assert_eq(doc.canvas_size, SIZE, "and the document keeps its size")
    SaLayerOps.new(doc).add()
    Bench.composite(easel)
    _shows_inside_only(easel, BOX, ground, "Cropped, another layer active")
    assert_true(_near(Bench.texel(easel.output, GROUND_AT), ground), "The background shows whole where nothing covers it")
    assert_true(doc.undo(), "The layer added is undone")
    assert_true(doc.undo(), "and the crop is one step")
    _redraw(easel)
    assert_true(_uncropped(paint), "Undone, the layer has no crop")
    _shows_whole(easel, "Undone")
    assert_true(doc.redo(), "and redone")
    _redraw(easel)
    _shows_inside_only(easel, BOX, ground, "Redone")
    easel.free()


## The Done clause of the suite: saved and opened again, the layer has its
## rectangle and its own chunks byte for byte, and draws as it did.
func test_a_cropped_layer_saves_and_opens_with_its_rectangle_and_its_own_chunks() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var ground := Bench.texel(easel.output, GROUND_AT)
    var painted := _chunks_of(paint)
    assert_true(_crop(doc, paint, BOX), "The crop is set")
    Bench.composite(easel)
    var path := ProjectSettings.globalize_path(SaDataRoot.path("g4_live_crop.sad"))
    assert_eq(SaExport.save_sad(doc, path), OK, "It saves")
    var loaded := Bench.easel(SIZE)
    assert_eq(SaExport.load_sad(loaded.document, path, loaded.compositor), OK, "It opens")
    DirAccess.remove_absolute(path)
    var reopened := loaded.document.get_node("Paint") as SaLayer
    var live := SaLiveTransform.of(reopened)
    assert_not_null(live, "with the layer's live transform")
    if live != null:
        assert_eq(live.crop.rect, BOX, "holding the rectangle as saved")
        assert_eq(live.matrix, Basis.IDENTITY, "under no map")
    assert_eq(_chunks_of(reopened), painted, "and its own chunks as saved, the paint outside the rectangle too")
    loaded.document.set_active_layer(reopened)
    Bench.composite(loaded)
    _shows_inside_only(loaded, BOX, ground, "Opened again")
    easel.free()
    loaded.free()


## Layer > Convert to Ordinary Layer writes the crop in with the map: the paint outside
## the box is cleared, a chunk the box leaves wholly outside is dropped, the
## picture is what the crop showed, and one undo gives the crop and every
## painted byte back.
func test_the_bake_clears_the_paint_outside_the_crop() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var ground := Bench.texel(easel.output, GROUND_AT)
    var painted := _chunks_of(paint)
    var inner := Rect2i(40, 40, 100, 80)
    assert_true(_crop(doc, paint, inner), "A box inside the first chunk crops the layer")
    assert_true(SaLiveTransform.bake(doc, paint), "and the crop bakes")
    _redraw(easel)
    assert_null(paint.live_transform, "Baked, the layer has no live transform")
    assert_eq(paint.chunks.keys(), [Vector2i(0, 0)], "and the chunk the box left out is dropped")
    var field := paint.get_field(Vector2i(0, 0))
    assert_true(_near(Bench.texel(field, inner.get_center()), PAINT), "The paint inside stays")
    for at: Vector2i in [Vector2i(39, 80), Vector2i(140, 80), Vector2i(90, 39), Vector2i(90, 120), Vector2i(255, 255)]:
        assert_true(Bench.texel(field, at).a <= TOLERANCE, "and the layer is empty outside at %s" % at)
    _shows_inside_only(easel, inner, ground, "Baked")
    assert_true(doc.undo(), "The bake undoes")
    _redraw(easel)
    assert_eq(SaLiveTransform.of(paint).crop.rect, inner, "to the crop")
    assert_eq(_chunks_of(paint), painted, "and every byte painted")
    _shows_inside_only(easel, inner, ground, "Undone")

    assert_true(doc.undo(), "The crop undoes too")
    assert_true(_crop(doc, paint, BOX), "A box across the seam crops the layer")
    assert_true(SaLiveTransform.bake(doc, paint), "and bakes")
    _redraw(easel)
    assert_eq(paint.chunks.size(), 2, "Both chunks the box reaches stay")
    var left := paint.get_field(Vector2i(0, 0))
    var right := paint.get_field(Vector2i(1, 0))
    assert_true(Bench.texel(left, Vector2i(BOX.position.x - 1, 90)).a <= TOLERANCE, "empty left of the box")
    assert_true(_near(Bench.texel(left, Vector2i(BOX.position.x, 90)), PAINT), "painted at its left edge")
    assert_true(_near(Bench.texel(right, Vector2i(BOX.end.x - 257, 90)), PAINT), "painted at its right edge")
    assert_true(Bench.texel(right, Vector2i(BOX.end.x - 256, 90)).a <= TOLERANCE, "and empty right of it")
    _shows_inside_only(easel, BOX, ground, "Baked across the seam")
    easel.free()


## A crop changed while the drag goes is drawn without a step, the layer active
## or not, and a change of the rectangle alone draws again only the strip
## between the two, not the cache's chunks.
func test_a_crop_moved_by_a_drag_draws_only_the_strip_between() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var ground := Bench.texel(easel.output, GROUND_AT)
    var steps := doc.history.step_count()
    assert_true(SaLiveTransform.crop_to(doc, paint, BOX), "The crop is shown")
    Bench.composite(easel)
    assert_true(SaLiveTransform.crop_to(doc, paint, WIDER), "and widened")
    easel.process_pending_composite()
    _shows_inside_only(easel, WIDER, ground, "Widened while the drag goes, the layer active")
    SaLayerOps.new(doc).add()
    Bench.composite(easel)
    assert_true(SaLiveTransform.crop_to(doc, paint, BOX), "and narrowed again with another layer active")
    easel.process_pending_composite()
    _shows_inside_only(easel, BOX, ground, "Narrowed while the drag goes, another layer active")
    assert_eq(doc.history.step_count(), steps + 1, "None of it is a step, only the layer added")

    var shown := SaLiveTransform.of(paint)
    var wider := SaLiveTransform.new(Basis.IDENTITY, SaLiveCrop.new(WIDER))
    wider._take(shown, paint)
    paint.live_transform = wider
    var changed := wider._settle(paint, {})
    assert_eq(changed.keys(), [Vector2i(1, 0)], "Only the chunk the ten columns lie in is drawn again")
    var strip: Rect2i = changed.get(Vector2i(1, 0), Rect2i())
    assert_true(strip.size.x <= 16 and strip.size.y <= BOX.size.y + 4, "and only the strip of it, %s" % strip)
    easel.free()


## A crop under a map: the box is in document pixels, the crop in the layer's
## own, and a new map keeps the crop the layer has.
func test_a_crop_under_a_quarter_turn_is_the_box_taken_back_through_the_map() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var turned := SaLiveTransform.composed(Vector2(0.0, 256.0), 90.0, Vector2.ONE, Vector2(256.0, 256.0))
    assert_true(SaLiveTransform.put(doc, paint, turned), "A quarter turn is put on")
    # The turn takes the texel at (x, y) to (511 - y, x + 256).
    var box := Rect2i(400, 300, 50, 40)
    assert_true(_crop(doc, paint, box), "The box crops the turned layer")
    var live := SaLiveTransform.of(paint)
    assert_eq(live.crop.rect, Rect2i(44, 62, 40, 50), "and the crop is the box turned back")
    assert_eq(SaLiveTransform.crop_box(paint), box, "which the map takes to the box again")
    var ground := Bench.texel(easel.output, GROUND_AT)
    Bench.composite(easel)
    _shows_inside_only(easel, box, ground, "Cropped under the turn")
    assert_true(SaLiveTransform.put(doc, paint, Basis.IDENTITY), "The map is taken back to none")
    assert_eq(SaLiveTransform.of(paint).crop.rect, live.crop.rect, "and the crop stays, in the layer's own pixels")
    easel.free()


## The Transform tool's session draws each map with `preview` and ends in one
## `put`, from the map it opened on. The crop stays through all of it and
## through its undo, so a crop is never lost to a move.
func test_a_transform_session_keeps_the_crop_through_its_step_and_its_undo() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    assert_true(_crop(doc, paint, BOX), "The layer is cropped")
    var moved := SaLiveTransform.composed(Vector2(30.0, 50.0), 0.0, Vector2.ONE, Vector2.ZERO)
    assert_true(SaLiveTransform.preview(doc, paint, moved), "A session draws a move")
    assert_eq(SaLiveTransform.of(paint).crop.rect, BOX, "and the crop goes with it")
    assert_true(SaLiveTransform.preview(doc, paint, Basis.IDENTITY), "The session shows the map it opened on")
    assert_true(SaLiveTransform.put(doc, paint, moved), "and ends in one step")
    assert_eq(SaLiveTransform.of(paint).crop.rect, BOX, "which keeps the crop")
    assert_eq(SaLiveTransform.crop_box(paint), Rect2i(BOX.position + Vector2i(30, 50), BOX.size), "moved with the paint")
    var ground := Bench.texel(easel.output, GROUND_AT)
    Bench.composite(easel)
    _shows_inside_only(easel, Rect2i(BOX.position + Vector2i(30, 50), BOX.size), ground, "Moved")
    assert_true(doc.undo(), "The move undoes")
    _redraw(easel)
    assert_eq(SaLiveTransform.of(paint).crop.rect, BOX, "to the crop")
    assert_eq(SaLiveTransform.of(paint).matrix, Basis.IDENTITY, "under no map")
    _shows_inside_only(easel, BOX, ground, "Undone")
    easel.free()


## The tool on an ordinary layer: the drag shows the crop with no step, Enter
## writes it into the layer's chunks as one step and leaves no transform, the
## rule, a second drag shows its own crop, Escape puts the
## written layer back, the document keeps its size throughout, and one undo
## gives every byte painted back.
func test_the_tool_crops_as_the_drag_goes_and_enter_and_escape_end_it() -> void:
    var surface := Fixtures.make_surface(SIZE)
    var machine := Fixtures.make_bound_machine(surface)
    var doc := surface.get_document()
    var layer := doc.active_layer
    _paint(layer)
    var painted := _chunks_of(layer)
    machine.set_active_tool(&"crop")
    var tool := machine.active_tool
    # The live transform is the skeleton's, reached through the role registry a
    # bare machine does not hand the tool.
    tool.roles = Fixtures.make_registries().roles
    tool.set(&"mode", LAYER_MODE)
    var steps := doc.history.step_count()

    _press(tool, surface.view, Vector2(100, 100))
    _move(tool, surface.view, Vector2(300, 200))
    assert_eq(SaLiveTransform.of(layer).crop.rect, Rect2i(100, 100, 200, 100), "The crop follows the drag")
    _move(tool, surface.view, Vector2(320, 230))
    assert_eq(SaLiveTransform.of(layer).crop.rect, Rect2i(100, 100, 220, 130), "move by move")
    _release(tool)
    assert_eq(doc.history.step_count(), steps, "with no step while the session is open")
    tool.handle_input(_key(KEY_ENTER))
    assert_eq(doc.history.step_count(), steps + 1, "Enter writes one step")
    assert_null(layer.live_transform, "which leaves the ordinary layer no transform")
    var left := layer.get_field(Vector2i(0, 0))
    var right := layer.get_field(Vector2i(1, 0))
    assert_true(_near(Bench.texel(left, Vector2i(150, 150)), PAINT), "The paint inside the box stays")
    assert_true(_near(Bench.texel(right, Vector2i(319 - 256, 229)), PAINT), "to its far corner")
    for at: Vector2i in [Vector2i(99, 150), Vector2i(150, 99), Vector2i(150, 230)]:
        assert_true(Bench.texel(left, at).a <= TOLERANCE, "and the layer is empty outside it at %s" % at)
    assert_true(Bench.texel(right, Vector2i(320 - 256, 150)).a <= TOLERANCE, "and right of it")
    assert_eq(tool.pending_rect(), Rect2i(Vector2i.ZERO, SIZE), "and the box is back on the canvas")
    var written := _chunks_of(layer)

    _press(tool, surface.view, Vector2(150, 120))
    _move(tool, surface.view, Vector2(400, 180))
    _release(tool)
    assert_eq(SaLiveTransform.of(layer).crop.rect, Rect2i(150, 120, 250, 60), "A second drag shows its own crop")
    tool.handle_input(_key(KEY_ESCAPE))
    assert_null(layer.live_transform, "and Escape takes it off")
    assert_eq(_chunks_of(layer), written, "leaving the first crop as it was written")
    assert_eq(doc.history.step_count(), steps + 1, "with no step")
    assert_eq(doc.canvas_size, SIZE, "The document keeps its size")
    assert_true(doc.undo(), "Undo")
    assert_null(layer.live_transform, "leaves no transform")
    assert_eq(_chunks_of(layer), painted, "and gives every byte painted back")
    assert_true(doc.redo(), "Redo")
    assert_eq(_chunks_of(layer), written, "writes the crop in again")
    Fixtures.teardown(surface, machine)


## A layer that takes no crop is said so once a drag, at the press and not at
## every move, and once more at Enter, which asks again. It keeps no crop.
func test_a_locked_layer_refuses_the_crop_with_a_sentence() -> void:
    var surface := Fixtures.make_surface(SIZE)
    var machine := Fixtures.make_bound_machine(surface)
    var doc := surface.get_document()
    var layer := doc.active_layer
    _paint(layer)
    layer.is_locked = true
    machine.set_active_tool(&"crop")
    var tool := machine.active_tool
    tool.roles = Fixtures.make_registries().roles
    tool.set(&"mode", LAYER_MODE)
    _press(tool, surface.view, Vector2(100, 100))
    _move(tool, surface.view, Vector2(300, 200))
    _move(tool, surface.view, Vector2(320, 230))
    _release(tool)
    assert_eq(SaProblems.pending_refusals.size(), 1, "The drag says one sentence")
    tool.handle_input(_key(KEY_ENTER))
    assert_eq(SaProblems.pending_refusals.size(), 2, "and Enter one more")
    var said := SaProblems.pending_refusals[0] if not SaProblems.pending_refusals.is_empty() else ""
    assert_true(said.contains("locked"), "saying the layer is locked: %s" % said)
    assert_null(layer.live_transform, "and the layer has no crop")
    Fixtures.teardown(surface, machine)


static func _press(tool: ToolState, view: SaView, at: Vector2) -> void:
    (view as Fixtures.FakeView).mouse_position = at
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    tool.handle_input(event)


static func _move(tool: ToolState, view: SaView, to: Vector2) -> void:
    (view as Fixtures.FakeView).mouse_position = to
    tool.handle_input(InputEventMouseMotion.new())


static func _release(tool: ToolState) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    tool.handle_input(event)


static func _key(code: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = true
    return event
