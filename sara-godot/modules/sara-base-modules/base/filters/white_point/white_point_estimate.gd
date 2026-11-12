## What White Point's Auto finds the cast by: sums of what the filter reads,
## taken chunk by chunk on the GPU, and the colour they say should be neutral.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Two guesses at the light a picture was taken under, the two darktable's
## colour calibration makes from the picture itself. **From surfaces** is a
## weighted grey world: the colours of the scene are taken to average to grey,
## each texel counted at a luminance of one, so a surface weighs by its area
## and not by how much light it sends back. **From edges** is a grey edge of the
## first order: the steps between neighbouring texels are taken to average to
## grey, so a wall of one colour weighs only along its edges and a picture
## mostly of one colour can still be read. Both are summed in light-linear sRGB,
## the space `picked` is kept in, and both answer at the mean luminance of the
## texels counted, so the swatch shows a colour as bright as the picture.
##
## A texel that holds no paint, is darker than [constant DARKEST] or reaches
## [constant BRIGHTEST] in a channel is left out of both sums, so a black
## background or a blown sky does not steer the guess. A step counts only
## between two counted texels.
##
## The input is `SaNodeInput`'s, one chunk at a time, and
## `white_point_estimate.gmacs` beside this file folds each chunk into one
## record of eight floats at the chunk's own slot. The records are read back
## once, after the last chunk, and added here in double precision. That is one
## read back of sums a press and never a texel, so hard rule 1 holds as it does
## for `SaNodeHistogram`, and every dispatch covers one chunk, so hard rule 2
## does. It is made for a press, never runs in a frame, and what it holds dies
## with the instance.
class_name SaWhitePointEstimate
extends RefCounted

## The ways a guess is made, in the order the panel's choice lists them.
enum From { SURFACES, EDGES }

## The shader file, by the key the shader index files it under.
const SHADER := "sara-base-modules/white_point_estimate"
const KERNEL := "white_point_estimate"
## The floats of one chunk's record, as the kernel lays them out: the surfaces
## and their weight, then the edges and the weighted luminance.
const RECORD := 8
## How many floats the push constant holds, 80 bytes.
const PUSH_FLOATS := 20
## The least luminance a counted texel has, CIE Y with white at one. Below it a
## colour is mostly noise, and a black background is all of it.
const DARKEST := 0.01
## The level no channel of a counted texel reaches, in the document's own
## linear RGB with white at one. A channel that high has most likely been
## clipped, and a clipped colour is not the colour of the light.
const BRIGHTEST := 0.98

const NONE := Vector3(NAN, NAN, NAN)

var _document: SaDocument = null
var _compute: SaCompute = null
var _records: SaCompute.Buffer = null


## The estimates of *document*'s nodes.
func _init(document: SaDocument) -> void:
    _document = document


## The colour *node* of *document* says should be neutral, guessed the way
## *from* names, as light-linear sRGB, or NAN in every channel when nothing
## there can be counted. *node* null is the document's root.
static func neutral(document: SaDocument, node: SaLayer, from: From) -> Vector3:
    return neutral_of(SaWhitePointEstimate.new(document).sums(node), from)


## The eight sums of *node*'s input, every chunk's record added up, all nought
## when nothing was read.
func sums(node: SaLayer) -> PackedFloat64Array:
    var total := PackedFloat64Array()
    total.resize(RECORD)
    total.fill(0.0)
    if _document == null:
        return total
    var input := SaNodeInput.new(_document, node)
    var places := input.positions()
    if places.is_empty() or not _ensure_resources(places.size()):
        return total
    var space := _document.color_space
    var read_any := false
    for slot in places.size():
        # The input answers every place in the same scratch, so each chunk is
        # dispatched before the next one is read, as SaNodeHistogram does.
        var source: SaTexture = input.at(places[slot])
        if source == null or not source.rid.is_valid():
            continue
        _compute.set_sampler("source", source.rid, RenderingDevice.SAMPLER_FILTER_NEAREST)
        _compute.set_storage("records", _records.rid)
        _compute.set_push_constant_float_array(push_for(space, source.size.x, slot))
        _compute.dispatch_kernel(KERNEL, 1, 1, 1)
        read_any = true
    if not read_any:
        return total
    var records := _records.read().to_float32_array()
    for slot in places.size():
        for at in RECORD:
            total[at] += records[slot * RECORD + at]
    return total


## The colour *totals* say should be neutral, guessed the way *from* names, at
## the mean luminance of the texels counted. NAN in every channel when no
## texel was counted, or for edges when no step was.
static func neutral_of(totals: PackedFloat64Array, from: From) -> Vector3:
    if totals.size() < RECORD or not (totals[3] > 0.0):
        return NONE
    var mean_luminance := totals[7] / totals[3]
    var guess := Vector3(totals[0], totals[1], totals[2]) / totals[3]
    if from == From.EDGES:
        var steps := Vector3(totals[4], totals[5], totals[6])
        var luminance := SaWhitePointFilter.luminance(steps)
        if not (luminance > 0.0):
            return NONE
        guess = steps / luminance
    var found := guess * mean_luminance
    return found if found.is_finite() else NONE


## The 80-byte push constant `white_point_estimate.gmacs` reads for a chunk
## *edge* texels across written at record *slot* on a document in *space*: the
## coordinate system, the edge, the slot and a spare, the matrix to linear
## sRGB by column, the document's curve, the two thresholds and a spare.
static func push_for(space: SaColorSpace, edge: int, slot: int) -> PackedFloat32Array:
    var held := space if space != null else SaColorSpace.srgb()
    var oklab := held.coordinates == SaColorSpace.Coordinates.OKLAB
    var push := PackedFloat32Array([float(held.coordinates), float(edge), float(slot), 0.0])
    var to_srgb := Basis.IDENTITY if oklab else held.to_linear_srgb_matrix()
    for column: Vector3 in SaColorSpaceGlsl.basis_columns(to_srgb):
        push.append_array(PackedFloat32Array([column.x, column.y, column.z]))
    var curve := held.transfer if held.transfer != null and not oklab else SaTransferFunction.linear()
    push.append_array(curve.to_params())
    push.append_array(PackedFloat32Array([DARKEST, BRIGHTEST, 0.0]))
    assert(push.size() == PUSH_FLOATS, "the white point estimate's push constant is the wrong size")
    return push


## The kernel and a record for each of *chunks* chunks, every one nought, so a
## chunk that turns out to hold nothing adds nothing.
func _ensure_resources(chunks: int) -> bool:
    if GlobalShaderCompiler.get_rd() == null or GlobalShaderCompiler.get_kernel_names(SHADER).is_empty():
        return false
    if _compute == null:
        _compute = SaCompute.new(SHADER)
    var zeros := PackedFloat32Array()
    zeros.resize(chunks * RECORD)
    zeros.fill(0.0)
    _records = SaCompute.Buffer.new(zeros.to_byte_array())
    return _records.rid.is_valid()
