## A selection keeps its hard edge and its feather is a live
## amount, so adding a shape never blurs the selection again.
##
## Every Shift add laid the tools' Feather over the whole selection once more,
## so an island across the canvas from the new shape shrank with each add. The
## selection holds its hard mask and one amount now (`SaSelectionFeather`), and
## what the readers bind is the hard mask feathered once by that amount. The
## shapes here land as the Marquee lands one, inside one change with the
## Feather set when the shape replaces the selection. Every mask is read back
## from VRAM. The running app is the scenario in `scenarios/` named after row
## Which reads the same numbers through the door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const CANVAS := Vector2i(1024, 512)
const FEATHER := 10
## At the left, in the first chunk, and the nine added after it at the right.
const FIRST := Rect2i(40, 60, 120, 140)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _doc: SaDocument = null


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _machine = Fixtures.make_bound_machine(_surface)
    _doc = _surface.get_document()


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null


## Lands *rect* in *mode* as the Marquee does, its Feather set when it replaces.
func _marquee(rect: Rect2i, mode: int, feather: int = FEATHER) -> void:
    var selection := _doc.selection
    var land := func() -> void:
        var replaced := mode == SaSelection.Mode.REPLACE or not selection.active
        selection.select_rect(rect, mode)
        if replaced:
            selection.feather.apply(selection, feather, _doc.canvas_size)
    selection.change(SaSelection.RECT_TITLE, land)


func _feather(radius: int) -> void:
    var selection := _doc.selection
    selection.change(SaSelection.FEATHER_TITLE, selection.feather.apply.bind(selection, radius, _doc.canvas_size))


## The nth of the nine rectangles added at the right, clear of the first by
## far more than the feather reaches.
func _added(n: int) -> Rect2i:
    @warning_ignore("integer_division")
    return Rect2i(560 + (n % 3) * 150, 30 + (n / 3) * 160, 90 + n * 3, 100)


func _bytes(chunks: Dictionary, grid_pos: Vector2i) -> PackedByteArray:
    var chunk: SaChunk = chunks.get(grid_pos, null)
    if chunk == null:
        return PackedByteArray()
    var texture := chunk.field(SaSelection.FIELD)
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


func _coverage(x: int, y: int) -> float:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var bytes := _bytes(_doc.selection.chunks, grid)
    if bytes.is_empty():
        return 0.0
    var local := Vector2i(x - grid.x * SaChunk.SIZE, y - grid.y * SaChunk.SIZE)
    return bytes.decode_float((local.y * SaChunk.SIZE + local.x) * 4)


## The largest difference, texel by texel, between the selection the readers
## bind and *chunks*, over every grid position either holds.
func _worst_against(chunks: Dictionary) -> float:
    var worst := 0.0
    var positions := {}
    for grid_pos: Vector2i in chunks.keys() + _doc.selection.chunks.keys():
        positions[grid_pos] = true
    for grid_pos: Vector2i in positions:
        var got := _bytes(_doc.selection.chunks, grid_pos)
        var want := _bytes(chunks, grid_pos)
        for i in range(0, maxi(got.size(), want.size()), 4):
            var a := got.decode_float(i) if i < got.size() else 0.0
            var b := want.decode_float(i) if i < want.size() else 0.0
            worst = maxf(worst, absf(a - b))
    return worst


## The hard mask the selection holds, feathered once by its amount in a
## selection of its own.
func _one_feather_of_the_hard_mask() -> Dictionary:
    var feather := _doc.selection.feather
    var scratch := SaSelection.new()
    scratch.chunks = feather.hard.chunks.duplicate()
    scratch.active = true
    scratch.bounds = feather.hard.bounds
    SaSelectionFilters.feather(scratch, feather.amount, _doc.canvas_size)
    return scratch.chunks


