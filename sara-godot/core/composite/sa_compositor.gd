## Composites the document's layer stack into the output texture, and resolves
## blend modes for whoever asks.
##
## The walk is bottom stack, active layer with the live stroke, top stack, in
## that order, and every step blends against the canvas as it is when the step
## is reached. `SaCompositeWalk` draws it through the calls here, and
## `SaLayerStack` decides what the two stacks hold and which of their entries
## are caches. Lives in the skeleton and maintains a registry of available
## blend modes registered by modules.
class_name SaCompositor
extends RefCounted

## Stable ID -> { "shader": String, "kernel": int }. Kernel numbers remain
## private implementation details of a shader and are never persisted.
var blend_modes: Dictionary[StringName, Dictionary] = {}
## The kernel file a seeded commit runs, which has a twin of every blend
## kernel of `composite.gmacs` under the same name, both made from one formula,
## this one with a rounded store.
const COMMIT_SHADER := "stroke_commit"
## The one uint `stroke_commit.gmacs` reads its seed from, made at the first
## seeded commit and written at each.
var _commit_seed: SaCompute.Buffer = null
var _cached_computes: Dictionary[String, SaCompute] = {}  # shader_name -> SaCompute instance
## The smudge mixes' computes, shader name to instance, see [method record_mix].
var _mix_computes: Dictionary[String, SaCompute] = {}
## The step a generated layer takes, with the scratch its kernel writes.
var _generated := SaGeneratedLayer.Step.new()
## The step an adjustment layer takes at its place in the walk, with the
## scratches it copies the backdrop through. The fold takes it too.
var adjustment := SaBackdropLayer.new()
## Every effect layer's cache, refreshed where its input moved before a walk.
var effect := SaEffectLayer.new()
## A clipping base and what is clipped to it, composited as one group by the
## walk, the fold, a flatten and a merge alike.
var clip_group := SaClipGroup.new()
## The point pass previewed on a document's active layer, a class of its own
## because the filter dialog drives it by document. Read at composite time,
## never written to a chunk.
var point_preview: SaPointPreview = SaPointPreview.new()
## A node's attached filters, run over its chunk before its mask and its
## clip. The host hands it the filter registry.
var filter_chain: SaFilterChain = SaFilterChain.new()
## Where a walk writes, the output or a display chunk.
var detail := SaDetailView.Target.new()
## A layer's filters, mask and clip over a chunk, flat for the output and every
## caller outside a walk, fine for a display chunk's walk, which keeps a chunk
## at 2.0 at its own density through all three.
var _flat: SaLayerShown = null
var _fine: SaLayerShown = null
## The walk itself, below the active layer, the active tier and above it, with
## the scratches, the stroke run and the halos only it reads.
var _walk: SaCompositeWalk = null
## The document whose canvas is being drawn, from the effect layers' refresh
## through the walk, and null otherwise, set by [method composite_chunks] and
## [method walk] alone. A layer clipped to its active layer reads the base as
## the canvas draws it, so a clip follows a pass a dialog previews on its base.
## A flatten, a merge, an export or a bake draws no canvas, and reads the base
## as it is stored, because the preview is no part of the document.
var _drawing: SaDocument = null

## How many scratch-chain chunks of one pass share a clear list before they
## are rendered and their slots reused. A pool slot is a whole chunk of VRAM
## kept between passes, and a pass over a whole layer, an opacity change
## inside an isolated group, would otherwise take a slot per chunk of the
## document and keep them all, the grid allocated by another road. A stroke's pass touches
## a handful of chunks, so eight keeps every one of its clears in one list.
const SCRATCH_RUN: int = 8

## Injected by the host. When present it is the authority: modes resolve their
## kernel by name through the compiler, so nothing depends on registration order.
var registry: SaBlendModeRegistry = null


func _init() -> void:
    # The 17 built-in modes register through the public API, in skeleton_module.gd.
    _flat = SaLayerShown.new(false, filter_chain, get_compute)
    _fine = SaLayerShown.new(true, filter_chain, get_compute)
    _walk = SaCompositeWalk.new(
        filter_chain, detail, clear_scratch_batch, composite_chunk_pairs, composite_chunk_batch, _composite_entry_chunk
    )


## Point the compositor at the registry that owns blend modes.
func set_registry(blend_registry: SaBlendModeRegistry) -> void:
    registry = blend_registry


