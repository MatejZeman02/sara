## Assign and convert the colour space of one document.
##
## A pass *over* a document, driven by a descriptor pair, and none of it is state
## the document holds between operations. So whoever converts builds one, the way
## every other pass is built: `SaColorConversion.new(document).convert_to(target)`.
## It is `RefCounted`, so it is gone when the call returns unless a history step
## holds it, which `UndoRedo` does for as long as the step can be undone.
@tool
class_name SaColorConversion
extends RefCounted

## The document being converted. A `Node`, so holding it forms no reference
## cycle with this `RefCounted`.
var _document: SaDocument


func _init(document: SaDocument) -> void:
    _document = document


## Why [method convert_to] would refuse, or "" when it would run.
##
## A predicate rather than a bare bool so the caller can say which of the reasons
## it is. The interesting one is the unspecified document: it has no source space
## to convert *from*, and converting it would transform pixels nobody ever
## described. That is the distinction `is_specified` was introduced to keep, and
## this is the code that finally spends it.
func blocked_reason(target: SaColorSpace) -> String:
    var space := _document.color_space
    if target == null:
        return "no target colour space was given"
    if space != null and not SaColorSpace.storage_supports_depth(space.depth):
        return "this document is stored at %s, which cannot be allocated" % SaColorSpace.depth_name(space.depth)
    if space == null or not space.is_specified:
        return "this document never declared a colour space, so assign one rather than converting from nothing"
    if space.matches(target.with_depth(space.depth)):
        return "the document is already in that colour space"
    return ""


## Declares what the document's existing numbers mean, without touching a pixel.
##
## Photoshop calls this Assign Profile, and it is the honest answer for a
## document loaded from a file that recorded no colour space: the pixels are
## already whatever they are, and what was missing was the label.
func assign(target: SaColorSpace) -> bool:
    if target == null:
        return false
    var space := _document.color_space
    # Assign relabels what is already stored, so it keeps the depth those pixels
    # are actually in for the same reason convert does. A label claiming a depth
    # the chunks are not at is the exact bug this whole item exists to remove.
    var labelled := target.with_depth(space.depth).with_rounding(space.rounds_at_save) if space != null else target
    if space != null and space.matches(labelled) and space.is_specified:
        return false

    # Through the history rather than UndoRedo directly, so its step count and
    # the tally beside it stay in step. Nothing to weigh: a label is not pixels.
    _document.history.commit_pair("Assign Colour Space", apply_space.bind(labelled), apply_space.bind(space))

    apply_space(labelled)
    return true


## Rewrites every colour-typed field of every layer into *target*.
##
## Named `convert_to` rather than `convert`, which shadows a GDScript built-in
## and is reported by the LSP alone: not by the tests, not by gdformat, and not
## by gdlint.
##
## One undo entry for the whole document, and it carries the descriptor as well
## as the pixels. Undoing only the pixels would leave converted-back values
## wearing the new label, which is a worse document than either end state.
##
## Only authoritative colour fields are dispatched. A height, thickness or
## concentration field is not colour and `SaFieldSpec.is_color` already says so,
## which is what keeps this from being a special case per layer type. A *derived*
## colour field is skipped too and marked unresolved instead, because its value
## is recomputed from fields this pass did not touch, so converting it would be
## overwritten by the next resolve. What a Kubelka-Munk layer's concentrations
## should mean across a colour space change is a real question, and it belongs to
## the layer type that introduces them rather than here.
func convert_to(target: SaColorSpace) -> bool:
    var blocked := blocked_reason(target)
    if not blocked.is_empty():
        push_warning("SaColorConversion.convert_to refused: %s" % blocked)
        return false

    # Depth is deliberately carried over rather than taken from the target.
    # Changing what colours mean is a compute pass over the pixels that are
    # there. Changing how many bits they get is a reallocation of every chunk,
    # and a preset like ACEScg naming F32 would otherwise silently rewrite an
    # F16 document's storage as a side effect of a gamut change.
    var source := _document.color_space
    var effective := target.with_depth(source.depth).with_rounding(source.rounds_at_save)
    var layers := paint_layers()

    var before: Array = []
    for layer in layers:
        before.append({"layer": layer, "chunks": _snapshot_layer(layer)})

    _dispatch(source, effective, layers)
    _document.color_space = effective

    var after: Array = []
    for layer in layers:
        after.append({"layer": layer, "chunks": _snapshot_layer(layer)})

    # The largest step the history can hold, every chunk of every layer twice.
    # It goes through the history rather than straight on UndoRedo, where the
    # byte tally beside it would desynchronise for every later commit. Charged
    # in full, it will evict other steps, which is the budget working rather
    # than a regression.
    var held := 0
    for entry: Dictionary in before + after:
        var chunks: Dictionary = entry["chunks"]
        held += SaHistory.bytes_of(chunks)
    _document.history.commit_pair(
        "Convert Colour Space", apply_conversion.bind(effective, after), apply_conversion.bind(source, before), held
    )

    _document.update_caches()
    _document.invalidate_all_allocated_chunks()
    _document.document_changed.emit()
    return true


