## Select's own Feather, Grow, Border and Shrink cross the seam.
## The feather knows the seam of a document whose kind wraps,
## and the other three still stopped at the canvas's edge, so a selection grown
## over the seam of a panorama ended there.
##
## The document is 1000 by 500, a 2:1 panorama, so its last chunk column is 232
## texels wide and the seam is where a partial chunk meets the first one. Each
## case runs once on the equirectangular kind and once on a flat document, which
## stops at the edge as it always did. Every mask is read back from VRAM.
##
## A selection over the seam spans the whole width, so every pass also runs
## over the two middle columns of chunks, which hold none of it. A chunk the
## selection does not hold is bound as a 1 by 1 zero, and a pass that took that
## texture's width for the row's laid a copy of the next chunk's selection into
## the middle, so those columns are read whole as well.
##
## The Feather is run through the selection's `feather.apply`, the way the Select menu runs it,
## and the Marquee's and the Lasso's own Feathers through a drag of each tool.
## The running app is `scenarios/select-s-own-feather-grow-border-and-shrink-cross-the-seam.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const SIZE := Vector2i(1000, 500)
const ROW := 200

## A rectangle whose right side is the canvas's right edge, the seam.
const TOUCHING := Rect2i(970, 180, 30, 40)
## The two halves of one rectangle folded over the seam, x 970 to 1029 unfolded.
const RIGHT_HALF := Rect2i(970, 160, 30, 80)
const LEFT_HALF := Rect2i(0, 160, 30, 80)
## The columns of chunks between the two halves, which hold none of either.
const MIDDLE: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0)]

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _doc: SaDocument = null
var _feather_was: float = 0.0


func before_each() -> void:
    _surface = Fixtures.make_surface(SIZE)
    _machine = Fixtures.make_bound_machine(_surface)
    _doc = _surface.get_document()
    _feather_was = SaSettings.selection_feather
    SaSettings.selection_feather = 0.0


func after_each() -> void:
    SaSettings.selection_feather = _feather_was
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null


func _panorama() -> void:
    _doc.projection = SaProjection.new(SaProjection.Equirectangular.new())


func _wrapping() -> SaProjection.Wrap:
    return _doc.projection.wrapping


func _bytes(chunk: SaChunk) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(chunk.field(SaSelection.FIELD).rid, 0)


## The mask's coverage at a document pixel, 0 where no chunk is.
func _coverage(x: int, y: int = ROW) -> float:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var chunk: SaChunk = _doc.selection.chunks.get(grid, null)
    if chunk == null:
        return 0.0
    var local := Vector2i(x - grid.x * SaChunk.SIZE, y - grid.y * SaChunk.SIZE)
    return _bytes(chunk).decode_float((local.y * chunk.field(SaSelection.FIELD).size.x + local.x) * 4)


## The most any texel of the chunk at *grid_pos* is selected, 0 with no chunk.
func _most_in(grid_pos: Vector2i) -> float:
    var chunk: SaChunk = _doc.selection.chunks.get(grid_pos, null)
    if chunk == null:
        return 0.0
    var most := 0.0
    for value: float in _bytes(chunk).to_float32_array():
        most = maxf(most, value)
    return most


func _assert_middle_clear(what: String) -> void:
    for grid_pos: Vector2i in MIDDLE:
        assert_almost_eq(_most_in(grid_pos), 0.0, 0.001, "%s leaves the chunk at %s clear" % [what, grid_pos])


func _folded() -> void:
    _doc.selection.select_rect(RIGHT_HALF)
    _doc.selection.select_rect(LEFT_HALF, SaSelection.Mode.ADD)


## The four as the Select menu runs them once its dialog is answered, each one
## change under its own title and handed the document's wrapping.
func _grow(radius: int) -> void:
    var selection := _doc.selection
    selection.change(SaSelection.GROW_TITLE, SaSelectionFilters.grow.bind(selection, radius, SIZE, _wrapping()))


func _shrink(radius: int) -> void:
    var selection := _doc.selection
    selection.change(SaSelection.SHRINK_TITLE, SaSelectionFilters.shrink.bind(selection, radius, SIZE, _wrapping()))


func _border(radius: int) -> void:
    var selection := _doc.selection
    selection.change(SaSelection.BORDER_TITLE, SaSelectionFilters.border.bind(selection, radius, SIZE, _wrapping()))


func _feather(radius: int) -> void:
    var selection := _doc.selection
    selection.change(SaSelection.FEATHER_TITLE, selection.feather.apply.bind(selection, radius, SIZE, _wrapping()))