## Legacy path: register by explicit kernel index, kept for a host without a registry.
## The index is the fragile coupling the registry removes, so prefer a SaBlendModeDescriptor.
func register_blend_mode(mode_id: StringName, shader_name: String, kernel_index: int = 0) -> void:
    assert(not mode_id.is_empty(), "Blend mode ID cannot be empty")
    assert(not shader_name.is_empty(), "Blend mode shader cannot be empty")
    var mode: Dictionary[String, Variant] = {"shader": shader_name, "kernel": kernel_index}
    blend_modes[mode_id] = mode


func has_blend_mode(mode_id: StringName) -> bool:
    if registry != null and registry.has(mode_id):
        return true
    return blend_modes.has(mode_id)


## Shader name and kernel index for a mode.
##
## Resolution goes through the registry by kernel *name*. The index is looked up
## in the compiled shader rather than supplied by the caller. An unknown mode
## falls back to Normal, which is why a missing kernel must be caught at
## registration (SaBlendModeRegistry.validate) rather than here.
func _get_blend_mode(mode_id: StringName) -> Dictionary[String, Variant]:
    if registry != null:
        var descriptor := registry.get_descriptor(mode_id)
        if descriptor == null:
            descriptor = registry.get_descriptor(SaLayer.BLEND_MODE.NORMAL)
        if descriptor != null:
            var index := GlobalShaderCompiler.get_kernel_index(descriptor.shader_name, descriptor.kernel_name)
            if index >= 0:
                return {
                    "shader": descriptor.shader_name,
                    "kernel": index,
                    "buffers": descriptor.extra_buffers,
                    "name": descriptor.kernel_name,
                }
    if blend_modes.has(mode_id):
        return blend_modes[mode_id]
    if blend_modes.has(SaLayer.BLEND_MODE.NORMAL):
        return blend_modes[SaLayer.BLEND_MODE.NORMAL]
    return {"shader": "composite", "kernel": 0}


## The cached SaCompute for a shader, with a mode's storage buffers bound by name.
func get_compute(shader_name: String, buffers: Dictionary = {}) -> SaCompute:
    if not _cached_computes.has(shader_name):
        _cached_computes[shader_name] = SaCompute.new(shader_name)
    _cached_computes[shader_name].set_storages(buffers)
    return _cached_computes[shader_name]


## Composites one source field into one destination texture. Every caller
## (cache rebuild, preview, and commit) goes through this method so blend
## selection cannot diverge between the live stroke and baked result.
##
## It takes textures rather than chunks on purpose: the compositor reads `albedo`
## and nothing else, and a layer whose albedo is derived resolves it before
## getting here. *density* is how many source texels lie along a destination
## pixel, and zero reads it off the source, 2 for a chunk at 2.0 and 1 for any
## other. The dispatch covers the region in destination pixels.
## The colour space is passed because one compositor can serve several easels,
## and a null one means gamma sRGB, what a shader test with no document gets.
func composite_chunk(
    destination: SaTexture,
    source: SaTexture,
    mode_id: StringName = SaLayer.BLEND_MODE.NORMAL,
    opacity: float = 1.0,
    destination_offset: Vector2 = Vector2.ZERO,
    space: SaColorSpace = null,
    blend_white: float = 1.0,
    chunk_region: Rect2i = Rect2i(),
    density: float = 0.0
) -> void:
    if destination == null or source == null:
        return
    # Both bindings share one format qualifier, so a mismatch is a bug in whoever
    # allocated one of them, said aloud rather than undefined values.
    if destination.format != source.format:
        push_warning(
            (
                ("SaCompositor.composite_chunk: destination is format %d and source is %d; " + "one dispatch cannot serve both.")
                % [destination.format, source.format]
            )
        )
        return

    var mode_info := _get_blend_mode(mode_id)
    var compute := get_compute(SaTyped.text_at(mode_info, "shader", "composite"), SaTyped.strings(mode_info.get("buffers", {})))
    compute.use_storage_format(destination.format)
    compute.set_texture(0, destination.rid)
    var d := density if density > 0.0 else SaDocumentTexels.density_of(source)
    var region := chunk_region if chunk_region.size.x > 0 else Rect2i(Vector2i.ZERO, Vector2i(Vector2(source.size) / d))
    var groups := _bind_source(compute, destination, source, destination_offset, opacity, space, blend_white, region, d)
    compute.dispatch(SaTyped.int_at(mode_info, "kernel", 0), groups.x, groups.y, 1)


