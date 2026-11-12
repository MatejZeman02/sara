## The Colourise layer, Krita's colorize mask as a layer of its own: a few
## scribbles of colour on it, and every region of a chosen line art layer
## filled with the colour of the scribble inside it, under the lines to their
## middle, with breaks in the lines up to the Gap Closing width kept shut.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A layer rather than a mask.** A mask in Sara is one channel of the layer
## it hides, and the scribbles are colours. A layer type registered through
## `SaRegistries` as any module's is (hard rule 6) has a schema of its own: the
## scribbles in `keys`, the colour field a brush paints (`SaPaintedField`),
## the flats in `flats`, worked out by an update and kept as a float field
## nobody paints, and `albedo` worked out of the two by the layer's resolve
## hook, which is all the compositor, an export, a merge and Rasterize Layer
## ever read. So every brush, the eraser and the fill lay scribbles, undo takes
## the scribbles and the flats back together, and a `.sad` keeps both with the
## layer's type as it keeps any type's fields. A file with no Colourise layer
## in it reads as it always did, because nothing in the format changed.
##
## **What it shows** is `colorize_show.gmacs`: the flats with every scribble
## they have not taken in drawn over them, so a stroke shows as it is laid,
## or the scribbles alone when the layer's switch says so.
##
## **What it reads and how** is the layer's own slice of module data, through
## `SaContext.layer_data`: the line art layer by name, as an effect layer
## keeps its source, the Gap Closing width, the Transparent key's colour, the
## switch that shows the scribbles alone and the Auto switch. A layer that
## names no line art reads the nearest paint layer under it, or over it.
##
## **An update** is [method update], `sa_colorize_fill.gd` on the card. The
## Update button's is one history step, the flats as they were taken back by
## one Ctrl+Z. With Auto on, a stroke's end, an undo and a redo on the layer
## each owe one, run the next frame and in no step of its own, so the flats
## always follow the scribbles they stand for and never move during a stroke.
## Layer > Rasterize Layer turns the layer into a paint layer of what it
## shows, one menu step and one history step.
extends RefCounted

const SaColorizeFill = preload("res://modules/sara-base-modules/base/colorize/sa_colorize_fill.gd")

## The type's id, which a `.sad` records, so it does not change.
const TYPE: StringName = &"colorize"
const KEYS: StringName = SaColorizeFill.KEYS
const FLATS: StringName = SaColorizeFill.FLATS
const SHOW := "colorize_show"
## The step an Update leaves in the history.
const STEP := "Update Colourise Layer"
## How near a scribble's colour has to be to another to count as the same, on
## channels of nought to one.
const TOLERANCE := 0.02
## What a new layer starts with: a break up to four pixels shut, a magenta that
## no flat is likely to want as the Transparent key, and Auto on.
const GAP := 4.0
const GAP_MOST := 64.0
const TRANSPARENT := Color(1.0, 0.0, 1.0, 1.0)

## How long the last update took on the card and the CPU together, in
## milliseconds, which the timing suite prints.
var took_ms: float = 0.0

var _ctx: SaContext = null
## The command registry, held weakly since a command may be bound to a module
## that holds this.
var _commands: WeakRef = null
var _fill: SaColorizeFill = SaColorizeFill.new()
var _show: SaCompute = null
## The instance ids of the layers whose strokes and swaps this hears.
var _heard: Dictionary[int, bool] = {}
## The layers an update is owed to once the frame is over, by instance id.
var _owed: Dictionary[int, SaLayer] = {}
## Whether an update of this class is recording its own step, which the layer
## says through the signal a stroke's end says too.
var _recording: bool = false


## *ctx* is narrowed to the module's own data slice, and the command registry
## is held weakly. The layer type and docker registries hold callables bound
## to this, so a context that held them would be a ring that nothing breaks,
## registry to callable to this and back to the registry, and a run would end
## leaking every surface a suite built.
func _init(ctx: SaContext) -> void:
    if ctx == null:
        return
    _ctx = SaContext.new(Callable(), Callable(), ctx.module_id)
    _commands = weakref(ctx.commands)


## The type a module registers: the scribbles, the flats and the colour shown.
func descriptor() -> SaLayerTypeDescriptor:
    var flats := SaFieldSpec.create(FLATS, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, false)
    var shown := SaFieldSpec.create(SaFieldSpec.ALBEDO, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, true, [KEYS, FLATS])
    var schema: Array[SaFieldSpec] = [SaFieldSpec.create(KEYS), flats, shown]
    var made := SaLayerTypeDescriptor.create(TYPE, schema)
    made.display_name = "Colourise Line Art"
    made.icon_name = "bucket"
    made.hint = (
        "Fills the regions of a line art layer from a few scribbles of colour,"
        + " closing small gaps and running the colour under the lines."
    )
    made.resolve = show
    return made


