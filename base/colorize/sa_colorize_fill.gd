## A Colourise layer's flats worked out on the card: the window round the
## line art and the scribbles gathered, the gaps closed, the keys carried to
## every pixel by `colorize_fill.gmacs`, and each chunk of the layer's flats
## written from it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The window** is the bounding box of the grid positions the line art and
## the layer hold, so a fill costs what the drawing covers and never the canvas
## (hard rule 2). Its three images live for one fill and go with it, since a
## 4000 pixel drawing holds a quarter of a gibibyte in them.
##
## **The read back** is the sweeps' count of the lines they moved, four bytes
## after every [constant ROUNDS_PER_READ] rounds, read through
## `SaCompute.Buffer.read`, an update's read outside any stroke as the wand's
## flood reads its flags. The count only grows, so the fill is done when a read
## finds it where the last one left it, and no clear of the buffer has to be
## ordered against the sweeps.
extends RefCounted

const KERNELS := "colorize_fill"
## The field a Colourise layer keeps its flats in.
const FLATS: StringName = &"flats"
## The scribbles, the field a brush paints on the layer.
const KEYS: StringName = &"keys"
## Rounds of a sweep along the rows and one down the columns between two
## reads of the count.
const ROUNDS_PER_READ: int = 2
## A drawing that has not settled after this many rounds is a maze of
## corridors, and the fill stops rather than stall the frame.
const MAX_ROUNDS: int = 240
## Threads a sweep's workgroup holds, the kernels' own.
const SWEEP_GROUP: int = 64

## Rounds the last fill ran, and the window it ran over in document pixels.
var rounds: int = 0
var window: Rect2i = Rect2i()

var _compute: SaCompute = null
var _cost: SaTexture = null
var _dist: SaTexture = null
var _label: SaTexture = null
var _moved: SaCompute.Buffer = null
## Stand-ins bound where a pass reads no chunk or writes no flats.
var _blank: SaTexture = null
var _no_flats: SaTexture = null


## The flats of *layer* worked out from *line_art*'s chunks and the layer's own
## scribbles, closing gaps up to *gap* pixels across, *transparent* the
## Transparent key's colour. Answers the grid positions whose flats it wrote,
## every one of the window's, or none when there is no rendering device.
## Allocates a chunk of the layer wherever the window reaches one it lacks.
func fill(layer: SaLayer, line_art: SaLayer, gap: float, transparent: Color, tolerance: float) -> Array[Vector2i]:
    var written: Array[Vector2i] = []
    rounds = 0
    var grid := grid_of(layer, line_art)
    if grid.size == Vector2i.ZERO or not _ready(layer):
        return written
    var side := SaLayer.CHUNK_SIZE
    window = Rect2i(grid.position * side, grid.size * side)
    _make_images(window.size)
    var params: Dictionary[String, Variant] = {
        "window_origin": Vector2(window.position),
        "window_size": Vector2(window.size),
        "chunk_origin": Vector2.ZERO,
        "chunk_scale": 1.0,
        # A break of *gap* pixels has its middle (gap + 1) / 2 from either end.
        "radius": (gap + 1.0) * 0.5 if gap >= 1.0 else 0.0,
        "transparent": transparent,
        "tolerance": tolerance,
        "spare_a": 0.0,
        "spare_b": 0.0,
        "spare_c": 0.0,
    }
    var whole := Vector2i(SaCompute.groups_for(window.size.x), SaCompute.groups_for(window.size.y))
    _pass("colorize_clear", params, whole, _blank, _no_flats)
    if line_art != null:
        for grid_pos: Vector2i in line_art.chunks:
            _chunk_pass("colorize_lines", params, grid_pos, line_art.get_field(grid_pos))
    if params["radius"] >= 1.0:
        _pass("colorize_near_rows", params, whole, _blank, _no_flats)
    _pass("colorize_walls", params, whole, _blank, _no_flats)
    _pass("colorize_unreach", params, whole, _blank, _no_flats)
    for grid_pos: Vector2i in layer.chunks:
        _chunk_pass("colorize_keys", params, grid_pos, layer.get_field(grid_pos, KEYS))
    _sweep(params)
    for y in range(grid.position.y, grid.end.y):
        for x in range(grid.position.x, grid.end.x):
            var grid_pos := Vector2i(x, y)
            var flats := layer.get_or_create_chunk(grid_pos).field(FLATS)
            if flats == null:
                continue
            params["chunk_origin"] = Vector2(grid_pos * side)
            params["chunk_scale"] = float(flats.size.x) / float(side)
            var groups := Vector2i(SaCompute.groups_for(flats.size.x), SaCompute.groups_for(flats.size.y))
            var ink: SaTexture = line_art.get_field(grid_pos) if line_art != null else null
            if ink != null and ink.rid.is_valid():
                params["spare_a"] = float(ink.size.x) / float(side)
                _compute.use_storage_format(ink.format)
                _pass("colorize_write", params, groups, ink, flats)
            else:
                params["spare_a"] = 0.0
                _pass("colorize_write", params, groups, _blank, flats)
            written.append(grid_pos)
    _let_go()
    return written