## Records *mode_id*'s composite of *over* onto *under* over *region*, for the
## smudge stage's mixes, which [SaSmudgeMix] sends in the stroke's own list
## between the stages that fill and empty the two images. Null for a mode
## without a registry descriptor, whose kernel has no name to record by, and
## the stage then mixes nothing in the mode rather than half of it.
##
## Its own computes, one a shader, apart from [method get_compute]'s, so the
## frame's composites never rebind the uniform set a recorded mix holds until
## the list it is in goes. The region is the images' own, at one texel a pixel,
## and nothing of the display's detail view places it.
func record_mix(
    under: SaTexture, over: SaTexture, mode_id: StringName, space: SaColorSpace, blend_white: float, region: Rect2i
) -> SaCompute.Recorded:
    var mode_info := _get_blend_mode(mode_id)
    var kernel_name := SaTyped.text_at(mode_info, "name", "")
    if under == null or over == null or kernel_name.is_empty() or region.size.x <= 0 or region.size.y <= 0:
        return null
    var compute := _mix_compute(mode_info)
    compute.use_storage_format(under.format)
    compute.set_texture(0, under.rid)
    compute.set_texture(1, over.rid)
    compute.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0, space, 1.0, blend_white, region))
    return compute.record(
        kernel_name, under.format, SaCompute.groups_for(region.size.x), SaCompute.groups_for(region.size.y), 1, true
    )


## The mix's own compute for the shader *mode_info* names, its buffers bound.
func _mix_compute(mode_info: Dictionary) -> SaCompute:
    var shader := SaTyped.text_at(mode_info, "shader", "composite")
    if not _mix_computes.has(shader):
        _mix_computes[shader] = SaCompute.new(shader)
    var compute: SaCompute = _mix_computes[shader]
    compute.set_storages(SaTyped.strings(mode_info.get("buffers", {})))
    return compute


## Binds one source chunk and its parameters, and answers how many workgroups it
## needs. Everything a single composite dispatch needs beyond the destination,
## which the batch below binds once for all of them.
##
## *region* is the part to composite in destination pixels, a zero *density* is
## read off the source, and [member detail] places both in a display chunk.
func _bind_source(
    compute: SaCompute,
    destination: SaTexture,
    source: SaTexture,
    destination_offset: Vector2,
    opacity: float,
    space: SaColorSpace,
    blend_white: float,
    region: Rect2i,
    density: float = 0.0
) -> Vector2i:
    compute.set_texture(1, source.rid)
    var d := density if density > 0.0 else SaDocumentTexels.density_of(source)
    var at := detail.placed(destination, destination_offset, region, d)
    compute.set_push_constant_float_array(
        SaCompute.pack_composite_params(at.offset, opacity, space, at.density, blend_white, at.region)
    )
    return Vector2i(SaCompute.groups_for(at.region.size.x), SaCompute.groups_for(at.region.size.y))


## *source*'s colour at full coverage into *destination* over *region*,
## chunk-local pixels, every pixel written: the plate a clip group lays its
## clipped layers on, so each blends with the base's colour alone.
func opaque_chunk(destination: SaTexture, source: SaTexture, region: Rect2i) -> void:
    var compute := get_compute("composite")
    compute.use_storage_format(destination.format)
    compute.set_texture(0, destination.rid)
    var groups := _bind_source(compute, destination, source, Vector2.ZERO, 1.0, null, 1.0, region)
    compute.dispatch_kernel("opaque", groups.x, groups.y, 1)


