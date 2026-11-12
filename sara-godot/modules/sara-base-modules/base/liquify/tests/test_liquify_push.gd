## Liquify pushes paint through a
## displacement field, read once from the original, sparse, masked by the
## selection, one history step, and at the layer's own density.
##
## Every case paints a vertical stripe, pushes across it, and reads the row
## through the brush's centre, where the falloff is flat and a push of ten
## document pixels at full strength moves the paint exactly ten.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const SessionScript = preload("res://modules/sara-base-modules/base/liquify/sa_liquify_session.gd")

## Four chunks by two, so a small dab can be seen to leave the rest alone.
const CANVAS := Vector2i(1024, 512)
## The stripe, in document pixels along x, and the row the brush runs along.
const STRIPE_FROM: int = 100
const STRIPE_TO: int = 104
const ROW: int = 128
const RED := Color(0.9, 0.1, 0.1, 1.0)

var _surface: SaSurface = null
var _machine: ToolMachine = null


func after_each() -> void:
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## A fresh document with the stripe on a new active layer at *scale*, in the
## two chunks of the top row and nowhere else.
func _open(scale: float = 1.0) -> SaLayer:
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _surface = Fixtures.make_surface(CANVAS)
    _machine = Fixtures.make_bound_machine(_surface)
    var doc := _surface.get_document()
    var layer := SaLayerOps.new(doc).add(&"", null, scale)
    doc.active_layer = layer
    for gx in 2:
        var grid_pos := Vector2i(gx, 0)
        var chunk := layer.get_or_create_chunk(grid_pos)
        var texture := chunk.albedo()
        var image := Image.create_empty(SaChunk.SIZE, SaChunk.SIZE, false, _image_format(texture))
        for y in SaChunk.SIZE:
            for x in SaChunk.SIZE:
                var at := gx * SaChunk.SIZE + x
                image.set_pixel(x, y, RED if at >= STRIPE_FROM and at < STRIPE_TO else Color(0.0, 0.0, 0.0, 0.0))
        if chunk.pixel_size() != SaChunk.SIZE:
            image.resize(chunk.pixel_size(), chunk.pixel_size(), Image.INTERPOLATE_NEAREST)
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
        layer.mark_unresolved(grid_pos)
    doc.invalidate_chunks(layer.chunks.keys())
    return layer


func _session() -> Variant:
    return SessionScript.new(_surface.get_document())


## The alpha of row *y* at the document's resolution, one value a document
## pixel of the top row of chunks, the 2.0 layer's two by two texels averaged.
func _row(layer: SaLayer, y: int) -> PackedFloat32Array:
    var row := PackedFloat32Array()
    row.resize(SaChunk.SIZE * 2)
    for gx in 2:
        var chunk: SaChunk = layer.chunks.get(Vector2i(gx, 0), null)
        if chunk == null:
            continue
        var texture := chunk.albedo()
        var edge := chunk.pixel_size()
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var texels := Image.create_from_data(edge, edge, false, _image_format(texture), bytes)
        @warning_ignore("integer_division")
        var t := edge / SaChunk.SIZE
        for x in SaChunk.SIZE:
            var sum := 0.0
            for dy in t:
                for dx in t:
                    sum += texels.get_pixel(x * t + dx, y * t + dy).a
            row[gx * SaChunk.SIZE + x] = sum / float(t * t)
    return row


## Where the paint on a row sits, as its alpha-weighted mean position.
static func _centre_of(row: PackedFloat32Array) -> float:
    var weight := 0.0
    var moment := 0.0
    for x in row.size():
        weight += row[x]
        moment += row[x] * (float(x) + 0.5)
    return moment / weight if weight > 0.0 else -1.0


## How many pixels of a row are neither empty nor opaque, which is how wide
## its edges are.
static func _soft(row: PackedFloat32Array) -> int:
    var count := 0
    for value: float in row:
        if value > 0.02 and value < 0.98:
            count += 1
    return count


func test_a_push_moves_the_stripe_by_the_motion() -> void:
    var layer := _open()
    var before := _centre_of(_row(layer, ROW))
    var session: Variant = _session()
    assert_true(session.begin(layer), "A session opens on the active layer")
    session.push(Vector2(102.0, ROW), Vector2(112.0, ROW), 120.0, 1.0)
    var after := _centre_of(_row(layer, ROW))
    assert_almost_eq(after - before, 10.0, 0.05, "A push of ten at full strength moves the stripe ten")
    assert_almost_eq(_soft(_row(layer, ROW)), 0.0, 0.0, "A whole-pixel push copies texels and softens nothing")


