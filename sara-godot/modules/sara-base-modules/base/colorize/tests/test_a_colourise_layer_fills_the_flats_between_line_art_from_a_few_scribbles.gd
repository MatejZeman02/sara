## A Colourise layer fills the flats between line art from a few scribbles.
##
## Line art of three closed regions, one with a three pixel break in its
## outline, a scribble of its own colour in each and a Transparent one outside.
## With Gap Closing at four pixels every region is its own colour up to the
## middle of its lines, nothing passes the break and the outside is empty. At
## nought the colour runs out through the break. A stroke of the Brush on the
## layer lands in its scribbles and not in what it shows, the flats survive a
## save and a load with the options and the line art's name, and an update of
## a 4000 by 4000 drawing is timed. With no line art to read an update fills
## nothing and the scribbles show alone, and Ctrl+Z takes the scribbles and the
## flats back, strokes and updates alike.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const SaColorize = preload("res://modules/sara-base-modules/base/colorize/sa_colorize.gd")

const SIDE := 512
const MODULE := &"sara-base-modules"
## The three regions' outlines, three pixels thick, and the break in the
## second one's bottom edge.
const A := Rect2i(40, 40, 180, 180)
const B := Rect2i(280, 40, 190, 180)
const C := Rect2i(40, 280, 430, 190)
const LINE := 3
const BREAK := Rect2i(370, 217, 3, 3)
const RED := Color(0.85, 0.15, 0.1)
const GREEN := Color(0.2, 0.7, 0.25)
const BLUE := Color(0.15, 0.3, 0.8)
## Where the outside's Transparent scribble lies, far from the break.
const OUTSIDE := Vector2i(500, 250)
## A pixel of the outside a little below the break.
const BELOW_BREAK := Vector2i(371, 225)

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _colorize: SaColorize = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(SIDE, SIDE))
    _registries = Fixtures.make_registries(_surface)
    var ctx := _registries.context.for_module(MODULE)
    _colorize = SaColorize.new(ctx)
    ctx.register_layer_type(_colorize.descriptor())


func after_each() -> void:
    Fixtures.teardown(_surface)
    _surface = null
    _registries = null
    _colorize = null


func test_each_region_takes_its_scribble_s_colour_to_the_middle_of_its_lines_and_the_break_holds() -> void:
    var layer := _drawing()
    _colorize.choose(layer, "gap", 4.0)
    assert_true(_colorize.update(layer), "The update ran")
    var doc := _surface.get_document()
    assert_eq(_colorize.line_art_of(layer), doc.get_node("Line Art"), "The layer reads the line art under it")
    var flats := _flats(layer)
    for region: Array in [[A, RED], [B, GREEN], [C, BLUE]]:
        var box: Rect2i = region[0]
        var colour: Color = region[1]
        var inner := box.grow(-LINE)
        var wrong := 0
        var seen := 0
        for y in range(inner.position.y, inner.end.y, 3):
            for x in range(inner.position.x, inner.end.x, 3):
                seen += 1
                wrong += 0 if _same(flats.get_pixel(x, y), colour) else 1
        assert_eq(wrong, 0, "Every one of %d pixels inside %s is its scribble's colour" % [seen, box])
        # Across the left line: the line's own pixels are left uncovered so
        # the ink shows over the flats, and the pixel beside it is the region's.
        var row := box.position.y + (box.size.y >> 1)
        assert_eq(flats.get_pixel(box.position.x + LINE - 1, row).a, 0.0, "The line's own pixels of %s are not covered" % box)
        assert_true(_same(flats.get_pixel(box.position.x + LINE, row), colour), "and the pixel beside the line is its colour")
    assert_eq(flats.get_pixel(BELOW_BREAK.x, BELOW_BREAK.y).a, 0.0, "Nothing passes the three pixel break below it")
    assert_true(_same(flats.get_pixel(BREAK.position.x + 1, BREAK.position.y - 2), GREEN), "and the region inside it is whole")
    assert_eq(flats.get_pixel(250, 130).a, 0.0, "The outside between two regions is empty")
    assert_eq(flats.get_pixel(5, 5).a, 0.0, "and so is the outside at the corner")
    print("Colourise, gap 4: %d rounds of the sweeps" % _colorize.rounds())


func test_with_no_gap_closing_the_colour_runs_out_through_the_break() -> void:
    var layer := _drawing()
    _colorize.choose(layer, "gap", 0.0)
    assert_true(_colorize.update(layer), "The update ran")
    var flats := _flats(layer)
    assert_true(_same(flats.get_pixel(BELOW_BREAK.x, BELOW_BREAK.y), GREEN), "The green runs out through the break")
    assert_true(_same(flats.get_pixel(A.get_center().x, A.get_center().y), RED), "and the closed regions keep their own")