## Composites many sources into one destination inside a single compute list.
##
## Every entry writes its own disjoint region of *destination*, so the dispatches
## carry no hazard between them and need no barrier. `compute_list_end()` inserts a
## full barrier, so a list per chunk would cost a tier of forty chunks forty of
## them to do work that needs one at the end.
##
## What this must *not* be used for is a chain where one dispatch reads what the
## last one wrote. A chunk under the live stroke is exactly that, and
## `SaStrokeRun` gives each chunk its own scratch so a stage can be one list.
##
## *entries* is an Array of `[source: SaTexture, destination_offset: Vector2,
## region: Rect2i]`, the region being the part of the source chunk to composite.
func composite_chunk_batch(
    destination: SaTexture,
    entries: Array,
    mode_id: StringName,
    opacity: float,
    space: SaColorSpace = null,
    blend_white: float = 1.0
) -> void:
    if destination == null or entries.is_empty():
        return

    var mode_info := _get_blend_mode(mode_id)
    var compute := get_compute(SaTyped.text_at(mode_info, "shader", "composite"), SaTyped.strings(mode_info.get("buffers", {})))
    # Chosen before the list opens: switching format reloads the kernels, which is
    # not something to do with a list already bound to one of them. Every chunk a
    # document owns follows its descriptor, so this is settled for the whole batch.
    compute.use_storage_format(destination.format)
    compute.set_texture(0, destination.rid)

    compute.list_begin(SaTyped.int_at(mode_info, "kernel", 0))
    for entry: Array in entries:
        var source: SaTexture = entry[0]
        if source == null or source.format != destination.format:
            continue
        var offset: Vector2 = entry[1]
        var region: Rect2i = entry[2]
        var groups := _bind_source(compute, destination, source, offset, opacity, space, blend_white, region)
        compute.list_dispatch(groups.x, groups.y, 1)
    compute.list_end()


## Composites many source chunks, each into its own destination, inside a single
## compute list.
##
## What [method composite_chunk_batch] cannot do: commit's bake writes every
## stroke chunk into the active layer's chunk at the same grid position, a
## different texture per entry. No pair touches another's, so no barrier is
## needed between them, and a chain still goes through [method composite_chunk].
##
## *entries* is an Array of `[destination: SaTexture, source: SaTexture]`, each
## composited over the whole source chunk at offset zero, which is what every
## bake does, or of `[destination, source, region: Rect2i]` over the region
## alone, which is what a stage of `SaStrokeRun` does. The storage format is
## settled by the first pair before the list opens, for the reason
## [method composite_chunk_batch] gives, and a pair at another depth is skipped
## with the warning [method composite_chunk] prints.
##
## *stroke_seed* is a brush stroke's seed, which only the commit passes, and a
## commit in any of `composite.gmacs`'s modes then runs its twin in
## `stroke_commit.gmacs`, whose store rounds to a half stochastically where the
## layer narrows it. Negative, every other caller's, is the plain composite
## kernel, and so is a mode a module brings in a shader of its own.
func composite_chunk_pairs(
    entries: Array, mode_id: StringName, opacity: float, space: SaColorSpace = null, blend_white: float = 1.0, stroke_seed := -1
) -> void:
    if entries.is_empty():
        return
    var first_destination: SaTexture = entries[0][0]
    if first_destination == null:
        return

    var mode_info := _get_blend_mode(mode_id)
    var compute := get_compute(SaTyped.text_at(mode_info, "shader", "composite"), SaTyped.strings(mode_info.get("buffers", {})))
    var kernel := SaTyped.int_at(mode_info, "kernel", 0)
    var twin := _commit_twin(mode_info) if stroke_seed >= 0 else ""
    if not twin.is_empty():
        var seeded := _seeded_commit(stroke_seed)
        if seeded.index_of_kernel(twin) >= 0:
            compute = seeded
            kernel = seeded.index_of_kernel(twin)
    compute.use_storage_format(first_destination.format)

    compute.list_begin(kernel)
    for entry: Array in entries:
        var destination: SaTexture = entry[0]
        var source: SaTexture = entry[1]
        if destination == null or source == null:
            continue
        if destination.format != first_destination.format or source.format != first_destination.format:
            push_warning(
                (
                    "SaCompositor.composite_chunk_pairs: destination is format %d and source is %d; one list cannot serve both."
                    % [destination.format, source.format]
                )
            )
            continue
        compute.set_texture(0, destination.rid)
        var d := SaDocumentTexels.density_of(source) / SaDocumentTexels.density_of(destination)
        var region: Rect2i = entry[2] if entry.size() > 2 else Rect2i(Vector2i.ZERO, Vector2i(Vector2(source.size) / d))
        var groups := _bind_source(compute, destination, source, Vector2.ZERO, opacity, space, blend_white, region, d)
        compute.list_dispatch(groups.x, groups.y, 1)
    compute.list_end()


## The kernel of `stroke_commit.gmacs` that commits in *mode_info*'s mode, or
## empty for a mode whose shader is not `composite.gmacs`.
static func _commit_twin(mode_info: Dictionary) -> String:
    if SaTyped.text_at(mode_info, "shader", "composite") != "composite":
        return ""
    var names := GlobalShaderCompiler.get_kernel_names("composite")
    var index := SaTyped.int_at(mode_info, "kernel", 0)
    if index < 0 or index >= names.size():
        return ""
    return str(names[index])


