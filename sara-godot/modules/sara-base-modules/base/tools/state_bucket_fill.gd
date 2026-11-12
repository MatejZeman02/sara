## The fill tool: a click floods a region and paints it.
##
## **Nothing here is a new flood, and nothing here is a new kernel.** The
## compute pass that grows a region from the clicked texel, chunk by chunk,
## allocating only what it reaches and stopping when a pass flips nothing, is
## `SaWand`, written for the magic wand, and `shaders/compute/fill.gmacs` is
## the masked fill a selection uses. Two floods that have to agree is a defect
## waiting to happen, so this wires the two together.
##
## The shape of one fill:
##
## 1. `SaWand.flood` grows the region from the clicked texel into the document's
##    selection, in the tolerance, contiguous or global, from this layer or the
##    merged picture.
## 2. The painter's own selection is put back, and the region is intersected with
##    it when it was active, so a fill never lands outside a selection.
## 3. Each chunk the region reached is allocated on the layer and dispatched
##    through the `fill` kernel with that chunk's mask, which is hard rule 2 and
##    hard rule 3 at once: a small shape allocates the chunks it covers and no
##    others.
## 4. One undo step, named for the tool.
extends ToolState

## The flood is found through the wand tool it sits beside: the engine file next
## to `state_wand.gd`, reached by path the way the module's tests reach it,
## rather than through the class cache.
const SaWandScript = preload("res://modules/sara-base-modules/base/wand/sa_wand.gd")
const GroupPicture = preload("res://modules/sara-base-modules/base/wand/group_picture.gd")

## The `fill_tolerance` option, the same scale the wand's is on: a fraction of
## the distance between two colours, not a per-channel step.
var tolerance: float = 0.1

## `fill_contiguous`. Off is Krita's "Fill entire selection" read the other way
## round: every texel of the layer within the tolerance of the seed, whether or
## not it is joined to it, which is `SaWand.select_matching`. On is
## `SaWand.flood`, the region joined to the click.
var contiguous: bool = true

## `fill_sample_merged`. What the region is grown over: this layer's own colours,
## or the picture every visible layer composites to.
var sample_merged: bool = false

## `fill_antialias`. One texel of feather on the region's edge before it is
## painted, so a fill against a soft line does not leave a hard step. The kernel
## reads coverage per texel, so a feathered mask is a soft fill for free.
var antialias: bool = true

## `fill_gap_close`, Krita's Close gap: the widest gap in a line, in pixels,
## that the region does not leak through, 0 for none. `SaWand.flood` closes it
## and takes the region back to the line, so a ring with a gap fills as a
## closed one does. A contiguous fill only, since Contiguous off has no
## region to leak.
var gap_close: int = 0

## The reference layer to find the region on, or empty to read the active layer
## or the merged picture. A group is read as what it shows, its filters and mask
## included, and not as what its members hold. A layer that is gone or the active layer itself finds
## the region as with none.
var reference_layer: String = ""

## `fill_grow`. The number of texels to grow the region by before it is painted,
## 0 to 10 texels, 0 for none. The grow passes under the line of an
## anti-aliased contour or reference layer rather than stopping short of it.
var grow: int = 0

var _wand: SaWandScript = SaWandScript.new()
var _fill: SaCompute = null


func handle_input(event: InputEvent) -> void:
    var doc: SaDocument = document()
    if doc == null:
        return
    if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
        return
    var at := get_document_mouse_position()
    fill_at(Vector2i(floori(at.x), floori(at.y)))


## The colour a fill lays down: the painter's foreground, read at the click.
##
## **Not a settings resource.** A `BrushSettings` of the tool's own carries a
## colour that only `EventBus.color_picked`, the eyedropper's signal, ever
## writes: choosing a colour in the picker or through a scenario's `colour`
## step moves `SaColors.foreground` and emits nothing a settings resource
## listens for, so the fill would go on painting the colour its resource was
## constructed with. `SaColors.foreground` is what the Edit menu's own fill
## command reads, and this reads it too.
func fill_colour() -> Color:
    var doc: SaDocument = document()
    # Into the document's own encoding, the way the brush does it. A colour
    # handed to the kernel raw is right for an sRGB document and wrong for every
    # other one: `#2060d0` written straight into an Oklab document comes out
    # olive.
    var space: SaColorSpace = doc.color_space if doc != null else null
    var foreground := SaInHand.Pair.foreground()
    return space.from_display(foreground) if space != null else foreground


