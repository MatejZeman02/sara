## Select Subject's and Object Selection's run on a document: its picture,
## or the part of it round a dragged box, made into the network's input on the
## card, the network, and its mask laid over the canvas, or over the box alone,
## as selection chunks that join the selection in the mode asked for, one undo
## step.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The picture is taken as the wand takes it: the merged picture when the
## caller hands it over, after a flush, and the active layer's chunks
## otherwise. `subject_prepare.gmacs` beside this file samples it into the 320
## by 320 tensor and applies `ToTensorLab(flag=0)`, the network runs, and
## `subject_spread.gmacs` writes its sigmoid into `r32f` chunks over the
## canvas, which [method SaSelection.merge_region] joins to the selection
## inside one [method SaSelection.change]. There is no threshold: the
## coverage is the sigmoid. Nothing of the picture or the mask is read back.
## The one read on the way is the merge's own, the four numbers of the
## selection's box that `SaSelection.measure_bounds` reduces on the card, which
## every wand click makes too.
##
## **A box** makes the run Object Selection's. The network reads the box grown
## by [constant MARGIN] of its size on each side, inside the canvas, so the
## object fills the tensor and has some of its surroundings to stand out from,
## and the mask is laid inside the box as dragged and nowhere else. Only the
## chunks the box touches are written, so a box in a large canvas costs what
## the box does.
##
## It selects and nothing else: no paint, no layer mask and no erase.
extends RefCounted

const SubjectNetwork := preload("../network/subject_network.gd")

## The history's titles for the step, a run over the whole picture and one
## inside a box.
const TITLE := "Select Subject"
const BOX_TITLE := "Object Selection"
## How far the picture the network reads reaches past a box on each side, as
## a fraction of the box's side along that axis.
const MARGIN := 0.1
## The network's side, the tensor's and the mask's.
const SIDE := SubjectNetwork.SIZE
## Invocations along a workgroup's x in the kernels of `subject_prepare`.
const LANES := 64
## No kernel of `subject_prepare` writes an image, so its variant is the same
## at any format, and the spread writes the selection's own.
const PREPARE_FORMAT := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

## Why the last run did nothing, empty when it ran.
var error: String = ""
## Runs that reached the selection, which a suite reads.
var runs: int = 0

var _prepare: SaCompute = null
var _spread: SaCompute = null
## Premultiplied colour and coverage, four planes of 320 by 320.
var _sums: SaCompute.Buffer = null
## The largest of each row of the tensor and then of them all.
var _largest: SaCompute.Buffer = null
## What the sampler holds for a layer with no chunks, which adds nothing.
var _blank: SaTexture = null


## Selects the subject of *document*'s picture in *mode*, a `SaSelection.Mode`,
## with *network*. *merged* is the composited picture the size of the canvas,
## flushed, or null to read the active layer alone. A *box* with an area, in
## document pixels, selects the object inside it alone, and an empty one the
## subject of the whole picture. Answers whether the selection was reached, and
## [member error] says why not.
func select(document: SaDocument, network: SubjectNetwork, mode: int, merged: SaTexture = null, box: Rect2i = Rect2i()) -> bool:
    error = ""
    if document == null:
        error = "There is no document to select in."
        return false
    var whole := Rect2i(Vector2i.ZERO, document.canvas_size)
    var clip := whole
    var region := whole
    if box.has_area():
        clip = box.intersection(whole)
        if not clip.has_area():
            error = "The box lies outside the canvas."
            return false
        region = grown(box).intersection(whole)
    if network == null or not network.error.is_empty():
        error = network.error if network != null else "There is no network to run."
        return false
    if not _prepare_input(document, network.input, merged, region):
        return false
    if not network.run():
        error = network.error
        return false
    var title := BOX_TITLE if box.has_area() else TITLE
    document.selection.change(title, _merge.bind(document, network.output, mode, clip, region))
    runs += 1
    return true


## *box* grown by [constant MARGIN] of its size on each side, in whole pixels.
static func grown(box: Rect2i) -> Rect2i:
    var by := Vector2i(ceili(box.size.x * MARGIN), ceili(box.size.y * MARGIN))
    return box.grow_individual(by.x, by.y, by.x, by.y)


