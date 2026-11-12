## The Stats docker's coverage and edge density: how much of the canvas is
## painted at all, and how much of what is painted is edge.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Two numbers, one tally**: how much of the canvas is painted at all, and
## how much of it is edge, from the Laplacian's energy. Both come from one
## tally of two cells a chunk, counted by
## `coverage_and_edges.gmacs` beside it over the composite's painted
## chunks through the reduction service, and the tally is the one thing read
## back.
##
## **Painted** is the share of the canvas where the composite differs from the
## background alone, which [Background] reads off the bottom of the stack: on
## a transparent document any alpha at all, and on one laid on a colour or a
## ground a colour further than `TOLERANCE` from the background's in Oklab, a
## ground's grain between its two colours counting as background. The canvas
## no layer holds is background and is never dispatched over (hard rule 2).
##
## **Edge** is the share of the painted area that is edge. Each painted texel
## counts by the energy of the Laplacian of its Oklab lightness, the square of
## it over `FULL`'s, wholly from a hard step of a tenth of the lightness range
## and less below it, so a hard edge counts more than the same edge blurred and
## a flat fill counts nothing.
##
## **The halo over sparse chunks.** The Laplacian reads one texel past each side
## of a chunk, so a chunk's border texels hold a tally that changes when the
## next chunk is painted. [Reach] re-reads the four chunks beside each changed
## one, so the fold over changed chunks never keeps an edge that is gone, and an
## edge along a chunk border counts as one inside a chunk does (hard rule 3).
extends SaStatsNumber

const SHADER := "coverage_and_edges"
const KERNEL := "coverage_and_edges"

## The tally's cells a chunk, and the fixed point the edge crosses the bus in.
## All four must match `coverage_and_edges.gmacs`.
const CELLS := 2
const CELL_PAINTED := 0
const CELL_EDGE := 1
const QUANT := 32768.0

## The Laplacian of Oklab L at which a texel is wholly edge, and how far from
## the background a texel is painted. Both must match the kernel, and the
## tooltip says both.
const FULL := 0.1
const TOLERANCE := 0.002

## The four chunks whose border texels read into a chunk, which the Laplacian's
## four neighbours reach and its corners do not.
const SIDES: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]

## What the rows say on hover: how painted is told and what counts as edge.
const HOVER := (
    "Painted is the share of the canvas that differs from the background alone:"
    + " any paint on a transparent document, and otherwise a colour more than 0.002 from the background's in Oklab,"
    + " a ground's grain between its two colours counting as background."
    + " Edge is the share of the painted canvas that is edge: each painted texel counts by the energy of the"
    + " Laplacian of its Oklab lightness against its four neighbours, wholly from a hard step of 0.1."
)


## The tally over the changed chunks and the four beside each, whose border
## texels the Laplacian reads into the changed one.
class Reach:
    extends SaReductionService.OverDocument

    ## A changed chunk is read again, and so are its four neighbours.
    func _on_chunks_invalidated(grid_positions: Array) -> void:
        var reached: Array = []
        for grid_pos: Vector2i in grid_positions:
            reached.append(grid_pos)
            for side: Vector2i in SIDES:
                reached.append(grid_pos + side)
        super(reached)


## What the canvas shows where nothing is painted, as the kernel compares it.
##
## The bottom of the stack, read the way `SaGeneratedLayer.ground_index` reads
## it: the grounds at the top level and the Background a new document was laid
## on, of which the topmost visible one shows. None is a transparent document,
## whose paint is laid over the document's mid grey for its lightness.
class Background:
    extends RefCounted

    ## Whether the document is laid on a colour or a ground.
    var laid: bool = false
    ## The background as the document stores it, and a ground's second colour,
    ## the first again for a plain colour.
    var first: Color = SaDocument.BACKGROUND_GREY
    var second: Color = SaDocument.BACKGROUND_GREY

    func _init(document: SaDocument) -> void:
        var space := document.color_space
        first = space.from_display(SaDocument.BACKGROUND_GREY) if space != null else SaDocument.BACKGROUND_GREY
        second = first
        var shown: SaLayer = null
        var index := 0
        for child in document.get_children():
            var layer := child as SaLayer
            if layer == null or layer.is_group or SaLayerStack.parent_of(layer) != null:
                break
            var named := index == 0 and str(layer.name) == SaDocumentBackground.LAYER_NAME
            if not (layer.is_generated() or named):
                break
            if layer.visible:
                shown = layer
            index += 1
        if shown == null:
            return
        laid = true
        if not shown.is_generated():
            first = document.background_fill()
            second = first
            return
        var held: Variant = shown.generator_params.get(SaGeneratedLayer.PARAM_COLOR)
        if held is Color:
            first = held
        var other: Variant = shown.generator_params.get(SaGeneratedLayer.PARAM_SECOND)
        second = other if other is Color else first