## Floods from *point* and paints what it found, as one undo step.
##
## The one door, called by the click, by a scenario through the tool's options
## and by the suite. Answers the number of chunks the fill touched, which is zero
## when the seed is off the canvas, the layer is locked or hidden, or the region fell
## outside the painter's selection.
func fill_at(point: Vector2i) -> int:
    var doc: SaDocument = document()
    var layer := doc.active_layer
    if layer == null or SaContext.refuse_stroke(layer, tr("fill")):
        return 0
    var region := _flood(point, layer)
    if region.is_empty():
        return 0
    return _paint(region, layer)


## The region around *point*, as `{grid_pos: SaChunk}` of coverage.
##
## `SaWand.flood` writes into the document's own selection, because that is what
## the wand wants. The painter's selection is snapshotted and put back, so a fill
## is not a selection gesture: clicking with this tool must leave the ants
## exactly where they were.
func _flood(point: Vector2i, layer: SaLayer) -> Dictionary:
    var doc: SaDocument = document()
    var selection := doc.selection
    var kept_chunks := selection.chunks
    var kept_active := selection.active
    var kept_bounds := selection.bounds

    selection.chunks = {}
    selection.active = true
    # What the region is grown over: the reference layer when a valid one is named,
    # else the merged picture when sample_merged is asked for, else the layer's own chunks.
    var colour: SaTexture = null
    var ref := _find_reference_layer(doc)
    var read_layer := layer
    # A group holds no paint, so what it shows is drawn into a layer of its own
    # for the flood to read, and freed once the flood has read it.
    var picture: SaLayer = null
    if ref != null and ref.is_group:
        picture = GroupPicture.shown(doc, ref)
        read_layer = picture
    elif ref != null:
        read_layer = ref
    elif sample_merged and surface != null and surface.easel != null:
        # A flood can reach past the window, so the picture there goes in first,
        # and a layer shown or hidden a moment before is in it, `SaEasel.catch_up`.
        surface.easel.catch_up()
        surface.easel.flush()
        colour = surface.easel.output
    var reached := 0
    if contiguous:
        reached = _wand.flood(doc, point, tolerance, SaSelection.Mode.REPLACE, colour, read_layer, gap_close)
    else:
        reached = _wand.select_matching(doc, point, tolerance, SaSelection.Mode.REPLACE, colour, read_layer)
    if picture != null:
        picture.free()
    if reached > 0 and grow > 0:
        var grow_radius := clampi(grow, 0, 10)
        if grow_radius > 0:
            SaSelectionFilters.grow(selection, grow_radius, doc.canvas_size, doc.projection.wrapping)
    # The chunks the flood itself entered, taken before the feather because the
    # feather works over the region's bounds grown by its radius and rounds that
    # out to whole chunks. One texel of softening then creates a chunk on each
    # side that the region never reached, and painting those lays bars of fill
    # colour clear of the shape. A selection never shows it, because a column
    # of coverage at a seam is invisible as ants and is paint here.
    var entered: Array = selection.chunks.keys()
    if reached > 0 and antialias:
        SaSelectionFilters.feather(selection, 1, doc.canvas_size, doc.projection.wrapping)
    var region: Dictionary = {}
    for grid_pos: Vector2i in entered:
        if selection.chunks.has(grid_pos):
            region[grid_pos] = selection.chunks[grid_pos]

    selection.chunks = kept_chunks
    selection.active = kept_active
    selection.bounds = kept_bounds
    selection.changed.emit()

    if reached <= 0:
        return {}
    return _clipped(region, selection) if kept_active else region