## The grid positions the fill covers, as a rectangle of chunks: every one the
## line art or the layer holds, or none when neither holds any.
static func grid_of(layer: SaLayer, line_art: SaLayer) -> Rect2i:
    var held: Array[Vector2i] = []
    held.append_array(layer.chunks.keys())
    if line_art != null:
        held.append_array(line_art.chunks.keys())
    if held.is_empty():
        return Rect2i()
    var box := Rect2i(held[0], Vector2i.ONE)
    for grid_pos: Vector2i in held:
        box = box.merge(Rect2i(grid_pos, Vector2i.ONE))
    return box


## The kernels and the stand-ins, made the first time, the stand-in chunk at
## the depth *layer*'s scribbles are stored at.
func _ready(layer: SaLayer) -> bool:
    if GlobalShaderCompiler.get_rd() == null:
        return false
    var keys := SaFieldSpec.find(layer.schema, KEYS)
    var format := keys.format if keys != null else RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    if _compute == null:
        _compute = SaCompute.new(KERNELS)
        _no_flats = SaTexture.new(Vector2i.ONE, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
        var zeros := PackedByteArray()
        zeros.resize(16)
        _moved = SaCompute.Buffer.new(zeros)
    if _blank == null or _blank.format != format:
        _blank = SaTexture.new(Vector2i.ONE, format)
        _blank.clear(SaFieldSpec.NO_PAINT)
    _compute.use_storage_format(format)
    return true


func _make_images(size: Vector2i) -> void:
    _cost = SaTexture.new(size, RenderingDevice.DATA_FORMAT_R32_SFLOAT)
    _dist = SaTexture.new(size, RenderingDevice.DATA_FORMAT_R32_SFLOAT)
    _label = SaTexture.new(size, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)


## The window's images go, and the stand-ins stay for the next fill.
func _let_go() -> void:
    _cost = null
    _dist = null
    _label = null


## One pass of the chunk at *grid_pos* read from *source*, over the chunk's
## document pixels. A position the layer holds no texture at reads nothing.
func _chunk_pass(kernel: String, params: Dictionary[String, Variant], grid_pos: Vector2i, source: SaTexture) -> void:
    if source == null or not source.rid.is_valid():
        return
    var side := SaLayer.CHUNK_SIZE
    params["chunk_origin"] = Vector2(grid_pos * side)
    params["chunk_scale"] = float(source.size.x) / float(side)
    _compute.use_storage_format(source.format)
    var groups := SaCompute.groups_for(side)
    _pass(kernel, params, Vector2i(groups, groups), source, _no_flats)


## Rounds of the sweeps until a read of the count finds nothing moved.
func _sweep(params: Dictionary[String, Variant]) -> void:
    var rows := Vector2i(ceili(float(window.size.y) / SWEEP_GROUP), 1)
    var columns := Vector2i(ceili(float(window.size.x) / SWEEP_GROUP), 1)
    var before := _count()
    while rounds < MAX_ROUNDS:
        for i in ROUNDS_PER_READ:
            _pass("colorize_sweep_rows", params, rows, _blank, _no_flats)
            _pass("colorize_sweep_columns", params, columns, _blank, _no_flats)
            rounds += 1
        var now := _count()
        if now == before:
            return
        before = now


func _count() -> int:
    var bytes := _moved.read(0, 4)
    return bytes.decode_u32(0) if bytes.size() >= 4 else 0


func _pass(kernel: String, params: Dictionary[String, Variant], groups: Vector2i, source: SaTexture, flats: SaTexture) -> void:
    if source == _blank:
        _compute.use_storage_format(_blank.format)
    _compute.set_image("src", source)
    _compute.set_image("flats", flats)
    _compute.set_image("cost", _cost)
    _compute.set_image("dist", _dist)
    _compute.set_image("label", _label)
    _compute.set_storage("moved", _moved.rid)
    _compute.set_params(params)
    _compute.dispatch_kernel(kernel, groups.x, groups.y, 1)
