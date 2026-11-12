## A feathered selection that runs past the canvas fades at no
## edge of it.
##
## A feather is a blur along the rows and then along the columns. The row pass
## read what the selection holds past the left and the right of the canvas, but
## it wrote the canvas's rows alone, so the column pass found nothing above the
## top or below the bottom and faded the selection there as if its own edge ran
## along them. Every mask is read back from VRAM, on a canvas whose chunks end
## where it does and on one whose last column and row of chunks run past it.
## The running app is
## `scenarios/a-feathered-selection-that-runs-past-the-canvas-fades-at-no-edge-of-it.json`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const FEATHER: int = 20
## How far the rectangle runs past every edge of the canvas.
const PAST: int = 50
## Float textures written by a compute pass and read back as float, so this is
## rounding rather than tolerance.
const TOLERANCE := 0.002

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _doc: SaDocument = null
## The selection's chunks read back once each, by grid position.
var _read: Dictionary[Vector2i, PackedByteArray] = {}


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null
    _read = {}


func _open(canvas: Vector2i) -> void:
    _surface = Fixtures.make_surface(canvas)
    _machine = Fixtures.make_bound_machine(_surface)
    _doc = _surface.get_document()


## Feather as the Select menu runs it once its dialog is answered.
func _feather(radius: int) -> void:
    var selection := _doc.selection
    selection.change(SaSelection.FEATHER_TITLE, selection.feather.apply.bind(selection, radius, _doc.canvas_size))
    _read = {}


func _coverage(at: Vector2i) -> float:
    @warning_ignore("integer_division")
    var grid := Vector2i(at.x / SaChunk.SIZE, at.y / SaChunk.SIZE)
    var chunk: SaChunk = _doc.selection.chunks.get(grid, null)
    if chunk == null:
        return 0.0
    var texture := chunk.field(SaSelection.FIELD)
    if not _read.has(grid):
        _read[grid] = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := at - grid * SaChunk.SIZE
    return _read[grid].decode_float((local.y * texture.size.x + local.x) * 4)


## The weakest coverage along the line of *count* pixels from *start* by *step*.
func _weakest(start: Vector2i, step: Vector2i, count: int) -> float:
    var out := INF
    for i in count:
        out = minf(out, _coverage(start + step * i))
    return out


## The outermost row and column on each side at full strength. Each is read
## short of the corners by a feather, so a side that fades fails its own line
## and not its neighbours', and the corners are read on their own.
func _assert_whole_at_every_edge(what: String) -> void:
    var size := _doc.canvas_size
    var last := size - Vector2i.ONE
    var sides := {
        "top row": [Vector2i(FEATHER, 0), Vector2i(1, 0), size.x - FEATHER * 2],
        "bottom row": [Vector2i(FEATHER, last.y), Vector2i(1, 0), size.x - FEATHER * 2],
        "left column": [Vector2i(0, FEATHER), Vector2i(0, 1), size.y - FEATHER * 2],
        "right column": [Vector2i(last.x, FEATHER), Vector2i(0, 1), size.y - FEATHER * 2],
    }
    for side: String in sides:
        var line: Array = sides[side]
        var weakest := _weakest(line[0], line[1], line[2])
        assert_true(weakest >= 1.0 - TOLERANCE, "%s: the %s is whole, weakest %f" % [what, side, weakest])
    var corners := minf(
        minf(_weakest(Vector2i.ZERO, Vector2i(1, 0), FEATHER), _weakest(Vector2i(last.x, 0), Vector2i(-1, 0), FEATHER)),
        minf(_weakest(Vector2i(0, last.y), Vector2i(1, 0), FEATHER), _weakest(last, Vector2i(-1, 0), FEATHER))
    )
    assert_true(corners >= 1.0 - TOLERANCE, "%s: the four corners are whole, weakest %f" % [what, corners])


func _feathered_past_the_canvas(canvas: Vector2i) -> void:
    _open(canvas)
    _doc.selection.select_rect(Rect2i(-PAST, -PAST, canvas.x + PAST * 2, canvas.y + PAST * 2))
    _feather(FEATHER)


func test_a_rectangle_past_a_canvas_its_chunks_end_at_stays_whole_at_every_edge() -> void:
    _feathered_past_the_canvas(Vector2i(512, 512))
    _assert_whole_at_every_edge("512 by 512")


func test_a_rectangle_past_a_canvas_inside_its_chunks_stays_whole_at_every_edge() -> void:
    _feathered_past_the_canvas(Vector2i(600, 400))
    _assert_whole_at_every_edge("600 by 400")


## A rectangle wholly inside fades over the feather on every side: half way at
## its edge, nothing a feather's width outside and everything one inside.
func test_a_rectangle_inside_the_canvas_still_fades_on_every_side() -> void:
    _open(Vector2i(600, 400))
    var box := Rect2i(100, 80, 400, 240)
    _doc.selection.select_rect(box)
    _feather(FEATHER)
    var mid := box.get_center()
    # The first pixel inside each edge, and the way out of the box from it.
    var sides := {
        "top": [Vector2i(mid.x, box.position.y), Vector2i(0, -1)],
        "bottom": [Vector2i(mid.x, box.end.y - 1), Vector2i(0, 1)],
        "left": [Vector2i(box.position.x, mid.y), Vector2i(-1, 0)],
        "right": [Vector2i(box.end.x - 1, mid.y), Vector2i(1, 0)],
    }
    for side: String in sides:
        var edge: Vector2i = sides[side][0]
        var out: Vector2i = sides[side][1]
        var at_edge := _coverage(edge)
        assert_true(at_edge > 0.4 and at_edge < 0.6, "The %s edge is half selected, %f" % [side, at_edge])
        var inside := _coverage(edge - out * FEATHER)
        assert_true(inside >= 1.0 - TOLERANCE, "a feather inside the %s edge is whole, %f" % [side, inside])
        var outside := _coverage(edge + out * (FEATHER + 1))
        assert_true(outside <= TOLERANCE, "and a feather outside it is empty, %f" % outside)


## A border is a dilate less an erode, run as the feather is, and its erode read
## nothing past the top and the bottom either, so the band of a selection past
## every edge ran along those two edges of the canvas and along no other.
func test_the_border_of_a_rectangle_past_every_edge_lays_no_band_on_the_canvas() -> void:
    _open(Vector2i(600, 400))
    var selection := _doc.selection
    selection.select_rect(Rect2i(-PAST, -PAST, 600 + PAST * 2, 400 + PAST * 2))
    selection.change(SaSelection.BORDER_TITLE, SaSelectionFilters.border.bind(selection, FEATHER, _doc.canvas_size))
    _read = {}
    var last := _doc.canvas_size - Vector2i.ONE
    var strongest := 0.0
    for at: Vector2i in [Vector2i(300, 0), Vector2i(300, last.y), Vector2i(0, 200), Vector2i(last.x, 200)]:
        strongest = maxf(strongest, _coverage(at))
    assert_true(strongest <= TOLERANCE, "No edge of the canvas carries a band, strongest %f" % strongest)
