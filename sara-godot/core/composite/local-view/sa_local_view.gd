## Isolate Active Layer, Blender's local view on a painting: the canvas draws
## the active layer alone, or the Layers docker's picked rows when a set is
## picked, framed to fill the room between the dockers, and the same command
## puts everything and the view back.
##
## **A state of the view, never of the document.** No layer's eye moves, no
## step is written and nothing is saved. The compositor asks
## [method SaLayerStack.shows], which asks [method leaves_out] here, and every
## command on the document asks [method SaLayerStack.contributes], so a merge
## or a bake while isolated takes what the file holds. A reader of the file's
## picture, an export or the save's preview, composites through
## [method flush_whole], which draws every visible layer for its read and puts
## the isolated picture back before the frame is drawn.
##
## **The shown set follows the active layer**, as Krita's Isolate Active Layer
## does: the layers it shows are [method SaPickedLayers.acted_on], read when
## the compositor asks, so a click on another row shows that row and a new
## layer is shown the moment it is made. The view is framed once, when
## isolation begins, and a pick never moves it.
##
## **Edit Smart Layer Contents is the same view on one smart layer**: the layer handed to [method begin]
## as *contents* is shown alone, whichever layer is active, and drawn through no
## map, [method untransformed], while `SaLiveTransform.of` still holds its map.
## So every tool paints into its own pixels as on an ordinary layer. The solid
## backdrop it is shown over is the canvas's, `SaContentsBackdrop`, and no
## layer or chunk, so nothing that reads the file's picture sees it. A reader
## of the file's picture draws the map, since [method flush_whole] suspends
## the view as it suspends isolation. A merge takes the layer as the file
## draws it, so a bake or a merge ends the view first, [method end_contents].
## A layer that left the document or stopped being smart ends it too, the
## next time [method of] is asked.
##
## Named the local view in code, because `SaLayer.isolated` is the group's
## compositing mode, which the painter reads as Blend Group on Its Own.
class_name SaLocalView
extends RefCounted

## The kernel of `local_view_bounds.gmacs`, named where the opener scan finds it.
const SHADER := "local_view_bounds"
const BOUNDS_BINDING: int = 1
## A coordinate no document reaches, the seed the reduction's minimum starts at.
const BOX_WIDE: int = 1 << 30
## The share of the free rectangle the framed paint fills, which leaves a
## margin round the paint.
const SHARE: float = 0.9

## Each document's local view while it is on, by the document's instance id, so
## a document freed while isolated holds nothing alive here.
static var _on: Dictionary[int, SaLocalView] = {}

## The view as isolation found it, which the second press puts back.
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _rotation: float = 0.0
## True while a reader of the file's picture composites every visible layer.
var _suspended: bool = false
## The smart layer whose contents the view opens, null for Isolate Active Layer.
var _contents: SaLayer = null


func _init(view: SaView = null, contents: SaLayer = null) -> void:
    _contents = contents
    if view != null:
        _zoom = view.get_zoom()
        _pan = view.get_pan()
        _rotation = view.get_rotation()


## *document*'s local view, or null while it shows everything. A contents view
## whose layer is gone from *document* or no longer smart, which a delete, a
## merge or an undo of Make Smart Layer leaves, is dropped here, since each of
## those composites the document again anyway.
static func of(document: SaDocument) -> SaLocalView:
    if document == null or _on.is_empty():
        return null
    var local: SaLocalView = _on.get(document.get_instance_id(), null)
    if local != null and local._contents != null and not local._holds(document):
        _on.erase(document.get_instance_id())
        return null
    return local


## Whether the contents layer is still a smart layer of *document*.
func _holds(document: SaDocument) -> bool:
    if not is_instance_valid(_contents) or SaLiveTransform.of(_contents) == null:
        return false
    var node := _contents.get_parent()
    while node != null and node != document:
        node = node.get_parent()
    return node == document


## The smart layer *document*'s contents view opens, or null when none is open.
static func contents_of(document: SaDocument) -> SaLayer:
    var local := of(document)
    return local._contents if local != null else null


## Whether *layer* is drawn through no map just now: its contents are open and
## no reader of the file's picture has the view suspended. `SaLiveTransform`
## asks it for the paint it draws, the paint it takes and the maps it refuses.
static func untransformed(layer: SaLayer) -> bool:
    if _on.is_empty() or layer == null:
        return false
    var local := of(layer.get_parent() as SaDocument)
    return local != null and not local._suspended and local._contents == layer


## The live transform a stroke on *layer* is painted through: its own, or none
## while its contents are open. `SaPaintContext` asks it.
static func map_of(layer: SaLayer) -> SaLiveTransform:
    return null if untransformed(layer) else SaLiveTransform.of(layer)


