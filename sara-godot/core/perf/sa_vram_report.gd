## VRAM three ways: what the driver reports, what Sara's own textures account
## for, and the chunk counts each depends on.
##
## `SaTexture.allocated_bytes` only ever counted `SaTexture`'s own textures, so
## it agrees with the driver's figure up to the engine's own textures and the
## driver's per-texture padding, and disagrees on purpose: the driver's number
## is the true VRAM floor and Sara's is its own accounting of what it
## allocated, not the card's memory.
## A gap between the two on either side is a leak worth chasing.
class_name SaVramReport
extends RefCounted


## One block, read at dump time rather than kept, because nothing here is
## cumulative in the way `SaCompute`'s counters are. `sara_buffers` and
## `history_bytes` are read from `SaCompute`'s static and the report's
## own history block once the fold exists.
static func block(document: SaDocument) -> Dictionary[String, Variant]:
    var rd := GlobalShaderCompiler.get_rd()
    var device := "none"
    var device_textures := 0
    var device_buffers := 0
    var device_total := 0
    if rd != null:
        device = rd.get_device_name()
        device_textures = rd.get_memory_usage(RenderingDevice.MEMORY_TEXTURES)
        device_buffers = rd.get_memory_usage(RenderingDevice.MEMORY_BUFFERS)
        device_total = rd.get_memory_usage(RenderingDevice.MEMORY_TOTAL)

    var sara_textures := SaTexture.allocated_bytes

    return {
        "device": device,
        "device_textures": device_textures,
        "device_buffers": device_buffers,
        "device_total": device_total,
        "sara_textures": sara_textures,
        # The engine's own textures, the driver's per-texture padding, and
        # anything freed in the last two drawn frames but not yet given back
        # by the main device's deferred free.
        "unaccounted_textures": device_textures - sara_textures,
        "chunks": _chunks_block(document),
        "chunk_edge": _chunk_edge(document),
    }


## `{layers: {name: n}, stroke, selection, total}`. `SaLayerStack.layers()`
## already appends the stroke buffer to the walk, so it is pulled back out and
## counted once under `stroke` rather than under its own layer name.
static func _chunks_block(document: SaDocument) -> Dictionary[String, Variant]:
    var per_layer: Dictionary[String, int] = {}
    var stroke := 0
    for layer: SaLayer in SaLayerStack.layers(document):
        if layer == document.stroke_layer:
            stroke = layer.chunks.size()
        else:
            per_layer[layer.name] = layer.chunks.size()

    # SaSelection extends RefCounted rather than Node, so it never appears in
    # SaLayerStack's walk and is asked for directly.
    var selection := document.selection.chunks.size()

    var total := stroke + selection
    for count: int in per_layer.values():
        total += count

    return {
        "layers": per_layer,
        "stroke": stroke,
        "selection": selection,
        "total": total,
    }


## The edge length `pixel_size()` reports for whichever chunk is found first,
## walking the same order `SaLayerStack.layers()` does and then the selection.
## Hard rule 3: never assume 256. `SaChunk.SIZE` stands in only when the
## document holds no chunk to ask, which is what it already names at full
## resolution.
static func _chunk_edge(document: SaDocument) -> int:
    for layer: SaLayer in SaLayerStack.layers(document):
        for chunk: SaChunk in layer.chunks.values():
            return chunk.pixel_size()
    for chunk: SaChunk in document.selection.chunks.values():
        return chunk.pixel_size()
    return SaChunk.SIZE
