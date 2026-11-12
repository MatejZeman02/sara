## A feathered selection holds paint
## to its feather across chunk edges.
##
## A square filled under a 30 px feather
## faded on its left and stopped dead on its right, where its edge was a
## chunk's, and a stroke and a path fill under a 6 px and a 40 px feather laid
## paint at full strength in a chunk nothing was selected near. Both were one
## fault in the feather's kernels: a pass over a chunk the selection held no
## mask in took the chunk's width from the 1 by 1 stand-in bound for it, so it
## read its neighbours one texel from the seam rather than one chunk, and
## wrote zeros where the spill belonged or a copy of the neighbour where
## nothing belonged.
##
## Each test fills or strokes through the doors a painter
## uses, the path step's fill and the brush on the tool machine, and reads
## the layer's texels back.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const ScenarioPath = preload("res://harness/scenario/sa_scenario_path.gd")

## Three chunks by three, so a square, its feather and a stroke can each cross
## a seam with a chunk to spare on every side.
const CANVAS := Vector2i(768, 768)

## A 200 px square whose right edge is the seam at x 512, Probe 2's fourth
## square moved onto a seam of this canvas.
const SEAM_SQUARE := Rect2i(312, 160, 200, 200)

## The probe's feather on that square.
const WIDE := 30

## The chunk the converse is read over, (1, 1), whose far corner from the
## canvas's origin is (512, 256) at its top right.
const CROSSED := Vector2i(1, 1)

## A square 90 px right of and 90 px below that corner, in the chunk beside
## the crossed one, which is where the crossed chunk's pass read its copy from.
const NEAR := Rect2i(602, 346, 60, 60)

## A second square in the chunk at the canvas's origin, added to the first,
## which carries the selection's box over the crossed chunk without entering
## it, as the jug's three shapes carried theirs.
const FAR := Rect2i(100, 100, 60, 60)

## The block-in's feather.
const NARROW := 6

## The row the stroke runs along, through the crossed chunk and the near square.
const STROKE_ROW := 376

## What counts as paint on a texel: anything a reader could see.
const SEEN := 0.002

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _doc: SaDocument = null
var _kept_foreground: Color
## Grid position -> the albedo bytes of that layer chunk, read once a test.
var _read: Dictionary = {}


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _machine = Fixtures.make_bound_machine(_surface)
    _doc = _surface.get_document()
    _kept_foreground = SaColors.foreground
    SaColors.foreground = Color(0.1, 0.1, 0.1, 1.0)
    _read.clear()


func after_each() -> void:
    SaColors.foreground = _kept_foreground
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null
    _read.clear()


## A 30 px feather on a square whose right edge is a chunk's fades the fill
## over the same width on both sides, and lays nothing past the feather.
func test_a_wide_feather_fades_the_same_on_both_sides_of_a_seam() -> void:
    _doc.selection.select_rect(SEAM_SQUARE)
    SaSelectionFilters.feather(_doc.selection, WIDE, CANVAS)
    assert_true(ScenarioPath.fill(_doc, _whole_canvas()) > 0, "The fill reached the square's chunks")

    var row := SEAM_SQUARE.get_center().y
    var left := _fade_width(row, SEAM_SQUARE.position.x - WIDE - 2, SEAM_SQUARE.position.x + WIDE + 2)
    var right := _fade_width(row, SEAM_SQUARE.end.x - WIDE - 2, SEAM_SQUARE.end.x + WIDE + 2)
    assert_true(left >= 2 * WIDE - 2, "The left edge fades over the feather's width each way, %d px" % left)
    assert_true(absi(left - right) <= 2, "and the right edge, on the seam, over the same width, %d px against %d" % [right, left])
    assert_true(_alpha(SEAM_SQUARE.end.x + 15, row) > 0.05, "Past the seam the fade still lays paint, halfway out")
    assert_true(_alpha(SEAM_SQUARE.end.x, row) < 0.9, "and on it the fill is no longer whole")
    _assert_within(_grown([SEAM_SQUARE], WIDE), "the 30 px fill")