## Ends *document*'s contents view with the view where it stands, for a step
## that takes the layers as the file draws them, a bake or a merge, which a
## view drawing one of them untransformed would misread. Isolation stays.
static func end_contents(document: SaDocument) -> void:
    if contents_of(document) != null:
        of(document)._owe_map()
        _on.erase(document.get_instance_id())
        _recomposite(document)


## Whether isolation is on for *document*, read by the command's tick and the
## sign on the canvas.
static func is_on(document: SaDocument) -> bool:
    return of(document) != null


## Turns isolation on for *document* and frames what it shows in *area* of
## *view*, or off and puts the view back. Answers whether it is on after.
static func toggle(document: SaDocument, view: SaView, area: Rect2) -> bool:
    if is_on(document):
        end(document, view)
        return false
    return begin(document, view, area)


## Leaves out of *document*'s canvas every layer but the shown ones and fits
## their painted box at [constant SHARE] of *area*, the whole document when
## they hold no paint, keeping the rotation. Answers false when there is
## nothing to isolate. With *contents*, a smart layer of *document*, it is
## that layer's contents view instead, which shows it alone and untransformed.
static func begin(document: SaDocument, view: SaView, area: Rect2, contents: SaLayer = null) -> bool:
    if document == null or document.active_layer == null or is_on(document):
        return false
    _on[document.get_instance_id()] = SaLocalView.new(view, contents)
    _recomposite(document)
    if view != null:
        var box := painted_box(document)
        if not box.has_area():
            box = Rect2i(Vector2i.ZERO, document.canvas_size)
        _frame(view, Rect2(box), area)
    return true


## Fits *rect*, a part of the document in document pixels, into *area* at
## [constant SHARE] of it and centres it there, at the rotation and the mirror
## *view* already has. Fit to View's sibling for a part of the picture, here
## rather than beside [method SaView.fit_into] because `SaView` stands at
## gdlint's limit of public methods. Not a fit the canvas takes again after a
## change of scale, because the part is the painter's choice of the moment.
static func _frame(view: SaView, rect: Rect2, area: Rect2) -> void:
    if rect.size.x <= 0.0 or rect.size.y <= 0.0 or area.size.x <= 0.0 or area.size.y <= 0.0:
        return
    var extent := SaView.rotated_extent(rect.size, view.get_rotation())
    var factor := minf(area.size.x / extent.x, area.size.y / extent.y) * SHARE
    view.set_zoom(clampf(factor, SaView.ZOOM_MIN, SaView.ZOOM_MAX))
    view.set_pan(area.get_center() - view.view_offset(rect.get_center()))


## Shows everything again and puts *view* back at the zoom, pan and rotation it
## had when isolation began.
static func end(document: SaDocument, view: SaView) -> void:
    var local := of(document)
    if local == null:
        return
    local._owe_map()
    _on.erase(document.get_instance_id())
    if view != null:
        view.set_rotation(local._rotation)
        view.set_zoom(local._zoom)
        view.set_pan(local._pan)
    _recomposite(document)


## Drops *document*'s isolation with the view as it is, for a document that
## was replaced under the view, whose new picture is composited whole anyway.
static func forget(document: SaDocument) -> void:
    if document != null:
        _on.erase(document.get_instance_id())


## The layers isolation shows in *document*, top first, empty while it is off,
## and the contents layer alone while its contents are open.
static func shown(document: SaDocument) -> Array[SaLayer]:
    var local := of(document)
    if local == null:
        return []
    if local._contents != null:
        var alone: Array[SaLayer] = [local._contents]
        return alone
    return document.picked.acted_on(document)


## Whether the canvas leaves *layer* out: isolation is on and *layer* is not a
## shown layer, a layer inside a shown group, a group a shown layer sits in, or
## the base a shown layer clips to, without which it would show nothing.
static func leaves_out(document: SaDocument, layer: SaLayer) -> bool:
    var local := of(document)
    if local == null or local._suspended or layer == null:
        return false
    for kept in shown(document):
        if SaLayerStack.is_inside(layer, kept) or SaLayerStack.is_inside(kept, layer):
            return false
        if SaLayerStack.clip_base(document, kept) == layer:
            return false
    return true


## Composites *easel* for a reader of the file's picture. While isolation is
## on, every visible layer is composited for the read, and the isolated
## picture comes back at the end of the frame, before it is drawn, so the
## painter never sees the whole picture flash. A layer shown or hidden a moment
## before is in the read, `SaEasel.catch_up`.
static func flush_whole(easel: SaEasel) -> void:
    if easel != null:
        easel.catch_up()
    var document := easel.document if easel != null else null
    var local := of(document)
    if local == null or local._suspended:
        if easel != null:
            easel.flush()
        return
    local._suspend(true)
    _recomposite(document)
    easel.process_pending_composite()
    easel.flush()
    # By the easel's id, so an easel freed before the frame ends is not held.
    _resume_by_id.call_deferred(easel.get_instance_id())