func test_one_closed_shape_with_one_scribble_fills_the_shape_and_not_the_page_round_it() -> void:
    var doc := _surface.get_document()
    var art := Image.create_empty(SIDE, SIDE, false, Image.FORMAT_RGBA8)
    var shape := Rect2i(120, 120, 240, 240)
    art.fill_rect(Rect2i(shape.position, Vector2i(shape.size.x, LINE)), Color.BLACK)
    art.fill_rect(Rect2i(shape.position.x, shape.end.y - LINE, shape.size.x, LINE), Color.BLACK)
    art.fill_rect(Rect2i(shape.position, Vector2i(LINE, shape.size.y)), Color.BLACK)
    art.fill_rect(Rect2i(shape.end.x - LINE, shape.position.y, LINE, shape.size.y), Color.BLACK)
    var line_art := doc.active_layer
    line_art.name = "Line Art"
    SaImageImport.upload(doc, line_art, art)
    var layer := _registries.context.for_module(MODULE).create_layer(SaColorize.TYPE, doc)
    var scribbles: Dictionary[Vector2i, Image] = {}
    _scribble(scribbles, Rect2i(shape.get_center() - Vector2i(15, 3), Vector2i(30, 6)), RED)
    _upload(layer, scribbles)
    assert_true(_colorize.update(layer), "The update ran")
    var flats := _flats(layer)
    assert_true(_same(flats.get_pixel(shape.get_center().x + 50, shape.get_center().y + 50), RED), "The shape is filled")
    assert_eq(flats.get_pixel(20, 20).a, 0.0, "The page outside the shape is left empty, at the corner")
    assert_eq(flats.get_pixel(450, 250).a, 0.0, "and beside it")
    assert_eq(flats.get_pixel(250, 450).a, 0.0, "and below it")


func test_the_layer_shows_the_flats_with_the_scribbles_taken_in_or_the_scribbles_alone() -> void:
    var layer := _drawing()
    var doc := _surface.get_document()
    layer.resolve_pending()
    var shown := _image_of(layer, SaFieldSpec.ALBEDO, Image.FORMAT_RGBAF)
    assert_eq(
        shown.get_pixel(A.get_center().x, A.get_center().y + 30).a, 0.0, "Before an update the layer shows the scribbles alone"
    )
    assert_true(_same(shown.get_pixel(A.get_center().x, A.get_center().y), RED), "the scribble itself among them")
    _colorize.update(layer)
    layer.resolve_pending()
    shown = _image_of(layer, SaFieldSpec.ALBEDO, Image.FORMAT_RGBAF)
    assert_true(_same(shown.get_pixel(A.get_center().x, A.get_center().y + 30), RED), "After it, the flats")
    assert_eq(shown.get_pixel(OUTSIDE.x, OUTSIDE.y).a, 0.0, "and the Transparent scribble is taken into the empty outside")
    _colorize.choose(layer, "alone", true)
    layer.resolve_pending()
    shown = _image_of(layer, SaFieldSpec.ALBEDO, Image.FORMAT_RGBAF)
    assert_eq(shown.get_pixel(A.get_center().x, A.get_center().y + 30).a, 0.0, "The switch shows the scribbles alone")
    assert_true(_same(shown.get_pixel(OUTSIDE.x, OUTSIDE.y), SaColorize.TRANSPARENT), "the Transparent one in its own colour")
    assert_true(doc.undo(), "The update is a step of its own")
    assert_eq(_flats(layer).get_pixel(A.get_center().x, A.get_center().y + 30).a, 0.0, "which one undo takes back")


func test_a_brush_stroke_on_the_layer_lands_in_its_scribbles_and_auto_fills_after_it() -> void:
    var layer := _drawing()
    var doc := _surface.get_document()
    doc.set_active_layer(layer)
    var brush: Object = StateBrushScript.new()
    brush.surface = _surface
    brush.settings.stabilizer_amount = 0.0
    brush.settings.radius = 4.0 / SIDE
    brush.settings.color = GREEN
    var row := float(C.get_center().y + 40)
    _surface.view.mouse_position = Vector2(100.0, row)
    _button(brush, true)
    for x in range(110, 200, 10):
        _move(brush, Vector2(x, row))
    _button(brush, false)
    var keys := _image_of(layer, SaColorize.KEYS, Image.FORMAT_RGBAF)
    assert_true(keys.get_pixel(150, int(row)).a > 0.5, "The stroke lies in the scribbles")
    assert_true(_same(_flats(layer).get_pixel(150, int(row) + 20), Color(0, 0, 0, 0)), "and the flats wait for the stroke's end")
    _colorize.pay()
    var flats := _flats(layer)
    assert_true(
        _same(flats.get_pixel(150, int(row) + 20), GREEN),
        "Auto filled after the stroke, the green taking its share of the region"
    )
    assert_true(_same(flats.get_pixel(C.end.x - 20, C.end.y - 20), BLUE), "and the blue keeping the rest of it")