## `stroke_commit.gmacs` with *stroke_seed*, folded to 24 bits, in the buffer
## it reads it from.
func _seeded_commit(stroke_seed: int) -> SaCompute:
    var bytes := PackedByteArray()
    bytes.resize(4)
    bytes.encode_u32(0, SaStrokeInfo.folded_seed(stroke_seed))
    if _commit_seed == null:
        _commit_seed = SaCompute.Buffer.new(bytes)
    else:
        _commit_seed.update(bytes)
    return get_compute(COMMIT_SHADER, {"stroke_draw": _commit_seed.rid})


## Clears many scratch chunks inside a single compute list.
##
## A clear has no source and a varying destination: every touched chunk of a
## pass gets its own pooled scratch, so *entries* is an Array of
## `[destination: SaTexture, region: Rect2i]` and each dispatch binds its own
## texture, never the same one twice, so no barrier is needed between them.
func clear_scratch_batch(entries: Array) -> void:
    if entries.is_empty():
        return
    var first_destination: SaTexture = entries[0][0]
    if first_destination == null:
        return
    var clear_compute: SaCompute = get_compute("clear")
    clear_compute.use_storage_format(first_destination.format)
    clear_compute.list_begin(clear_compute.index_of_kernel("clear_chunk"))
    for entry: Array in entries:
        var destination: SaTexture = entry[0]
        var wanted: Rect2i = entry[1]
        var region := detail.placed(destination, Vector2.ZERO, wanted, 1.0).region
        if destination == null or region.size.x <= 0 or region.size.y <= 0:
            continue
        clear_compute.set_texture(0, destination.rid)
        clear_compute.set_push_constant_float_array(
            PackedFloat32Array([0.0, 0.0, region.position.x, region.position.y, region.size.x, region.size.y, 0.0, 0.0])
        )
        clear_compute.list_dispatch(SaCompute.groups_for(region.size.x), SaCompute.groups_for(region.size.y), 1)
    clear_compute.list_end()


## *layer*'s coverage at *grid_pos*, or null where it hides nothing there: no
## mask, a mask switched off, or a position that reads one. A mask resting at zero
## answers its 1 by 1 rest where it holds no chunk. Null skips the pass entirely,
## so an unmasked document dispatches no mask pass at all.
static func coverage_at(layer: SaLayer, grid_pos: Vector2i) -> SaTexture:
    if layer == null or layer.mask == null or not layer.mask.enabled:
        return null
    return layer.mask.coverage(grid_pos)


## What *layer* shows of *source* at *grid_pos*, *node*'s filters and then the
## layer's mask, as [SaLayerShown] says. *neighbours* is what
## `SaFilterChain.filtered` takes, and null answers nothing shows.
func shown(
    node: SaLayer, layer: SaLayer, source: SaTexture, grid_pos: Vector2i, region: Rect2i, neighbours: SaLayer = null
) -> SaTexture:
    return _layer_shown().shown(node, layer, source, grid_pos, region, neighbours)


## *source* hidden by *layer*'s mask at *grid_pos*, or as it is without one.
func masked(layer: SaLayer, source: SaTexture, grid_pos: Vector2i, region: Rect2i) -> SaTexture:
    return _layer_shown().masked(layer, source, grid_pos, region)


## *source* with its alpha multiplied by *mask*'s coverage over *region*: what
## a layer's mask does to its chunk, composited before the next call.
func mask_chunk(source: SaTexture, mask: SaTexture, region: Rect2i) -> SaTexture:
    return _layer_shown().mask_chunk(source, mask, region)


## *source* with its alpha multiplied by *mask*'s, over *region*: what a layer
## clipped to the one below reads as, composited before the next call.
func clip_chunk(source: SaTexture, mask: SaTexture, region: Rect2i) -> SaTexture:
    return _layer_shown().clip_chunk(source, mask, region)


