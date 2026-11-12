## What an adjustment layer's row shows: its records' output over the backdrop
## it reads, the way its own pixels would look were it a painted layer, at a
## reduced size and with its mask left out, because the mask has a picture of
## its own beside it.
##
## The backdrop is the document brought down by a power of two into one plate
## a chunk across. A layer's chunk reaches it as a block of a few texels, and
## no dispatch covers the canvas at full size (hard rule 2, dirty-rect dispatch only). Then the layer's
## records run over the plate through the chain's `filtered`, one dispatch a
## pass over a chunk's worth of texels. A record that reads its neighbours reads
## them at the plate's size, so a blur is approximated there, which a picture
## thirty-two texels across cannot tell apart. Nothing is read back (hard
## rule 1).
##
## **Two ways to the plate, one picture.** The walk of a flatten,
## `SaTreeRender.render_below`, draws any stack: groups, masks, filters, clip
## groups, effect layers. The compositor's display target,
## `SaDetailView.Target`, places every composite of that walk into the plate at
## the reduced density, the way it places one into a display chunk at twice the
## density. But the walk issues a composite a layer a chunk, each its own list
## ended by a barrier, which on a large document of a few layers costs tens of
## milliseconds on the card and more on the CPU. So a backdrop of plain layers, paint
## with no record, transformed or not, grounds, and adjustment layers lifted by
## nothing, each masked or not and a clipping base with its run or not, is
## drawn the quick way, [Quick]: each paint layer's or ground's chunks, and each
## mask's, brought down into a plate of its own by `backdrop_thumbnail.gmacs`,
## one list a plate, and those plates composited in the layers' modes and
## opacities, one dispatch each, with each adjustment run over the plate where
## it stands and a clip run laid through the compositor's `clip_group`.
## Anything else below takes the walk.
##
## **The plates are kept, and only what moved is drawn into them again.** They
## follow the document's `chunks_invalidated`, the positions a stroke, an undo
## or a filter edit moved, and a redraw clears and draws again those alone. All
## of it is drawn again when it is first made, when the document says
## `document_changed`, and when the stack's order, visibility, opacity, modes,
## masks or records moved, which a signature of the layers catches whichever
## path moved them. The records always run over the whole plate, so an edit of
## the layer's own filter shows on the next redraw.
##
## **The walk is paid over frames.** A walk draws a chunk position of the
## plate at a time, and each position walks the whole stack below the layer at
## full size, a few milliseconds a position. A test document of
## 308 layers with 97 adjustment layers in groups made one frame
## of the eye's click walk every one of them, 34 to 116 s of the main thread.
## So a redraw with a deadline draws positions until it passes, keeps
## the rest in [member _due] and answers null with [method pending] true, and
## the row keeps its last picture until a redraw finds nothing due. A redraw
## with no deadline draws them all, which a shot and a suite ask for. A walk of
## the positions a stroke moved waits for the painter to stop, [method waits],
## so a stroke redraws its own layer's row and no adjustment's.
##
## The plate stays in VRAM and the row draws it into its picture with the same
## kernel a layer's chunks are drawn by. The texture handed back is the plate or
## the chain's scratch, so the caller samples it before anything else runs.
class_name SaBackdropThumbnail
extends RefCounted

## The side of the plate in texels, a chunk's, which is also the most the
## document is brought down to.
const PLATE := 256

## The document brought down into one chunk across, transparent where nothing
## is below the layer.
var _plate: SaTexture = null
## The walk the backdrop is drawn by, kept with its scratches for the next
## redraw of the same row.
var _tree: SaTreeRender = null
## The document `_tree` walks and whose signals the plate follows.
var _walked: SaDocument = null
## The reduction the plate was drawn at, so a canvas resize draws it afresh.
var _by: int = 0
## Whether the next redraw draws the whole plate again.
var _whole: bool = true
## The positions moved since the last redraw.
var _stale: Dictionary[Vector2i, bool] = {}
## The stack as the last redraw found it, [method _signature].
var _stack: int = 0
## The canvas the plate was last drawn over, and its colour space.
var drawn_canvas := Vector2i.ZERO
var drawn_space: SaColorSpace = null
## The quick way's plates, while the backdrop is plain enough to take it.
var _quick: Quick = null
## The positions a walk has still to draw into the plate, in the order it
## draws them.
var _due: Array[Vector2i] = []
## What the last position the walk drew took, in microseconds, which the next
## is expected to take as well.
var _position_usec: int = 0
## The frame paint last moved positions in, by `Engine.get_process_frames`,
## which [method _changed] reads.
var _moved_frame: int = -1