## Two squares with a chunk between them, feathered by 6 px, and a stroke and a
## path fill across that chunk: nothing lands further than the feather from
## the squares, in the crossed chunk or anywhere else.
func test_a_stroke_and_a_fill_lay_nothing_past_a_narrow_feather() -> void:
    var selection := _doc.selection
    selection.select_rect(FAR)
    selection.select_rect(NEAR, SaSelection.Mode.ADD)
    assert_false(selection.chunks.has(CROSSED), "No square enters the crossed chunk")
    assert_true(selection.bounds.intersects(SaSelection.chunk_rect(CROSSED)), "though the selection's box crosses it")
    SaSelectionFilters.feather(selection, NARROW, CANVAS)
    var allowed := _grown([FAR, NEAR], NARROW)

    _stroke(Vector2(SaChunk.SIZE + 10, STROKE_ROW), Vector2(NEAR.end.x + 40, STROKE_ROW))
    assert_true(_alpha(NEAR.get_center().x, STROKE_ROW) > 0.5, "The stroke painted the near square")
    _assert_within(allowed, "the stroke")

    _doc.undo()
    _read.clear()
    assert_true(ScenarioPath.fill(_doc, _whole_canvas()) > 0, "The path fill reached the squares' chunks")
    assert_true(_alpha(FAR.get_center().x, FAR.get_center().y) > 0.5, "The fill covered the far square")
    assert_true(_alpha(NEAR.get_center().x, NEAR.get_center().y) > 0.5, "and the near one")
    _assert_within(allowed, "the path fill")


## A path step over the whole canvas kept inside the selection, a flat fill of a selection.
static func _whole_canvas() -> Dictionary:
    var polygon := [[-4, -4], [CANVAS.x + 4, -4], [CANVAS.x + 4, CANVAS.y + 4], [-4, CANVAS.y + 4]]
    return {"polygon": polygon, "inside_selection": true}


## Each of *rects* grown by *radius* on every side, which is everything a box
## blur of that radius can reach.
static func _grown(rects: Array, radius: int) -> Array[Rect2i]:
    var out: Array[Rect2i] = []
    for rect: Rect2i in rects:
        out.append(rect.grow(radius))
    return out


## A brush stroke from *from* to *to* in document pixels, through the tool
## machine as a pen would make it.
func _stroke(from: Vector2, to: Vector2) -> void:
    _machine.set_active_tool(&"brush")
    _surface.view.mouse_position = from
    _button(true)
    var steps := 24
    for i in range(1, steps + 1):
        var motion := InputEventMouseMotion.new()
        motion.pressure = 1.0
        _surface.view.mouse_position = from.lerp(to, float(i) / steps)
        _machine.active_tool.handle_input(motion)
    _button(false)


func _button(pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    _machine.active_tool.handle_input(event)


## How many columns of *row* between *from* and *to* hold part of the fill,
## more than nothing and less than all of it.
func _fade_width(row: int, from: int, to: int) -> int:
    var width := 0
    for x in range(from, to):
        var a := _alpha(x, row)
        if a > SEEN and a < 1.0 - SEEN:
            width += 1
    return width


## Every texel of every chunk the layer holds that carries paint lies inside one
## of *allowed*. Fails once, naming the first texel past them and how many.
func _assert_within(allowed: Array[Rect2i], what: String) -> void:
    var stray := 0
    var first := Vector2i(-1, -1)
    var painted := 0
    for grid_pos: Vector2i in _doc.active_layer.chunks:
        var origin := grid_pos * SaChunk.SIZE
        for y in SaChunk.SIZE:
            for x in SaChunk.SIZE:
                if _alpha(origin.x + x, origin.y + y) <= SEEN:
                    continue
                painted += 1
                var at := origin + Vector2i(x, y)
                if not _inside_any(allowed, at):
                    if stray == 0:
                        first = at
                    stray += 1
    assert_true(painted > 0, "%s laid paint" % what.capitalize())
    assert_eq(stray, 0, "and none of it past the feather, the first stray texel at %s" % first)


static func _inside_any(rects: Array[Rect2i], at: Vector2i) -> bool:
    for rect: Rect2i in rects:
        if rect.has_point(at):
            return true
    return false


## The layer's alpha at a document pixel, zero where it holds no chunk.
func _alpha(x: int, y: int) -> float:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var chunk: SaChunk = _doc.active_layer.chunks.get(grid, null)
    if chunk == null:
        return 0.0
    var texture: SaTexture = chunk.field(SaFieldSpec.ALBEDO)
    if not _read.has(grid):
        _read[grid] = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var bytes: PackedByteArray = _read[grid]
    var texel := (y % SaChunk.SIZE) * texture.size.x + x % SaChunk.SIZE
    if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
        return bytes.decode_half(texel * 8 + 6)
    return bytes.decode_float(texel * 16 + 12)
