## Apply and cancel, the two ways a filter's dialog ends, and the guarded call
## its `run` is made through.
##
## Apply is the only thing in the whole filter door that writes to a layer. A
## filter's `run` is handed an [SaFilterContext], which can read the layer and
## hand back a result, and has no way to touch a chunk. That is what makes
## cancel free: dropping the context is the whole of it, because nothing was
## ever written, and it is what makes a `run` that dies halfway harmless.
##
## Static, like `SaExport`. There is no state between an apply and the next one,
## and a filter that had to construct something before it could commit would be
## one more thing a student has to learn.
class_name SaFilterApply
extends RefCounted

## The kernel that sets a word wherever a texel differs from a blank, the one
## a save sweeps its chunks with, named by its file so the filter door needs
## nothing else of the save.
const SWEEP := "sad_snapshot_sweep"


## Writes the last shown texture into *layer* over the rectangle the run
## covered, as one undo step called *step_name*. Answers whether it wrote.
##
## GPU to GPU, one `texture_copy` per chunk the rectangle reaches when no
## selection is active: the result was made in VRAM and it stays there. A
## selection blends the result into what was there instead,
## through `apply_masked.gmacs`, so a filter under a lasso, an ellipse or a
## feathered selection stops writing outside it. Chunks are allocated where the
## rectangle reaches and none were, and those go into the undo state as null,
## which is the swap action's own spelling of "there was no tile here", so undo
## removes them again rather than leaving empty ones behind.
##
## *kept*, a dictionary of layer to pixel state, takes the write's undo state
## under the layer in place of a step, here and in the two walks below, so a
## bake into a group's layers is one step (`SaFilterOps.bake_under`).
static func apply(ctx: SaFilterContext, step_name: String, kept: Variant = null) -> bool:
    if ctx == null or refuses_bake(step_name, ctx.layer):
        return false
    if ctx.point is SaNeighbourhoodPass:
        var gather: SaNeighbourhoodPass = ctx.point
        return apply_neighbourhood(ctx.document, ctx.layer, gather, ctx.kernel(gather.shader), step_name, kept)
    if ctx.point != null:
        return apply_point(ctx.document, ctx.layer, ctx.point, ctx.kernel(ctx.point.shader), step_name, kept)
    if ctx.shown == null:
        SaProblems.report("SaFilterApply", "there is nothing to apply, the filter never called show().")
        return false
    var rect := ctx.shown_rect
    if rect.size.x <= 0 or rect.size.y <= 0:
        SaProblems.report("SaFilterApply", "the result covers an empty rectangle, so there is nothing to write.")
        return false

    # Read from the context rather than passed in beside it: a document and a
    # layer given twice are a document and a layer that can disagree, and the
    # pair the result was made from is the only pair it may be written to.
    var document: SaDocument = ctx.document
    var layer: SaLayer = ctx.layer
    var rd := GlobalShaderCompiler.get_rd()
    if document == null or layer == null or rd == null:
        return false
    var selection: SaSelection = document.selection
    var masked := selection != null and selection.active
    var mask_compute: SaCompute = null
    var side := SaFilterDensity.side_of(layer)
    var masks := SaFilterDensity.Masks.new()

    var state: Dictionary[Vector2i, Variant] = {}
    var touched: Array[Vector2i] = []
    for grid_pos in _grid_positions(rect):
        var mask: SaTexture = null
        if masked:
            # Null is a selection that leaves this chunk out entirely, so there
            # is nothing here to blend and no chunk worth allocating for it.
            mask = selection.texture_for(grid_pos)
            if mask == null:
                continue
        # The chunk's share in its own texels and where it sits in the shown
        # texture, which is at the layer's density.
        var placed := SaFilterDensity.place(grid_pos, rect, side)
        var local: Rect2i = placed[0]
        var at: Rect2i = placed[1]
        if local.size.x <= 0 or local.size.y <= 0:
            continue
        var existing: SaChunk = layer.chunks.get(grid_pos, null)
        state[grid_pos] = _snapshot(layer, grid_pos, existing, local)
        var chunk := layer.get_or_create_chunk(grid_pos)
        var destination := chunk.field(SaFieldSpec.ALBEDO)
        if destination == null:
            state.erase(grid_pos)
            continue
        if mask != null:
            if mask_compute == null:
                mask_compute = SaCompute.new("apply_masked")
            _blend_masked(mask_compute, ctx.shown, destination, masks.at(mask, side), at.position - local.position, local)
        else:
            SaFilterDensity.copy_share(rd, destination, grid_pos, rect, ctx.shown, false)
        layer.mark_unresolved(grid_pos)
        touched.append(grid_pos)

    if touched.is_empty():
        return false
    return _recorded(document, layer, state, step_name, kept)