## How many document pixels one texel of the plate holds along each edge, the
## least power of two that fits *canvas* into [constant PLATE] texels.
static func reduction(canvas: Vector2i) -> int:
    var longest := maxi(canvas.x, canvas.y)
    var by := 1
    while ceili(float(longest) / float(by)) > PLATE:
        by *= 2
    return by


## The part of the plate the document fills, in plate texels.
static func filled(canvas: Vector2i) -> Rect2i:
    var by := float(reduction(canvas))
    return Rect2i(Vector2i.ZERO, Vector2i(ceili(canvas.x / by), ceili(canvas.y / by)))


## Whether *layer*'s picture is one of these, an adjustment layer's.
static func takes(layer: SaLayer) -> bool:
    return layer.is_adjustment()


## Whether the last [method drawn] left positions of a walk undrawn, so its
## null means "not yet" rather than "nothing". The row has a frame that walked
## drawn even so, because the walk's lists go to the card with a drawn frame:
## on a large test document the frames of a walk drew nothing, and the
## frame its picture showed in sent all their lists at once and its draw waited
## 40 to 150 ms on them.
func pending() -> bool:
    return not _due.is_empty()


## What the next position of a pending walk is expected to take, in
## microseconds, nought when nothing is due.
func next_usec() -> int:
    return _position_usec if pending() else 0


## Whether the next [method drawn] for *layer* of *document* waits for the
## painter to stop: a walk of the positions paint moved, into a plate drawn
## before, with no walk under way, while the idle clock says the painter has
## not stopped. On a large test document those walks were two or
## three frames of 60 to 99 ms after every stroke, each position a few
## milliseconds of the main thread and a draw that sent the lists of every
## frame before it, so the
## row keeps its picture from before the stroke until the painter stops and
## then walks the positions every stroke since has moved. A whole plate does
## not wait, nor does the quick way, which costs a dispatch a layer.
func waits(document: SaDocument, layer: SaLayer) -> bool:
    if document != _walked or _plate == null or not _plate.rid.is_valid() or _whole or _quick != null or pending():
        return false
    if not SaSettingsPerformance.holds_redraw(SaSettingsPerformance.STOPPED):
        return false
    return Quick.layers_below(document, layer).is_empty() and not Quick.reads_nothing(document, layer)


## *layer*'s records run over the backdrop it reads in *document*, the whole
## document in one texture [constant PLATE] across at [method reduction]. Null
## when there is no compositor, or when a walk into a display chunk is in hand,
## which never happens between two frames, where a row redraws. Null as well,
## with [method pending] true, when *until_usec*, a `Time.get_ticks_usec`
## deadline, passed with positions of the walk still to draw. Nought is no
## deadline.
func drawn(document: SaDocument, layer: SaLayer, until_usec: int = 0) -> SaTexture:
    var compositor := document.compositor if document != null else null
    if compositor == null or layer == null or compositor.detail.active():
        return null
    var format := SaFieldSpec.schema_for_space(document.color_space)[0].format
    _follow(document)
    var by := reduction(document.canvas_size)
    if _plate == null or _plate.format != format or by != _by:
        _plate = SaTexture.new(Vector2i(PLATE, PLATE), format)
        _by = by
        _whole = true
    if not _plate.rid.is_valid():
        return null
    drawn_canvas = document.canvas_size
    drawn_space = document.color_space
    var stack := _signature(document)
    _whole = _whole or stack != _stack
    _stack = stack

    var below := Quick.layers_below(document, layer)
    if below.is_empty() and not Quick.reads_nothing(document, layer):
        _quick = null
        _walk(compositor, document, layer, until_usec)
        if pending():
            return null
    else:
        _due.clear()
        if _quick == null:
            _quick = Quick.new()
            _whole = true
        _quick.draw(compositor, document, below, _plate, by, _whole, _stale)
    _whole = false
    _stale.clear()
    return compositor.filter_chain.filtered(layer, _plate, Vector2i.ZERO, filled(document.canvas_size))


