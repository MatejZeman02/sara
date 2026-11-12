## The histogram of what a record attached to a node filters: the door call an
## attached Levels, or a Levels adjustment layer, equalizes from.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The input is `SaNodeInput`'s, one chunk position at a time, and the counts
## are binned by the Graph docker's own `graph_bin` kernel, pushed the
## parameters `SaGraphParams` packs for the plot as well, so the counts are the
## Levels graph's bin for bin. It is one binner reached from core, not a second
## one: the plot keeps its picture, its modes and its draw, and this class
## keeps only a buffer of counts. A module asks for a result and the skeleton
## keeps the walk and the dispatch it owns.
##
## The kernels declare the picture the draw kernel writes, and the clear and
## the bin ask its size for the waveform's live grid, which a histogram never
## reaches. So a picture one texel across stands in for it, and nothing draws
## into it.
##
## One readback of counts per call and never a texel, so the canvas stays in
## VRAM, and every dispatch covers one chunk. It is made for a press
## and never runs in a frame, and what it holds dies with the instance.
class_name SaNodeHistogram
extends RefCounted

const SHADER_NAME := "graph"

## The format of the picture the kernels declare, the plot's own.
const FORMAT := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT

var _document: SaDocument = null
var _compute: SaCompute = null
var _counts: SaCompute.Buffer = null
## The kernel's `shown` map, which sends every point to the screen.
var _shown := SaCompute.Buffer.new(PackedFloat32Array(SaGraphPlot.EVERY_POINT_SHOWN).to_byte_array())
var _stand_in: SaTexture = null


## A histogram of *document*'s nodes.
func _init(document: SaDocument) -> void:
    _document = document


## The node *record* hangs on and whether it hangs there at all, as
## `[found, node]`, the node null for the document's root.
static func node_of(document: SaDocument, record: SaAttachedFilter) -> Array:
    return SaNodeInput.node_of(document, record)


## The count buffer of *node*'s input binned for *channel*, laid out as the
## plot's `read_counts` answers it, and empty when the node holds nothing to
## bin. *node* null is the root. *channel* is a key of `SaGraphParams.ROW_FLAGS`.
func counts(node: SaLayer, channel: String) -> PackedInt32Array:
    if _document == null or not _ensure_resources():
        return PackedInt32Array()
    var input := SaNodeInput.new(_document, node)
    var space := _document.color_space
    var flag_word := SaGraphParams.flags(space, true, channel)
    var mode := SaGraphParams.MODE_HISTOGRAM
    var cleared := false
    for grid_pos: Vector2i in input.positions():
        # The input answers every position in the same scratch, so each is
        # binned before the next is read, a dispatch a position rather than one
        # list: a list may not stay open across the composite.
        var source: SaTexture = input.at(grid_pos)
        if source == null or not source.rid.is_valid():
            continue
        var edge := source.size.x
        _compute.use_storage_format(FORMAT)
        _compute.set_texture(0, _stand_in.rid)
        _compute.set_sampled_texture(1, source.rid, RenderingDevice.SAMPLER_FILTER_NEAREST)
        _compute.set_buffer(2, _counts.rid)
        _compute.set_buffer(3, _shown.rid)
        var params := SaGraphParams.pack_square(edge, space, mode, 1.0, flag_word, SaGraphParams.NO_CLOUD)
        _compute.set_push_constant_float_array(params)
        if not cleared:
            _compute.dispatch_kernel("graph_clear", int(ceil(float(SaGraphParams.LIVE_SLOT) / 64.0)), 1, 1)
            cleared = true
        _compute.dispatch_kernel("graph_bin", SaCompute.groups_for(edge), SaCompute.groups_for(edge), 1)
    if not cleared:
        return PackedInt32Array()
    return _counts.read().to_int32_array().slice(0, SaGraphParams.LIVE_SLOT)


func _ensure_resources() -> bool:
    if _compute == null and not GlobalShaderCompiler.get_kernel_names(SHADER_NAME).is_empty():
        _compute = SaCompute.new(SHADER_NAME)
    if _compute == null:
        return false
    if _counts == null:
        var zeros := PackedInt32Array()
        zeros.resize(SaGraphParams.LIVE_SLOT)
        _counts = SaCompute.Buffer.new(zeros.to_byte_array())
        if not _counts.rid.is_valid():
            _counts = null
            return false
    if _stand_in == null:
        _stand_in = SaTexture.new(Vector2i.ONE, FORMAT)
        if not _stand_in.rid.is_valid():
            _stand_in = null
            return false
    return true
