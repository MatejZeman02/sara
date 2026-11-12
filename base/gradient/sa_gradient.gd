## The gradient tool's pass: a ramp from the foreground colour to the
## background one, across a layer, through the selection.
##
## The shape is the adjustments pass's, one step further: snapshot every chunk
## the ramp will reach, dispatch `gradient.gmacs` over each, and record the
## snapshots as one history step, so an undo puts the chunks back whole. Where
## it differs is that a ramp lands on the whole canvas rather than on the
## chunks a layer already has, so the grid is allocated the way a fill
## allocates it and the positions that were absent are recorded as absent.
##
## A ramp covers everything the selection reaches, which is the one shape hard
## rule 2, dirty-rect dispatch, cannot narrow: there is no dirty rect smaller than the region the
## painter asked to be filled. What the rule still buys is the selection, which
## keeps a ramp under a small marquee to the chunks that marquee touches.
##
## The colour walk is Oklab, so the middle of a red to blue ramp is the
## perceptual middle. The ramp is converted here, once per change of a stop
## rather than once per pixel, into a 1024-texel lookup the kernel samples, and
## the kernel only converts back out. The ends are an `SaColorRamp`, which is any
## number of stops with an alpha each, and the texture is what carries them:
## the push constant is already at the 128 bytes Vulkan guarantees, and the
## reasoning is written out in `gradient.gmacs`, beside this file in the
## gradient's own folder.
##
## In the base module beside the gradient tool, because the pass serves that
## tool alone and nothing in the skeleton. It carries a global class name, the
## way the stamp brush's engines carry theirs.
class_name SaGradient
extends RefCounted

## Which way the ramp runs from the press.
enum Shape { LINEAR = 0, RADIAL = 1 }

## What happens past the release point, and how the ramp is read on the way
## there. Must match the constants in `gradient.gmacs`.
##
## `NONE` holds the far colour, `MIRROR` runs the ramp out and back, `REPEAT`
## starts it again with a hard edge where the far colour meets the near one, and
## `STEPS` cuts it into bands rather than blending, which is the posterised look
## a hard-edged gradient wants. `STEPS` is the one that is not a tiling, and it
## is here rather than in an option of its own because a painter picks one of
## these four and never two.
enum Repeat { NONE = 0, MIRROR = 1, REPEAT = 2, STEPS = 3 }

## How far the ramp is pushed off its own axis before the repeat runs, and by
## what. Must match the constants in `gradient.gmacs`.
##
## `NOISE` is three octaves of value noise, which
## reads as a soft ripple, and `VORONOI` is the distance to the nearest of a
## jittered lattice, which reads as cells. Both live in
## `shaders/compute/libs/noise.gmacs` so the brush tip engine can call them.
enum Wobble { NONE = 0, NOISE = 1, VORONOI = 2 }

## The fewest bands `Repeat.STEPS` will cut a ramp into. One band is a fill and
## two is the fewest that is still a gradient.
const MIN_STEPS: int = 2

## The history step a finished drag leaves behind.
const ACTION_NAME := "Gradient"

## Where the ramp lookup binds, after the canvas at 0 and the selection at 1.
const RAMP_BINDING: int = 2

## The format the ramp lookup is kept in. Full floats, because Oklab L is
## around 1 while a and b are hundredths, and because the ramp is written once
## per dispatch run rather than per pixel so its size buys nothing.
const RAMP_FORMAT := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

var _document: SaDocument
var _compute: SaCompute = null
## The lookup the kernel samples, rebuilt whenever the ramp it was built from
## has changed. One texture for the life of the pass: 16 KB, and rebuilding it
## per dispatch would upload it once per chunk.
var _ramp_texture: SaTexture = null
## What [member _ramp_texture] was last built from, the stops as
## `SaColorRamp.to_array` writes them and the document's way into linear sRGB,
## so a drag that moves no stop builds no texels.
var _ramp_key: Array = []
## The stroke-layer positions the last preview wrote to, so the drag can take
## its ramp back off the canvas without walking the whole grid.
var _previewed: Array[Vector2i] = []
## What the last [method apply] overwrote, the very dictionary its history step
## holds: the chunk that was at each position, or null where there was none.
## [method take_back] and [method relay] put it back, which is sound exactly
## while that step is the one the document stands on, because the undo is what
## swaps these chunks into the layer. The tool lets the ramp's ends go the
## moment the history moves, so it never asks after that.
var snapshot: Dictionary = {}
## Whether [method take_back] has put [member snapshot] back since the ramp was
## last laid, so [method relay] does not put it back a second time.
var _taken_back: bool = false


