## Why a stroke changed no texel, said once on the status line.
##
## A stroke can change nothing for reasons a painter cannot see from the pen: an
## active selection of nothing clips every dab to nothing, and an Erase left on
## makes a stroke on an empty layer an "Erase Stroke" that takes nothing.
##
## The cause is read from what the stroke already kept on the CPU, never from
## the pixels, because the canvas stays in VRAM during a stroke. The
## transaction knows every region a dab landed in, and a dab lands only where
## the selection holds a chunk. The selection's bounds are an over-estimate, so
## a stroke whose regions miss them painted nothing for certain. The layer's
## chunks, and the snapshot of the ones a direct stroke made, say whether there
## was paint for an eraser to take. A cause that cannot be proved this way is
## not said, because a wrong reason is worse than none.
##
## A brush engine commits through [method commit] rather than straight through
## `SaDocument.commit_stroke`, because only the engine knows it is erasing: a
## build-up eraser paints straight in with the stroke buffer tagged Normal.
class_name SaStrokeNote
extends RefCounted

## The line for a stroke whose dabs all fell outside the selection.
const OUTSIDE_SELECTION := "Nothing is selected where you painted"

## The line for an eraser that swept a layer holding no paint where it went.
const ERASING_NOTHING := "Erase is on"

## The line last said, so the next stroke of the same cause says nothing more,
## and a stroke that paints clears it once.
static var _said: String = ""

## Whether the strokes running now are a preset's picture, which says nothing on
## the message bar either.
static var _quiet: bool = false


## Commits the stroke on *document* the way `SaDocument.commit_stroke` does and
## says on the status line why it changed nothing, when it did. *erasing* is the
## engine's own answer, settled at the press. *tool* is the engine itself, whose
## view's zoom and brush radius tell the selection reminder how near is near.
## An engine that names none is found on the surface showing *document*, and
## where there is none the margin is read at zoom 1 with no brush.
static func commit(document: SaDocument, erasing: bool, tool: ToolState = null) -> void:
    var line := cause(document, erasing)
    var refused := refusal(document, erasing)
    var bounds := painted_bounds(document)
    document.stroke_transaction.erasing = erasing
    document.commit_stroke()
    say(line)
    if not refused.is_empty() and not _quiet and not _embedded(document, tool):
        EventBus.paint_refused.emit(refused)
    var outside := line == TranslationServer.translate(OUTSIDE_SELECTION)
    SaSelectionReminder.after_stroke(document, outside, bounds, _near(document, tool))


## The sentence for the stroke *document* is about to commit, empty when the
## stroke changed something or the cause cannot be proved. Asked before the
## commit, because the commit resets the transaction and bakes into the layer.
static func cause(document: SaDocument, erasing: bool) -> String:
    if document == null or document.active_layer == null or document.selection == null:
        return ""
    var transaction := document.stroke_transaction
    # The quick mask and a layer's mask paint coverage rather than the picture,
    # and neither is clipped by the selection the way a stroke on a layer is.
    if document.selection.editing or transaction.mask != null:
        return ""
    var painted := transaction.painted_regions
    if document.selection.active and not _reaches(painted, document.selection.bounds, document.active_layer):
        return TranslationServer.translate(OUTSIDE_SELECTION)
    if erasing and not painted.is_empty() and not _met_paint(painted, transaction.before_chunks, document.active_layer):
        return TranslationServer.translate(ERASING_NOTHING)
    return ""


## The line for the message bar the stroke *document* is about to commit says,
## once, empty when it has nothing to say. A stroke on a hidden layer never
## gets here, its press is turned away by `SaContext.refuse_hidden`. An erase
## that met no paint of the active layer names it and
## the nearest layer below holding paint where the stroke went. Asked before
## the commit for the reason [method cause] is, from the regions and snapshots
## the stroke kept on the CPU and the layers' chunk lists, never the pixels.
static func refusal(document: SaDocument, erasing: bool) -> String:
    if document == null or document.active_layer == null:
        return ""
    var layer := document.active_layer
    var transaction := document.stroke_transaction
    var painted := transaction.painted_regions
    if not erasing or transaction.mask != null or painted.is_empty():
        return ""
    if document.selection != null and document.selection.editing:
        return ""
    if _met_paint(painted, transaction.before_chunks, layer):
        return ""
    return SaContext.empty_erase_line(layer, _paint_below(document, layer, painted))


## The nearest layer under *layer* in *document* that shows and holds a chunk
## where *painted* names one, or null. Groups, adjustments and effects hold no
## paint of their own and are passed over.
static func _paint_below(document: SaDocument, layer: SaLayer, painted: Dictionary[Vector2i, Rect2i]) -> SaLayer:
    var index := layer.get_index() - 1
    while index >= 0:
        var under := document.get_child(index) as SaLayer
        index -= 1
        if under == null or under.is_group or under.is_adjustment() or under.is_effect() or SaContext.hidden(under):
            continue
        for grid_pos: Vector2i in painted:
            if under.chunks.has(grid_pos):
                return under
    return null


