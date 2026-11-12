## Select > Feather sets how soft the edge is, zero included.
##
## A Feather was laid over the selection as it stood, so 20 and then 5 blurred
## twice and barely moved an edge already 20 wide, and 0 had nothing to give
## back. The feather is a live amount over the hard mask now
## (`SaSelectionFeather`), so a new Feather replaces the last, a Grow grows the
## hard mask under it, and an undo brings both back. Every mask is read back
## from VRAM. The running app is
## `scenarios/select-feather-sets-how-soft-the-edge-is-zero-included.json`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Clear of the canvas's edge by more than the widest feather, and across the
## seam between chunks at 256.
const BOX := Rect2i(200, 200, 120, 120)
const TOLERANCE := 0.002

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _doc: SaDocument = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _machine = Fixtures.make_bound_machine(_surface)
    _doc = _surface.get_document()


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null


## Feather as the Select menu runs it once its dialog is answered.
func _feather(radius: int) -> void:
    var selection := _doc.selection
    selection.change(SaSelection.FEATHER_TITLE, selection.feather.apply.bind(selection, radius, _doc.canvas_size))


func _grow(radius: int) -> void:
    var selection := _doc.selection
    selection.change(SaSelection.GROW_TITLE, SaSelectionFilters.grow.bind(selection, radius, _doc.canvas_size))


func _coverage(x: int, y: int) -> float:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var chunk: SaChunk = _doc.selection.chunks.get(grid, null)
    if chunk == null:
        return 0.0
    var texture := chunk.field(SaSelection.FIELD)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := Vector2i(x - grid.x * SaChunk.SIZE, y - grid.y * SaChunk.SIZE)
    return bytes.decode_float((local.y * texture.size.x + local.x) * 4)


## The mask along a line through the box's middle, from 40 px left of its left
## edge to 40 px right of it, and the same across its top edge.
func _across_the_edge() -> PackedFloat32Array:
    var out := PackedFloat32Array()
    var mid := BOX.get_center()
    for offset in range(-40, 41):
        out.append(_coverage(BOX.position.x + offset, mid.y))
        out.append(_coverage(mid.x, BOX.position.y + offset))
    return out


func _assert_close(got: PackedFloat32Array, want: PackedFloat32Array, what: String) -> void:
    assert_eq(got.size(), want.size(), what + ": same samples")
    var worst := 0.0
    for i in mini(got.size(), want.size()):
        worst = maxf(worst, absf(got[i] - want[i]))
    assert_true(worst <= TOLERANCE, "%s: the worst texel is %f off" % [what, worst])


func test_five_after_twenty_gives_the_edge_five_gives_alone() -> void:
    _doc.selection.select_rect(BOX)
    _feather(5)
    var alone := _across_the_edge()
    _doc.selection.select_rect(BOX)
    _feather(20)
    var wide := _across_the_edge()
    var steps := _doc.undo_redo.get_history_count()
    _feather(5)
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "the second Feather is one undo step")
    _assert_close(_across_the_edge(), alone, "5 after 20 against 5 alone")
    var differs := 0.0
    for i in alone.size():
        differs = maxf(differs, absf(alone[i] - wide[i]))
    assert_true(differs > 0.05, "and 20 alone was a different edge, or the check proves nothing")


func test_zero_after_feathering_gives_the_hard_edge_back() -> void:
    _doc.selection.select_rect(BOX)
    var hard := _across_the_edge()
    _feather(20)
    _feather(5)
    _feather(0)
    _assert_close(_across_the_edge(), hard, "0 after 5 after 20 against the rectangle")
    assert_eq(_doc.selection.bounds, BOX, "and the box is the rectangle's")


func test_zero_with_no_feather_before_it_changes_nothing() -> void:
    _doc.selection.select_rect(BOX)
    var steps := _doc.undo_redo.get_history_count()
    _feather(0)
    assert_eq(_doc.undo_redo.get_history_count(), steps, "no step recorded")


func test_a_grow_after_a_feather_grows_the_hard_mask_and_keeps_the_feather() -> void:
    # What 5 over the rectangle grown by 2 gives, made from scratch.
    _doc.selection.select_rect(BOX.grow(2))
    _feather(5)
    var over_grown := _across_the_edge()
    _doc.selection.select_rect(BOX)
    _feather(5)
    var first := _across_the_edge()
    _grow(2)
    _assert_close(_across_the_edge(), over_grown, "5 then grow 2 against 5 over the grown rectangle")
    var steps := _doc.undo_redo.get_history_count()
    _feather(5)
    assert_eq(_doc.undo_redo.get_history_count(), steps, "and a Feather of the amount it has changes nothing")
    var moved := 0.0
    for i in first.size():
        moved = maxf(moved, absf(first[i] - over_grown[i]))
    assert_true(moved > 0.05, "and it is not the first Feather's edge over again")


func test_an_undone_feather_brings_its_amount_back_with_the_hard_mask() -> void:
    _doc.selection.select_rect(BOX)
    var hard := _across_the_edge()
    _feather(20)
    var wide := _across_the_edge()
    _feather(5)
    _doc.undo_redo.undo()
    _assert_close(_across_the_edge(), wide, "the undo brought the 20 back")
    _feather(0)
    _assert_close(_across_the_edge(), hard, "a Feather of 0 after the undo gives the hard edge back")
    _doc.undo_redo.undo()
    _assert_close(_across_the_edge(), wide, "as one step, which an undo takes back to the 20")