func _init(document: SaDocument) -> void:
    _document = document


## Paints the ramp into the stroke buffer, where the compositor shows it over
## the active layer without touching it. Called on every motion of the drag.
##
## The preview always replaces rather than composites, because the stroke
## chunk it writes into already holds the previous frame's ramp and an over
## onto that would stack a translucent ramp on itself as the pointer moves.
## The compositor then puts the stroke layer over the painting, which is the
## over the painter asked for.
func preview(from: Vector2, to: Vector2, ramp: SaColorRamp, shape: int, repeat: int, wobble: Dictionary = {}) -> void:
    var layer := _document.stroke_layer if _document != null else null
    if layer == null:
        return
    previews += 1
    _previewed = _dispatch_over(layer, from, to, ramp, shape, repeat, true, false, wobble)
    if not _previewed.is_empty():
        _document.invalidate_chunks(_previewed)


## How many previews this pass has dispatched: a reading for the test that
## proves a drag dispatches one a frame and not one a motion event.
var previews: int = 0


## Drops the preview, on a release or on a cancelled drag.
func clear_preview() -> void:
    if _document == null or _document.stroke_layer == null or _previewed.is_empty():
        return
    var was := _previewed.duplicate()
    _document.stroke_layer.chunks.clear()
    _previewed.clear()
    _document.invalidate_chunks(was)


## Lays the ramp into *layer* as one undoable step. True when anything landed.
##
## *ramp* runs from the press to the release, its stops in the colours a picker
## shows. *replace* writes the ramp over what is there alpha and all, rather
## than compositing it.
func apply(
    layer: SaLayer, from: Vector2, to: Vector2, ramp: SaColorRamp, shape: int, repeat: int, replace: bool, wobble: Dictionary = {}
) -> bool:
    if _document == null or layer == null or layer.refuses_paint():
        return false

    var before := _snapshot_of(layer)
    var alpha_locked: bool = ("alpha_locked" in layer) and layer.alpha_locked
    var touched := _dispatch_over(layer, from, to, ramp, shape, repeat, replace, alpha_locked, wobble)
    if touched.is_empty():
        return false

    _document.record_pixel_step(ACTION_NAME, layer, before)
    snapshot = before
    _taken_back = false
    _document.invalidate_chunks(before.keys())
    _document.modified = true
    _document.document_changed.emit()
    return true


## Takes the last apply's ramp back off *layer* and leaves its step standing,
## for a drag on one of its ends: the preview stands in for it until
## [method relay] lays it again.
##
## A copy of each kept chunk goes in rather than the kept chunk itself, because
## the kept one is the history's and an undo swaps it into the layer later. A
## position that held nothing is emptied again.
func take_back(layer: SaLayer) -> void:
    if _taken_back or layer == null or snapshot.is_empty():
        return
    for grid_pos: Vector2i in snapshot:
        var kept: SaChunk = snapshot[grid_pos]
        layer.set_chunk(grid_pos, kept.duplicate_chunk() if kept != null else null)
    _taken_back = true
    _document.invalidate_chunks(snapshot.keys())


## Lays the ramp again over the step the last [method apply] wrote, with no
## step of its own: the chunks go back to [member snapshot] and the ramp is
## dispatched over them, so an undo still takes the layer back to what it held
## before the first drag. What a moved end or a changed option comes to. True
## when anything landed.
func relay(
    layer: SaLayer, from: Vector2, to: Vector2, ramp: SaColorRamp, shape: int, repeat: int, replace: bool, wobble: Dictionary = {}
) -> bool:
    if _document == null or layer == null or snapshot.is_empty() or layer.refuses_paint():
        return false
    take_back(layer)
    var alpha_locked: bool = ("alpha_locked" in layer) and layer.alpha_locked
    var touched := _dispatch_over(layer, from, to, ramp, shape, repeat, replace, alpha_locked, wobble)
    _taken_back = false
    _document.invalidate_chunks(snapshot.keys())
    _document.modified = true
    _document.document_changed.emit()
    return not touched.is_empty()


