## The Magnetic Lasso's cost window: the links out of every cell of a square
## of the picture, weighed on the card by `magnetic_lasso.gmacs` and read back
## once, for the path's search to read.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A window is [constant SIDE] cells across, a cell [member cell] document
## pixels, so what it costs is the window's and never the canvas's. The tool
## asks for one each time the trace's last anchor moves, and the window stands
## round that anchor. The kernel's header says what each pass does.
##
## **The read back** is one buffer, twelve bytes a cell, after the six passes.
## A tool's read outside any stroke, the kind the wand's flood reads, through
## `SaCompute.Buffer.read`, which rule 1's list holds already.
extends RefCounted

## Cells along a side of the window. 256 is a reach of 128 cells round the
## anchor, more than the Width option looks and than a hand moves between two
## anchors at the Frequency's lowest, and a search over the whole of it is
## still a fraction of a second.
const SIDE: int = 256
## Bytes a cell has in what [method window] answers: the eight links, the
## cell's own cost, where across the cell the edge lies along x and along y,
## each 128 for the middle and 254 a cell, and one of padding.
const BYTES_PER_CELL: int = 12
## Taps a cell gathers along each axis at the most, so a window at a zoom of
## a tenth reads sixteen texels a cell and not a hundred.
const MAX_TAPS: int = 4

## Where the last window's cell (0, 0) sits in document pixels, and how many
## document pixels a cell spans.
var origin: Vector2 = Vector2.ZERO
var cell: float = 1.0

var _compute: SaCompute = null
var _picture: SaTexture = null
var _gradient: SaTexture = null
var _laplacian: SaTexture = null
var _local: SaTexture = null
var _nearest: SaTexture = null
var _costs: SaCompute.Buffer = null
## A transparent texel, bound as the source of every pass that reads none.
var _blank: SaTexture = null


## The links of the window whose cell (0, 0) is at *at* in document pixels,
## each cell *span* pixels across, read from *merged* when it is given, the
## merged output at document coordinates, and else from *layer*'s own chunks.
## *contrast* is the gradient, in Oklab units a pixel, below which a cell is no
## edge. Answers [constant BYTES_PER_CELL] bytes a cell, row after row, or
## nothing when there is no rendering device.
func window(space: SaColorSpace, at: Vector2, span: float, contrast: float, merged: SaTexture, layer: SaLayer) -> PackedByteArray:
    origin = at
    cell = maxf(span, 1.0)
    if not _ready():
        return PackedByteArray()
    var tail := space.to_push_constant() if space != null else SaColorSpace.srgb().to_push_constant()
    var groups := SaCompute.groups_for(SIDE)
    _bind(_blank)
    _run("magnetic_blank", Vector2.ZERO, 1.0, contrast, tail, groups)
    for source: Array in _sources(merged, layer):
        var texture: SaTexture = source[0]
        _bind(texture)
        _run("magnetic_gather", source[1], source[2], contrast, tail, groups)
    _bind(_blank)
    _run("magnetic_oklab", Vector2.ZERO, 1.0, contrast, tail, groups)
    _run("magnetic_features", Vector2.ZERO, 1.0, contrast, tail, groups)
    _run("magnetic_local", Vector2.ZERO, 1.0, contrast, tail, groups)
    _run("magnetic_links", Vector2.ZERO, 1.0, contrast, tail, groups)
    return _costs.read()


## The document pixel the middle of cell *at* stands on.
func to_document(at: Vector2i) -> Vector2:
    return origin + (Vector2(at) + Vector2(0.5, 0.5)) * cell


## The cell document pixel *at* falls in, which may lie outside the window.
func to_cell(at: Vector2) -> Vector2i:
    return Vector2i(((at - origin) / cell).floor())


## The sources the gather adds up, each the texture, where its texel (0, 0)
## sits in document pixels and its texels a document pixel: the merged picture
## alone, or every chunk of the layer the window reaches. A chunk stored at
## another resolution says so by its own size (hard rule 3).
func _sources(merged: SaTexture, layer: SaLayer) -> Array[Array]:
    var found: Array[Array] = []
    if merged != null:
        found.append([merged, Vector2.ZERO, 1.0])
        return found
    if layer == null:
        return found
    var reach := Rect2(origin, Vector2(SIDE, SIDE) * cell)
    var side := float(SaChunk.SIZE)
    var first := Vector2i((reach.position / side).floor())
    var last := Vector2i((reach.end / side).floor())
    for y in range(first.y, last.y + 1):
        for x in range(first.x, last.x + 1):
            var grid_pos := Vector2i(x, y)
            if not layer.chunks.has(grid_pos):
                continue
            var texture := layer.get_field(grid_pos)
            if texture == null or not texture.rid.is_valid():
                continue
            found.append([texture, Vector2(grid_pos) * side, float(texture.size.x) / side])
    return found


## Whether the kernel and its images are there, made the first time.
func _ready() -> bool:
    if _compute != null:
        return true
    if GlobalShaderCompiler.get_rd() == null:
        return false
    _compute = SaCompute.new("magnetic_lasso")
    var size := Vector2i(SIDE, SIDE)
    var format := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    _picture = SaTexture.new(size, format)
    _gradient = SaTexture.new(size, format)
    _laplacian = SaTexture.new(size, format)
    _local = SaTexture.new(size, format)
    _nearest = SaTexture.new(size, format)
    _blank = SaTexture.new(Vector2i.ONE, format)
    _blank.clear(Color(0.0, 0.0, 0.0, 0.0))
    var zeros := PackedByteArray()
    zeros.resize(SIDE * SIDE * BYTES_PER_CELL)
    _costs = SaCompute.Buffer.new(zeros)
    return true


## Binds the window's images and buffer, with *source* as the picture read.
func _bind(source: SaTexture) -> void:
    _compute.use_storage_format(source.format)
    _compute.set_image("src", source)
    _compute.set_image("picture", _picture)
    _compute.set_image("gradient", _gradient)
    _compute.set_image("laplacian", _laplacian)
    _compute.set_image("local", _local)
    _compute.set_image("nearest", _nearest)
    _compute.set_storage("costs", _costs.rid)


## One pass over the window, with the push constant the kernel's `params`
## block lays out: the window, the source, the side, then the colour space.
func _run(
    kernel: String, source_at: Vector2, source_scale: float, contrast: float, tail: PackedFloat32Array, groups: int
) -> void:
    var push := PackedFloat32Array([origin.x, origin.y, cell, contrast, source_at.x, source_at.y, source_scale, float(SIDE)])
    push.append_array(tail)
    _compute.set_push_constant_float_array(push)
    _compute.dispatch_kernel(kernel, groups, groups, 1)