func test_a_grow_over_the_seam_carries_on_from_the_left_edge() -> void:
    _panorama()
    _doc.selection.select_rect(TOUCHING)
    _grow(10)
    assert_almost_eq(_coverage(999), 1.0, 0.001, "The rectangle's own last column stays selected")
    assert_almost_eq(_coverage(960), 1.0, 0.001, "Its left edge moved out by ten, to x 960")
    assert_almost_eq(_coverage(959), 0.0, 0.001, "and no further")
    assert_almost_eq(_coverage(0), 1.0, 0.001, "Past the seam the first column is selected")
    assert_almost_eq(_coverage(9), 1.0, 0.001, "and so is the tenth, the same ten as on the left side")
    assert_almost_eq(_coverage(10), 0.0, 0.001, "and the eleventh is not")
    assert_almost_eq(_coverage(5, 170), 1.0, 0.001, "Across the seam the top edge moved out by ten as well")
    assert_almost_eq(_coverage(5, 169), 0.0, 0.001, "and no further")
    assert_eq(_doc.selection.bounds, Rect2i(0, 170, 1000, 60), "The bounds hold both sides of the seam")


func test_a_grow_on_a_flat_document_stops_at_the_edge() -> void:
    _doc.selection.select_rect(TOUCHING)
    _grow(10)
    assert_almost_eq(_coverage(960), 1.0, 0.001, "The left edge moved out by ten")
    assert_almost_eq(_coverage(999), 1.0, 0.001, "and the right one is the canvas's edge")
    assert_almost_eq(_coverage(0), 0.0, 0.001, "Nothing comes back on the left edge")
    assert_almost_eq(_coverage(9), 0.0, 0.001, "anywhere in the ten")
    assert_eq(_doc.selection.bounds, Rect2i(960, 170, 40, 60), "The bounds end at the canvas's edge")


func test_a_grow_of_a_selection_over_the_seam_lays_nothing_between() -> void:
    _panorama()
    _folded()
    _grow(10)
    assert_almost_eq(_coverage(960), 1.0, 0.001, "The left edge moved out by ten")
    assert_almost_eq(_coverage(39), 1.0, 0.001, "and the right one, across the seam")
    assert_almost_eq(_coverage(40), 0.0, 0.001, "and no further")
    _assert_middle_clear("The grow")


## The pass that read a missing chunk as one texel wide was there before the
## seam, on a flat canvas whose selection spans a chunk it does not hold.
func test_a_grow_of_two_shapes_far_apart_on_a_flat_document_lays_nothing_between() -> void:
    _doc.selection.select_rect(Rect2i(10, 180, 30, 40))
    _doc.selection.select_rect(Rect2i(900, 180, 30, 40), SaSelection.Mode.ADD)
    _grow(10)
    assert_almost_eq(_coverage(0), 1.0, 0.001, "The left shape grew to the edge")
    assert_almost_eq(_coverage(939), 1.0, 0.001, "and the right one by ten")
    _assert_middle_clear("A grow of two shapes")


func test_a_shrink_of_a_selection_over_the_seam_keeps_the_seam() -> void:
    _panorama()
    _folded()
    _shrink(10)
    assert_almost_eq(_coverage(999), 1.0, 0.001, "The seam is no edge, so its last column stays")
    assert_almost_eq(_coverage(0), 1.0, 0.001, "and so does its first")
    assert_almost_eq(_coverage(980), 1.0, 0.001, "The left edge moved in by ten, to x 980")
    assert_almost_eq(_coverage(979), 0.0, 0.001, "and x 979 is out")
    assert_almost_eq(_coverage(19), 1.0, 0.001, "The right edge, across the seam, moved in by ten too")
    assert_almost_eq(_coverage(20), 0.0, 0.001, "and x 20 is out")
    assert_almost_eq(_coverage(0, 170), 1.0, 0.001, "The top edge moved in by ten on the seam")
    assert_almost_eq(_coverage(0, 169), 0.0, 0.001, "and no further")
    _assert_middle_clear("The shrink")


func test_a_shrink_on_a_flat_document_moves_away_from_the_edge() -> void:
    _folded()
    _shrink(10)
    assert_almost_eq(_coverage(999), 0.0, 0.001, "The canvas's edge counts as unselected on the right")
    assert_almost_eq(_coverage(0), 0.0, 0.001, "and on the left")
    assert_almost_eq(_coverage(989), 1.0, 0.001, "The right half ends ten in from the edge")
    assert_almost_eq(_coverage(990), 0.0, 0.001, "and not past it")
    assert_almost_eq(_coverage(10), 1.0, 0.001, "The left half begins ten in from the edge")
    assert_almost_eq(_coverage(9), 0.0, 0.001, "and not before it")
    _assert_middle_clear("The flat shrink")


func test_a_border_reaches_across_the_seam() -> void:
    _panorama()
    _doc.selection.select_rect(TOUCHING)
    _border(5)
    assert_almost_eq(_coverage(967), 1.0, 0.001, "The band lies over the left edge")
    assert_almost_eq(_coverage(985), 0.0, 0.001, "and the middle is out")
    assert_almost_eq(_coverage(997), 1.0, 0.001, "The band lies over the right edge, at the seam")
    assert_almost_eq(_coverage(0), 1.0, 0.001, "and carries on past it")
    assert_almost_eq(_coverage(4), 1.0, 0.001, "five texels wide")
    assert_almost_eq(_coverage(5), 0.0, 0.001, "and no wider")


