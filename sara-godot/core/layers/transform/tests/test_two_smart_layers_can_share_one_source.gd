## Two smart layers can share one source, so one edit to it
## shows in both. Share Source with a Copy copies a smart layer onto the
## same source, each copy keeps a map of its own, a stroke painted in one's
## contents shows in both at the place each map gives, and Convert to Ordinary
## Layer, Make Source Independent, a delete and a save each treat the source as
## a shared pointer: it lives while a layer uses it, a user leaving bakes or
## copies only its own picture, and a file stores it once.
##
## The painting is four chunks across and four down, the grey background
## hidden, with brush strokes painted along a row by the tool machine a frame a
## step, as the sibling suite paints its own.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const LayersReport = preload("res://harness/report/sa_layers_report.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(1024, 1024)
const MIDDLE := Vector2(512.0, 512.0)
## The first user's map, turned and scaled about the middle.
const MOVE := Vector2(180.0, 260.0)
const TURN := 30.0
const SCALE := Vector2(1.4, 1.4)
## The second user's map, a move down and to the left.
const SHIFT := Vector2(-100.0, 420.0)
## The first stroke's path in document pixels, a frame a step.
const FROM := Vector2(200.0, 200.0)
const STEP := Vector2(16.0, 0.0)
const STEPS := 14
## Where the stroke painted in a user's contents starts.
const SECOND := Vector2(200.0, 330.0)
## Where a third stroke starts, for the edits after a user leaves.
const THIRD := Vector2(330.0, 470.0)
## What counts as paint.
const VISIBLE := 0.05
## How far from its path, in source pixels, a stroke's paint and the cache's
## filtering reach.
const REACH := 48.0


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()


static func _surface() -> SaSurface:
    var surface := Fixtures.make_surface(SIZE)
    surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    (surface.get_document().get_node("Background") as SaLayer).visible = false
    return surface


static func _turned() -> Basis:
    return SaLiveTransform.composed(MOVE, TURN, SCALE, MIDDLE)


static func _shifted() -> Basis:
    return SaLiveTransform.composed(SHIFT, 0.0, Vector2.ONE, MIDDLE)


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


## A stroke of the active tool from *from* along STEP, a frame a step.
static func _stroke(surface: SaSurface, machine: ToolMachine, from: Vector2) -> void:
    surface.view.mouse_position = from
    _button(machine, true)
    for i in range(1, STEPS + 1):
        _move(machine, from + STEP * i)
        _frame(surface, machine)
    _button(machine, false)
    _frame(surface, machine)


## A stroke from *from* painted in *layer*'s contents, opened for it and closed
## after, the way the view paints.
static func _paint_in(surface: SaSurface, machine: ToolMachine, layer: SaLayer, from: Vector2) -> void:
    var doc := surface.get_document()
    doc.set_active_layer(layer)
    SaLocalView.begin(doc, null, Rect2(), layer)
    _redraw(surface, machine)
    _stroke(surface, machine, from)
    SaLocalView.end(doc, null)
    _redraw(surface, machine)


## The middle of a stroke that starts at *from*.
static func _middle(from: Vector2) -> Vector2:
    return from + STEP * (STEPS / 2.0)


## The colour *layer*'s chunks hold at *at*, a position in its own grid, clear
## where it holds no chunk.
static func _texel(layer: SaLayer, at: Vector2) -> Color:
    var grid_pos := Vector2i(floori(at.x / SaLayer.CHUNK_SIZE), floori(at.y / SaLayer.CHUNK_SIZE))
    if not layer.chunks.has(grid_pos):
        return Color(0, 0, 0, 0)
    var chunk: SaChunk = layer.chunks[grid_pos]
    var texture := chunk.albedo()
    var texel := Vector2i(at - Vector2(grid_pos * chunk.pixel_size()))
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, texel.y * texture.size.x + texel.x)