static func is_colorize(layer: SaLayer) -> bool:
    return layer != null and layer.layer_type == TYPE


## The layer's own options, the slice its file keeps.
func options(layer: SaLayer) -> Dictionary[String, Variant]:
    return _ctx.layer_data(layer) if _ctx != null else layer.module_data


func gap_of(layer: SaLayer) -> float:
    return clampf(float(options(layer).get("gap", GAP)), 0.0, GAP_MOST)


func transparent_of(layer: SaLayer) -> Color:
    var held: Variant = options(layer).get("transparent", null)
    if held is Array and (held as Array).size() >= 3:
        var rgb: Array = held
        return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]), 1.0)
    return TRANSPARENT


func alone_of(layer: SaLayer) -> bool:
    return bool(options(layer).get("alone", false))


func auto_of(layer: SaLayer) -> bool:
    return bool(options(layer).get("auto", true))


## Writes one of the layer's options, *key* one of `line_art`, `gap`,
## `transparent`, `alone` and `auto`, and shows or fills again what it moves.
func choose(layer: SaLayer, key: String, value: Variant) -> void:
    if not is_colorize(layer):
        return
    var stored: Variant = value
    if value is Color:
        var colour: Color = value
        stored = [colour.r, colour.g, colour.b]
    options(layer)[key] = stored
    var document := _document_of(layer)
    if document != null:
        document.modified = true
    if key == "alone" or key == "transparent":
        _show_again(layer)
    if key != "alone" and key != "auto" and auto_of(layer):
        owe(layer)


## The line art *layer* reads: the layer its options name, or when they name
## none or a layer the document lacks, the nearest readable layer under it, or over it
## when there is none under, so a Colourise layer the painter drags under
## its ink still reads that ink.
func line_art_of(layer: SaLayer) -> SaLayer:
    var document := _document_of(layer)
    if document == null:
        return null
    var named := str(options(layer).get("line_art", ""))
    var below: SaLayer = null
    var above: SaLayer = null
    var past := false
    for child in document.get_children():
        if child == layer:
            past = true
        elif readable(child, layer):
            if not named.is_empty() and child.name == named:
                return child
            if not past:
                below = child
            elif above == null:
                above = child
    return below if below != null else above


## Whether *candidate* is a layer *layer* can read as line art: paint of its
## own, and not another Colourise layer.
static func readable(candidate: Node, layer: SaLayer) -> bool:
    if not candidate is SaLayer or candidate == layer:
        return false
    var other: SaLayer = candidate
    if other.is_group or other.is_generated() or other.is_adjustment() or other.is_effect() or other.is_scene():
        return false
    return not is_colorize(other)


## Whether *layer* has line art to fill between: a layer it reads that holds
## paint. Without one there are no regions to speak of, the whole page would be
## one, so an update fills nothing and the layer shows its scribbles alone.
func has_line_art(layer: SaLayer) -> bool:
    var line_art := line_art_of(layer)
    return line_art != null and not line_art.chunks.is_empty()


## Works the flats of *layer* out from its scribbles and its line art. As
## *step*, one history step the painter can take back, and otherwise none.
## False when the layer is not a Colourise layer or there is no card.
##
## **With no line art** the flats are emptied instead of filled, so a layer
## whose line art is blank or missing shows the scribbles as they were laid and
## never a solid block the size of the chunks they touch.
func update(layer: SaLayer, step: bool = true) -> bool:
    var document := _document_of(layer)
    if not is_colorize(layer) or document == null or GlobalShaderCompiler.get_rd() == null:
        return false
    follow(layer)
    var started := Time.get_ticks_usec()
    var line_art := line_art_of(layer)
    if line_art == null or line_art.chunks.is_empty():
        _empty_flats(document, layer, step)
        took_ms = float(Time.get_ticks_usec() - started) / 1000.0
        return true
    var before: Dictionary[Vector2i, Variant] = {}
    if step:
        var grid := SaColorizeFill.grid_of(layer, line_art)
        for y in range(grid.position.y, grid.end.y):
            for x in range(grid.position.x, grid.end.x):
                before[Vector2i(x, y)] = layer.duplicate_chunk(Vector2i(x, y))
    var written: Array[Vector2i] = _fill.fill(layer, line_art, gap_of(layer), transparent_of(layer), TOLERANCE)
    for grid_pos in written:
        layer.mark_unresolved(grid_pos)
    if step and not written.is_empty():
        _recording = true
        document.record_pixel_step(STEP, layer, before)
        _recording = false
    _shown(document, layer, written)
    took_ms = float(Time.get_ticks_usec() - started) / 1000.0
    return true