## Why *layer* takes no *way* of a filter dialog's Apply, `bake`, `attach` or
## `layer`, translated, or an empty string when it takes it. The one place the
## dialog dims a way from and a suite asks.
##
## Bake writes paint, so a layer that stores none, an adjustment, an effect or
## a generated layer, refuses it with its kind's `STORE` sentence, and any
## other the brush refuses, a locked or a scene layer, with the line the brush
## says. The kind goes first, because unlocking gives no such kind paint. A
## group bakes into its paint layers, and with *every*, the dialog's Affect
## all, Bake reaches every layer of the picture, so either refuses it only
## when no layer it reaches takes paint, with `SaFilterOps.bake_refusal`'s
## sentence. Attach and Layer write no pixel, and `SaFilterOps.attach` hangs a
## record on a group and on a locked layer as on any other, so neither
## refuses a layer.
static func way_refusal(layer: SaLayer, way: StringName, every: bool = false) -> String:
    if layer == null or way != &"bake":
        return ""
    var document := layer.get_parent() as SaDocument
    if document != null and (every or layer.is_group):
        return SaFilterOps.new(document).bake_refusal(null if every else layer)
    # The kinds' table reads no document for a sentence.
    var stores := SaLayerRefusals.new(null).sentence(SaLayerRefusals.Act.STORE, layer)
    if not stores.is_empty():
        return TranslationServer.translate(stores) % layer.name
    return SaContext.paint_refusal_line(layer, TranslationServer.translate("filter"))


## Refuses a bake into *layer* with `way_refusal`'s sentence in the corner,
## under *title*, and answers whether it did. What every write of a one-shot
## asks first, so a caller that reached one past the dialog's dimmed Bake
## hears why nothing was written.
static func refuses_bake(title: String, layer: SaLayer) -> bool:
    if layer == null:
        return false
    if SaLayerRefusals.new(null).refuses(title, SaLayerRefusals.Act.STORE, layer):
        return true
    if not layer.refuses_paint():
        return false
    SaProblems.refuse(title, SaContext.paint_refusal_line(layer, TranslationServer.translate("filter")))
    return true


## Walks *recorded* once over every chunk of *layer* the selection reaches, through
## *compute*, as one history step called *step_name*. Answers whether it wrote.
##
## The point path, and the one the adjustments take as well, so the preview the
## compositor runs from the same record and this cannot disagree. Nothing is
## allocated but the undo: each chunk is snapshotted as the walk asks for it,
## which is the last moment before the kernel writes over what it records, and
## rewritten in place. A position with no chunk is nothing to rewrite, so a
## point pass never allocates one. The selection is the kernel's to read per
## pixel, and the walk skips a chunk it leaves out.
static func apply_point(
    document: SaDocument, layer: SaLayer, recorded: SaPointPass, compute: SaCompute, step_name: String, kept: Variant = null
) -> bool:
    if document == null or layer == null or recorded == null or compute == null:
        return false
    if refuses_bake(step_name, layer):
        return false
    var state: Dictionary[Vector2i, SaChunk] = {}
    var selection := document.selection
    var snapshot := func(grid_pos: Vector2i) -> SaChunk:
        var chunk: SaChunk = layer.chunks.get(grid_pos, null)
        if chunk == null or selection.texture_for(grid_pos) == null:
            return null
        state[grid_pos] = layer.duplicate_chunk(grid_pos)
        return chunk
    # The walk covers whole chunks, so every stop starts at the chunk's own
    # origin and the push constant's origin is the walk's aligned start. The
    # chunk's document corner goes beside it for a kernel that asks for one.
    var push := func(grid_pos: Vector2i, _local: Rect2i, start: Vector2i) -> PackedFloat32Array:
        return recorded.push_for(start, grid_pos * SaChunk.SIZE)
    # The selection is bound here rather than by the walk, at the chunk's
    # density, so a kernel reading its mask at its own texel reads the pixel
    # that texel lies in on a layer at 2.0 as well.
    var masks := SaFilterDensity.Masks.new()
    var bindings := func(grid_pos: Vector2i) -> Dictionary[int, Variant]:
        var bound: Dictionary[int, Variant] = {}
        bound.assign(recorded.buffers)
        bound[SaSelection.BINDING] = masks.at(selection.texture_for(grid_pos), layer.chunks[grid_pos].pixel_size())
        return bound
    var walk := SaChunkWalk.new(compute, null, layer)
    walk.run(recorded.kernel, SaChunkWalk.reach_of(layer.chunks.keys()), snapshot, push, bindings)
    if state.is_empty():
        return false
    return _recorded(document, layer, state, step_name, kept)