## The plate drawn by the walk of a flatten, a chunk position at a time, the
## positions that moved alone unless the whole is due, added to what an earlier
## call left due. Draws at least one position, then each one the time left
## before *until_usec* is expected to pay for, and all of them for nought.
func _walk(compositor: SaCompositor, document: SaDocument, layer: SaLayer, until_usec: int) -> void:
    var block := floori(float(PLATE) / _by)
    if _whole:
        compositor.clear_scratch_batch([[_plate, Rect2i(0, 0, PLATE, PLATE)]])
        _due = SaNodeInput.new(document, layer).positions().duplicate()
    elif not _stale.is_empty():
        var clears: Array = []
        for grid_pos: Vector2i in _stale:
            clears.append([_plate, Rect2i(grid_pos * block, Vector2i(block, block))])
        compositor.clear_scratch_batch(clears)
        for grid_pos: Vector2i in SaNodeInput.new(document, layer).positions():
            if _stale.has(grid_pos) and not _due.has(grid_pos):
                _due.append(grid_pos)
    _whole = false
    _stale.clear()
    var density := 1.0 / float(_by)
    var drew := 0
    while not _due.is_empty():
        var start := Time.get_ticks_usec()
        if until_usec > 0 and drew > 0 and start + _position_usec > until_usec:
            return
        var grid_pos: Vector2i = _due.pop_front()
        # The walk composites at offset nought into a target a chunk across,
        # so the display target's origin is minus the chunk's corner, and each
        # chunk lands at its corner times the density.
        compositor.detail.begin(_plate, -Vector2(grid_pos * SaLayer.CHUNK_SIZE), density)
        _tree.render_below(_plate, grid_pos, layer)
        compositor.detail.end()
        _position_usec = Time.get_ticks_usec() - start
        drew += 1


## Follows *document*'s changes from now, and lets go of the last one's. A new
## document draws the whole plate.
func _follow(document: SaDocument) -> void:
    if document == _walked and _tree != null:
        return
    if is_instance_valid(_walked):
        if _walked.chunks_invalidated.is_connected(_moved):
            _walked.chunks_invalidated.disconnect(_moved)
        if _walked.document_changed.is_connected(_changed):
            _walked.document_changed.disconnect(_changed)
    document.chunks_invalidated.connect(_moved)
    document.document_changed.connect(_changed)
    _walked = document
    _tree = SaTreeRender.new(document)
    _whole = true


func _moved(grid_positions: Array) -> void:
    for grid_pos: Vector2i in grid_positions:
        _stale[grid_pos] = true
    if not grid_positions.is_empty():
        _moved_frame = Engine.get_process_frames()


## A change heard in the frame paint moved is that paint's commit, a stroke's,
## an undo's or a filter's applied, and the positions it moved say what to draw
## again. Every stroke on a large test document ends in one, and it
## walked each adjustment row's whole plate again, 17 frames a row. Any other
## change draws the whole plate, because a record edited below moves no
## position the plate hears of. A change of the stack is the signature's.
func _changed() -> void:
    if _moved_frame != Engine.get_process_frames():
        _whole = true


## What of the stack the backdrop depends on beyond the paint: each layer, its
## place, whether it shows, its opacity and its mode.
static func _signature(document: SaDocument) -> int:
    var stack: Array = []
    for child in document.get_children():
        var layer := child as SaLayer
        if layer != null:
            var masked := layer.mask != null and layer.mask.enabled
            var parent := SaLayerStack.parent_of(layer)
            (
                stack
                . append(
                    [
                        layer.get_instance_id(),
                        parent.get_instance_id() if parent != null else 0,
                        layer.visible,
                        layer.opacity,
                        layer.get_blend_mode_name(),
                        masked,
                        SaFilterChain.has_enabled(layer.filters),
                    ]
                )
            )
    return hash(stack)