## What the ramp is about to overwrite, as the swap `SaHistory` exchanges: the
## chunk that was at each position the dispatch will stop at, or null where the
## layer had none, so an undo puts a tile back or takes an allocated one away
## again. The same bookkeeping `SaDocument.fill_layer` does.
##
## **The walk's region and not the layer's keys**. Duplicating every chunk the
## layer has and adding the absent positions beside them would charge the
## history a whole layer for a ramp the size of a postage stamp: a gradient
## under a small marquee reaches the marquee's chunks and nothing else, and a
## layer painted past the canvas edge carries chunks the ramp can never touch.
## The region here is the one `_dispatch_over` walks, `positions_in` over the
## canvas filtered by the selection, so the snapshot and the write cover the
## same ground by construction rather than by two rules that have to agree.
##
## A position the walk then declines is recorded as absent and stays absent,
## which round-trips: the swap reads null, removes nothing and writes null back.
func _snapshot_of(layer: SaLayer) -> Dictionary:
    var before: Dictionary = {}
    for grid_pos: Vector2i in SaChunkWalk.positions_in(Rect2i(Vector2i.ZERO, _document.canvas_size)):
        if _document.selection.texture_for(grid_pos) == null:
            continue
        before[grid_pos] = layer.duplicate_chunk(grid_pos)
    return before


## Runs the kernel over every chunk of *layer* the selection reaches, creating
## the ones that are missing. Returns the positions written.
func _dispatch_over(
    layer: SaLayer,
    from: Vector2,
    to: Vector2,
    ramp: SaColorRamp,
    shape: int,
    repeat: int,
    replace: bool,
    alpha_locked: bool,
    wobble: Dictionary
) -> Array[Vector2i]:
    var touched: Array[Vector2i] = []
    var compute := _get_compute()
    if compute == null:
        return touched
    var lookup := _lookup_for(ramp, _document.color_space)
    if lookup == null:
        return touched
    var tail := _space_tail(_document.color_space)
    var flags := PackedFloat32Array(
        [
            1.0 if shape == Shape.RADIAL else 0.0,
            float(repeat),
            1.0 if replace else 0.0,
            1.0 if alpha_locked else 0.0,
        ]
    )
    # The band count, the wobble's kind and how far it pushes, and one spare
    # float. A dictionary rather than three arguments because two of the three
    # are meaningless without the first and a caller that wants none of them
    # passes nothing.
    var extra := PackedFloat32Array(
        [
            float(maxi(int(wobble.get("steps", 5)), MIN_STEPS)),
            float(wobble.get("kind", Wobble.NONE)),
            clampf(float(wobble.get("amount", 0.0)), 0.0, 1.0),
            0.0,
        ]
    )
    # The drag arrives in each chunk's own texels rather than the document's,
    # which is what gradient.gmacs takes and why the push constant is built per
    # stop rather than once. A layer at 2.0 has two texels a document pixel, so
    # the drag is scaled by the layer's scale after the chunk's origin is taken
    # off.
    var texels := layer.resolution_scale
    var per_chunk := func(grid_pos: Vector2i, _local: Rect2i, _start: Vector2i) -> PackedFloat32Array:
        var origin := Vector2(grid_pos * SaLayer.CHUNK_SIZE)
        var start := (from - origin) * texels
        var end := (to - origin) * texels
        var push := PackedFloat32Array([start.x, start.y, end.x, end.y])
        push.append_array(flags)
        push.append_array(extra)
        push.append_array(tail)
        return push
    # A ramp lands edge to edge, so the walk allocates what the selection
    # reaches. It asks for a chunk only where there is a mask, which is what
    # keeps a ramp under a small marquee from allocating the whole canvas. One
    # list for every chunk, because each stop writes its own chunk and reads
    # the ramp and the selection, which nothing in the walk writes.
    var walk := SaChunkWalk.new(compute, _document.selection, layer, &"", {}, true)
    return walk.run(
        "gradient",
        Rect2i(Vector2i.ZERO, _document.canvas_size),
        layer.get_or_create_chunk,
        per_chunk,
        {RAMP_BINDING: SaChunkWalk.Sampled.new(lookup)}
    )