## Puts the isolated picture back on *easel* after [method flush_whole], which
## the end of the frame runs and a suite, which cannot await a frame, calls.
static func resume(easel: SaEasel) -> void:
    if not is_instance_valid(easel):
        return
    var local := of(easel.document)
    if local == null or not local._suspended:
        return
    local._suspend(false)
    _recomposite(easel.document)
    easel.process_pending_composite()


## Sets whether every visible layer is shown for a read of the whole picture.
func _suspend(whole: bool) -> void:
    _suspended = whole
    if whole:
        _owe_map()


## Owes the contents layer's map a whole redraw, before the map draws it again
## at a close or a read of the file's picture. Paint the view took went into the
## layer through no map, so the map's cache was told of it only when the tool
## happened to say which chunks it wrote, and a stroke buffer's commit does not.
func _owe_map() -> void:
    var live := SaLiveTransform.of(_contents) if _contents != null else null
    if live != null:
        live.moved_all()


static func _resume_by_id(easel_id: int) -> void:
    resume(instance_from_id(easel_id) as SaEasel)


## Folds the caches again and marks every chunk, because what the canvas
## leaves out moved for every layer at once. Marked as a reveal, since no
## layer's paint or eye moved and an effect layer's cache draws its input
## whatever the view leaves out.
static func _recomposite(document: SaDocument) -> void:
    if document == null:
        return
    if document.fold != null and document.active_layer != null:
        document.update_caches(Rect2(), true)
    else:
        document.reveal_all_allocated_chunks()


## The document pixels the shown layers' paint covers, the empty box when
## they hold none. A generated or an adjustment layer covers the document, and
## a group answers for its members.
static func painted_box(document: SaDocument) -> Rect2i:
    var whole := Rect2i(Vector2i.ZERO, document.canvas_size)
    var box := Rect2i()
    var measure := Measure.new()
    for layer in SaLayerStack.layers(document):
        if layer.is_group or not _inside_shown(document, layer):
            continue
        var found := whole if layer.is_generated() or layer.is_adjustment() else measure.painted(layer, whole)
        if found.has_area():
            box = found if not box.has_area() else box.merge(found)
    return box


## Whether *layer* is a shown layer or sits in a shown group, which a group the
## shown layer sits in is not: its other members are left out.
static func _inside_shown(document: SaDocument, layer: SaLayer) -> bool:
    for kept in shown(document):
        if SaLayerStack.is_inside(layer, kept):
            return true
    return false


## The reduction over one layer's chunks: `local_view_bounds.gmacs` over every
## chunk the layer holds and nowhere else, which is hard rules 2 and 3, and
## four ints read back, which is hard rule 1's allowance for a command that
## has finished rather than a stroke. *fallback* where there is no device or a
## chunk holds no colour to say where its paint is.
class Measure:
    extends RefCounted

    var _compute: SaCompute = null
    var _box: SaCompute.Buffer = null

    func painted(layer: SaLayer, fallback: Rect2i) -> Rect2i:
        if layer.chunks.is_empty():
            return Rect2i()
        if GlobalShaderCompiler.get_rd() == null:
            return fallback
        for chunk: SaChunk in layer.chunks.values():
            var albedo: SaTexture = chunk.fields.get(SaFieldSpec.ALBEDO, null)
            if albedo == null or not albedo.rid.is_valid():
                return fallback
        if _compute == null:
            _compute = SaCompute.new(SHADER)
        var wide := PackedInt32Array([BOX_WIDE, BOX_WIDE, -BOX_WIDE, -BOX_WIDE]).to_byte_array()
        if _box == null:
            _box = SaCompute.Buffer.new(wide)
        else:
            _box.update(wide)
        var reach := SaChunkWalk.reach_of(layer.chunks.keys())
        var chunk_at := func(grid_pos: Vector2i) -> SaChunk: return layer.chunks.get(grid_pos, null)
        for field_id: StringName in [SaFieldSpec.ALBEDO, SaFieldSpec.HEIGHT]:
            var channel := 1.0 if field_id == SaFieldSpec.HEIGHT else 0.0
            var push := func(grid_pos: Vector2i, local: Rect2i, start: Vector2i) -> PackedFloat32Array:
                var chunk: SaChunk = layer.chunks[grid_pos]
                var scale := float(chunk.pixel_size()) / SaChunk.SIZE
                var origin := grid_pos * SaChunk.SIZE
                return PackedFloat32Array([start.x, start.y, local.end.x, local.end.y, origin.x, origin.y, scale, channel])
            SaChunkWalk.new(_compute, null, null, field_id).run(SHADER, reach, chunk_at, push, {BOUNDS_BINDING: _box})
        var read := _box.read().to_int32_array()
        if read.size() < 4 or read[2] < read[0] or read[3] < read[1]:
            return Rect2i()
        return Rect2i(read[0], read[1], read[2] - read[0] + 1, read[3] - read[1] + 1)