func test_with_no_line_art_an_update_fills_nothing_and_the_scribbles_show_alone() -> void:
    var doc := _surface.get_document()
    var layer := _registries.context.for_module(MODULE).create_layer(SaColorize.TYPE, doc)
    var scribbles: Dictionary[Vector2i, Image] = {}
    _scribble(scribbles, Rect2i(100, 100, 30, 6), GREEN)
    _upload(layer, scribbles)
    assert_false(_colorize.has_line_art(layer), "The layer under it holds no paint, so there is no line art")
    assert_true(_colorize.update(layer), "The update still runs")
    var flats := _flats(layer)
    assert_eq(flats.get_pixel(110, 103).a, 0.0, "and the scribble's own place is not filled")
    assert_eq(flats.get_pixel(200, 200).a, 0.0, "nor is the page round it")
    layer.resolve_pending()
    var shown := _image_of(layer, SaFieldSpec.ALBEDO, Image.FORMAT_RGBAF)
    assert_true(_same(shown.get_pixel(110, 103), GREEN), "The layer shows the scribble")
    assert_eq(shown.get_pixel(200, 200).a, 0.0, "and nothing else, no block the size of its chunk")


func test_an_update_with_no_line_art_takes_back_the_flats_it_emptied() -> void:
    var layer := _drawing()
    var doc := _surface.get_document()
    _colorize.update(layer)
    var inside := A.get_center() + Vector2i(0, 30)
    assert_true(_same(_flats(layer).get_pixel(inside.x, inside.y), RED), "The line art's regions are filled first")
    var blank := SaLayerOps.new(doc).add()
    blank.name = "Blank"
    _colorize.choose(layer, "line_art", "Blank")
    assert_false(_colorize.has_line_art(layer), "Pointed at a layer with no paint there is no line art to read")
    assert_true(_colorize.update(layer), "an update runs")
    assert_eq(_flats(layer).get_pixel(inside.x, inside.y).a, 0.0, "and empties the flats")
    assert_true(doc.undo(), "as one step")
    assert_true(_same(_flats(layer).get_pixel(inside.x, inside.y), RED), "which one undo takes back")


func test_ctrl_z_takes_back_a_stroke_and_the_flats_it_filled_and_an_update_its_own_step() -> void:
    var layer := _drawing()
    var doc := _surface.get_document()
    doc.set_active_layer(layer)
    _colorize.update(layer, false)
    var brush: Object = StateBrushScript.new()
    brush.surface = _surface
    brush.settings.stabilizer_amount = 0.0
    brush.settings.radius = 4.0 / SIDE
    brush.settings.color = GREEN
    var row := float(C.get_center().y + 40)
    _surface.view.mouse_position = Vector2(100.0, row)
    _button(brush, true)
    for x in range(110, 200, 10):
        _move(brush, Vector2(x, row))
    _button(brush, false)
    _colorize.pay()
    assert_true(_same(_flats(layer).get_pixel(150, int(row) + 20), GREEN), "The stroke and its flats are laid")
    assert_true(doc.undo(), "Ctrl+Z")
    _colorize.pay()
    assert_eq(_image_of(layer, SaColorize.KEYS, Image.FORMAT_RGBAF).get_pixel(150, int(row)).a, 0.0, "takes the stroke back")
    assert_true(_same(_flats(layer).get_pixel(150, int(row) + 20), BLUE), "and the flats follow it, the blue holding the region")
    assert_true(doc.redo(), "Ctrl+Shift+Z")
    _colorize.pay()
    assert_true(_same(_flats(layer).get_pixel(150, int(row) + 20), GREEN), "puts both back")
    _colorize.choose(layer, "auto", false)
    _colorize.choose(layer, "gap", 0.0)
    _colorize.update(layer)
    var below := _flats(layer).get_pixel(BELOW_BREAK.x, BELOW_BREAK.y)
    assert_true(_same(below, GREEN), "An update with no gap closing lets the green out")
    assert_true(doc.undo(), "Ctrl+Z")
    assert_eq(_flats(layer).get_pixel(BELOW_BREAK.x, BELOW_BREAK.y).a, 0.0, "takes that update back and nothing else")
    assert_true(_same(_flats(layer).get_pixel(150, int(row) + 20), GREEN), "the stroke's flats stay")


