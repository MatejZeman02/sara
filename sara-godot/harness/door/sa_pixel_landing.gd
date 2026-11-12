## Where the array of a `write_pixels` step lands: one upload, a copy into each
## chunk at the layer's own depth on the graphics card, and what undo keeps of
## what the copies overwrote. Apart from `sa_scenario_pixels.gd`, because both
## halves of this file are what keep a NumPy slider's large write quick. Beside
## the door rather than the step, because `harness/scenario` stands at its
## budget, the file map's top page has no room for a folder, and a write's
## history is the door's to say.
##
## **The array goes up as it came**, `float32`, and a kernel writes it into the
## chunk, half floats in the document Sara opens with. Converting on the CPU
## first, `Image.convert` to `RGBAH`, would cost a large write several times
## what the upload and its copies take. The copy is
## `copy_region.gmacs`, a dispatch, which is the shape [SaFilterApply] lands a
## filter's answer in, and a chunk the write makes is blanked by `clear.gmacs`
## first where the array does not reach, because `texture_clear` is not ordered
## against the compute that follows it.
##
## **A drag holds its undo step open.** A write with `history` off records no
## step, as a kernel's rerun records none, and keeps in a [Held] what it
## overwrote that no write before it kept. The next write with history on
## records all of it as its one step, so the thirty writes of a slider's drag
## and the one when it is let go are one undo, back to before the first.
extends RefCounted

## The depth every array crosses the door in, `<f4` of `harness/sa_npy.gd`.
const UPLOAD_FORMAT := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

## The binding of `copy_region.gmacs` the array is read from, the upload's
## depth whatever the chunk's.
const SOURCE_BINDING := 1


## What the writes without history overwrote, layer by layer, until a write
## with history records it. The step's driver owns one for the session.
##
## Kept only while the history stands still. A step recorded, undone or redone
## in between lets all of it go, since what it would put back may no longer be
## what lies under the writes, and the write that records then takes back only
## itself. That is what a stroke painted in the middle of a drag costs, and it
## is the safe side: a kept snapshot of before an undo would undo the undo.
## It listens for `version_changed` rather than comparing `get_version()`,
## which an undo and a new step bring back to the same number.
class Held:
    extends RefCounted

    ## Layer to grid position to what was there before the first write that
    ## reached it: a delta, a whole chunk, or null where there was no chunk.
    var _kept: Dictionary = {}

    ## The history listened to, the document's whose layers are held.
    var _watched: UndoRedo = null

    ## What *layer*'s writes without history kept, for the next write to add
    ## to, an empty one when nothing is held for it. A document other than the
    ## last one's lets everything go first.
    func of(document: SaDocument, layer: SaLayer) -> Dictionary:
        if not is_instance_valid(_watched) or _watched != document.undo_redo:
            _watch(document.undo_redo)
        if not _kept.has(layer):
            _kept[layer] = {}
        return _kept[layer]

    ## What *layer*'s writes without history kept, handed to the write that
    ## records it and forgotten here.
    func take(document: SaDocument, layer: SaLayer) -> Dictionary:
        var kept := of(document, layer)
        _kept.erase(layer)
        return kept

    ## How many layers hold writes no step has recorded yet, which a suite reads.
    func layers_held() -> int:
        return _kept.size()

    func _watch(history: UndoRedo) -> void:
        if is_instance_valid(_watched) and _watched.version_changed.is_connected(_let_go):
            _watched.version_changed.disconnect(_let_go)
        _kept.clear()
        _watched = history
        if history != null:
            history.version_changed.connect(_let_go)

    func _let_go() -> void:
        _kept.clear()