## The lookup for *ramp*, uploaded to VRAM. Null when there is no ramp or no
## rendering device, which is what stops the dispatch above.
##
## Rebuilt only when the stops or the document's gamut differ from the last
## build, compared by value. `to_oklab_texels` is 1024 texels of two Oklab
## conversions each in GDScript, which measured 25 ms on the laptop, once per
## move of a drag and once more on the release, for a ramp no move changes.
## The comparison reads the stops rather than a dirty flag,
## because a control edits the ramp in place and nothing tells the pass.
##
## *space* is the document's, because a stop's colour was picked in its gamut
## and a ramp read as sRGB would start a P3 document's gradient at a duller red
## than the fill beside it.
func _lookup_for(ramp: SaColorRamp, space: SaColorSpace) -> SaTexture:
    if ramp == null or GlobalShaderCompiler.get_rd() == null:
        return null
    if _ramp_texture == null:
        _ramp_texture = SaTexture.new(Vector2i(SaColorRamp.TEXELS, 1), RAMP_FORMAT)
        _ramp_key = []
    if not _ramp_texture.rid.is_valid():
        _ramp_texture = null
        return null
    var key: Array = [ramp.to_array(), null]
    if space != null:
        key[1] = space.to_linear_srgb_matrix()
    if key == _ramp_key:
        return _ramp_texture
    var texels := ramp.to_oklab_texels(SaColorRamp.TEXELS, space)
    GlobalShaderCompiler.get_rd().texture_update(_ramp_texture.rid, 0, texels.to_byte_array())
    _ramp_key = key
    return _ramp_texture


## Half of `SaColorSpace.to_push_constant`: the matrix and the curve that take
## linear sRGB into the document, and the coordinate system.
##
## The other half, the way back in, is what the kernel never needs: a ramp
## writes colour and never reads one. There is room for it now that the two
## ends have left for the lookup texture, and it stays out because sending a
## matrix nothing multiplies by is not an improvement.
static func _space_tail(space: SaColorSpace) -> PackedFloat32Array:
    var used := space if space != null else SaColorSpace.srgb()
    var packed := PackedFloat32Array()
    for column: Vector3 in SaColorSpace.basis_columns(used.from_linear_srgb_matrix()):
        packed.append(column.x)
        packed.append(column.y)
        packed.append(column.z)
    packed.append_array(used.transfer.to_params())
    packed.append(float(used.coordinates))
    packed.append(0.0)
    packed.append(0.0)
    return packed


## Builds the kernel at the depth of the document this pass paints, and points
## the pass's own pipelines at it, so the first move of a drag finds both.
##
## **The cost is the compile, not the pipeline**, as it is for
## the brush. A kernel is built once per storage format, and the pass makes its
## `SaCompute` at F32, so the first move on an F16 document built `gradient` at
## F16 there and then, about 25 ms of that frame.
func warm() -> void:
    var compute := _get_compute()
    if compute == null or _document == null or _document.color_space == null:
        return
    compute.use_storage_format(_document.color_space.texel_format())


## Builds the kernel at *format*, for a document that has just opened or
## changed its depth. The compiler keeps the build, so the object made here is
## let go at once and the pass's own finds the build in place.
static func warm_at(format: int) -> void:
    if GlobalShaderCompiler.get_rd() == null:
        return
    SaCompute.new("gradient").use_storage_format(format)


func _get_compute() -> SaCompute:
    if _compute == null and GlobalShaderCompiler.get_rd() != null:
        _compute = SaCompute.new("gradient")
    return _compute