## The bytes of every chunk of *layer*'s cache, by grid position.
static func _cache_bytes(layer: SaLayer) -> Dictionary:
    var out := {}
    var cache := SaLiveTransform.paint_of(layer)
    for grid_pos: Vector2i in cache.chunks:
        var texture := cache.chunks[grid_pos].albedo()
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return out


## How many texels of *layer*'s cache differ from *before* farther than *reach*
## from the segment *from* to *to* in document pixels, and whether any differ
## at all, so a stroke that changed nothing is not read as one in place.
static func _changed_away(layer: SaLayer, before: Dictionary, from: Vector2, to: Vector2, reach: float) -> Array:
    var cache := SaLiveTransform.paint_of(layer)
    var away := 0
    var any := false
    for grid_pos: Vector2i in cache.chunks:
        var chunk: SaChunk = cache.chunks[grid_pos]
        var texture := chunk.albedo()
        var now := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var was: PackedByteArray = before.get(grid_pos, PackedByteArray())
        if now == was:
            continue
        var count := texture.size.x * texture.size.y
        var corner := Vector2(grid_pos * chunk.pixel_size())
        for i in count:
            var after := SaFieldSpec.decode_texel(now, texture.format, i).a
            var earlier := SaFieldSpec.decode_texel(was, texture.format, i).a if not was.is_empty() else 0.0
            if absf(after - earlier) < VISIBLE:
                continue
            any = true
            var p := corner + Vector2(i % texture.size.x, floorf(float(i) / texture.size.x))
            if Geometry2D.get_closest_point_to_segment(p, from, to).distance_to(p) > reach:
                away += 1
    return [away, any]


## Whether *layer*'s drawn picture, its transform's cache, shows paint at *at*.
static func _shows(layer: SaLayer, at: Vector2) -> bool:
    return _texel(SaLiveTransform.paint_of(layer), at).a > VISIBLE


## Where *layer*'s map shows *at* of its paint.
static func _shown_at(layer: SaLayer, at: Vector2) -> Vector2:
    return SaLiveTransform.of(layer).map_point(at)


static func _report(doc: SaDocument, name: String) -> Dictionary:
    for entry: Dictionary in LayersReport.stack(doc):
        if entry["name"] == name:
            return entry
    return {}


## A painting with a stroke on a smart layer named Paint at the turned map, and
## its linked copy at the shifted one. Answers the surface, the machine and the
## two layers.
func _linked() -> Array:
    var surface := _surface()
    var machine := Fixtures.make_bound_machine(surface)
    var doc := surface.get_document()
    var paint := doc.active_layer
    paint.name = "Paint"
    machine.set_active_tool(&"brush")
    _stroke(surface, machine, FROM)
    assert_true(SaLiveTransform.make_smart(doc, paint), "Make Smart Layer runs")
    assert_true(SaLiveTransform.put(doc, paint, _turned()), "and the turned map is put on")
    var steps := doc.history.step_count()
    var copy := SaSharedSource.link(doc, paint)
    assert_not_null(copy, "Share Source with a Copy makes a copy")
    assert_eq(doc.history.step_count(), steps + 1, "as one history step")
    assert_true(SaLiveTransform.put(doc, copy, _shifted()), "and the copy takes a map of its own")
    _redraw(surface, machine)
    return [surface, machine, paint, copy]