## *region* with everything outside *selection* taken out of it.
##
## `combine` is the only set operation the selection kernels have and it is a
## difference, so an intersection is two of them: `region - (region - selection)`.
## The scratch chunk in between is the only allocation, and it is one chunk at a
## time rather than a second copy of the region.
## **Not an [SaChunkWalk].** The walk dispatches one kernel per stop and this
## dispatches two, into two chunks neither of which is the one it walks, because
## an intersection out of a difference kernel is two differences with a scratch
## in between. A door that took a list of kernels would be a loop with extra
## words round it.
func _clipped(region: Dictionary, selection: SaSelection) -> Dictionary:
    var out: Dictionary = {}
    var side := SaChunk.SIZE
    var whole := Rect2i(0, 0, side, side)
    var params := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, float(side), float(side)])
    for grid_pos: Vector2i in region:
        var mine: SaTexture = (region[grid_pos] as SaChunk).field(SaSelection.FIELD)
        var theirs: SaTexture = selection.texture_for(grid_pos)
        if theirs == null:
            # Nothing of this chunk is selected, so the fill leaves it alone.
            continue
        var outside := selection.make_chunk()
        selection.dispatch(
            "combine",
            outside.field(SaSelection.FIELD),
            whole,
            params,
            {SaSelection.BINDING_BEFORE: mine, SaSelection.BINDING_AFTER: theirs}
        )
        var inside := selection.make_chunk()
        selection.dispatch(
            "combine",
            inside.field(SaSelection.FIELD),
            whole,
            params,
            {SaSelection.BINDING_BEFORE: mine, SaSelection.BINDING_AFTER: outside.field(SaSelection.FIELD)}
        )
        out[grid_pos] = inside
    return out


## Paints *region* onto *layer* with the foreground colour, as one undo step.
##
## Only the chunks the region reached are allocated: a fill inside a small shape leaves the chunk count
## where it was.
func _paint(region: Dictionary, layer: SaLayer) -> int:
    var doc: SaDocument = document()
    var colour := fill_colour()
    var undo_data: Dictionary = {}
    for grid_pos: Vector2i in region:
        undo_data[grid_pos] = layer.duplicate_chunk(grid_pos) if layer.chunks.has(grid_pos) else null

    if _fill == null:
        _fill = SaCompute.new("fill")
    var alpha_lock := 1.0 if layer.alpha_locked else 0.0
    var params := PackedFloat32Array([colour.r, colour.g, colour.b, colour.a, alpha_lock, 0.0, 0.0, 0.0])
    layer.mark_all_unresolved()
    # The flood's own chunks are the mask, one per position, which is why the
    # bindings are answered per stop. The walk is given no selection of its own
    # for the same reason: the region has already been clipped to it.
    var chunk_at := func(grid_pos: Vector2i) -> SaChunk:
        return layer.get_or_create_chunk(grid_pos) if region.has(grid_pos) else null
    var same := func(_g: Vector2i, _l: Rect2i, _s: Vector2i) -> PackedFloat32Array: return params
    var mask_of := func(grid_pos: Vector2i) -> Dictionary:
        return {SaSelection.BINDING: (region[grid_pos] as SaChunk).field(SaSelection.FIELD)}
    var walk := SaChunkWalk.new(_fill, null, layer)
    var touched := walk.run("fill", SaChunkWalk.reach_of(region.keys()), chunk_at, same, mask_of).size()

    doc.record_pixel_step("Fill", layer, undo_data)
    doc.invalidate_chunks(region.keys())
    doc.modified = true
    doc.document_changed.emit()
    return touched


## The layer named by reference_layer when it exists in *doc* and is not the
## active layer, or null when reference_layer is empty, gone, or the active
## layer itself.
func _find_reference_layer(doc: SaDocument) -> SaLayer:
    if reference_layer.is_empty() or reference_layer == "none":
        return null
    if doc == null:
        return null
    for child: Variant in doc.get_children():
        var child_layer := child as SaLayer
        if child_layer != null and child_layer != doc.stroke_layer and str(child_layer.name) == reference_layer:
            if child_layer == doc.active_layer:
                return null
            return child_layer
    return null