## Whether *document* is painted on a surface set inside a docker, the brush
## editor's scratchpad and its kind, whose strokes try a brush and say nothing
## on the message bar.
static func _embedded(document: SaDocument, tool: ToolState) -> bool:
    var surface: SaSurface = tool.surface if tool != null else _surface_of(document)
    return surface != null and surface.is_embedded


## Puts *line* on the status line unless it is the one said last. An empty
## line clears what was said, once.
static func say(line: String) -> void:
    if line == _said:
        return
    _said = line
    EventBus.stroke_explained.emit(line)


## Runs *work*, strokes on a document no painter sees, and leaves the status
## line as it was. A preset's picture is painted by the brush itself, whose
## every stroke commits through [method commit], so the line a painter had just
## been told was gone within the frame while the Brush Presets docker drew, and
## an eraser preset's picture put "Erase is on" in its place.
static func aside(work: Callable) -> void:
    var kept := _said
    _quiet = true
    work.call()
    _quiet = false
    say(kept)


## The bounds in document pixels of every region the stroke *document* is
## about to commit painted, empty when it painted none. Asked before the commit
## for the reason [method cause] is.
static func painted_bounds(document: SaDocument) -> Rect2i:
    if document == null or document.active_layer == null:
        return Rect2i()
    var painted := document.stroke_transaction.painted_regions
    var bounds := Rect2i()
    for grid_pos: Vector2i in painted:
        var region := _region(grid_pos, painted[grid_pos], document.active_layer)
        bounds = region if bounds.size == Vector2i.ZERO else bounds.merge(region)
    return bounds


## The reminder's margin in document pixels for a stroke on *document* by
## *tool*, read from the view the stroke ended in and the brush's radius.
static func _near(document: SaDocument, tool: ToolState) -> float:
    var surface: SaSurface = tool.surface if tool != null else _surface_of(document)
    var engine: ToolState = tool
    if engine == null and surface != null and surface.tool_machine is Object:
        var machine: Object = surface.tool_machine
        var active: Variant = machine.get(&"active_tool")
        if active is ToolState:
            engine = active
    var zoom := surface.view.get_zoom() if surface != null and surface.view != null else 1.0
    var diameter := maxf(0.0, engine.get_cursor_radius()) * 2.0 if engine != null else 0.0
    return SaSelectionReminder.margin(zoom, diameter)


## The surface showing *document*, from the context the modules were loaded
## against, or null where Sara runs without one, as a suite does.
static func _surface_of(document: SaDocument) -> SaSurface:
    var context: SaContext = ModuleLoader._context
    if context == null:
        return null
    for held: Variant in context.list_surfaces():
        if not held is SaSurface:
            continue
        var surface: SaSurface = held
        if surface.get_document() == document:
            return surface
    return null


## Whether any region of *painted*, kept in *layer*'s texels per chunk, meets
## *bounds* in document pixels. The regions are widened to whole workgroups, so
## a stroke that only grazes the bounds counts as reaching them.
static func _reaches(painted: Dictionary[Vector2i, Rect2i], bounds: Rect2i, layer: SaLayer) -> bool:
    if bounds.size.x <= 0 or bounds.size.y <= 0:
        return false
    for grid_pos: Vector2i in painted:
        if _region(grid_pos, painted[grid_pos], layer).intersects(bounds):
            return true
    return false


## The region *texels* of the chunk at *grid_pos*, kept in *layer*'s texels, in
## document pixels.
static func _region(grid_pos: Vector2i, texels: Rect2i, layer: SaLayer) -> Rect2i:
    var scale := layer.resolution_scale if layer.resolution_scale > 0.0 else 1.0
    var origin := grid_pos * SaLayer.CHUNK_SIZE
    return Rect2i(origin + Vector2i(Vector2(texels.position) / scale), Vector2i(Vector2(texels.size) / scale))


## Whether the stroke met a chunk of *layer* that was there before it, over the
## chunks *painted* names. A direct stroke snapshots each chunk into *before*,
## a null where there was none, and a buffered one has not touched the layer
## yet, so the layer's own chunks answer for it.
static func _met_paint(painted: Dictionary[Vector2i, Rect2i], before: Dictionary[Vector2i, Variant], layer: SaLayer) -> bool:
    for grid_pos: Vector2i in painted:
        if before.has(grid_pos):
            if before[grid_pos] != null:
                return true
        elif layer.chunks.has(grid_pos):
            return true
    return false