## Rewrites one layer painted in *from_space* into the document's own space,
## with no history step of its own: the caller's step owns the layer. What a
## paste needs when the clipboard came from a document that stored its colours
## differently. Depth is the caller's to have checked, as convert_to keeps it.
func convert_layer(layer: SaLayer, from_space: SaColorSpace) -> void:
    if layer == null or from_space == null or from_space.matches(_document.color_space):
        return
    var layers: Array[SaLayer] = [layer]
    _dispatch(from_space, _document.color_space, layers)


## Every layer that holds paint. The caches are rebuilt from these and the stroke
## buffer is transient, so neither is converted.
func paint_layers() -> Array[SaLayer]:
    var layers: Array[SaLayer] = []
    for child in _document.get_children():
        if child is SaLayer:
            layers.append(child as SaLayer)
    return layers


func _snapshot_layer(layer: SaLayer) -> Dictionary[Vector2i, SaChunk]:
    var data: Dictionary[Vector2i, SaChunk] = {}
    for grid_pos: Vector2i in layer.chunks:
        data[grid_pos] = layer.duplicate_chunk(grid_pos)
    return data


## The compute pass itself. One push constant for the whole document, because
## the source and target pair does not vary per chunk.
func _dispatch(source: SaColorSpace, target: SaColorSpace, layers: Array[SaLayer]) -> void:
    # Built per pass and dropped with it, so no pipeline and no uniform set
    # outlives the conversion inside a history step that only needs the undo.
    var compute := SaCompute.new("convert_color_space")
    var params := source.to_conversion_push_constant(target)

    var same := func(_grid_pos: Vector2i, _local: Rect2i, _start: Vector2i) -> PackedFloat32Array: return params
    for layer in layers:
        # No selection: a conversion is about what the numbers mean and reaches
        # every layer edge to edge, so there is nothing to mask and nothing to
        # allocate. The rectangle is the one the layer's own chunks cover.
        var chunk_at := func(grid_pos: Vector2i) -> SaChunk: return layer.chunks.get(grid_pos, null)
        var walk := SaChunkWalk.new(compute, null, layer)
        walk.run("convert_color_space", SaChunkWalk.reach_of(layer.chunks.keys()), chunk_at, same)
        layer.mark_all_unresolved()


## Undo/redo for the descriptor alone, used by [method assign]. Public because
## `UndoRedo` binds it as a callable and has to be able to reach it.
func apply_space(space: SaColorSpace) -> void:
    _document.color_space = space
    _document.invalidate_all_allocated_chunks()
    _document.document_changed.emit()


## Undo/redo for a conversion: the descriptor and every layer's chunks together.
func apply_conversion(space: SaColorSpace, snapshots: Array) -> void:
    _document.color_space = space
    for entry: Dictionary in snapshots:
        var layer: SaLayer = entry["layer"]
        if layer == null or not is_instance_valid(layer):
            continue
        var data := SaTyped.chunks(entry["chunks"])
        for grid_pos: Vector2i in data:
            var stored: SaChunk = data[grid_pos]
            if stored == null:
                layer.set_chunk(grid_pos, null)
            else:
                # Copy, so the history backup stays untouched in VRAM.
                layer.set_chunk(grid_pos, stored.duplicate_chunk())
    _document.update_caches()
    _document.invalidate_all_allocated_chunks()
    _document.document_changed.emit()
