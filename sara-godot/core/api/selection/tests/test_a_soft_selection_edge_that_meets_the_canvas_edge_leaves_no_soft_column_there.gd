## A soft selection edge that meets the canvas edge leaves no
## soft column there.
##
## A feather is a box blur along the rows and then the columns, and it read
## what the selection holds past a flat canvas's edge, which is nothing unless
## the outline ran past it. A feathered rectangle from x 0 to the canvas's
## width then faded against the left and the right edges, and a fill through it
## left soft columns there. The blur now reads the edge's own texels past it,
## so the edge columns read what the column a feather inside reads, and a
## rectangle that stops ten texels short fades as it did, by the tent a box
## blur lays. Every mask and the fill are read back from VRAM, on a canvas whose
## chunks end where it does and on one whose last chunk runs past it. The
## running app is
## `scenarios/a-soft-selection-edge-that-meets-the-canvas-edge-leaves-no-soft-column-there.json`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const FEATHER: int = 20
## How far short of the left and the right edges the second rectangle stops.
const SHORT: int = 10
## The rows the rectangle covers, well inside the canvas so the columns read
## at its middle row are the rows' feather alone.
const TOP: int = 100
const HEIGHT: int = 200
## Half the height, how far below the top the middle row is.
const MIDDLE: int = 100
const FILL := Color(0.2, 0.6, 0.3, 1.0)
## Float textures written by a compute pass and read back as float, so this is
## rounding rather than tolerance.
const TOLERANCE := 0.002

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _doc: SaDocument = null


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null


## A canvas *width* wide with a rectangle from *inset* to *inset* short of its
## right edge, feathered as the Select menu feathers once its dialog is
## answered.
func _feathered(width: int, inset: int) -> void:
    _surface = Fixtures.make_surface(Vector2i(width, 400))
    _machine = Fixtures.make_bound_machine(_surface)
    _doc = _surface.get_document()
    _doc.active_layer.allocate_grid(_doc.canvas_size)
    _doc.selection.select_rect(Rect2i(inset, TOP, width - inset * 2, HEIGHT))
    var selection := _doc.selection
    selection.change(SaSelection.FEATHER_TITLE, selection.feather.apply.bind(selection, FEATHER, _doc.canvas_size))


## The red channel's float at *at* of *texture*, which holds *stride* floats a
## texel: the selection's coverage or a layer texel's first channel.
func _read(texture: SaTexture, local: Vector2i, stride: int, channel: int) -> float:
    var data := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return data.decode_float(((local.y * texture.size.x + local.x) * stride + channel) * 4)


func _grid(at: Vector2i) -> Vector2i:
    @warning_ignore("integer_division")
    return Vector2i(at.x / SaChunk.SIZE, at.y / SaChunk.SIZE)


func _coverage(x: int) -> float:
    var at := Vector2i(x, TOP + MIDDLE)
    var chunk: SaChunk = _doc.selection.chunks.get(_grid(at), null)
    if chunk == null:
        return 0.0
    return _read(chunk.field(SaSelection.FIELD), at - _grid(at) * SaChunk.SIZE, 1, 0)


## The alpha a fill through the selection laid at column *x* of the middle row.
func _alpha(x: int) -> float:
    var at := Vector2i(x, TOP + MIDDLE)
    var texture: SaTexture = _doc.active_layer.get_or_create_field(_grid(at))
    return _read(texture, at - _grid(at) * SaChunk.SIZE, 4, 3)


## The first and last columns read what the column a feather inside reads, in
## the selection and in a fill through it.
func _assert_whole_at_the_edges(width: int) -> void:
    _feathered(width, 0)
    var last := width - 1
    var pairs := {"first": [0, FEATHER], "last": [last, last - FEATHER]}
    for side: String in pairs:
        var edge: int = pairs[side][0]
        var inside: int = pairs[side][1]
        var at_edge := _coverage(edge)
        var within := _coverage(inside)
        assert_almost_eq(at_edge, within, TOLERANCE, "%d wide: the %s column's coverage is a feather inside's" % [width, side])
        assert_true(at_edge >= 1.0 - TOLERANCE, "%d wide: the %s column is whole, %f" % [width, side, at_edge])
    _doc.active_layer.fill(FILL)
    for side: String in pairs:
        var edge_alpha := _alpha(pairs[side][0])
        var inside_alpha := _alpha(pairs[side][1])
        var what := "%d wide: the fill's %s column is as opaque as inside" % [width, side]
        assert_almost_eq(edge_alpha, inside_alpha, TOLERANCE, what)


## A tent: a box of 2 FEATHER + 1 texels centred SHORT texels outside the
## selection's edge holds FEATHER - SHORT + 1 selected texels.
func _assert_fades_short_of_the_edges(width: int) -> void:
    _feathered(width, SHORT)
    var expected := float(FEATHER - SHORT + 1) / float(2 * FEATHER + 1)
    for x: int in [0, width - 1]:
        var got := _coverage(x)
        assert_almost_eq(got, expected, TOLERANCE, "%d wide: column %d fades as the tent lays it, %f" % [width, x, got])
    var half := _coverage(SHORT)
    assert_true(half > 0.4 and half < 0.6, "%d wide: the selection's own edge is half selected, %f" % [width, half])


func test_a_rectangle_that_meets_both_edges_of_a_canvas_its_chunks_end_at_is_whole_there() -> void:
    _assert_whole_at_the_edges(512)


func test_a_rectangle_that_meets_both_edges_of_a_canvas_inside_its_chunks_is_whole_there() -> void:
    _assert_whole_at_the_edges(600)


func test_a_rectangle_ten_short_of_the_edges_of_a_canvas_its_chunks_end_at_fades_as_before() -> void:
    _assert_fades_short_of_the_edges(512)


func test_a_rectangle_ten_short_of_the_edges_of_a_canvas_inside_its_chunks_fades_as_before() -> void:
    _assert_fades_short_of_the_edges(600)