func test_a_border_of_a_selection_over_the_seam_finds_no_edge_there() -> void:
    _panorama()
    _folded()
    _border(5)
    assert_almost_eq(_coverage(999), 0.0, 0.001, "The seam runs through the middle, so it is out")
    assert_almost_eq(_coverage(0), 0.0, 0.001, "on both sides")
    assert_almost_eq(_coverage(967), 1.0, 0.001, "The band lies over the left edge")
    assert_almost_eq(_coverage(30), 1.0, 0.001, "and over the right one, across the seam")
    assert_almost_eq(_coverage(999, 157), 1.0, 0.001, "The top band runs up to the seam")
    assert_almost_eq(_coverage(0, 157), 1.0, 0.001, "and on past it")
    _assert_middle_clear("The border")


func test_a_border_on_a_flat_document_stops_at_the_edge() -> void:
    _doc.selection.select_rect(TOUCHING)
    _border(5)
    assert_almost_eq(_coverage(997), 1.0, 0.001, "The band lies along the canvas's edge")
    assert_almost_eq(_coverage(2), 0.0, 0.001, "and nothing comes back on the left")
    _folded()
    _border(5)
    assert_almost_eq(_coverage(999), 1.0, 0.001, "Each half of the folded one has an edge at the canvas's edge")
    assert_almost_eq(_coverage(0), 1.0, 0.001, "on both sides")
    _assert_middle_clear("The flat border")


## A box blur of 8 makes a tent, so a texel *k* past the seam reads what the
## texel *k* before the rectangle's left edge reads, (8 - k) / 17.
func test_a_feather_across_the_seam_is_the_feather_of_the_far_edge() -> void:
    _panorama()
    _doc.selection.select_rect(TOUCHING)
    _feather(8)
    for k in 9:
        var across := _coverage(k)
        var mirrored := _coverage(969 - k)
        assert_almost_eq(across, (8.0 - k) / 17.0, 0.002, "x %d past the seam is the tent's %d" % [k, k])
        assert_almost_eq(across, mirrored, 0.002, "and the same as x %d before the left edge" % (969 - k))
    assert_almost_eq(_coverage(999), _coverage(970), 0.002, "The two edges inside are alike")


func test_a_feather_of_a_selection_over_the_seam_softens_nothing_between() -> void:
    _panorama()
    _folded()
    _feather(8)
    assert_almost_eq(_coverage(999), 1.0, 0.001, "The seam stays whole")
    assert_almost_eq(_coverage(0), 1.0, 0.001, "on both sides")
    _assert_middle_clear("The feather")


func test_a_feather_on_a_flat_document_stops_at_the_edge() -> void:
    _doc.selection.select_rect(TOUCHING)
    _feather(8)
    assert_true(_coverage(965) > 0.0, "The left edge is soft")
    assert_almost_eq(_coverage(0), 0.0, 0.001, "and nothing comes back on the left")


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


## A drag of *tool* through *points*, pressed at the first and let go at the last.
func _drag(tool: StringName, points: Array[Vector2]) -> void:
    _machine.set_active_tool(tool)
    var state := _machine.active_tool
    _surface.view.mouse_position = points[0]
    state.handle_input(_button(true))
    for at: Vector2 in points.slice(1):
        _surface.view.mouse_position = at
        state.handle_input(InputEventMouseMotion.new())
    state.handle_input(_button(false))


func _lasso_around_touching() -> void:
    var corners: Array[Vector2] = [Vector2(970, 180), Vector2(1000, 180), Vector2(1000, 220), Vector2(970, 220)]
    corners.append(corners[0])
    _drag(&"lasso", corners)


## The tools' Feather is a fraction of the smaller side, so 0.016 of 500 is 8.
func test_the_marquee_s_and_the_lasso_s_feathers_cross_the_seam() -> void:
    _panorama()
    SaSettings.selection_feather = 0.016
    _drag(&"marquee", [Vector2(970, 180), Vector2(1000, 220)])
    assert_eq(_doc.selection.bounds.position.x, 0, "The Marquee's soft edge reaches the first column")
    assert_true(_coverage(2) > 0.0, "and x 2 is soft: %f" % _coverage(2))
    _doc.selection.drop()
    _lasso_around_touching()
    assert_eq(_doc.selection.bounds.position.x, 0, "The Lasso's soft edge reaches the first column")
    assert_true(_coverage(2) > 0.0, "and x 2 is soft: %f" % _coverage(2))


func test_on_a_flat_document_the_tools_feathers_stop_at_the_edge() -> void:
    SaSettings.selection_feather = 0.016
    _drag(&"marquee", [Vector2(970, 180), Vector2(1000, 220)])
    assert_true(_coverage(965) > 0.0, "The Marquee's left edge is soft")
    assert_almost_eq(_coverage(2), 0.0, 0.001, "and nothing comes back on the left")
    _doc.selection.drop()
    _lasso_around_touching()
    assert_true(_coverage(965) > 0.0, "The Lasso's left edge is soft")
    assert_almost_eq(_coverage(2), 0.0, 0.001, "and nothing comes back on the left")