## The first clause: the copy shares the source, each user keeps its own map,
## and a stroke painted in the first one's contents shows in both caches at the
## place its own map gives and nowhere else, then one undo takes it from both.
func test_a_stroke_in_one_users_contents_shows_in_both_at_its_own_map() -> void:
    var made := _linked()
    var surface: SaSurface = made[0]
    var machine: ToolMachine = made[1]
    var paint: SaLayer = made[2]
    var copy: SaLayer = made[3]
    var doc := surface.get_document()
    assert_eq(String(copy.name), "Paint Copy", "The copy is named as a duplicate is")
    assert_eq(doc.active_layer, copy, "and is the active layer")
    assert_true(is_same(paint.chunks, copy.chunks), "The two hold one chunk dictionary")
    assert_eq(SaSharedSource.of(paint), SaSharedSource.of(copy), "drawn from one source")
    assert_true(SaSmartLayer.is_marked(copy), "The copy is a smart layer")
    assert_true(SaLiveTransform.of(paint).matrix.is_equal_approx(_turned()), "Paint keeps its own map")
    assert_true(SaLiveTransform.of(copy).matrix.is_equal_approx(_shifted()), "and the copy its own")
    var names: Array = _report(doc, "Paint").get("source", [])
    assert_eq(names, ["Paint", "Paint Copy"], "The layers report names both under one source")
    assert_eq(_report(doc, "Paint Copy").get("source", []), names, "from either layer")

    var at := _middle(SECOND)
    var in_paint := _shown_at(paint, at)
    var in_copy := _shown_at(copy, at)
    # What each cache shows where the other's map takes the stroke, and where
    # it was painted, before it is painted.
    var paint_elsewhere := [_shows(paint, in_copy), _shows(paint, at)]
    var copy_elsewhere := [_shows(copy, in_paint), _shows(copy, at)]
    assert_false(_shows(paint, in_paint), "Before the stroke Paint shows nothing where it will land")
    assert_false(_shows(copy, in_copy), "and nor does the copy")
    var steps := doc.history.step_count()
    var paint_before := _cache_bytes(paint)
    var copy_before := _cache_bytes(copy)
    _paint_in(surface, machine, paint, SECOND)
    assert_true(_texel(paint, at).a > VISIBLE, "The stroke lands in the source")
    var end := SECOND + STEP * STEPS
    var stray := _changed_away(paint, paint_before, _shown_at(paint, SECOND), _shown_at(paint, end), REACH * SCALE.x)
    assert_eq(stray, [0, true], "Every texel of Paint's cache the stroke changed is along its own map's stroke")
    stray = _changed_away(copy, copy_before, _shown_at(copy, SECOND), _shown_at(copy, end), REACH)
    assert_eq(stray, [0, true], "and every one of the copy's along the shifted map's")
    assert_true(_shows(paint, in_paint), "Paint's cache shows it where the turned map takes it")
    assert_true(_shows(copy, in_copy), "and the copy's where the shifted map takes it")
    assert_eq([_shows(paint, in_copy), _shows(paint, at)], paint_elsewhere, "Paint shows it nowhere else")
    assert_eq([_shows(copy, in_paint), _shows(copy, at)], copy_elsewhere, "and nor does the copy")
    var canvas := surface.easel.output
    var rd := GlobalShaderCompiler.get_rd()
    var bytes := rd.texture_get_data(canvas.rid, 0)
    var on_canvas := func(p: Vector2) -> float:
        return SaFieldSpec.decode_texel(bytes, canvas.format, int(p.y) * canvas.size.x + int(p.x)).a
    assert_true(on_canvas.call(in_paint) > VISIBLE, "The canvas shows Paint's stroke")
    assert_true(on_canvas.call(in_copy) > VISIBLE, "and the copy's")

    assert_true(doc.history.step_count() > steps, "The stroke is a step")
    assert_true(doc.undo(), "which undoes")
    _redraw(surface, machine)
    assert_false(_texel(paint, at).a > VISIBLE, "Undone, the source is as it was")
    assert_false(_shows(paint, in_paint), "for Paint")
    assert_false(_shows(copy, in_copy), "and for the copy")
    Fixtures.teardown(surface, machine)