## Records the preparation of *region* of the picture into *tensor* and
## submits it as one list.
func _prepare_input(document: SaDocument, tensor: SaCompute.Buffer, merged: SaTexture, region: Rect2i) -> bool:
    if _prepare == null:
        _prepare = SaCompute.new("subject_prepare")
        _spread = SaCompute.new("subject_spread")
        var zeros := PackedFloat32Array()
        zeros.resize(4 * SIDE * SIDE)
        _sums = SaCompute.Buffer.new(zeros.to_byte_array())
        var rows := PackedFloat32Array()
        rows.resize(3 * SIDE + 1)
        _largest = SaCompute.Buffer.new(rows.to_byte_array())
    var canvas := Vector2(document.canvas_size)
    var sources := _sources(document, merged, Rect2(region))
    _prepare.set_storage("sums", _sums.rid)
    _prepare.set_storage("tensor", tensor.rid)
    _prepare.set_storage("largest", _largest.rid)
    var params := _colour_params(document.color_space)
    params["region_origin"] = Vector2(region.position)
    params["region_size"] = Vector2(region.size)
    params["source_origin"] = Vector2.ZERO
    params["source_size"] = canvas
    var first: SaTexture = sources[0][0] if not sources.is_empty() else _blank_texture()
    _prepare.set_sampler("source", first.rid)
    _prepare.set_params(params)
    var plane := SIDE * SIDE
    var recorded: Array[SaCompute.Recorded] = []
    var clear := _prepare.record("subject_clear", PREPARE_FORMAT, _groups(4 * plane), 1, 1, false)
    if clear == null:
        error = "The kernels that prepare the picture could not be recorded."
        return false
    recorded.append(clear)
    for each: Array in sources:
        var texture: SaTexture = each[0]
        var covers: Rect2 = each[1]
        _prepare.set_sampler("source", texture.rid)
        params["source_origin"] = covers.position
        params["source_size"] = covers.size
        _prepare.set_params(params)
        var gather := _prepare.record("subject_gather", PREPARE_FORMAT, _groups(plane), 1, 1, true)
        if gather != null:
            recorded.append(gather)
    for step: Array in [
        ["subject_flatten", plane], ["subject_rows", 3 * SIDE], ["subject_largest", 1], ["subject_normalise", plane]
    ]:
        var one := _prepare.record(step[0], PREPARE_FORMAT, _groups(step[1]), 1, 1, true)
        if one == null:
            error = "The kernel %s could not be recorded." % step[0]
            return false
        recorded.append(one)
    SaCompute.submit(recorded, "subject_prepare")
    return true


## What the picture is read from, each a texture and the rectangle of the
## canvas it covers: the merged picture once, or the active layer's chunks
## that reach into *region*.
func _sources(document: SaDocument, merged: SaTexture, region: Rect2) -> Array:
    var canvas := Vector2(document.canvas_size)
    if merged != null:
        return [[merged, Rect2(Vector2.ZERO, canvas)]]
    var out: Array = []
    var layer := document.active_layer
    if layer == null:
        return out
    var whole := Rect2(Vector2.ZERO, canvas).intersection(region)
    for grid_pos: Vector2i in layer.chunks:
        var colour := layer.get_field(grid_pos)
        var covers := Rect2(Vector2(SaSelection.chunk_rect(grid_pos).position), Vector2(SaChunk.SIZE, SaChunk.SIZE))
        if colour != null and covers.intersects(whole):
            out.append([colour, covers])
    return out


## The colour space's way to the display, as `subject_prepare` names it.
static func _colour_params(space: SaColorSpace) -> Dictionary:
    var used := space if space != null else SaColorSpace.srgb()
    var transfer := used.transfer if used.transfer != null else SaTransferFunction.srgb()
    var matrix := PackedFloat32Array()
    for column: Vector3 in SaColorSpace.basis_columns(used.to_linear_srgb_matrix()):
        matrix.append_array(PackedFloat32Array([column.x, column.y, column.z]))
    var curve := transfer.to_params()
    return {
        "display_passthrough": 1.0 if used.is_display_ready() else 0.0,
        "coordinates": float(used.coordinates),
        "to_linear_srgb": matrix,
        "transfer_slope": curve[0],
        "transfer_threshold": curve[1],
        "transfer_gain": curve[2],
        "transfer_exponent": curve[3],
    }


## Lays *mask*, which stands for *covers*, over every chunk *clip* touches,
## nought outside *clip*, and joins those chunks to the selection in *mode*.
## Runs inside the selection's change, so the two are one step.
func _merge(document: SaDocument, mask: SaCompute.Buffer, mode: int, clip: Rect2i, covers: Rect2i) -> int:
    var selection := document.selection
    var region: Dictionary = {}
    var recorded: Array[SaCompute.Recorded] = []
    _spread.set_storage("subject", mask.rid)
    var first := Vector2i(floori(float(clip.position.x) / SaChunk.SIZE), floori(float(clip.position.y) / SaChunk.SIZE))
    var last := Vector2i(ceili(float(clip.end.x) / SaChunk.SIZE), ceili(float(clip.end.y) / SaChunk.SIZE))
    for y: int in range(first.y, last.y):
        for x: int in range(first.x, last.x):
            var grid_pos := Vector2i(x, y)
            var chunk := selection.make_chunk()
            var texture := chunk.field(SaSelection.FIELD)
            var origin := SaSelection.chunk_rect(grid_pos).position
            _spread.set_image("mask", texture)
            (
                _spread
                . set_params(
                    {
                        "origin_x": origin.x,
                        "origin_y": origin.y,
                        "clip_x": clip.position.x,
                        "clip_y": clip.position.y,
                        "clip_width": clip.size.x,
                        "clip_height": clip.size.y,
                        "region_x": float(covers.position.x),
                        "region_y": float(covers.position.y),
                        "region_width": float(covers.size.x),
                        "region_height": float(covers.size.y),
                    }
                )
            )
            var one := _spread.record(
                "subject_spread",
                SaSelection.FORMAT,
                SaCompute.groups_for(texture.size.x),
                SaCompute.groups_for(texture.size.y),
                1,
                false
            )
            if one == null:
                error = "The kernel subject_spread could not be recorded."
                return 0
            recorded.append(one)
            region[grid_pos] = chunk
    SaCompute.submit(recorded, "subject_spread")
    selection.merge_region(region, mode)
    return region.size()


static func _groups(lanes: int) -> int:
    return ceili(float(lanes) / LANES)


func _blank_texture() -> SaTexture:
    if _blank == null:
        _blank = SaTexture.new(Vector2i(1, 1), PREPARE_FORMAT)
        _blank.clear(Color(0.0, 0.0, 0.0, 0.0))
    return _blank