func test_ten_rectangles_added_one_by_one_leave_the_first_as_it_was() -> void:
    _marquee(FIRST, SaSelection.Mode.REPLACE)
    var first := _bytes(_doc.selection.chunks, Vector2i.ZERO)
    assert_true(_coverage(FIRST.position.x, FIRST.get_center().y) < 0.9, "the first rectangle's edge is soft")
    for n in 9:
        _marquee(_added(n), SaSelection.Mode.ADD)
        assert_eq(_bytes(_doc.selection.chunks, Vector2i.ZERO), first, "the first is as it was after add %d" % (n + 1))
    assert_almost_eq(_doc.selection.feather.amount, float(FEATHER), 0.0001, "and the amount is the first shape's")
    assert_true(_coverage(FIRST.get_center().x, FIRST.get_center().y) > 0.999, "its middle is selected")


func test_the_feathered_mask_is_one_feather_of_the_hard_mask_after_any_sequence() -> void:
    _marquee(FIRST, SaSelection.Mode.REPLACE)
    _marquee(_added(0), SaSelection.Mode.ADD)
    assert_true(_worst_against(_one_feather_of_the_hard_mask()) < 1e-6, "after an add")
    _feather(20)
    _marquee(_added(1), SaSelection.Mode.ADD)
    assert_true(_worst_against(_one_feather_of_the_hard_mask()) < 1e-6, "after a Feather of 20 and an add")
    _feather(5)
    _feather(20)
    _marquee(_added(4), SaSelection.Mode.SUBTRACT)
    _marquee(Rect2i(0, 0, 900, 400), SaSelection.Mode.INTERSECT)
    assert_true(_worst_against(_one_feather_of_the_hard_mask()) < 1e-6, "after 5, 20, a subtract and an intersect")
    var growing := _doc.selection
    growing.change(SaSelection.GROW_TITLE, SaSelectionFilters.grow.bind(growing, 3, _doc.canvas_size))
    assert_true(_worst_against(_one_feather_of_the_hard_mask()) < 1e-6, "after a Grow, which grew the hard mask")
    assert_almost_eq(_doc.selection.feather.amount, 20.0, 0.0001, "and the amount is the last Feather's")


func test_twenty_five_twenty_is_one_twenty_and_zero_gives_the_hard_edge_back() -> void:
    _marquee(FIRST, SaSelection.Mode.REPLACE, 0)
    var hard := _doc.selection.chunks.duplicate()
    _feather(20)
    var once := _doc.selection.chunks.duplicate()
    _feather(5)
    _feather(20)
    assert_true(_worst_against(once) < 1e-6, "20, 5 and 20 is one Feather of 20")
    _feather(0)
    assert_true(_worst_against(hard) < 1e-6, "and 0 gives the hard edge back")
    assert_eq(_doc.selection.bounds, FIRST, "with the rectangle's box")


func test_an_undone_add_brings_the_hard_mask_and_the_amount_back() -> void:
    _marquee(FIRST, SaSelection.Mode.REPLACE)
    _feather(15)
    var hard_before := _doc.selection.feather.hard
    var shown := _doc.selection.chunks.duplicate()
    _marquee(_added(2), SaSelection.Mode.ADD)
    _feather(4)
    _doc.undo_redo.undo()
    _doc.undo_redo.undo()
    assert_almost_eq(_doc.selection.feather.amount, 15.0, 0.0001, "the amount is back")
    assert_eq(_doc.selection.feather.hard, hard_before, "the hard mask is back")
    assert_true(_worst_against(shown) < 1e-6, "and the feathered mask is what it was")
    _marquee(_added(3), SaSelection.Mode.ADD)
    assert_true(_worst_against(_one_feather_of_the_hard_mask()) < 1e-6, "and the next add feathers the hard mask once")


func test_a_shape_that_replaces_takes_the_tool_s_amount_and_select_all_is_hard() -> void:
    _marquee(FIRST, SaSelection.Mode.REPLACE)
    _marquee(_added(0), SaSelection.Mode.REPLACE, 6)
    assert_almost_eq(_doc.selection.feather.amount, 6.0, 0.0001, "a replace takes the tool's amount")
    var selection := _doc.selection
    selection.change(SaSelection.ALL_TITLE, selection.select_all.bind(_doc.canvas_size))
    assert_eq(selection.feather.amount, 0.0, "Select All is hard")
    assert_true(selection.selects_everything(), "and is still the whole canvas")