## Declares the options of the bucket fill tool: tolerance, contiguous, sample merged,
## anti-aliasing, gap close, reference layer, and grow.
static func fill_options() -> Array[SaOptionSpec]:
    var tolerance_row := SaOptionSpec.make_float(
        &"fill_tolerance",
        "Tolerance",
        0.0,
        1.0,
        0.01,
        {
            "on_tool": true,
            "property": ^"tolerance",
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "bar": false,
            "tooltip": "How far a colour may be from the clicked one and still be filled"
        }
    )
    var contiguous_row := SaOptionSpec.make(
        &"fill_contiguous",
        "Contiguous",
        SaOptionSpec.Kind.BOOL,
        {
            "on_tool": true,
            "property": ^"contiguous",
            "bar": false,
            "tooltip": "Fill only the connected area you click. Off fills every matching pixel on the layer."
        }
    )
    var merged_row := SaOptionSpec.make(
        &"fill_sample_merged",
        "Sample merged",
        SaOptionSpec.Kind.BOOL,
        {
            "on_tool": true,
            "property": ^"sample_merged",
            "bar": false,
            "tooltip": "Read every layer as shown, rather than the active layer alone."
        }
    )
    var antialias_row := SaOptionSpec.make(
        &"fill_antialias",
        "Anti-aliasing",
        SaOptionSpec.Kind.BOOL,
        {
            "on_tool": true,
            "property": ^"antialias",
            "bar": false,
            "tooltip": "Soften the filled edge by one pixel, so a fill against a soft line has no step."
        }
    )
    var gap_row := SaOptionSpec.make_float(
        &"fill_gap_close",
        "Close gaps",
        0.0,
        float(SaWandScript.MAX_GAP),
        2.0,
        {
            "on_tool": true,
            "property": ^"gap_close",
            "decimals": 0,
            "suffix": "px",
            "bar": false,
            "enabled_when": &"fill_contiguous",
            "enabled_when_values": [true],
            "tooltip":
            (
                "The widest gap in a line the fill closes, in pixels, so a sketch that is not quite shut fills inside "
                + "rather than leaking out. Zero leaves gaps open. A space narrower than this fills only around the "
                + "click, and a click this close to a gap can still leak through it."
            )
        }
    )
    var reference_row := SaOptionSpec.make_custom(
        &"fill_reference",
        "Reference",
        _build_reference_control,
        _bind_reference_control,
        {
            "on_tool": true,
            "property": ^"reference_layer",
            "bar": false,
            "tooltip":
            (
                "Find the filled region from this layer's colours instead of the active layer. "
                + "None uses the active layer (or merged)."
            )
        }
    )
    # The fill paints, so without bar_own_tool its row would stand on the bar
    # under every tool the way the brush's radius does, and a painter with a
    # brush in hand would read a Grow slider that fills nothing. Hidden off a
    # fresh bar and one tick away in Preferences > Top Menu Bar, where every row
    # that follows one tool sits: a tool switch on the shipped profile then
    # shows the same controls and costs no refit. The row is on the Tool Options
    # docker whatever this says. Its group is the brush's, because what the fill
    # lays down is the brush group's question, so the bar draws its break
    # between the stroke group and this row rather than losing the break a row
    # with no group of its own swallows.
    var grow_row := SaOptionSpec.make_float(
        &"fill_grow",
        "Grow",
        0.0,
        10.0,
        1.0,
        {
            "on_tool": true,
            "property": ^"grow",
            "decimals": 0,
            "suffix": "px",
            "bar_own_tool": true,
            "bar_hidden": true,
            "bar_group": SaOptionSpec.BAR_GROUP_BRUSH,
            "tooltip": "Grow the filled region under the line by this many texels, so an anti-aliased edge leaves no pale fringe."
        }
    )
    return [tolerance_row, contiguous_row, merged_row, antialias_row, gap_row, reference_row, grow_row]


## The document whose layers the reference row lists: the one the front tab
## shows, which is the surface the fill paints on, read through the door. The
## row is static and holds no tool, so it asks the door for the front surface
## as the tool's own [method ToolState.document] asks its surface. A row handed
## a document of its own as its `document` meta, a suite's, reads that one.
static func _find_document(choice: Control) -> SaDocument:
    if choice.has_meta(&"document") and choice.get_meta(&"document") is SaDocument:
        return choice.get_meta(&"document") as SaDocument
    return SaSurface.document_of(SaInHand.Canvas.front())