## Walks the neighbourhood pass *recorded* over every chunk of *layer* and the
## ring of positions around them its halo reaches, through *compute*, as one
## history step called *step_name*. Answers whether it wrote.
##
## Every chunk is filtered before any is written, because a neighbour has to be
## read as it was and not as the walk left it: each answer goes into a texture
## of its own, and the writes follow in a second loop. That is one chunk-sized
## texture per chunk written, rather than two over the whole rectangle the
## layer covers. The ring is allocated where the halo carries paint past the
## painted chunks, and a ring position the selection leaves out is skipped. A
## ring position whose answer came out transparent in every texel is skipped
## too, found by `_paint_reached` on the card, so a blur of paint far from a
## chunk's edge leaves the grid as it was and a second blur does not grow it
## by a ring of empty chunks round the first one's. A position that
## had no chunk goes into the undo state as null, so undo removes it again.
##
## A pass that reads the whole node gathers the layer's chunks into one texture
## before the first chunk is filtered and reads that, the same gather the
## compositor's chain makes, so the one-shot and the attached form still cannot
## disagree. Its halo is zero, so it writes the chunks the layer holds, and
## past them the positions its declaration says its paint lands on, allocated
## as the ring is: a wrap of a layer that holds one chunk writes where that
## chunk moved to as well.
static func apply_neighbourhood(
    document: SaDocument,
    layer: SaLayer,
    recorded: SaNeighbourhoodPass,
    compute: SaCompute,
    step_name: String,
    kept: Variant = null
) -> bool:
    if document == null or layer == null or recorded == null or compute == null:
        return false
    if refuses_bake(step_name, layer):
        return false
    var format: int = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    var spec := SaFieldSpec.find(layer.schema, SaFieldSpec.ALBEDO)
    if spec != null:
        format = spec.format
    var runner := SaNeighbourhoodPass.Runner.new()
    runner.reads_canvas_of(document)
    # A chunk of the layer's own side, 512 texels on a layer at twice the
    # document's resolution, and the selection enlarged to it.
    var side := SaFilterDensity.side_of(layer)
    var whole := Rect2i(Vector2i.ZERO, Vector2i(side, side))
    var masks := SaFilterDensity.Masks.new()
    var node: SaNeighbourhoodPass.Whole = null
    if recorded.whole():
        if side != SaChunk.SIZE:
            SaProblems.refuse(
                step_name,
                (
                    TranslationServer.translate(
                        "%s reads the whole layer, which a layer at twice the resolution does not offer yet."
                    )
                    % step_name
                )
            )
            return false
        node = runner.gather(layer.chunks.keys(), layer.get_field, format)
    var answers: Dictionary[Vector2i, SaTexture] = {}
    for grid_pos: Vector2i in neighbourhood_reach(document, layer, recorded):
        var mask := masks.at(document.selection.texture_for(grid_pos), side)
        if mask == null:
            continue
        var answer := SaTexture.new(whole.size, format)
        if node != null:
            runner.run_whole(recorded, compute, answer, node, grid_pos, whole, mask)
        else:
            runner.run(recorded, compute, answer, layer.get_field(grid_pos), layer.get_field, grid_pos, whole, mask)
        answers[grid_pos] = answer
    if node == null:
        _paint_reached(answers, layer)
    if answers.is_empty():
        return false
    var copier := SaCompute.new("copy_region")
    var state: Dictionary[Vector2i, SaChunk] = {}
    for grid_pos: Vector2i in answers:
        state[grid_pos] = layer.duplicate_chunk(grid_pos) if layer.chunks.has(grid_pos) else null
        var destination := layer.get_or_create_chunk(grid_pos).field(SaFieldSpec.ALBEDO)
        if destination == null:
            state.erase(grid_pos)
            continue
        var answer: SaTexture = answers[grid_pos]
        copier.use_storage_format(answer.format)
        copier.set_texture(0, destination.rid)
        copier.set_texture(1, answer.rid)
        copier.set_push_constant_float_array(PackedFloat32Array([0.0, 0.0, 0.0, 0.0, whole.size.x, whole.size.y, 0.0, 0.0]))
        copier.dispatch_kernel("copy_region", SaCompute.groups_for(whole.size.x), SaCompute.groups_for(whole.size.y), 1)
        layer.mark_unresolved(grid_pos)
    if state.is_empty():
        return false
    return _recorded(document, layer, state, step_name, kept)