## The flats of *layer* emptied where it holds any, as one history step when
## *step* is set and something was there to empty.
func _empty_flats(document: SaDocument, layer: SaLayer, step: bool) -> void:
    var before: Dictionary[Vector2i, Variant] = {}
    var emptied: Array[Vector2i] = []
    for grid_pos: Vector2i in layer.chunks:
        var flats := layer.get_field(grid_pos, FLATS)
        if flats == null:
            continue
        if step:
            before[grid_pos] = layer.duplicate_chunk(grid_pos)
        flats.clear(Color(0.0, 0.0, 0.0, 0.0))
        layer.mark_unresolved(grid_pos)
        emptied.append(grid_pos)
    if step and not emptied.is_empty():
        _recording = true
        document.record_pixel_step(STEP, layer, before)
        _recording = false
    _shown(document, layer, emptied)


## Turns the active layer into a paint layer of what it shows, one history
## step, through the Layer menu's own command, so a module reaches Rasterize
## Layer by the door rather than by the class behind it. False when no
## handler took it.
func rasterize() -> bool:
    var commands: Variant = _commands.get_ref() if _commands != null else null
    return commands != null and commands.execute(&"layer_rasterize")


## Rounds of the sweeps the last update ran.
func rounds() -> int:
    return _fill.rounds


## The resolve hook: what *layer* shows at *grid_pos* worked out into the
## chunk's `albedo` from its scribbles and its flats.
func show(layer: SaLayer, _grid_pos: Vector2i, chunk: SaChunk) -> void:
    follow(layer)
    var albedo := chunk.albedo()
    var keys := chunk.field(KEYS)
    var flats := chunk.field(FLATS)
    if albedo == null or keys == null or flats == null or GlobalShaderCompiler.get_rd() == null:
        return
    if _show == null:
        _show = SaCompute.new(SHOW)
    _show.use_storage_format(albedo.format)
    _show.set_image("albedo", albedo)
    _show.set_image("keys", keys)
    _show.set_image("flats", flats)
    var params: Dictionary[String, Variant] = {
        "transparent": transparent_of(layer),
        "tolerance": TOLERANCE,
        "alone": 1.0 if alone_of(layer) else 0.0,
        "spare_a": 0.0,
        "spare_b": 0.0,
    }
    _show.set_params(params)
    _show.dispatch_kernel(SHOW, SaCompute.groups_for(albedo.size.x), SaCompute.groups_for(albedo.size.y), 1)


## Hears *layer*'s strokes, undos and redos, once, so Auto can follow them.
func follow(layer: SaLayer) -> void:
    var id := layer.get_instance_id()
    if _heard.has(id):
        return
    _heard[id] = true
    layer.paint_recorded.connect(_painted.bind(layer))
    layer.paint_swapped.connect(_painted.bind(layer))


## An update owed to *layer* once this frame is over, so a stroke's end, which
## is where the signal comes from, finishes first.
func owe(layer: SaLayer) -> void:
    if _owed.is_empty():
        pay.call_deferred()
    _owed[layer.get_instance_id()] = layer


## Runs every update owed, each in no step of its own.
func pay() -> void:
    var owed := _owed
    _owed = {}
    for id: int in owed:
        var layer: SaLayer = owed[id]
        if is_instance_valid(layer) and is_colorize(layer) and auto_of(layer):
            update(layer, false)


func _painted(_grid_positions: Array, layer: SaLayer) -> void:
    if _recording or not is_instance_valid(layer) or not is_colorize(layer) or not auto_of(layer):
        return
    owe(layer)


## Every chunk of *layer* shown again from what it holds.
func _show_again(layer: SaLayer) -> void:
    var held: Array[Vector2i] = []
    for grid_pos: Vector2i in layer.chunks:
        layer.mark_unresolved(grid_pos)
        held.append(grid_pos)
    var document := _document_of(layer)
    if document != null:
        _shown(document, layer, held)


static func _shown(document: SaDocument, layer: SaLayer, written: Array[Vector2i]) -> void:
    if written.is_empty():
        return
    document.invalidate_chunks(written, layer)
    if layer != document.active_layer:
        document.request_cache_update()
    document.modified = true
    document.document_changed.emit()


static func _document_of(layer: SaLayer) -> SaDocument:
    if layer == null or not is_instance_valid(layer):
        return null
    return layer.get_parent() as SaDocument