## What a layer clipped to *base* reads its alpha from at *grid_pos*, the base
## as it shows, and null where it holds no chunk. While a canvas is drawn the
## base's chunk is read through `point_preview` as the canvas draws it, so a
## layer clipped to a photograph follows a blur previewed on the photograph the
## way the photograph does, and Cancel, which clears the pass, puts it back.
func clip_alpha(base: SaLayer, grid_pos: Vector2i, region: Rect2i) -> SaTexture:
    var drawn: SaTexture = null
    if SaLayerTypeRegistry.composites(base) != SaLayerTypeRegistry.Composites.GENERATED:
        drawn = point_preview.drawn(self, _drawing, base, base.get_field(grid_pos), grid_pos, region)
    return _layer_shown().clip_alpha(base, drawn, grid_pos, region)


## The fine one inside a display chunk's walk, the flat one everywhere else.
func _layer_shown() -> SaLayerShown:
    return _fine if detail.active() else _flat


## *layer*'s kernel evaluated over *region* of the chunk at *offset*, at
## *format*, as [SaGeneratedLayer.Step] says.
func generate_chunk(layer: SaLayer, offset: Vector2, region: Rect2i, format: int) -> SaTexture:
    return _generated.generate(self, layer, offset, region, format)


## Generates *layer* over *region* and composites it into *target* at
## *offset*, hidden by its own mask.
func composite_generated_chunk(
    target: SaTexture,
    layer: SaLayer,
    mode_id: StringName,
    opacity: float,
    grid_pos: Vector2i,
    offset: Vector2,
    region: Rect2i,
    space: SaColorSpace,
    blend_white: float
) -> void:
    var source: SaTexture = generate_chunk(layer, Vector2(grid_pos * SaLayer.CHUNK_SIZE), region, target.format)
    source = shown(layer, layer, source, grid_pos, region)
    composite_chunk(target, source, mode_id, opacity, offset, space, blend_white, region)


## Clears many output chunks inside a single compute list. Each clear writes its
## own disjoint region, so they need no barrier between them, and one list ends in
## one barrier where a list a chunk would pay one a chunk.
func clear_canvas_chunks(canvas: SaTexture, dirty_regions: Dictionary[Vector2i, Rect2i]) -> void:
    if canvas == null or dirty_regions.is_empty():
        return
    var clear_compute: SaCompute = get_compute("clear")
    clear_compute.use_storage_format(canvas.format)
    clear_compute.set_texture(0, canvas.rid)
    clear_compute.list_begin(clear_compute.index_of_kernel("clear_chunk"))
    for grid_pos: Vector2i in dirty_regions:
        var at := detail.placed(canvas, Vector2(grid_pos * SaLayer.CHUNK_SIZE), dirty_regions[grid_pos], 1.0)
        var offset := at.offset
        var region := at.region
        clear_compute.set_push_constant_float_array(
            PackedFloat32Array([offset.x, offset.y, region.position.x, region.position.y, region.size.x, region.size.y, 0.0, 0.0])
        )
        # Exactly what the passes write, in the destination's own pixels.
        clear_compute.list_dispatch(SaCompute.groups_for(region.size.x), SaCompute.groups_for(region.size.y), 1)
    clear_compute.list_end()


## Flattens all visible layers and the live stroke into *canvas*, *held* and
## *budget* as in [method composite_chunks].
func composite_all_layers(
    canvas: SaTexture,
    document: SaDocument,
    visible_rect: Rect2,
    held: SaCompositeBacklog = null,
    budget: SaCompositeBudget = null
) -> Dictionary[Vector2i, Rect2i]:
    if canvas == null or document == null:
        return {}
    var all_chunks: Dictionary[Vector2i, Rect2i] = {}
    for layer in SaLayerStack.layers(document):
        for grid_pos in layer.chunks:
            all_chunks[grid_pos] = SaDocument.WHOLE_CHUNK
    # A layer that stores nothing contributes everywhere, so every cell is drawn.
    if SaGeneratedLayer.any_in(document):
        for grid_pos in SaLayer.grid_positions(document.canvas_size):
            all_chunks[grid_pos] = SaDocument.WHOLE_CHUNK
    return composite_chunks(canvas, document, all_chunks, visible_rect, true, held, budget)