## The grid positions *recorded* over *layer* writes: every allocated chunk,
## and when the halo is not zero the eight around each that lie on the canvas,
## since paint within the halo of a chunk's edge spills into them. A pass that
## reads the whole node answers where it declares its paint lands instead.
static func neighbourhood_reach(document: SaDocument, layer: SaLayer, recorded: SaNeighbourhoodPass) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    if recorded.whole():
        out.assign(recorded.lands_on(layer.chunks.keys(), document.canvas_size).keys())
        return out
    var halo := recorded.halo()
    var grid := Vector2i(ceili(float(document.canvas_size.x) / SaChunk.SIZE), ceili(float(document.canvas_size.y) / SaChunk.SIZE))
    var found: Dictionary[Vector2i, bool] = {}
    for grid_pos: Vector2i in layer.chunks.keys():
        found[grid_pos] = true
        if halo <= 0:
            continue
        for dy: int in [-1, 0, 1]:
            for dx: int in [-1, 0, 1]:
                var at: Vector2i = grid_pos + Vector2i(dx, dy)
                if at.x >= 0 and at.y >= 0 and at.x < grid.x and at.y < grid.y:
                    found[at] = true
    out.assign(found.keys())
    return out


## Drops from *answers* every position *layer* holds no chunk at whose answer
## is its blank in every texel, compared bit for bit, so a ring position the
## halo carried no paint into is never allocated nor put in the undo step.
##
## One word a position on the card, set by the save's sweep kernel, and read
## back once, at an explicit Apply and never in a stroke: a kernel's result,
## a word a ring position, and never a texel of the canvas. A position the
## read cannot answer for is kept, since writing an empty chunk only costs
## memory and leaving one out would lose paint. A pass that reads the whole
## node does not come here, because its declaration already names where its
## paint lands.
static func _paint_reached(answers: Dictionary[Vector2i, SaTexture], layer: SaLayer) -> void:
    var ring: Array[Vector2i] = []
    for grid_pos: Vector2i in answers:
        if not layer.chunks.has(grid_pos):
            ring.append(grid_pos)
    if ring.is_empty() or GlobalShaderCompiler.get_rd() == null:
        return
    var words := PackedByteArray()
    words.resize(4 * ring.size())
    words.fill(0)
    var flags := SaCompute.Buffer.new(words)
    var sweep := SaCompute.new(SWEEP)
    for slot: int in ring.size():
        var answer: SaTexture = answers[ring[slot]]
        var params := {"blank": Color(0, 0, 0, 0), "width": answer.size.x, "height": answer.size.y, "channels": 4, "slot": slot}
        sweep.run(SWEEP, {"field": answer, "flags": flags}, params, Rect2i(Vector2i.ZERO, answer.size))
    var back := flags.read()
    if back.size() < words.size():
        return
    for slot: int in ring.size():
        if back.decode_u32(4 * slot) == 0:
            answers.erase(ring[slot])


## One chunk's share of Apply under a selection: *destination* becomes
## `mix(destination, filtered, mask)` over *local*, through `apply_masked.gmacs`.
##
## *local* is in the chunk's own texels, and *filtered_offset* is how far a
## texel of *filtered* (`ctx.shown`) sits from the chunk's texel it lands on,
## both at the layer's density, and *mask* is the selection at that density
## too. The dispatch aligns to the workgroup grid the way every chunk-local
## kernel in the tree does (`SaChunkWalk._aligned_start`), because a workgroup
## is dispatched whole.
static func _blend_masked(
    compute: SaCompute, filtered: SaTexture, destination: SaTexture, mask: SaTexture, filtered_offset: Vector2i, local: Rect2i
) -> void:
    var workgroup := SaCompute.WORKGROUP_SIZE
    var start := Vector2i(
        floori(float(local.position.x) / workgroup) * workgroup, floori(float(local.position.y) / workgroup) * workgroup
    )
    var covered := Vector2i(local.end.x - start.x, local.end.y - start.y)
    compute.use_storage_format(destination.format)
    compute.set_texture(0, destination.rid)
    compute.set_texture(1, filtered.rid)
    compute.set_texture(2, mask.rid)
    compute.set_push_constant_float_array(
        PackedFloat32Array([start.x, start.y, filtered_offset.x, filtered_offset.y, covered.x, covered.y])
    )
    compute.dispatch_kernel("apply_masked", SaCompute.groups_for(covered.x), SaCompute.groups_for(covered.y), 1)