func test_rasterize_layer_turns_it_into_a_paint_layer_of_its_flats_in_one_step() -> void:
    var layer := _drawing()
    _colorize.update(layer)
    var doc := _surface.get_document()
    assert_true(SaRasterizeLayer.can_rasterize(doc, layer), "Layer > Rasterize Layer takes a Colourise layer")
    assert_eq(doc.active_layer, layer, "The Colourise layer is the active one")
    assert_true(_colorize.rasterize(), "and the docker's Convert to Paint Layer runs the Layer menu's command")
    var paint: SaLayer = doc.active_layer
    assert_false(SaColorize.is_colorize(paint), "into a paint layer")
    var shown := _image_of(paint, SaFieldSpec.ALBEDO, Image.FORMAT_RGBAF)
    assert_true(_same(shown.get_pixel(A.get_center().x, A.get_center().y + 30), RED), "of its flats")
    assert_true(doc.undo(), "in one step")
    assert_true(SaColorize.is_colorize(doc.active_layer), "which one undo takes back")


func test_the_flats_options_and_line_art_survive_a_save_and_a_load() -> void:
    var layer := _drawing()
    _colorize.choose(layer, "gap", 6.0)
    _colorize.update(layer)
    var path := SaDataRoot.path("colourise_%d.sad" % Time.get_ticks_usec())
    var doc := _surface.get_document()
    assert_eq(SaSadFile.save_file(doc, path, 0), OK, "The document saves")
    var opened := SaDocument.new()
    assert_eq(SaSadFile.load_file(opened, path, SaCompositor.new()), OK, "and opens")
    var back: SaLayer = null
    for child in opened.get_children():
        if child is SaLayer and child.name == layer.name:
            back = child
    assert_not_null(back, "with the Colourise layer")
    if back != null:
        assert_eq(back.layer_type, SaColorize.TYPE, "of its kind")
        assert_eq(_colorize.gap_of(back), 6.0, "its Gap Closing kept")
        var art := _colorize.line_art_of(back)
        assert_true(art != null and art.name == "Line Art", "and the line art it reads")
        assert_true(_same(_flats(back).get_pixel(A.get_center().x, A.get_center().y + 30), RED), "its flats kept")
    opened.free()
    DirAccess.remove_absolute(path)


func test_an_update_of_a_4000_by_4000_drawing_takes_under_a_second() -> void:
    Fixtures.teardown(_surface)
    var size := 4000
    _surface = Fixtures.make_surface(Vector2i(size, size))
    _registries = Fixtures.make_registries(_surface)
    var ctx := _registries.context.for_module(MODULE)
    _colorize = SaColorize.new(ctx)
    ctx.register_layer_type(_colorize.descriptor())
    var doc := _surface.get_document()
    var art := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
    var cell := 250
    for i in range(0, size + 1, cell):
        art.fill_rect(Rect2i(mini(i, size - LINE), 0, LINE, size), Color.BLACK)
        art.fill_rect(Rect2i(0, mini(i, size - LINE), size, LINE), Color.BLACK)
    var line_art := doc.active_layer
    line_art.name = "Line Art"
    SaImageImport.upload(doc, line_art, art)
    var layer := ctx.create_layer(SaColorize.TYPE, doc)
    var scribbles: Dictionary[Vector2i, Image] = {}
    var palette: Array[Color] = [RED, GREEN, BLUE, Color(0.9, 0.8, 0.2)]
    var k := 0
    for y in range(cell >> 1, size, cell):
        for x in range(cell >> 1, size, cell):
            _scribble(scribbles, Rect2i(x - 10, y - 3, 20, 6), palette[k % palette.size()])
            k += 1
    _upload(layer, scribbles)
    _colorize.update(layer, false)
    var times: Array[float] = []
    for i in 3:
        _colorize.update(layer, false)
        times.append(_colorize.took_ms)
    times.sort()
    print("Colourise, 4000 by 4000: an update takes %.1f ms at the median of 3, %d rounds" % [times[1], _colorize.rounds()])
    assert_true(times[1] < 1000.0, "An update of a 4000 by 4000 drawing takes %.1f ms" % times[1])
    var flats := _image_of(layer, SaColorize.FLATS, Image.FORMAT_RGBAH, Rect2i(0, 0, cell * 2, cell))
    assert_true(_same(flats.get_pixel(cell >> 1, (cell >> 1) + 40), RED), "and the first cell is filled")
    assert_true(_same(flats.get_pixel(cell + (cell >> 1), (cell >> 1) + 40), GREEN), "and the next one with its own")