static func _refresh_reference_choices(choice: SaChoiceButton) -> void:
    var doc := _find_document(choice)
    var choices: Array = [{"id": "", "label": TranslationServer.translate("None")}]
    if doc != null:
        var layers: Array = doc.get_children()
        layers.reverse()
        for child: Variant in layers:
            var layer := child as SaLayer
            if layer != null and layer != doc.stroke_layer:
                choices.append({"id": str(layer.name), "label": str(layer.name)})
    choice.set_choices(choices)


static func _build_reference_control(spec: SaOptionSpec, write: Callable) -> Control:
    var choice := SaChoiceButton.new()
    choice.custom_minimum_size = Vector2(84, 24)
    choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    choice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    if not spec.tooltip.is_empty():
        choice.tooltip_text = TranslationServer.translate(spec.tooltip)
    choice.choice_picked.connect(
        func(picked: Variant) -> void:
            var picked_name := String(picked)
            choice.set_meta(&"current_value", picked_name)
            if write.is_valid():
                write.call(picked_name)
            _bind_reference_control(choice, picked_name)
    )
    choice.popup.about_to_popup.connect(func() -> void: _refresh_reference_choices(choice))
    choice.tree_entered.connect(
        func() -> void:
            var doc := _find_document(choice)
            if doc != null:
                if not doc.active_layer_changed.is_connected(_on_doc_active_layer_changed.bind(choice)):
                    doc.active_layer_changed.connect(_on_doc_active_layer_changed.bind(choice))
                if not doc.child_order_changed.is_connected(_on_doc_structure_changed.bind(choice)):
                    doc.child_order_changed.connect(_on_doc_structure_changed.bind(choice))
    )
    choice.tree_exiting.connect(
        func() -> void:
            var doc := _find_document(choice)
            if doc != null:
                if doc.active_layer_changed.is_connected(_on_doc_active_layer_changed.bind(choice)):
                    doc.active_layer_changed.disconnect(_on_doc_active_layer_changed.bind(choice))
                if doc.child_order_changed.is_connected(_on_doc_structure_changed.bind(choice)):
                    doc.child_order_changed.disconnect(_on_doc_structure_changed.bind(choice))
    )
    return choice


## A change of the active layer or of the stack shows what the reference now
## is and builds no rows. A row a layer, rebuilt at every `child_order_changed`,
## was 130 ms an emit on a file of 293 layers, and a move of a
## group emits once for every node it moves, so one Move Up froze Sara for
## seconds and filled the heap with rows freed only at the frame's end. The
## rows are built when the popup opens, which `about_to_popup` does, and
## rebuilt here only while it shows.
static func _on_doc_active_layer_changed(_layer: SaLayer, choice: SaChoiceButton) -> void:
    if is_instance_valid(choice):
        _show_reference(choice)


static func _on_doc_structure_changed(choice: SaChoiceButton) -> void:
    if is_instance_valid(choice):
        if choice.popup.visible:
            _refresh_reference_choices(choice)
        _show_reference(choice)


static func _bind_reference_control(control: Control, value: Variant) -> void:
    var choice := control as SaChoiceButton
    if choice == null:
        return
    choice.set_meta(&"current_value", String(value))
    _refresh_reference_choices(choice)
    _show_reference(choice)


## The button's words for the reference it holds: None, the layer's name, or
## None (gone) and None (active) for a name the fill cannot read. A name the
## rows built earlier do not carry, a layer renamed since, gets the two rows
## it needs, so the button can show it with the popup shut.
static func _show_reference(choice: SaChoiceButton) -> void:
    var ref_name := String(choice.get_meta(&"current_value", ""))
    var doc := _find_document(choice)
    if ref_name.is_empty() or ref_name == "none":
        choice.select_value("")
        return

    var found_layer: SaLayer = null
    if doc != null:
        for child: Variant in doc.get_children():
            if child is SaLayer and child != doc.stroke_layer and str(child.name) == ref_name:
                found_layer = child as SaLayer
                break

    if found_layer == null:
        choice.clear_choice(TranslationServer.translate("None (gone)"))
    elif found_layer == doc.active_layer:
        choice.clear_choice(TranslationServer.translate("None (active)"))
    elif not choice.select_value(ref_name):
        choice.set_choices([{"id": "", "label": TranslationServer.translate("None")}, {"id": ref_name, "label": ref_name}])
        choice.select_value(ref_name)