## The share of the canvas painted and the share of that which is edge, as
## fractions, from the last total read.
var painted: float = 0.0
var edge: float = 0.0

var _painted_row: SaPageRow = null
var _edge_row: SaPageRow = null


func _init() -> void:
    reduction = Reach.new(SHADER, KERNEL, CELLS, push_for)


## A section of its own with two rows, painted and edge, each a percentage.
func declare(page: SaPage) -> void:
    var hover := tr(HOVER)
    var block := page.section("Painted and edges")
    _painted_row = block.custom("Painted", readout(hover)).named(&"painted").node("PaintedShare")
    _edge_row = block.custom("Edge", readout(hover)).named(&"edge_density").node("EdgeShare")
    _show()


## Reads *document*'s two shares out of the reduction's total and writes them into
## the rows.
func _fold(document: SaDocument) -> void:
    var numbers := reduction as SaReductionService.OverDocument
    var canvas := document.canvas_size
    painted = painted_share(numbers.total, canvas.x * canvas.y)
    edge = edge_share(numbers.total)
    _show()


## The share of a canvas of *texels* texels that *total* counts as painted.
static func painted_share(total: PackedInt64Array, texels: int) -> float:
    if texels <= 0 or total.size() < CELLS:
        return 0.0
    return float(total[CELL_PAINTED]) / float(texels)


## The share of the painted texels *total* counts that is edge, nought where
## nothing is painted.
static func edge_share(total: PackedInt64Array) -> float:
    if total.size() < CELLS or total[CELL_PAINTED] <= 0:
        return 0.0
    return float(total[CELL_EDGE]) / QUANT / float(total[CELL_PAINTED])


## The push constant `coverage_and_edges.gmacs` reads for *rect* of the
## composite, the chunk's share of the canvas, adding into *slot*. Static, so
## the reduction holds no callable that holds the part.
static func push_for(rect: Rect2i, slot: int, document: SaDocument) -> PackedFloat32Array:
    var space := document.color_space
    var params := PackedFloat32Array(
        [
            float(rect.position.x),
            float(rect.position.y),
            float(rect.end.x),
            float(rect.end.y),
            float(slot),
            float(space.coordinates),
        ]
    )
    params.append_array(space.transfer.to_params())
    for column: Vector3 in SaColorSpace.basis_columns(space.to_linear_srgb_matrix()):
        params.append_array(PackedFloat32Array([column.x, column.y, column.z]))
    var ground := Background.new(document)
    (
        params
        . append_array(
            PackedFloat32Array(
                [
                    1.0 if ground.laid else 0.0,
                    ground.first.r,
                    ground.first.g,
                    ground.first.b,
                    ground.second.r,
                    ground.second.g,
                    ground.second.b,
                ]
            )
        )
    )
    return params


## The two shares as percentages, the row's value to two places and its words
## to one. The words go into the control the row was handed, which is on the
## page before `realize` has filled in the row's `control`.
func _show() -> void:
    _write(_painted_row, painted)
    _write(_edge_row, edge)


static func _write(row: SaPageRow, share: float) -> void:
    if row == null:
        return
    var percent := snappedf(share * 100.0, 0.01)
    row.value = percent
    var shown := row.custom_control as Label
    if shown != null and is_instance_valid(shown):
        shown.text = "%.1f %%" % snappedf(percent, 0.1)