## The second clause's first half: Convert to Ordinary Layer bakes only the
## layer converted, the other still follows the source's edits, and the undo
## brings the converted one back sharing.
func test_converting_one_user_bakes_its_own_picture_and_the_other_follows_the_source() -> void:
    var made := _linked()
    var surface: SaSurface = made[0]
    var machine: ToolMachine = made[1]
    var paint: SaLayer = made[2]
    var copy: SaLayer = made[3]
    var doc := surface.get_document()
    var source := SaSharedSource.of(copy)
    var stroke_shown := _shown_at(paint, _middle(FROM))
    assert_true(SaLiveTransform.bake(doc, paint), "Convert to Ordinary Layer runs on Paint")
    _redraw(surface, machine)
    assert_null(SaLiveTransform.of(paint), "Paint is ordinary")
    assert_false(is_same(paint.chunks, source.chunks), "and holds chunks of its own")
    assert_true(_texel(paint, stroke_shown).a > VISIBLE, "its picture baked where its map showed it")
    assert_false(_texel(paint, _middle(FROM)).a > VISIBLE, "and gone from where it was painted")
    assert_true(_texel(copy, _middle(FROM)).a > VISIBLE, "The source still holds the stroke where it was painted")
    assert_eq(SaSharedSource.names_sharing(copy), [] as Array[String], "The copy shares with nobody now")
    assert_true(_shows(copy, _shown_at(copy, _middle(FROM))), "and draws the source through its map")

    var at := _middle(THIRD)
    var baked_there := _texel(paint, at)
    _paint_in(surface, machine, copy, THIRD)
    assert_true(_shows(copy, _shown_at(copy, at)), "An edit to the source reaches the copy")
    assert_eq(_texel(paint, at), baked_there, "and not the converted layer")
    assert_true(doc.undo(), "The stroke undoes")
    assert_true(doc.undo(), "and so does the convert")
    _redraw(surface, machine)
    assert_not_null(SaLiveTransform.of(paint), "Paint is smart again")
    assert_true(is_same(paint.chunks, copy.chunks), "on the shared source")
    assert_eq(SaSharedSource.names_sharing(paint).size(), 2, "with the copy")
    assert_true(_shows(paint, stroke_shown), "and draws the stroke through its map")
    Fixtures.teardown(surface, machine)


## A painter's answer on merging one user: a Merge Down of the copy into Paint
## bakes Paint's own picture and the copy's into Paint's chunks, the source the
## copy held is left as it was, and the undo brings both back sharing it.
func test_a_merge_into_one_user_writes_its_own_chunks_and_leaves_the_source() -> void:
    var made := _linked()
    var surface: SaSurface = made[0]
    var machine: ToolMachine = made[1]
    var paint: SaLayer = made[2]
    var copy: SaLayer = made[3]
    var doc := surface.get_document()
    var source := SaSharedSource.of(paint)
    var held := source.chunks.size()
    var painted := _texel(paint, _middle(FROM))
    var in_paint := _shown_at(paint, _middle(FROM))
    var in_copy := _shown_at(copy, _middle(FROM))
    assert_true(SaLayerOps.new(doc).merge_down(copy), "Merge Down runs on the copy")
    _redraw(surface, machine)
    assert_null(copy.get_parent(), "The copy is merged away")
    assert_null(SaLiveTransform.of(paint), "Paint is ordinary")
    assert_false(is_same(paint.chunks, source.chunks), "with chunks of its own")
    assert_true(_texel(paint, in_paint).a > VISIBLE, "holding its own picture")
    assert_true(_texel(paint, in_copy).a > VISIBLE, "and the copy's")
    assert_eq(source.chunks.size(), held, "The source holds the chunks it held")
    assert_eq(_texel(copy, _middle(FROM)), painted, "and the paint, where it was painted")
    assert_true(doc.undo(), "The merge undoes")
    _redraw(surface, machine)
    assert_eq(copy.get_parent(), doc, "The copy is back")
    assert_true(is_same(paint.chunks, copy.chunks), "and the two share the source again")
    assert_eq(_texel(paint, _middle(FROM)), painted, "which holds the paint it held")
    assert_true(_shows(copy, _shown_at(copy, _middle(FROM))), "and the copy draws it")
    Fixtures.teardown(surface, machine)