## The drawing the first suites read: line art of the three regions on the
## document's first layer, renamed, and a Colourise layer above it holding a
## scribble in each region and the Transparent one outside.
func _drawing() -> SaLayer:
    var doc := _surface.get_document()
    var art := Image.create_empty(SIDE, SIDE, false, Image.FORMAT_RGBA8)
    for box: Rect2i in [A, B, C]:
        art.fill_rect(Rect2i(box.position, Vector2i(box.size.x, LINE)), Color.BLACK)
        art.fill_rect(Rect2i(box.position.x, box.end.y - LINE, box.size.x, LINE), Color.BLACK)
        art.fill_rect(Rect2i(box.position, Vector2i(LINE, box.size.y)), Color.BLACK)
        art.fill_rect(Rect2i(box.end.x - LINE, box.position.y, LINE, box.size.y), Color.BLACK)
    art.fill_rect(BREAK, Color(0, 0, 0, 0))
    var line_art := doc.active_layer
    line_art.name = "Line Art"
    SaImageImport.upload(doc, line_art, art)
    var layer := _registries.context.for_module(MODULE).create_layer(SaColorize.TYPE, doc)
    var scribbles: Dictionary[Vector2i, Image] = {}
    _scribble(scribbles, Rect2i(A.get_center() - Vector2i(15, 3), Vector2i(30, 6)), RED)
    _scribble(scribbles, Rect2i(B.get_center() - Vector2i(15, 3), Vector2i(30, 6)), GREEN)
    _scribble(scribbles, Rect2i(C.get_center() - Vector2i(15, 3), Vector2i(30, 6)), BLUE)
    _scribble(scribbles, Rect2i(OUTSIDE - Vector2i(3, 6), Vector2i(6, 12)), SaColorize.TRANSPARENT)
    _upload(layer, scribbles)
    return layer


## *rect* of *colour* drawn into the tiles of *scribbles*, one a chunk.
func _scribble(scribbles: Dictionary[Vector2i, Image], rect: Rect2i, colour: Color) -> void:
    var side := SaChunk.SIZE
    for y in range(rect.position.y, rect.end.y):
        for x in range(rect.position.x, rect.end.x):
            var grid := Vector2i(floori(float(x) / side), floori(float(y) / side))
            if not scribbles.has(grid):
                scribbles[grid] = Image.create_empty(side, side, false, Image.FORMAT_RGBAF)
            scribbles[grid].set_pixel(x - grid.x * side, y - grid.y * side, colour)


## The tiles of *scribbles* written into *layer*'s scribbles, as a brush's
## strokes would leave them.
func _upload(layer: SaLayer, scribbles: Dictionary[Vector2i, Image]) -> void:
    var rd := GlobalShaderCompiler.get_rd()
    for grid: Vector2i in scribbles:
        var keys := layer.get_or_create_chunk(grid).field(SaColorize.KEYS)
        rd.texture_update(keys.rid, 0, scribbles[grid].get_data())
        layer.mark_unresolved(grid)


func _flats(layer: SaLayer) -> Image:
    return _image_of(layer, SaColorize.FLATS, Image.FORMAT_RGBAH)


## *field* of *layer* over *area* as one picture, transparent where the layer
## holds no chunk.
func _image_of(layer: SaLayer, field: StringName, format: int, area: Rect2i = Rect2i(0, 0, SIDE, SIDE)) -> Image:
    var out := Image.create_empty(area.size.x, area.size.y, false, Image.FORMAT_RGBAF)
    var rd := GlobalShaderCompiler.get_rd()
    var side := SaChunk.SIZE
    for grid: Vector2i in layer.chunks:
        var texture := (layer.chunks[grid] as SaChunk).field(field)
        if texture == null:
            continue
        var tile := Image.create_from_data(texture.size.x, texture.size.y, false, format, rd.texture_get_data(texture.rid, 0))
        tile.convert(Image.FORMAT_RGBAF)
        out.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), grid * side - area.position)
    return out


static func _same(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01 and absf(a.a - b.a) < 0.01


func _button(brush: Object, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    brush.handle_input(event)


func _move(brush: Object, at: Vector2) -> void:
    _surface.view.mouse_position = at
    var event := InputEventMouseMotion.new()
    event.pressure = 1.0
    brush.handle_input(event)