## Renders the invalidated part of each invalidated chunk into the output canvas.
##
## *dirty_regions* is grid position -> Rect2i in chunk-local pixels, from SaDocument.consume_dirty_chunks().
## Every pass in here uses the same rectangle for a given chunk, the invariant the result depends on:
## the clear and every tier written on top of it must cover the same pixels, or the difference is
## either composited twice or blanked and never redrawn.
##
## *whole* says the regions were gathered from the chunks and never went through
## the document, so they are grown by every halo in it and not by the new ones.
## *held*, when given, takes every grown region *visible_rect* does not reach,
## and with *budget* given too, every one past what this frame pays for.
## Answers the regions walked, which a display chunk is composited over too.
func composite_chunks(
    canvas: SaTexture,
    document: SaDocument,
    dirty_regions: Dictionary[Vector2i, Rect2i],
    visible_rect: Rect2,
    whole: bool = false,
    held: SaCompositeBacklog = null,
    budget: SaCompositeBudget = null
) -> Dictionary[Vector2i, Rect2i]:
    if canvas == null or document == null:
        return {}
    var traced := SaFrameTrace.now()
    if not dirty_regions.is_empty() and document.fold != null:
        document.fold.debt.settle(document)
    SaFrameTrace.spent("fold settle", traced)

    # Derived fields are recomputed before anything reads albedo, so no stale
    # resolve shows. A layer with none returns at once.
    traced = SaFrameTrace.now()
    for layer in SaLayerStack.layers(document):
        layer.resolve_pending()
    SaFrameTrace.spent("resolve pending", traced)

    # Grown by the halo of a record attached or touched since the document grew
    # them, and for the root's filters when they read their neighbours.
    # A layer drawn through a live transform shows its paint where the map
    # takes it, so its regions are walked there too.
    traced = SaFrameTrace.now()
    dirty_regions = SaLiveTransform.refresh(document, dirty_regions, whole)
    var spilled := filter_chain.spilled(document, dirty_regions, whole)
    SaFrameTrace.spent("spill", traced)
    _drawing = document
    traced = SaFrameTrace.now()
    effect.note(document, spilled, not whole)
    SaFrameTrace.spent("effect note", traced)
    if held != null:
        held.hold_outside(spilled, visible_rect, document)
        if budget != null:
            budget.hold_beyond(spilled, held, document)
    traced = SaFrameTrace.now()
    var room := -1 if budget == null else 0 if budget.waits else budget.chunks_per_frame(document)
    effect.refresh(self, document, spilled, held if budget != null else null, room)
    SaFrameTrace.spent("effect refresh", traced)
    var dirty_chunks := filter_chain.root_regions(document, canvas, spilled)
    traced = SaFrameTrace.now()
    adjustment.sweep.walk(self, document, canvas, dirty_chunks, visible_rect, not whole)
    SaFrameTrace.spent("sweep walk", traced)
    # 4. The root's filters over the whole composite, nothing when it has none.
    filter_chain.filter_root(document, canvas, spilled, dirty_chunks)
    _drawing = null
    return dirty_chunks


## Steps 1 to 3 of [method composite_chunks] into *canvas*, cleared over
## *dirty_chunks* already: below the active layer, the active tier, above it,
## as [SaCompositeWalk] draws them. A display chunk's walk comes here and not
## through [method composite_chunks], so this marks the canvas drawn too, and
## gives back what it found for the adjustment sweep's walk inside one.
func walk(canvas: SaTexture, document: SaDocument, dirty_chunks: Dictionary[Vector2i, Rect2i], visible_rect: Rect2) -> void:
    var was := _drawing
    _drawing = document
    _walk.walk(self, canvas, document, dirty_chunks, visible_rect)
    _drawing = was


## One stack entry's chunk into *target* at *offset*, the step a group
## composited afresh takes per member. The walk's `SaFineGroup` is handed this
## as a callable, so the walk reaches the compositor without holding it.
func _composite_entry_chunk(
    target: SaTexture,
    offset: Vector2,
    stack_entry: Dictionary,
    grid_pos: Vector2i,
    region: Rect2i,
    space: SaColorSpace,
    blend_white: float,
    depth: int = 0
) -> void:
    _walk.composite_entry_chunk(self, target, offset, stack_entry, grid_pos, region, space, blend_white, depth)


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        # Free the scratch SaTexture first while the RenderingDevice is still valid.
        _walk = null
        clip_group = null
        _flat = null
        _fine = null
        _generated = null
        adjustment = null
        effect = null
        point_preview = null
        filter_chain = null
        # Dropping SaCompute RefCounted objects triggers their PREDELETE which frees
        # pipeline RIDs and queued uniform set RIDs via GlobalShaderCompiler.
        _cached_computes.clear()
        _mix_computes.clear()