## The second clause's second half: Make Source Independent keeps the layer
## smart at its map, the source's edits stop reaching it, the other user still
## follows them, and the undo puts it back on the source.
func test_make_source_independent_keeps_the_map_and_stops_the_sources_edits() -> void:
    var made := _linked()
    var surface: SaSurface = made[0]
    var machine: ToolMachine = made[1]
    var paint: SaLayer = made[2]
    var copy: SaLayer = made[3]
    var doc := surface.get_document()
    var steps := doc.history.step_count()
    assert_true(SaSharedSource.can_unlink(copy), "The copy shares its source, so the row is lit")
    assert_true(SaSharedSource.make_independent(doc, copy), "Make Source Independent runs on the copy")
    assert_eq(doc.history.step_count(), steps + 1, "as one step")
    assert_true(SaSmartLayer.is_marked(copy), "The copy stays a smart layer")
    assert_true(SaLiveTransform.of(copy).matrix.is_equal_approx(_shifted()), "at its map")
    assert_null(SaSharedSource.of(copy), "drawn from no shared source")
    assert_false(is_same(copy.chunks, paint.chunks), "and holds its own chunks")
    assert_true(_shows(copy, _shown_at(copy, _middle(FROM))), "which hold the stroke")
    assert_false(SaSharedSource.can_unlink(paint), "Paint shares with nobody now")
    assert_false(SaSharedSource.make_independent(doc, paint), "so the command refuses on it")

    var at := _middle(THIRD)
    var copy_there := _shown_at(copy, at)
    _paint_in(surface, machine, paint, THIRD)
    assert_true(_shows(paint, _shown_at(paint, at)), "An edit to Paint's source shows in Paint")
    assert_false(_texel(copy, at).a > VISIBLE, "and not in the copy's own chunks")
    assert_false(_shows(copy, copy_there), "nor in its picture")
    assert_true(doc.undo(), "The stroke undoes")
    assert_true(doc.undo(), "and so does the command")
    _redraw(surface, machine)
    assert_true(is_same(copy.chunks, paint.chunks), "The copy shares the source again")
    assert_eq(SaSharedSource.names_sharing(copy).size(), 2, "with Paint")
    _paint_in(surface, machine, paint, THIRD)
    assert_true(_shows(copy, copy_there), "and an edit to it reaches the copy again")
    Fixtures.teardown(surface, machine)


## The second clause's deletes: the source lives while any user does, a user
## deleted leaves the other unchanged and its undo brings it back sharing, a
## user the history lets go never empties the other, and with the last user
## gone the source is freed.
func test_a_delete_acts_as_a_shared_pointer() -> void:
    var made := _linked()
    var surface: SaSurface = made[0]
    var machine: ToolMachine = made[1]
    var paint: SaLayer = made[2]
    var copy: SaLayer = made[3]
    var doc := surface.get_document()
    var source_ref: WeakRef = weakref(SaSharedSource.of(paint))
    var ops := SaLayerOps.new(doc)
    var shown := _shown_at(paint, _middle(FROM))
    var held := paint.chunks.size()
    assert_true(ops.remove(copy), "The copy is deleted")
    _redraw(surface, machine)
    assert_not_null(SaSharedSource.of(paint), "Paint still has the source")
    assert_eq(paint.chunks.size(), held, "with every chunk it held")
    assert_true(_shows(paint, shown), "and draws as it did")
    assert_true(doc.undo(), "The delete undoes")
    _redraw(surface, machine)
    assert_eq(copy.get_parent(), doc, "and the copy is back")
    assert_true(is_same(copy.chunks, paint.chunks), "sharing the source")
    assert_eq(SaSharedSource.names_sharing(paint), ["Paint", "Paint Copy"] as Array[String], "the report says")

    assert_true(ops.remove(paint), "Paint is deleted")
    doc.undo_redo.clear_history()
    doc.history.reset()
    assert_not_null(source_ref.get_ref(), "With Paint let go by the history, the source is still there")
    assert_eq(copy.chunks.size(), held, "and the copy still holds every chunk")
    assert_true(_shows(copy, _shown_at(copy, _middle(FROM))), "and draws the stroke")

    assert_true(ops.remove(copy), "The last user is deleted")
    doc.undo_redo.clear_history()
    doc.history.reset()
    assert_null(source_ref.get_ref(), "and once the history lets it go the source is freed")
    Fixtures.teardown(surface, machine)


