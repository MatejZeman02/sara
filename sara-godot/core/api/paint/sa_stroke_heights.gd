## The heights one stroke moves, the surface beneath its layer, and the
## height a dab binds.
##
## Paint mixes with the relief under it rather than building on it: the surface
## a texel shows moves towards the brush's own height, `sa_height_mixed` in the
## door's `height_deposit` library. There is no ceiling and nothing the stroke
## started from, so this keeps no copy of the layer's height for a deposit. A
## stroke crossing itself reads its own paint as it stands. An engine makes one of
## these when its stroke begins and lets it go at the pen's lift.
##
## The surface a texel stands on is `beneath` plus the layer's own height, which
## is signed, so a stroke that levels a lower layer's bump writes a negative
## height over it and the lower layer keeps its own. GPU to GPU throughout, and
## the eraser's copy is a `texture_copy` rather than a dispatch, so nothing here
## reads the canvas back.
class_name SaStrokeHeights
extends RefCounted

var _document: SaDocument
## The layer whose paint the stroke thickens, the active layer as the stroke
## began.
var _layer: SaLayer
## Grid position -> the chunk's height as a wash eraser's stroke first
## lowered it, what `lower_under` measures every lowering from.
var _found: Dictionary[Vector2i, SaTexture] = {}
## Whether `reach` has asked for the layer's height yet, which it does once.
var _asked: bool = false
## Grid position -> the surface beneath the layer there, summed on the
## stroke's first ask.
var _beneath: Dictionary[Vector2i, SaTexture] = {}
## Grid position -> the paint beneath the layer there, its colour and its
## height, or nothing, taken on the stroke's first ask.
var _paint_beneath: Dictionary[Vector2i, Array] = {}
## What sums it, made on the first ask, which holds the kernels.
var _relief: SaRelief = null
## The kernel `lower_under` dispatches, made on its first call.
var _lowering: SaCompute = null
## One texel at the height's format, what `held` answers where there is none.
## Static, so a kernel bound to it by a suite or an engine keeps it alive
## without holding this object, the way the smudge carry's stand-in is.
static var _none: SaTexture = null


func _init(document: SaDocument, layer: SaLayer) -> void:
    _document = document
    _layer = layer


## The layer's height in the chunk at *grid_pos*, for a dab about to write it,
## or null when the layer cannot carry one: a group, a generated layer, or no
## layer at all. A writer calls it once a dab per target, before the dispatch,
## and it is cheap after the chunk's first touch. The first call asks for the
## layer's height through `SaHeightOps.gain`, so a layer gains the field on the
## first height-writing dab that lands on it and never before. Every call
## snapshots the chunk for undo before the dab writes, because a buffered stroke
## leaves the layer's colour alone until the commit and its height would
## otherwise reach the commit's snapshot already changed.
func reach(grid_pos: Vector2i) -> SaTexture:
    if _layer == null or _document == null:
        return null
    if not _asked:
        _asked = true
        SaHeightOps.new(_document).gain(_layer)
    if not _layer.carries_height():
        return null
    if _document.stroke_transaction != null:
        _document.stroke_transaction.capture_before(_layer, grid_pos)
    return _layer.get_or_create_field(grid_pos, SaFieldSpec.HEIGHT)


## The surface beneath the layer over the chunk at *grid_pos*, every layer
## below it that shows and the grounds' tooth, summed on the stroke's first
## ask there and the same texture on every ask after it, since nothing below
## changes while the stroke paints. Null with no layer or document, or with no
## rendering device.
func beneath(grid_pos: Vector2i) -> SaTexture:
    if _layer == null or _document == null:
        return null
    if not _beneath.has(grid_pos):
        if _relief == null:
            _relief = SaRelief.new()
        var surface := _relief.beneath(_document, _layer, grid_pos)
        if surface == null:
            return null
        _beneath[grid_pos] = surface
    return _beneath[grid_pos]


## The paint beneath the layer over the chunk at *grid_pos*, its colour and
## its height, or nothing where no paint below has a height there,
## `SaRelief.paint_beneath`. Taken on the stroke's first ask there and the
## same pair on every ask after it, since nothing below the layer changes
## while the stroke paints, as `beneath` is. The paint layers below are
## composited with the Background and the grounds left out, and their own height
## weighs the colour.
func paint_beneath(grid_pos: Vector2i) -> Array[SaTexture]:
    var found: Array[SaTexture] = []
    if _layer == null or _document == null:
        return found
    if not _paint_beneath.has(grid_pos):
        if _relief == null:
            _relief = SaRelief.new()
        _paint_beneath[grid_pos] = _relief.paint_beneath(_document, _layer, grid_pos)
    found.assign(_paint_beneath[grid_pos])
    return found