## The quick way to the plate: each plain layer below brought down into a
## plate of its own, one compute list a layer, and the plates composited in
## order. Kept between redraws, so a dab brings down its chunks alone.
class Quick:
    extends RefCounted

    const SHADER_NAME := "backdrop_thumbnail"
    ## The chunks one dispatch brings down, the kernel's sampler slots.
    const SLOTS := 16

    ## A layer's instance id to its plate.
    var _plates: Dictionary[int, SaTexture] = {}
    ## A masked layer's instance id to its mask brought down, one channel.
    var _masks: Dictionary[int, SaTexture] = {}
    var _compute: SaCompute = null
    ## An adjustment's output made opaque, and the backdrop it is blended
    ## over, for [method _adjust].
    var _adjusted: SaTexture = null
    var _solid: SaTexture = null

    ## The layers *layer* reads as its backdrop that contribute, bottom first,
    ## when every one of them is plain, and empty otherwise or when there is
    ## none. Plain is a paint layer with no record, whose live transform, when
    ## it has one, is drawn from its cache as the walk does, a ground with no
    ## record, or an adjustment layer lifted by nothing, at the top level of
    ## its scope, masked or not, clipped or a clipping base or neither. A row
    ## whose own layer is clipped reads the base's plate, which the walk draws.
    static func layers_below(document: SaDocument, layer: SaLayer) -> Array[SaLayer]:
        var found: Array[SaLayer] = []
        var scope := SaTreeRender.scope_of(layer)
        if SaLayerStack.parent_of(layer) != scope or SaLayerStack.clip_base(document, layer) != null:
            return found
        for node: SaLayer in SaLayerStack.members(document, scope):
            if node == layer:
                return found
            if not SaLayerStack.contributes(document, node):
                continue
            if not plain(document, node):
                return [] as Array[SaLayer]
            found.append(node)
        return found

    ## Whether every layer *layer* would read is hidden or missing, so the
    ## plate is transparent and the quick way draws it so.
    static func reads_nothing(document: SaDocument, layer: SaLayer) -> bool:
        var scope := SaTreeRender.scope_of(layer)
        if SaLayerStack.parent_of(layer) != scope:
            return false
        for node: SaLayer in SaLayerStack.members(document, scope):
            if node == layer:
                return true
            if node.visible:
                return false
        return true

    ## An adjustment layer lifted by nothing is plain too: its records run
    ## over the plate as it stands at its place, at the plate's size, as the
    ## row's own records do. The walk drew it a chunk at a time, and a blur
    ## over another blur drew the chunks around each chunk again through the
    ## one below, nine times as many a layer, so the ten blurs of the l1
    ## scenario stalled the frame and grew past 14G of host memory. A mask
    ## is brought down as a plate of its own and a clip run is laid through
    ## `clip_group` on plates, so neither sends the stack back to that walk,
    ## where a clipped blur's halo drew the clip group that drew it again
    ## until the script's stack ran out.
    static func plain(_document: SaDocument, node: SaLayer) -> bool:
        if node.is_group or node.is_effect():
            return false
        if node.is_adjustment():
            return not SaBackdropLayer.lifts(node)
        return not SaFilterChain.has_enabled(node.filters)

    ## Brings *layers* down into their plates, over *stale* alone when
    ## *whole* is false and wholly otherwise, and composites them into *plate*.
    func draw(
        compositor: SaCompositor,
        document: SaDocument,
        layers: Array[SaLayer],
        plate: SaTexture,
        by: int,
        whole: bool,
        stale: Dictionary[Vector2i, bool]
    ) -> void:
        var side := floori(float(SaBackdropThumbnail.PLATE) / by)
        var all := Rect2i(0, 0, SaBackdropThumbnail.PLATE, SaBackdropThumbnail.PLATE)
        var kept: Dictionary[int, SaTexture] = {}
        var masks: Dictionary[int, SaTexture] = {}
        var clears: Array = []
        var lists: Array = []
        for layer in layers:
            if layer.mask != null and layer.mask.enabled:
                masks[layer.get_instance_id()] = _mask_down(compositor, document, layer, plate.size, whole, stale, side)
            if layer.is_adjustment():
                continue
            var id := layer.get_instance_id()
            var own: SaTexture = _plates.get(id, null)
            var fresh := own == null or own.format != plate.format
            if fresh:
                own = SaTexture.new(plate.size, plate.format)
            kept[id] = own
            var positions: Array[Vector2i] = []
            if whole or fresh:
                clears.append([own, all])
                positions = _held(document, layer)
            else:
                for grid_pos: Vector2i in stale:
                    clears.append([own, Rect2i(grid_pos * side, Vector2i(side, side))])
                for grid_pos: Vector2i in _held(document, layer):
                    if stale.has(grid_pos):
                        positions.append(grid_pos)
            lists.append([layer, own, positions])
        _plates = kept
        compositor.clear_scratch_batch(clears)
        for entry: Array in lists:
            _bring_down(compositor, entry[0], entry[1], entry[2], side)

        var space := document.color_space
        var white := document.blend_reference_white
        _masks = masks
        compositor.clear_scratch_batch([[plate, all]])
        var region := SaBackdropThumbnail.filled(document.canvas_size)
        for layer in layers:
            if SaLayerStack.clip_base(document, layer) != null:
                continue
            var run: Array[SaLayer] = []
            for member in SaLayerStack.clipped_run(document, layer):
                if layers.has(member):
                    run.append(member)
            if run.is_empty():
                _lay(compositor, layer, plate, all, region, space, white)
                continue
            var lay_base := func(into: SaTexture) -> void:
                var shown := _shown(compositor, layer, all)
                compositor.composite_chunk(into, shown, SaLayer.BLEND_MODE.NORMAL, 1.0, Vector2.ZERO, space, white, all)
            var lay_clipped := func(into: SaTexture) -> void:
                for member in run:
                    _lay(compositor, member, into, all, region, space, white)
            var mode := layer.get_blend_mode_name()
            compositor.clip_group.composite(
                compositor, plate, Vector2.ZERO, all, mode, layer.opacity, space, white, lay_base, lay_clipped
            )

    ## *layer* laid over *plate*: an adjustment run over it, and a paint
    ## layer's or ground's plate, through its mask, composited in its mode.
    func _lay(
        compositor: SaCompositor, layer: SaLayer, plate: SaTexture, all: Rect2i, region: Rect2i, space: SaColorSpace, white: float
    ) -> void:
        if layer.is_adjustment():
            _adjust(compositor, layer, plate, region, space, white)
            return
        compositor.composite_chunk(
            plate, _shown(compositor, layer, all), layer.get_blend_mode_name(), layer.opacity, Vector2.ZERO, space, white, all
        )

    ## *layer*'s plate as it shows, through its mask's plate when it has one,
    ## in the compositor's mask scratch, read before the next masking call.
    func _shown(compositor: SaCompositor, layer: SaLayer, all: Rect2i) -> SaTexture:
        var own := _plates[layer.get_instance_id()]
        var mask: SaTexture = _masks.get(layer.get_instance_id(), null)
        return own if mask == null else compositor.mask_chunk(own, mask, all)

    ## *layer*'s mask brought down into a one channel plate of its own: the
    ## whole of it, cleared to the mask's rest first, when *whole* is true or
    ## the plate is new, and the *stale* positions alone otherwise, each read
    ## through the mask's `absent` texture where it holds no chunk.
    func _mask_down(
        compositor: SaCompositor,
        document: SaDocument,
        layer: SaLayer,
        size: Vector2i,
        whole: bool,
        stale: Dictionary[Vector2i, bool],
        side: int
    ) -> SaTexture:
        var mask := layer.mask
        var own: SaTexture = _masks.get(layer.get_instance_id(), null)
        var fresh := own == null
        if fresh:
            own = SaTexture.new(size, SaSelection.FORMAT)
        var positions: Array[Vector2i] = []
        if whole or fresh:
            own.clear(Color(mask.rest, mask.rest, mask.rest, mask.rest))
            positions = mask.grid_positions()
        else:
            var canvas := Rect2i(Vector2i.ZERO, SaLayer.grid_positions(document.canvas_size).back() + Vector2i.ONE)
            for grid_pos: Vector2i in stale:
                if canvas.has_point(grid_pos):
                    positions.append(grid_pos)
        var sources: Array[SaTexture] = []
        for grid_pos in positions:
            var held := mask.texture_for(grid_pos)
            sources.append(held if held != null else mask.absent())
        _down(compositor, own, sources, positions, side)
        return own

    ## *layer*, an adjustment, over *region* of *plate*, the steps
    ## `SaBackdropLayer` takes over a chunk with no halo: its records over the
    ## plate, both made opaque, the output masked, blended over the backdrop in
    ## the layer's mode and opacity, and the backdrop's alpha kept.
    func _adjust(
        compositor: SaCompositor, layer: SaLayer, plate: SaTexture, region: Rect2i, space: SaColorSpace, white: float
    ) -> void:
        var mode := layer.get_blend_mode_name()
        if not SaBackdropLayer.changes(layer, mode):
            return
        var out := compositor.filter_chain.filtered(layer, plate, Vector2i.ZERO, region)
        if out == null:
            return
        if _adjusted == null or _adjusted.format != plate.format or _adjusted.size != out.size:
            _adjusted = SaTexture.new(out.size, plate.format)
        if _solid == null or _solid.format != plate.format:
            _solid = SaTexture.new(plate.size, plate.format)
        _kernel(compositor, "opaque", _adjusted, out, region, space, white)
        _kernel(compositor, "opaque", _solid, plate, region, space, white)
        var mask: SaTexture = _masks.get(layer.get_instance_id(), null)
        var source := _adjusted if mask == null else compositor.mask_chunk(_adjusted, mask, region)
        compositor.composite_chunk(_solid, source, mode, layer.opacity, Vector2.ZERO, space, white, region)
        _kernel(compositor, "keep_alpha", plate, _solid, region, space, white)

    ## One of the kernels `composite.gmacs` ends on, *source* into
    ## *destination* over *region*.
    static func _kernel(
        compositor: SaCompositor,
        kernel: String,
        destination: SaTexture,
        source: SaTexture,
        region: Rect2i,
        space: SaColorSpace,
        white: float
    ) -> void:
        var compute := compositor.get_compute("composite")
        compute.use_storage_format(destination.format)
        compute.set_texture(0, destination.rid)
        compute.set_texture(1, source.rid)
        compute.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0, space, 1.0, white, region))
        compute.dispatch_kernel(kernel, SaCompute.groups_for(region.size.x), SaCompute.groups_for(region.size.y), 1)

    ## The positions *layer* draws on: its chunks, or its cache's while it
    ## carries a live transform, or the whole canvas for a ground.
    static func _held(document: SaDocument, layer: SaLayer) -> Array[Vector2i]:
        var positions: Array[Vector2i] = []
        if layer.is_generated():
            return SaLayer.grid_positions(document.canvas_size)
        positions.assign(SaLiveTransform.paint_of(layer).chunks.keys())
        return positions

    ## *positions* of *layer* brought down into *own*, [constant SLOTS] chunks
    ## a dispatch in one list. A ground is generated once, at the first chunk,
    ## and brought down into every block, which at a texel per several pixels
    ## is its look all over.
    func _bring_down(compositor: SaCompositor, layer: SaLayer, own: SaTexture, positions: Array[Vector2i], side: int) -> void:
        if positions.is_empty():
            return
        var ground: SaTexture = null
        if layer.is_generated():
            ground = compositor.generate_chunk(layer, Vector2.ZERO, SaDocument.WHOLE_CHUNK, own.format)
        var paint := SaLiveTransform.paint_of(layer)
        var sources: Array[SaTexture] = []
        for grid_pos in positions:
            sources.append(ground if ground != null else paint.get_field(grid_pos))
        _down(compositor, own, sources, positions, side)

    ## *sources*, each the chunk at its place in *positions*, brought down into
    ## their blocks of *own*, [constant SLOTS] a dispatch in one list.
    func _down(_compositor: SaCompositor, own: SaTexture, all: Array[SaTexture], positions: Array[Vector2i], side: int) -> void:
        if _compute == null and not GlobalShaderCompiler.get_kernel_names(SHADER_NAME).is_empty():
            _compute = SaCompute.new(SHADER_NAME)
        if _compute == null:
            return
        var sources: Array[SaTexture] = []
        var corners := PackedFloat32Array()
        for i in positions.size():
            var source := all[i]
            if source == null or not source.rid.is_valid():
                continue
            sources.append(source)
            var corner := positions[i] * side
            corners.append(float(corner.x + corner.y * own.size.x))
        if sources.is_empty():
            return
        var groups := SaCompute.groups_for(side)
        _compute.use_storage_format(own.format)
        _compute.set_texture(0, own.rid)
        _compute.list_begin(0)
        for first in range(0, sources.size(), SLOTS):
            var count := mini(SLOTS, sources.size() - first)
            var params := PackedFloat32Array([float(side), float(count)])
            for slot in SLOTS:
                # A slot past the count is never read, but still bound.
                var at := first + mini(slot, count - 1)
                _compute.set_sampled_texture(1 + slot, sources[at].rid)
                params.append(corners[at])
            _compute.set_push_constant_float_array(params)
            _compute.list_dispatch(groups, groups, SLOTS)
        _compute.list_end()