## Calls *filter*'s `run` with everything a failure needs to be legible.
##
## Answers whether the run produced a result, which is what a dialog gates its
## apply button on. GDScript has no exceptions and no catch, so a run that dies
## inside cannot be intercepted here. What can be promised is the half that
## matters: the context it was handed has no writer, so the layer is untouched
## whatever happened, and a run that came back with nothing to show says so in
## the console naming the student's own file and the line `run` starts on.
##
## `run` is abstract on `SaFilter`, so a filter that forgot it never parsed and
## its module was refused at load with a sentence naming the method.
static func call_run(filter: SaFilter, ctx: SaFilterContext) -> bool:
    if filter == null or ctx == null:
        SaProblems.report("SaFilterApply", "a filter cannot run without both a filter and a context.")
        return false
    filter.run(ctx)
    if ctx.shown == null and ctx.point == null:
        SaProblems.report(
            "SaFilterApply", "%s came back without showing a result, so the layer was left alone." % source_of(filter)
        )
        return false
    return true


## Where *filter* is written, as `res://path.gd:line` when the line can be
## found and the path alone when it cannot.
##
## The line is where `run` begins, not where an error happened: GDScript hands a
## caller no way to learn the second. Where a student's file opens is still the
## question the message has to answer, and a filter is forty lines long.
static func source_of(filter: Object) -> String:
    if filter == null:
        return "an unnamed filter"
    var script: Script = filter.get_script()
    if script == null:
        return "an unnamed filter"
    var path := script.resource_path
    if path.is_empty():
        return "an unsaved filter script"
    # `source_code` is empty in an exported build, where the script is bytecode
    # and there is no text to count lines in. The path on its own still opens
    # the right file.
    var lines := script.source_code.split("\n")
    for index in lines.size():
        if lines[index].strip_edges().begins_with("func run("):
            return "%s:%d" % [path, index + 1]
    return path


## What undo has to put back for one chunk: the region as it stands, or null
## where there is no chunk at all yet.
##
## Null is not "nothing to record". It is the swap action's own spelling of a
## tile that did not exist, and it is what makes an apply that allocated chunks
## undo into the layer that was there rather than into a layer of empty ones.
## A capture that comes back null, which is a region that clipped away to
## nothing, falls back to the whole tile rather than to that spelling, because
## the two mean opposite things.
static func _snapshot(layer: SaLayer, grid_pos: Vector2i, existing: SaChunk, local: Rect2i) -> Variant:
    if existing == null:
        return null
    var delta := SaChunkDelta.capture(existing, local)
    if delta != null:
        return delta
    return layer.duplicate_chunk(grid_pos)


## What every write ends on: *state*, what *layer* held where the write
## landed, recorded as one step named *step_name*, or handed to the dictionary
## *kept* under *layer* with no step, for a caller that commits many layers as
## one. Answers true, since there was a write.
static func _recorded(document: SaDocument, layer: SaLayer, state: Dictionary, step_name: String, kept: Variant) -> bool:
    if kept is Dictionary:
        var states: Dictionary = kept
        states[layer] = state
        return true
    document.record_pixel_step(step_name, layer, state)
    document.invalidate_chunks(state.keys(), layer)
    document.modified = true
    document.document_changed.emit()
    return true


## Every chunk grid position *rect* reaches.
static func _grid_positions(rect: Rect2i) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    var first := Vector2i(floori(float(rect.position.x) / SaChunk.SIZE), floori(float(rect.position.y) / SaChunk.SIZE))
    var last := Vector2i(floori(float(rect.end.x - 1) / SaChunk.SIZE), floori(float(rect.end.y - 1) / SaChunk.SIZE))
    for y in range(first.y, last.y + 1):
        for x in range(first.x, last.x + 1):
            out.append(Vector2i(x, y))
    return out