## The third clause: a save stores the source's chunks once and opens with the
## two layers still sharing, so an edit through one reaches the other, and a
## file of two independent copies stores them twice.
func test_a_save_stores_the_source_once_and_opens_shared() -> void:
    var made := _linked()
    var surface: SaSurface = made[0]
    var machine: ToolMachine = made[1]
    var paint: SaLayer = made[2]
    var doc := surface.get_document()
    var held := paint.chunks.size()
    assert_true(held > 0, "The source holds chunks")
    assert_eq(SaSadFile.version_for(doc), SaSadSharedSource.VERSION, "A document with a shared source takes 15")
    assert_eq(_stored(doc, ["Paint", "Paint Copy"]), held, "The file stores the source's chunks once")

    var path := ProjectSettings.globalize_path(SaDataRoot.path("shared_source.sad"))
    assert_eq(SaSadFile.save_file(doc, path, 0), OK, "It saves")
    var loaded := _surface()
    var reopened := loaded.get_document()
    assert_eq(SaExport.load_sad(reopened, path, loaded.easel.compositor), OK, "It opens")
    DirAccess.remove_absolute(path)
    var paint_back := reopened.get_node("Paint") as SaLayer
    var copy_back := reopened.get_node("Paint Copy") as SaLayer
    assert_true(paint_back != null and copy_back != null, "with both layers")
    if paint_back == null or copy_back == null:
        Fixtures.teardown(surface, machine)
        Fixtures.teardown(loaded)
        return
    assert_true(is_same(paint_back.chunks, copy_back.chunks), "still sharing one source")
    assert_eq(paint_back.chunks.size(), held, "which holds every chunk")
    assert_true(SaLiveTransform.of(paint_back).matrix.is_equal_approx(_turned()), "Paint at its map")
    assert_true(SaLiveTransform.of(copy_back).matrix.is_equal_approx(_shifted()), "and the copy at its own")
    var stroke := _middle(FROM)
    var in_copy := _shown_at(copy_back, stroke)
    assert_true(_shows(copy_back, in_copy), "The copy draws the stroke")
    var grid_pos := Vector2i(floori(stroke.x / SaLayer.CHUNK_SIZE), floori(stroke.y / SaLayer.CHUNK_SIZE))
    paint_back.set_chunk(grid_pos, null)
    assert_false(copy_back.chunks.has(grid_pos), "A chunk dropped through Paint is gone from the copy")
    assert_false(_shows(copy_back, in_copy), "and the copy's picture follows")

    var plain := SaLayerOps.new(doc).duplicate(paint)
    assert_not_null(SaLiveTransform.of(plain), "Duplicate Layer of a smart layer keeps its transform")
    assert_true(SaSmartLayer.is_marked(plain), "and a smart layer")
    assert_false(is_same(plain.chunks, paint.chunks), "with chunks of its own")
    assert_true(SaLiveTransform.of(plain).matrix.is_equal_approx(_turned()), "at the map it copied")
    SaLayerOps.new(doc).remove(made[3])
    var independent := _stored(doc, ["Paint", String(plain.name)])
    assert_eq(independent, 2 * held, "Two independent copies of the same picture store it twice")
    Fixtures.teardown(surface, machine)
    Fixtures.teardown(loaded)


## How many chunks a save of *doc* writes for the layers *names*.
static func _stored(doc: SaDocument, names: Array) -> int:
    var blobs := PackedByteArray()
    var header := SaSadFile.header_of(doc, blobs, GlobalShaderCompiler.get_rd())
    var count := 0
    for raw: Variant in header.get("layers", []):
        var entry := SaTyped.strings(raw)
        if names.has(str(entry.get("name", ""))):
            count += (entry.get("chunks", []) as Array).size()
    return count