func test_ten_small_pushes_are_no_softer_than_one() -> void:
    var layer := _open()
    var once: Variant = _session()
    once.begin(layer)
    once.push(Vector2(102.0, ROW), Vector2(112.0, ROW), 120.0, 0.37)
    var one_row := _row(layer, ROW)

    layer = _open()
    var often: Variant = _session()
    often.begin(layer)
    for step in 10:
        often.push(Vector2(102.0 + step, ROW), Vector2(103.0 + step, ROW), 120.0, 0.37)
    var ten_row := _row(layer, ROW)

    assert_true(_soft(one_row) > 0, "A push by a fraction of a pixel reads between texels")
    assert_true(
        _soft(ten_row) <= _soft(one_row),
        "Ten pushes read the original once: %d soft pixels against one push's %d" % [_soft(ten_row), _soft(one_row)]
    )
    assert_almost_eq(_centre_of(ten_row), _centre_of(one_row), 0.05, "Ten pushes of one land where one of ten does")


func test_no_field_chunk_where_no_dab_landed() -> void:
    var layer := _open()
    var session: Variant = _session()
    session.begin(layer)
    session.push(Vector2(102.0, ROW), Vector2(112.0, ROW), 40.0, 1.0)
    assert_eq(session.fields.keys(), [Vector2i(0, 0)], "A dab inside one chunk makes one field chunk")
    assert_false(layer.chunks.has(Vector2i(2, 1)), "Nor does it make a layer chunk far from it")


func test_the_selection_holds_what_it_leaves_out() -> void:
    var layer := _open()
    var doc := _surface.get_document()
    # The rows above the brush's centre are selected and the rows below not.
    doc.selection.select_rect(Rect2i(0, 0, CANVAS.x, ROW))
    var session: Variant = _session()
    session.begin(layer)
    session.push(Vector2(102.0, ROW), Vector2(112.0, ROW), 200.0, 1.0)
    assert_almost_eq(_centre_of(_row(layer, ROW - 30)), 112.0, 0.05, "A selected row moves")
    assert_almost_eq(_centre_of(_row(layer, ROW + 30)), 102.0, 0.05, "An unselected row stays")


func test_undo_after_commit_restores_the_layer() -> void:
    var layer := _open()
    var doc := _surface.get_document()
    var session: Variant = _session()
    session.begin(layer)
    session.push(Vector2(102.0, ROW), Vector2(112.0, ROW), 120.0, 1.0)
    session.push(Vector2(112.0, ROW), Vector2(112.0, ROW + 40.0), 120.0, 1.0)
    assert_true(session.commit(), "The session commits as a step")
    assert_false(session.is_open(), "And closes")
    assert_almost_eq(_centre_of(_row(layer, ROW)), 112.0, 0.5, "The push is in the layer")
    assert_true(doc.undo(), "One undo")
    assert_almost_eq(_centre_of(_row(layer, ROW)), 102.0, 0.001, "Takes the whole session back")
    assert_true(doc.redo(), "And a redo")
    assert_almost_eq(_centre_of(_row(layer, ROW)), 112.0, 0.5, "Brings it again")


func test_escape_before_the_commit_leaves_nothing() -> void:
    var layer := _open()
    var doc := _surface.get_document()
    var chunks_before := layer.chunks.keys()
    var row_before := _row(layer, ROW)
    var version := doc.undo_redo.get_version()
    var session: Variant = _session()
    session.begin(layer)
    # Across the chunk seam and into the row of chunks below, where the layer
    # holds none.
    session.push(Vector2(102.0, ROW), Vector2(112.0, 300.0), 300.0, 1.0)
    session.cancel()
    assert_eq(_row(layer, ROW), row_before, "Escape puts every texel back")
    assert_eq(layer.chunks.keys(), chunks_before, "And takes away every chunk the session made")
    assert_true(session.fields.is_empty(), "And lets the field go")
    assert_eq(doc.undo_redo.get_version(), version, "Leaving no step in the history")


func test_a_double_resolution_layer_moves_by_the_document_pixel() -> void:
    var layer := _open(2.0)
    assert_eq(layer.chunks[Vector2i(0, 0)].pixel_size(), SaChunk.SIZE * 2, "The layer is at 2.0")
    var session: Variant = _session()
    session.begin(layer)
    session.push(Vector2(102.0, ROW), Vector2(112.0, ROW), 120.0, 1.0)
    var field: SaTexture = session.fields[Vector2i(0, 0)]
    assert_eq(field.size, Vector2i(SaChunk.SIZE * 2, SaChunk.SIZE * 2), "The field is at the layer's density")
    assert_almost_eq(_centre_of(_row(layer, ROW)), 112.0, 0.05, "The stripe moves ten document pixels")


func test_the_tool_commits_when_it_is_left() -> void:
    var layer := _open()
    var doc := _surface.get_document()
    _machine.set_active_tool(&"liquify")
    var tool: Variant = _machine.active_tool
    tool.settings.strength = 1.0
    tool.press(Vector2(102.0, ROW))
    tool.drag_to(Vector2(112.0, ROW))
    tool.release()
    assert_true(bool(tool.capture_report(&"liquify", true)["liquify"]["open"]), "A drag leaves a session open")
    _machine.set_active_tool(&"transform")
    assert_almost_eq(_centre_of(_row(layer, ROW)), 112.0, 0.05, "The switch keeps the push")
    assert_true(doc.undo(), "As one step")
    assert_almost_eq(_centre_of(_row(layer, ROW)), 102.0, 0.001, "Which undo takes back")