## Writes *image*, `RGBAF` the size of *rect*, into *layer* at each of
## *positions*, the grid positions *rect* reaches, and answers the ones it wrote.
##
## A position with no chunk whose part of the array is all zero bytes is
## skipped, so a write into empty space allocates only where it lands paint.
## Before anything is written, *kept* gains what each written position held
## and does not hold already: the region as it stands, the whole chunk when
## the region clips away, or null where there was no chunk, the swap's spelling
## of a tile that did not exist. A position it holds already has its region
## grown to this write's, from the chunk's own texels outside the old region.
static func land(layer: SaLayer, rect: Rect2i, image: Image, positions: Array[Vector2i], kept: Dictionary) -> Array[Vector2i]:
    var touched: Array[Vector2i] = []
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null:
        return touched
    var edge := layer.CHUNK_SIZE
    for grid_pos: Vector2i in positions:
        var covered := Rect2i(grid_pos * edge, Vector2i(edge, edge))
        var overlap := covered.intersection(rect)
        var existing: SaChunk = layer.chunks.get(grid_pos, null)
        if existing == null and _is_blank(image.get_region(Rect2i(overlap.position - rect.position, overlap.size))):
            continue
        var local := Rect2i(overlap.position - covered.position, overlap.size)
        if kept.has(grid_pos):
            kept[grid_pos] = _widened(kept[grid_pos], existing, local)
        else:
            kept[grid_pos] = _snapshot(layer, grid_pos, existing, local)
        touched.append(grid_pos)
    if touched.is_empty():
        return touched

    var upload := SaTexture.new(rect.size, UPLOAD_FORMAT)
    rd.texture_update(upload.rid, 0, image.get_data())
    var fresh: Array[Vector2i] = []
    for grid_pos: Vector2i in touched:
        if not layer.chunks.has(grid_pos):
            fresh.append(grid_pos)
    _blank_where_the_array_does_not_reach(layer, rect, fresh)
    var copier := SaCompute.new("copy_region")
    copier.use_binding_format(SOURCE_BINDING, UPLOAD_FORMAT)
    for grid_pos: Vector2i in touched:
        var covered := Rect2i(grid_pos * edge, Vector2i(edge, edge))
        var overlap := covered.intersection(rect)
        var from := overlap.position - rect.position
        var to := overlap.position - covered.position
        var destination := layer.get_or_create_chunk(grid_pos).field(SaFieldSpec.ALBEDO)
        copier.set_texture(0, destination.rid)
        copier.set_texture(SOURCE_BINDING, upload.rid)
        var placed := PackedFloat32Array([from.x, from.y, to.x, to.y, overlap.size.x, overlap.size.y, 0.0, 0.0])
        copier.set_push_constant_float_array(placed)
        copier.list_dispatch_kernel(
            "copy_region", destination.format, SaCompute.groups_for(overlap.size.x), SaCompute.groups_for(overlap.size.y), 1
        )
        layer.mark_unresolved(grid_pos)
    copier.list_end()
    return touched


## Clears every chunk of *fresh* that *rect* does not cover whole, by kernel,
## in one list that ends before the copies begin. A new chunk is cleared by
## `texture_clear`, a transfer, and the copy that follows is compute, which a
## transfer is not ordered against inside a frame, so the part the array does
## not reach would be left to a clear that may land after the composite reads.
static func _blank_where_the_array_does_not_reach(layer: SaLayer, rect: Rect2i, fresh: Array[Vector2i]) -> void:
    var clearer: SaCompute = null
    var edge := layer.CHUNK_SIZE
    for grid_pos: Vector2i in fresh:
        var covered := Rect2i(grid_pos * edge, Vector2i(edge, edge))
        if rect.encloses(covered):
            continue
        if clearer == null:
            clearer = SaCompute.new("clear")
        var chunk := layer.get_or_create_chunk(grid_pos)
        var target := chunk.field(SaFieldSpec.ALBEDO)
        var side := chunk.pixel_size()
        clearer.set_texture(0, target.rid)
        clearer.set_push_constant_float_array(PackedFloat32Array([0.0, 0.0, 0.0, 0.0, side, side, 0.0, 0.0]))
        clearer.list_dispatch_kernel("clear_chunk", target.format, SaCompute.groups_for(side), SaCompute.groups_for(side), 1)
    if clearer != null:
        clearer.list_end()


## What undo puts back for one chunk: the region as it stands, the whole chunk
## when the region clips away, or null where there was no chunk.
static func _snapshot(layer: SaLayer, grid_pos: Vector2i, existing: SaChunk, local: Rect2i) -> Variant:
    if existing == null:
        return null
    var delta := SaChunkDelta.capture(existing, local)
    if delta != null:
        return delta
    return layer.duplicate_chunk(grid_pos)


## *entry*, kept by an earlier write, over this write's *local* region too. A
## delta grows by the bands it did not cover, read from the chunk before this
## write lands. A whole chunk, or the null of a chunk that was not there, is
## already all of it.
static func _widened(entry: Variant, existing: SaChunk, local: Rect2i) -> Variant:
    if entry is SaChunkDelta:
        return (entry as SaChunkDelta).grown_to(existing, local)
    return entry


## Whether every byte of *part* is zero, which is transparent black. A compare
## of two byte arrays is native, where a loop over the texels would be seconds
## on a 2048 square.
static func _is_blank(part: Image) -> bool:
    var data := part.get_data()
    var zeros := PackedByteArray()
    zeros.resize(data.size())
    return data == zeros