## The height *chunk* holds, for a dab that lowers it, or the stand-in where
## it holds none, a one texel texture a kernel knows by its size and never
## writes. Never allocates, because lowering nothing leaves nothing, and static
## because it keeps no stroke's state.
static func held(chunk: SaChunk) -> SaTexture:
    if chunk != null and chunk.has_field(SaFieldSpec.HEIGHT):
        return chunk.field(SaFieldSpec.HEIGHT)
    if _none == null:
        _none = SaTexture.new(Vector2i(1, 1), SaFieldSpec.HEIGHT_FORMAT)
        _none.clear(Color(0.0, 0.0, 0.0, 0.0))
    return _none


## Lowers the layer's height under a wash eraser's stroke so far. The stroke
## gathers coverage in the buffer and carves the layer's alpha once at the pen's
## lift, so the relief would otherwise stand at full height under the pen until
## then and drop at the lift. The document runs this over each region the dabs
## land on and once more at the commit, with no document of its own since
## lowering never gains a layer its height. The rule is a build-up eraser's,
## `sa_height_towards` with a target of nought and the eraser's strength as the
## rate, run by `height.gmacs`. The buffer's coverage only grows within a
## stroke, so a texel lowered twice would land past where once leaves it, which
## is why the eraser keeps the one copy this object takes of each chunk's height
## as it first reached it. A negative height rises to nought the same way and
## never past it.
##
## Lowers by the
## coverage *buffer* holds and the eraser's *opacity*, over each chunk-local
## region of *regions*, in document pixels, or in the chunk's texels when
## *in_texels*. *capture* snapshots a layer's chunk for undo, given the layer
## and the grid position, the stroke transaction's `capture_before`. Each texel
## moves from the height the stroke found there towards nought, from above or
## below, and never back away from it, so a region lowered again stays where the
## coverage puts it. A chunk with no height has nothing to lower and is left
## without one, and the first touch of a chunk snapshots it for undo, as
## `reach` does.
func lower_under(buffer: SaLayer, regions: Dictionary, opacity: float, capture: Callable, in_texels: bool = false) -> void:
    if _layer == null or not _layer.carries_height() or GlobalShaderCompiler.get_rd() == null:
        return
    for grid_pos: Vector2i in regions:
        var height := _layer.get_field(grid_pos, SaFieldSpec.HEIGHT)
        var painted: SaChunk = buffer.chunks.get(grid_pos, null)
        var region: Rect2i = regions[grid_pos]
        if height == null or painted == null or region.size.x <= 0 or region.size.y <= 0:
            continue
        if not in_texels:
            var scale := maxf(painted.resolution_scale, 1.0)
            region = Rect2i(Vector2i(Vector2(region.position) * scale), Vector2i((Vector2(region.size) * scale).ceil()))
        if capture.is_valid():
            capture.call(_layer, grid_pos)
        if not _found.has(grid_pos):
            _found[grid_pos] = _copy_of(height)
        if _lowering == null:
            _lowering = SaCompute.new("height")
        var paint := painted.albedo()
        _lowering.use_storage_format(height.format)
        _lowering.use_binding_format(2, paint.format)
        _lowering.set_texture(0, height.rid)
        _lowering.set_texture(1, _found[grid_pos].rid)
        _lowering.set_texture(2, paint.rid)
        _lowering.set_push_constant_float_array(PackedFloat32Array([opacity, 0.0, region.position.x, region.position.y]))
        _lowering.dispatch_kernel("height_erased", SaCompute.groups_for(region.size.x), SaCompute.groups_for(region.size.y), 1)


func _copy_of(height: SaTexture) -> SaTexture:
    var copy := SaTexture.new(height.size, height.format)
    var rd := GlobalShaderCompiler.get_rd()
    if rd != null:
        rd.texture_copy(height.rid, copy.rid, Vector3.ZERO, Vector3.ZERO, Vector3(height.size.x, height.size.y, 1), 0, 0, 0, 0)
    return copy
