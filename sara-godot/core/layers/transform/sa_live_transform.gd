## A live transform on a paint layer: a projective map the layer is drawn
## through while its own chunks keep the paint as it was painted, so the map
## stays editable for as long as the painter wants.
##
## **The map.** A 3 by 3 projective matrix, a `Basis` read as one, which takes
## a document position (x, y, 1) to (X, Y, W) and the point to (X / W, Y / W).
## A move, a turn, a scale, a skew and a perspective are all one map. It is set
## in the constructor and never written again, so a change of the map is a new
## object, and one history step swaps the two.
##
## **The cache.** An unparented layer holding the paint resampled through the
## map by `live_transform.gmacs`, the core's own bilinear read, which an
## `SaLiveKernel` dispatches, with the layer's mask folded into its alpha, so
## the mask moves with the paint. A chunk of it is allocated only where the
## moved footprint of a chunk the layer holds lands inside the canvas, which is
## hard rule 3, and only what moved is resampled again, which is hard rule 2.
## The fold composites the cache in the layer's place with the layer still the
## node whose filters run over it, and the walk reads it for the active layer,
## both through [method paint_of].
##
## **What moved.** The layer tells its live transform where its paint changed,
## from `SaLayer.mark_unresolved` and the other places a chunk is written or
## dropped, and the next [method paint_of] resamples those footprints alone,
## over the dirty region [method refresh] was handed for each. The compositor
## hands [method refresh] its dirty regions before it walks them, and a region
## at a position the layer holds paint at is mapped through the map, so a
## change of the layer's opacity, mode or visibility redraws where the paint
## shows rather than where it was painted.
##
## **The crop.** An `SaLiveCrop`, kept with the map and saved with it, outside
## which the layer draws nothing. The Crop tool's box shows it as the drag goes,
## [method crop_to], each change drawing again only the strips between two
## crops. Enter is one step, [method commit], which writes it into an ordinary
## layer (`SaTransformBake`), and Escape puts the transform back.
##
## **Painted through the inverse.** A brush stroke on a layer whose map is
## affine lands in the layer's own pixels where the map shows it under the
## pointer: `SaPaintContext` takes each region back through
## [method layer_area] and each dab's size, turn and mirror through
## [method dab], and the stroke buffer holds the stroke in the layer's pixels,
## so the commit composites it chunk for chunk as on any layer. The walk would
## draw that buffer where it was painted, so the paint context hides it from
## the walk, and the cache draws it over the layer's paint instead, as the
## commit will leave it, until the buffer lets it go and [method _unstroke]
## shows it again. A perspective, a selection, a smudge and every tool but the
## brush still refuse paint, `SaLayer.refuses_paint`, with the sentence
## `SaContext.paint_refusal_line` gives. While its contents are open,
## `SaLocalView`, the layer is drawn and painted as an ordinary one.
##
## **Smart and ordinary.** Only a smart layer keeps one of these at rest, `SaSmartLayer`, and the Transform tool resamples
## an ordinary layer at Enter. Convert to Ordinary Layer, [method bake], writes
## the map into the chunks, one step, as Merge Down and Flatten do.
class_name SaLiveTransform
extends RefCounted

## The key a layer's `.sad` entry keeps the map under, nine floats row by row.
## Absent for a layer drawn where it was painted, which is every file written
## before this key.
const KEY := "transform"
## The name a change of the map takes in the history and in the corner.
const STEP := "Transform Layer"
## The name the bake takes in the history, in the corner and on the Layer menu.
const BAKE := "Convert to Ordinary Layer"
## How near nought a map's w may come at a corner of the canvas's grid before
## the layer would cross the horizon of a perspective.
const HORIZON := 1.0e-6
## The name a change of the crop takes in the history and in the corner.
const CROP_STEP := "Crop Layer"
## The writer of a crop into a layer's chunks, for a module that sees this door only.
const IN_CHUNKS := preload("sa_transform_bake.gd")
## How large a map's two w terms may be together, against its constant, for
## the map to count as affine and take a stroke.
const AFFINE := 1.0e-9

## The map from a position in the layer's paint to where it shows. Read it
## anywhere, and make a new object for another map.
var matrix := Basis.IDENTITY
## The rectangle of the layer's own pixels it draws. Set in the constructor
## beside the map and never written again.
var crop := SaLiveCrop.new()
## Whether the painter made the layer smart, so it keeps a transform at rest,
## an identity included, `SaSmartLayer`. Set in the constructor.
var smart := false
## The paint shared with other smart layers, `SaSharedSource`, or null.
var source: SaSharedSource = null

var _inverse := Basis.IDENTITY
## The paint resampled through the map, made at the first refresh.
var _cache: SaLayer = null
## The layer's grid positions whose paint changed since the last refresh.
var _moved: Dictionary[Vector2i, bool] = {}
## The parts of the layer's grid positions a change of the crop owes the cache,
## chunk-local, written when this transform took over another's cache.
var _owed: Dictionary[Vector2i, Rect2i] = {}
## Where a stroke changed the layer's paint since the last refresh, held
## position to the region in the layer's own pixels, which [method painted]
## knows where `SaLayer` tells only the position.
var _painted: Dictionary[Vector2i, Rect2i] = {}
## Where the stroke buffer holds a stroke under way on the layer, held
## position to the region it painted, which the cache draws over the layer's
## paint until the buffer lets it go.
var _stroked: Dictionary[Vector2i, Rect2i] = {}
## Whether the layer's chunk at each held position shows on the canvas, for
## [method lands], and the canvas in grid positions it was answered for.
var _lands: Dictionary[Vector2i, bool] = {}
var _lands_grid := Rect2i()
## Whether the whole cache is owed: at the start, after a change nothing said
## the positions of, and once the history lets it go.
var _all := true
## The layer's mask as the last refresh saw it, whose change is a whole cache.
var _mask_seen := ""
## The kernel the paint is resampled through, which the cache's next transform
## takes over.
var _kernel: SaLiveKernel = null


func _init(map := Basis.IDENTITY, kept: SaLiveCrop = null, made_smart := false, shared: SaSharedSource = null) -> void:
    matrix = map
    smart = made_smart
    source = shared
    crop = kept if kept != null else SaLiveCrop.new()
    _inverse = map.inverse() if absf(map.determinant()) > 0.0 else Basis.IDENTITY
    _kernel = SaLiveKernel.new(_inverse, Rect2(crop.kept()))


## The live transform of *layer*, or null for a layer drawn where it was painted.
static func of(layer: SaLayer) -> SaLiveTransform:
    return layer.live_transform as SaLiveTransform if layer != null else null


## The layer whose chunks show *layer*'s paint: the cache of its live transform,
## brought up to date first, or *layer* itself when it has none. What the fold
## and the walk composite in its place.
static func paint_of(layer: SaLayer) -> SaLayer:
    var live := of(layer)
    if live == null or SaLocalView.untransformed(layer) or SaSceneTransform.passes(layer, live):
        return layer
    var changed := live._settle(layer, {})
    if not changed.is_empty():
        (layer.get_parent() as SaDocument).invalidate_chunk_regions(changed)
    return live._cache


## *point*, a document position in the layer's paint, where the map shows it.
func map_point(point: Vector2) -> Vector2:
    return _project(matrix, point)


## *point*, where the map shows paint, back in the layer's own pixels.
func unmap_point(point: Vector2) -> Vector2:
    return _project(_inverse, point)


## Whether the map keeps parallel lines parallel, a move, a turn, a scale or a
## skew, which a stroke is painted through. A perspective does not.
func affine() -> bool:
    return absf(matrix.x.z) + absf(matrix.y.z) <= AFFINE * absf(matrix.z.z)


## Whether a tool on *layer* paints into its own pixels, `SaLayer.refuses_paint`:
## any tool while its contents are open, and a brush, *mapped*, through an
## affine map with no selection active, since the selection is drawn in the
## document and a dab is masked in the layer's pixels.
func takes_paint(layer: SaLayer, mapped := true) -> bool:
    var document := layer.get_parent() as SaDocument if layer != null else null
    var through := mapped and affine() and (document == null or not document.selection.active)
    return through or SaLocalView.untransformed(layer)


## The box in the layer's own pixels that *area* of the document shows: the
## box around its four corners taken back through the map, which holds the
## whole of it, since the map takes a rectangle to a convex quad.
func layer_area(area: Rect2) -> Rect2:
    var box := Rect2(unmap_point(area.position), Vector2.ZERO)
    for corner: Vector2 in [Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)]:
        box = box.expand(unmap_point(corner))
    return box


## Whether the layer's chunk at *held* shows anywhere on *document*'s canvas
## through the map, the only place a stroke may make one, as the paint context
## makes none wholly past the canvas's edge for a layer drawn where it was
## painted, hard rule 3. Kept per position until the canvas changes.
func lands(document: SaDocument, held: Vector2i) -> bool:
    var grid := _grid(document)
    if grid != _lands_grid:
        _lands.clear()
        _lands_grid = grid
    if not _lands.has(held):
        _lands[held] = not SaLiveKernel.reached(_quad(_part(held, SaDocument.WHOLE_CHUNK)), grid).is_empty()
    return _lands[held]


## *data*, a dab's push constant packed in the document's frame, with its half
## extent, its turn and its mirror taken into the layer's own pixels and its
## falloff following the half extent, [method SaLiveDab.back].
func dab(data: PackedFloat32Array) -> PackedFloat32Array:
    return SaLiveDab.back(_inverse, data)


## Notes that a stroke on *document*'s active layer, the layer this map draws,
## painted *regions*, grid position to chunk-local region in the layer's own
## pixels, into the layer, or into the stroke buffer over it with *buffered*,
## and answers where they show in the document: the stroke's dirty regions
## taken forward through the map, which the paint context invalidates in their
## place. The next refresh draws the cache over them, the buffer's stroke over
## the layer's paint.
func painted(document: SaDocument, regions: Dictionary[Vector2i, Rect2i], buffered: bool) -> Dictionary[Vector2i, Rect2i]:
    var shown: Dictionary[Vector2i, Rect2i] = {}
    var grid := _grid(document)
    for held: Vector2i in regions:
        var region: Rect2i = regions[held]
        _add(_painted, held, region)
        if buffered:
            _add(_stroked, held, region)
        var reached := SaLiveKernel.reached(_quad(_part(held, region)), grid)
        for grid_pos: Vector2i in reached:
            _add(shown, grid_pos, reached[grid_pos])
    return shown


## Notes that the layer's paint changed at *grid_pos*. `SaLayer` calls it.
func moved(grid_pos: Vector2i) -> void:
    _moved[grid_pos] = true
    if source != null:
        source.moved(grid_pos)


## Notes that the layer's paint may have changed anywhere, for a write that
## replaced its chunks without saying where. `SaLayer` calls it.
func moved_all() -> void:
    _all = true
    if source != null:
        source.moved_all()


## Lets the cache go, for a map the history keeps while the layer shows
## another. The refresh after it is put back makes the cache again.
func release() -> void:
    if _cache != null:
        _cache.release_chunks()
    _moved.clear()
    _painted.clear()
    _stroked.clear()
    _all = true


## Brings every live transform of *document* up to date before a compositor
## walks *dirty*, grid position to chunk-local region, and answers the regions
## to walk: *dirty*, and each region of it at a position a transformed layer
## holds paint at taken through that layer's map onto the cache chunks it
## reaches, and where a cache changed in bringing it up to date, the
## footprint of what moved. With *whole* every cache chunk is walked, for a composite of the
## whole document, which gathers the positions of the layers it holds and not
## of a cache. *dirty* itself is never written.
static func refresh(document: SaDocument, dirty: Dictionary[Vector2i, Rect2i], whole: bool) -> Dictionary[Vector2i, Rect2i]:
    var walked := dirty
    var asked := false
    for child in document.get_children():
        var layer := child as SaLayer
        var live := of(layer)
        if live == null or SaSceneTransform.passes(layer, live):
            continue
        var changed := live._settle(layer, dirty)
        if not changed.is_empty() and layer != document.active_layer:
            # A cache the fold baked into a run's shows once the fold is built
            # again, which happens before the next frame, and that frame
            # composites where it changed.
            document.invalidate_chunk_regions(changed)
            asked = true
        var mapped := live._mapped(layer, dirty, whole)
        if changed.is_empty() and mapped.is_empty():
            continue
        if walked == dirty:
            walked = dirty.duplicate()
        for found: Dictionary in [changed, mapped]:
            for grid_pos: Vector2i in found:
                var region: Rect2i = found[grid_pos]
                walked[grid_pos] = (walked[grid_pos] as Rect2i).merge(region) if walked.has(grid_pos) else region
    if asked:
        document.request_cache_update()
    return walked


## What [method refresh] adds to the walk for *layer*: each region of *dirty* at
## a position the layer holds paint at, through the map, on the cache chunks it
## reaches, and every cache chunk with *whole*.
func _mapped(layer: SaLayer, dirty: Dictionary[Vector2i, Rect2i], whole: bool) -> Dictionary[Vector2i, Rect2i]:
    var found: Dictionary[Vector2i, Rect2i] = {}
    if _cache == null:
        return found
    var shown := _cache.chunks
    if whole:
        for grid_pos: Vector2i in shown:
            found[grid_pos] = SaDocument.WHOLE_CHUNK
        return found
    var grid := _grid(layer.get_parent() as SaDocument)
    for held: Vector2i in dirty:
        if not layer.chunks.has(held):
            continue
        var reached := SaLiveKernel.reached(_quad(_part(held, dirty[held])), grid)
        for grid_pos: Vector2i in reached:
            if shown.has(grid_pos):
                found[grid_pos] = (
                    (found[grid_pos] as Rect2i).merge(reached[grid_pos]) if found.has(grid_pos) else reached[grid_pos]
                )
    return found


## Why *layer* of *document* cannot be drawn through *map*, a `Basis`, as a
## sentence, or empty when it can. Null takes the transform off, which is
## never refused. A relief is not refused, since its height moves with it.
static func refusal(document: SaDocument, layer: SaLayer, map: Variant) -> String:
    var why := _refusal(document, layer, map)
    return "" if why.is_empty() else TranslationServer.translate(str(why[0])) % why.slice(1)


## The refusal as its untranslated sentence and the name it takes, the way
## `SaEffectLayer` keeps its own.
static func _refusal(document: SaDocument, layer: SaLayer, map: Variant) -> Array:
    if document == null or layer == null or layer.get_parent() != document:
        return ["There is no layer here to transform."]
    if map == null:
        return []
    var name := String(layer.name)
    if SaLocalView.untransformed(layer):
        return ["'%s' is open for painting in Edit Smart Layer Contents. Close it there first.", name]
    if layer.is_group:
        return ["'%s' is a group. The Transform tool moves every layer inside it together.", name]
    if layer.is_generated() or layer.is_adjustment() or layer.is_effect():
        return ["'%s' holds no paint of its own to transform.", name]
    if layer.is_locked:
        return ["'%s' is locked. Unlock it in the Layers docker first.", name]
    if layer.resolution_scale != 1.0:
        return ["'%s' is at another resolution than the document. Resample it to the document's resolution first.", name]
    var flat := ["That transform folds '%s' flat, so it was not set.", name]
    if not map is Basis:
        return flat
    var basis: Basis = map
    if absf(basis.determinant()) < 1.0e-12:
        return flat
    if not _ahead(basis, _grid(document)):
        return ["That perspective takes '%s' past its horizon, so it was not set.", name]
    return []


## Whether *map* keeps every position of *grid*, in chunks, on the near side of
## its horizon. Its w is affine in the position, so the four corners decide.
static func _ahead(map: Basis, grid: Rect2i) -> bool:
    var side := float(SaLayer.CHUNK_SIZE)
    var area := Rect2(Vector2(grid.position) * side, Vector2(grid.size) * side).grow(2.0)
    for at: Vector2 in [area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)]:
        if (map * Vector3(at.x, at.y, 1.0)).z <= HORIZON:
            return false
    return true


## Draws *layer* through *map*, a `Basis`, or where it was painted for null, as
## one history step, and answers whether it did. A refusal is said in the
## corner. The layer's chunks are not touched, which is what keeps it live. A
## crop the layer has stays with a new map, since it is in the layer's own
## pixels, and null takes it off with the map, or on a layer made smart puts
## the identity, `SaSmartLayer.held`.
static func put(document: SaDocument, layer: SaLayer, map: Variant) -> bool:
    var why := _refusal(document, layer, map)
    if not why.is_empty():
        SaProblems.refuse(STEP, TranslationServer.translate(str(why[0])) % why.slice(1))
        return false
    var after := SaSmartLayer.held(of(layer), map)
    if _same(of(layer), after):
        return false
    put_step(document, layer, after, STEP)
    return true


## Puts *after* on *layer*, null for none, as one history step named *name*
## whose undo puts back the transform the layer had.
static func put_step(document: SaDocument, layer: SaLayer, after: SaLiveTransform, name: String) -> void:
    var before := of(layer)
    _apply(document, layer, after)
    document.history.commit_pair(name, _apply.bind(document, layer, after), _apply.bind(document, layer, before))


## Draws *layer* through *map* as [method put] does, with no history step and
## nothing said, and answers whether it did. For a tool's session, which shows
## each map as the hand moves, holds the last one drawn when a map is refused,
## and ends in one [method put]. A crop the layer has stays with each map, as
## [method put] keeps it, so a session that ends puts it back where it was.
static func preview(document: SaDocument, layer: SaLayer, map: Variant) -> bool:
    if not _refusal(document, layer, map).is_empty():
        return false
    _apply(document, layer, SaSmartLayer.held(of(layer), map))
    return true


## Puts *live* on *layer*, null for none, and redraws where the paint showed
## and where it shows now. The map that leaves lets its cache go.
static func _apply(document: SaDocument, layer: SaLayer, live: SaLiveTransform) -> void:
    var shown := SaTyped.positions(paint_of(layer).chunks)
    var before := of(layer)
    if before != null:
        before.release()
    layer.live_transform = live
    SaSharedSource.relink(layer, before, live)
    shown.merge(SaTyped.positions(paint_of(layer).chunks))
    document.modified = true
    document.invalidate_chunks(shown.keys())
    document.update_caches()


## A scene layer's transform at rest and where its scene's copy of *regions*
## shows, `SaSceneTransform`, for the scene layer, which sees this face only.
static func rest_scene(layer: SaLayer) -> void:
    SaSceneTransform.rest(layer)


static func scene_copied(
    document: SaDocument, layer: SaLayer, regions: Dictionary[Vector2i, Rect2i]
) -> Dictionary[Vector2i, Rect2i]:
    return SaSceneTransform.copied(document, layer, regions)


## Whether *layer* has a live transform to bake, which is what lights Layer >
## Convert to Ordinary Layer. A scene layer's never is, `SaSceneTransform`.
## Quiet, because the menu asks it on every open.
static func can_bake(layer: SaLayer) -> bool:
    return of(layer) != null and not SaSceneTransform.refuses_bake(layer)


## Layer > Convert to Ordinary Layer: writes what *layer* shows through its live transform
## into its own chunks and takes the transform off, as one history step, and
## answers whether it did. A locked layer is refused with a sentence in the
## corner. The undo puts the chunks back as they were painted and the
## transform back on them.
static func bake(document: SaDocument, layer: SaLayer) -> bool:
    if SaSceneTransform.refuses_bake(layer):
        SaProblems.refuse(
            BAKE, TranslationServer.translate("'%s' is drawn by its scene each frame, so its transform stays live.") % layer.name
        )
        return false
    if document == null or layer == null or layer.get_parent() != document or not can_bake(layer):
        return false
    if layer.is_locked:
        SaProblems.refuse(BAKE, TranslationServer.translate("'%s' is locked. Unlock it in the Layers docker first.") % layer.name)
        return false
    if GlobalShaderCompiler.get_rd() == null:
        return false
    var state: Dictionary[Vector2i, Variant] = {}
    var live := bake_into(document, layer, state)
    if document.history != null:
        document.history.commit(BAKE, toggled(document, layer, live, document.swap_pixels.bind(layer, state)), state)
    return true


## Writes what *layer* shows through its live transform into its own chunks and
## takes the transform off, with no step of its own, for a step that takes the
## layer as it is drawn: the bake, and a Merge Down or a Flatten into it. Each
## chunk it replaces or drops goes into *state* the first time, the way
## `SaTreeRender.bake` keeps them, so the step's swap puts each back, and the
## transform taken off is answered for [method toggled]. Null, with nothing
## written, for a layer drawn where it was painted. It ends an open contents
## view, which would draw the layer untransformed. The transform comes off
## before the new chunks go in, so its cache is never drawn from paint it was
## not made for.
static func bake_into(document: SaDocument, layer: SaLayer, state: Dictionary[Vector2i, Variant]) -> SaLiveTransform:
    SaLocalView.end_contents(document)
    var live := of(layer)
    if live == null or document == null:
        return null
    var made := live._baked(layer)
    _apply(document, layer, null)
    var positions := SaTyped.positions(layer.chunks)
    positions.merge(SaTyped.positions(made))
    for grid_pos: Vector2i in positions:
        if not state.has(grid_pos):
            state[grid_pos] = layer.chunks.get(grid_pos, null)
        var baked: SaChunk = made.get(grid_pos, null)
        layer.set_chunk(grid_pos, baked)
    document.invalidate_chunks(positions.keys())
    document.update_caches()
    document.document_changed.emit()
    return live


## *swap*, the one exchange a step runs both ways, with *live*, the transform
## [method bake_into] took off *layer*, put back after it on the undo and
## taken off before it on the redo, so the transform is never on while the
## layer holds the baked chunks. *swap* itself for a null *live*.
##
## The wrapper holds *swap*'s object as well. The history keeps the object of
## a method it is handed alive, a `SaLayerOps` made for one merge among them,
## and a lambda's object is not that one, so without the second entry the undo
## of a merge called a method on a freed object.
static func toggled(document: SaDocument, layer: SaLayer, live: SaLiveTransform, swap: Callable) -> Callable:
    if live == null:
        return swap
    var held: Array = [live, swap.get_object()]
    return func() -> void:
        var kept: SaLiveTransform = held[0]
        if of(layer) != null:
            held[0] = _exchange(document, layer, kept)
            swap.call()
        else:
            swap.call()
            held[0] = _exchange(document, layer, kept)


## Puts *live* on *layer*, null for none, and answers the transform it took off.
static func _exchange(document: SaDocument, layer: SaLayer, live: SaLiveTransform) -> SaLiveTransform:
    var before := of(layer)
    _apply(document, layer, live)
    return before


## Every chunk of *layer*'s paint through the map, at each position inside the
## canvas the moved paint lands on, with each field resampled: the paint by its
## own alpha, the height as it reads, and the mask, when the layer carries one,
## as coverage that reads its rest where the layer holds nothing. So the mask
## and the relief move with the paint, as the cache folds them in, and a mask
## switched off moves too. A derived field opens at its blank, and the layer's
## resolve works it out from the paint.
func _baked(layer: SaLayer) -> Dictionary[Vector2i, SaChunk]:
    layer.resolve_pending()
    var made: Dictionary[Vector2i, SaChunk] = {}
    var rest := layer.mask.rest if layer.mask != null and not layer.mask.is_own() else 1.0
    var reach := _reach(layer, _grid(layer.get_parent() as SaDocument))
    for grid_pos: Vector2i in reach:
        var chunk := SaChunk.create(layer.schema)
        for field_id: StringName in chunk.field_ids() + [SaFieldSpec.HEIGHT]:
            if field_id in [SaFieldSpec.ALBEDO, SaFieldSpec.HEIGHT]:
                _resample(chunk, layer, field_id, grid_pos, SaDocument.WHOLE_CHUNK, reach[grid_pos], false, 0.0)
            elif field_id == SaFieldSpec.MASK:
                _resample(chunk, layer, field_id, grid_pos, SaDocument.WHOLE_CHUNK, reach[grid_pos], false, rest)
            else:
                var blank: Color = chunk.blanks.get(field_id, SaFieldSpec.NO_PAINT)
                chunk.field(field_id).clear(blank)
        made[grid_pos] = chunk
    return made


## The map that scales by *scale* and turns by *degrees*, both about *pivot*,
## and then moves by *offset*, all in document pixels. A positive turn is
## clockwise on the screen, whose y runs down. A turn by a whole number of
## quarters is exact.
static func composed(offset: Vector2, degrees: float, scale: Vector2, pivot: Vector2) -> Basis:
    var turn := deg_to_rad(degrees)
    var c := cos(turn)
    var s := sin(turn)
    if is_zero_approx(fmod(degrees, 90.0)):
        c = roundf(c)
        s = roundf(s)
    var a := c * scale.x
    var b := -s * scale.y
    var d := s * scale.x
    var e := c * scale.y
    var tx := pivot.x - (a * pivot.x + b * pivot.y) + offset.x
    var ty := pivot.y - (d * pivot.x + e * pivot.y) + offset.y
    return _rows(Vector3(a, b, tx), Vector3(d, e, ty), Vector3(0.0, 0.0, 1.0))


## The map taking the corners of *rect*, top left, top right, bottom right and
## bottom left, to the four *corners* in that order, a perspective when they
## are no parallelogram. Null for a rectangle with no area or corners that
## make no map, three of them on one line.
static func cornered(rect: Rect2, corners: PackedVector2Array) -> Variant:
    if corners.size() != 4 or not rect.has_area():
        return null
    var p0 := corners[0]
    var p1 := corners[1]
    var p2 := corners[2]
    var p3 := corners[3]
    var dx3 := p0.x - p1.x + p2.x - p3.x
    var dy3 := p0.y - p1.y + p2.y - p3.y
    var g := 0.0
    var h := 0.0
    if not is_zero_approx(dx3) or not is_zero_approx(dy3):
        var dx1 := p1.x - p2.x
        var dx2 := p3.x - p2.x
        var dy1 := p1.y - p2.y
        var dy2 := p3.y - p2.y
        var det := dx1 * dy2 - dx2 * dy1
        if is_zero_approx(det):
            return null
        g = (dx3 * dy2 - dx2 * dy3) / det
        h = (dx1 * dy3 - dx3 * dy1) / det
    # The unit square onto the four corners, after the rectangle onto the unit
    # square.
    var square := _rows(
        Vector3(p1.x - p0.x + g * p1.x, p3.x - p0.x + h * p3.x, p0.x),
        Vector3(p1.y - p0.y + g * p1.y, p3.y - p0.y + h * p3.y, p0.y),
        Vector3(g, h, 1.0)
    )
    var unit := _rows(
        Vector3(1.0 / rect.size.x, 0.0, -rect.position.x / rect.size.x),
        Vector3(0.0, 1.0 / rect.size.y, -rect.position.y / rect.size.y),
        Vector3(0.0, 0.0, 1.0)
    )
    var map := square * unit
    if absf(map.determinant()) > 1.0e-12:
        return map
    return null


## The map as nine floats row by row, what `.sad` keeps.
func floats() -> Array[float]:
    var m := matrix
    var numbers: Array[float] = [m.x.x, m.y.x, m.z.x, m.x.y, m.y.y, m.z.y, m.x.z, m.y.z, m.z.z]
    return numbers


## The map nine numbers row by row describe, or null for anything else.
static func map_of(numbers: Variant) -> Variant:
    if not numbers is Array:
        return null
    var given: Array = numbers
    if given.size() != 9:
        return null
    for number: Variant in given:
        if not (number is float or number is int):
            return null
    var n := PackedFloat64Array(given)
    return _rows(Vector3(n[0], n[1], n[2]), Vector3(n[3], n[4], n[5]), Vector3(n[6], n[7], n[8]))


## Writes *layer*'s map, crop and smart marker into its `.sad` entry
## *layer_dict*, `SaSmartLayer.write_header`.
static func write_header(layer: SaLayer, layer_dict: Dictionary[String, Variant]) -> void:
    SaSmartLayer.write_header(layer, layer_dict)


## Gives *layer* the transform its `.sad` entry keeps, `SaSmartLayer.read_header`.
static func read_header(layer: SaLayer, layer_data: Dictionary[String, Variant]) -> void:
    SaSmartLayer.read_header(layer, layer_data)


## Layer > Make Smart Layer and Reset Transform, `SaSmartLayer`.
static func make_smart(document: SaDocument, layer: SaLayer) -> bool:
    return SaSmartLayer.make(document, layer)


static func reset_map(document: SaDocument, layer: SaLayer) -> bool:
    return SaSmartLayer.reset(document, layer)


## Says in the corner why *layer* of *document* cannot be cropped, and answers
## whether it said anything. A tool asks once, at its press, since
## [method crop_to] is asked on every move of a drag and says nothing.
static func crop_refused(document: SaDocument, layer: SaLayer) -> bool:
    var live := of(layer)
    var why := _refusal(document, layer, live.matrix if live != null else Basis.IDENTITY)
    if why.is_empty():
        return false
    SaProblems.refuse(CROP_STEP, TranslationServer.translate(str(why[0])) % why.slice(1))
    return true


## Shows *layer* cropped to *box*, a rectangle in document pixels, under the
## map it has, with no history step, and answers whether it did. The crop is
## the box taken back through the map into the layer's own pixels, the
## smallest rectangle holding its four corners.
static func crop_to(document: SaDocument, layer: SaLayer, box: Rect2i) -> bool:
    if not box.has_area():
        return false
    var live := of(layer)
    var map := live.matrix if live != null else Basis.IDENTITY
    var kept := SaLiveCrop.through(map, box)
    if not kept.any():
        return false
    if live != null and live.crop.rect == kept.rect:
        return true
    return show_live(document, layer, SaLiveTransform.new(map, kept, live != null and live.smart, SaSharedSource.of(layer)))


## *layer*'s crop through its map, in document pixels, the smallest rectangle
## holding its four corners, and empty for a layer with no crop. What the Crop
## tool reports.
static func crop_box(layer: SaLayer) -> Rect2i:
    var live := of(layer)
    return live.crop.box(live.matrix) if live != null else Rect2i()


## Shows *layer* drawn through *live*, null for where it was painted, with no
## history step, and answers whether it did: what a tool shows while its drag
## goes, and how Escape puts back the transform it opened on. *live* takes
## over the cache of the transform it replaces, so a change of the crop alone
## draws again only the strips between the two rectangles. Quiet, because a
## drag asks on every move, and [method crop_refused] is what to say instead.
static func show_live(document: SaDocument, layer: SaLayer, live: SaLiveTransform) -> bool:
    if document == null or layer == null or layer.get_parent() != document:
        return false
    if live != null and not _refusal(document, layer, live.matrix).is_empty():
        return false
    var before := of(layer)
    if live == before:
        return true
    if live == null or before == null:
        # A first cache or none, drawn the way a step is done and undone.
        _apply(document, layer, live)
        return true
    live._take(before, layer)
    layer.live_transform = live
    document.modified = true
    document.invalidate_chunk_regions(live._settle(layer, {}))
    if layer != document.active_layer:
        document.update_caches()
    return true


## One history step named *step* taking *layer* from *before*, its transform
## when a tool's session opened, to the one [method show_live] put on, and
## whether there was a change to write. An ordinary layer, *before* null, has
## what it shows written into its chunks instead, `SaTransformBake`.
static func commit(document: SaDocument, layer: SaLayer, before: SaLiveTransform, step: String = CROP_STEP) -> bool:
    if document == null or layer == null or layer.get_parent() != document:
        return false
    var after := of(layer)
    if _same(before, after):
        return false
    if before == null and SaTransformBake.crop_in(document, layer, step):
        return true
    document.modified = true
    if document.history != null:
        document.history.commit_pair(step, _apply.bind(document, layer, after), _apply.bind(document, layer, before))
    return true


## Whether *layer* shows other than *before*, what [method commit] would write.
static func changed_from(layer: SaLayer, before: SaLiveTransform) -> bool:
    return not _same(before, of(layer))


## Whether *one* and *other* draw a layer alike: both none, or one map and crop.
static func _same(one: SaLiveTransform, other: SaLiveTransform) -> bool:
    if one == null or other == null:
        return one == other
    return one.matrix == other.matrix and one.crop.rect == other.crop.rect


## Takes over *from*'s cache, what *layer* showed before this transform. Under
## the same map only the strips between the two crops are owed, with what *from*
## still owed, and under another the whole cache, still the one object the
## fold's stack holds until its rebuild. *from* makes one again when shown again.
func _take(from: SaLiveTransform, layer: SaLayer) -> void:
    if from == null or from._cache == null or _cache != null:
        return
    var given := from._give()
    _cache = given[0]
    var kernel: SaLiveKernel = given[1]
    _kernel = SaLiveKernel.new(_inverse, Rect2(crop.kept()), kernel)
    _mask_seen = given[2]
    var owed_whole: bool = given[3]
    _all = owed_whole or matrix != from.matrix
    _moved = given[4]
    _owed = given[5]
    if _all:
        return
    var side := SaLayer.CHUNK_SIZE
    for held: Vector2i in layer.chunks:
        var cell := Rect2i(held * side, Vector2i(side, side))
        var strip := crop.owed(from.crop, cell)
        if strip.has_area():
            _owed[held] = (_owed[held] as Rect2i).merge(strip) if _owed.has(held) else strip


## Gives up the cache and what it is drawn with, in the order [method _take]
## reads them, and is left owing a whole cache it makes again when it is shown
## again.
func _give() -> Array:
    var given: Array = [_cache, _kernel, _mask_seen, _all, _moved, _owed]
    _cache = null
    _all = true
    _moved = {}
    _owed = {}
    return given


## Brings the cache up to date with *layer*: whole when that is owed, and
## otherwise over the footprints of the positions that moved, each over the
## region a stroke painted there and the region *dirty* holds for a position the
## layer said moved, or its whole chunk where *dirty* holds none. A cache chunk
## nothing reaches any more is dropped. Answers where the cache changed, which
## its caller hands to the walk or says to the document. The layer's derived
## fields are resolved first, as the walk resolves them, since it reads colour.
func _settle(layer: SaLayer, dirty: Dictionary[Vector2i, Rect2i]) -> Dictionary[Vector2i, Rect2i]:
    layer.resolve_pending()
    _follow_format(layer)
    var mask_now := _mask_key(layer)
    if mask_now != _mask_seen:
        _mask_seen = mask_now
        _all = true
    var document := layer.get_parent() as SaDocument
    var changed: Dictionary[Vector2i, Rect2i] = {}
    if document == null:
        return changed
    _unstroke(layer, document)
    if not _all and _moved.is_empty() and _painted.is_empty() and _owed.is_empty():
        return changed
    var grid := _grid(document)
    var reach := _reach(layer, grid)
    var asked: Dictionary[Vector2i, Rect2i] = {}
    if _all:
        for grid_pos: Vector2i in reach:
            asked[grid_pos] = SaDocument.WHOLE_CHUNK
    else:
        var held_regions: Dictionary[Vector2i, Rect2i] = _painted.duplicate()
        for held: Vector2i in _moved:
            var region: Rect2i = dirty.get(held, SaDocument.WHOLE_CHUNK)
            _add(held_regions, held, region)
        for held: Vector2i in held_regions:
            var reached := SaLiveKernel.reached(_quad(_part(held, held_regions[held])), grid)
            for grid_pos: Vector2i in reached:
                _add(asked, grid_pos, reached[grid_pos])
        # A strip the crop gave or took, through the map whole, because what
        # a crop took away is outside the crop it has now.
        for held: Vector2i in _owed:
            var owed := SaLiveKernel.reached(_footprint(_part(held, _owed[held])), grid)
            for grid_pos: Vector2i in owed:
                _add(asked, grid_pos, owed[grid_pos])
    _all = false
    _moved.clear()
    _painted.clear()
    _owed.clear()
    for grid_pos: Vector2i in _cache.chunks.keys():
        if not reach.has(grid_pos):
            _cache.set_chunk(grid_pos, null)
            changed[grid_pos] = SaDocument.WHOLE_CHUNK
    for grid_pos: Vector2i in asked:
        if reach.has(grid_pos):
            _draw(layer, grid_pos, asked[grid_pos], reach[grid_pos])
            changed[grid_pos] = asked[grid_pos]
    return changed


## Makes the cache at the depth of *layer*'s colour, and empties it when the
## depth changed, which owes the whole of it again.
func _follow_format(layer: SaLayer) -> void:
    var format: int = layer.schema[0].format if not layer.schema.is_empty() else RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    if _cache == null:
        _cache = SaLayer.new()
    elif _cache.schema[0].format == format:
        return
    # The same object rather than a new one, because the fold's stack holds it
    # until the next rebuild, and a freed one there would be read.
    _cache.release_chunks()
    _cache.schema = SaFieldSpec.default_schema(format)
    _all = true


## What the cache depends on of *layer*'s mask: nothing when it hides nothing,
## and which mask and its rest otherwise.
static func _mask_key(layer: SaLayer) -> String:
    var mask := layer.mask
    if mask == null or not mask.enabled:
        return ""
    return "%d %s" % [mask.get_instance_id(), mask.rest]


## Lets go of the stroke the buffer no longer holds, committed or dropped: what
## it painted is owed again from the layer's own paint, and once none of it is
## left the buffer shows to the walk again, which the paint context hid it from.
func _unstroke(layer: SaLayer, document: SaDocument) -> void:
    if _stroked.is_empty():
        return
    var stroke := _stroke_of(layer)
    for held: Vector2i in _stroked.keys():
        if stroke == null or not stroke.chunks.has(held):
            _add(_painted, held, _stroked[held])
            _stroked.erase(held)
    if _stroked.is_empty() and document.stroke_layer != null:
        document.stroke_layer.visible = true


## The document's stroke buffer while it holds a stroke on *layer* painted
## through the map, which the cache draws over the layer's paint, or null.
func _stroke_of(layer: SaLayer) -> SaLayer:
    var document := layer.get_parent() as SaDocument
    if _stroked.is_empty() or document == null or layer != document.active_layer:
        return null
    return document.stroke_layer


## Every cache position inside *grid* a chunk *layer* holds reaches through the
## map, to the held positions that reach it, the stroke buffer's among them
## while it holds a stroke on the layer.
func _reach(layer: SaLayer, grid: Rect2i) -> Dictionary[Vector2i, Array]:
    var found: Dictionary[Vector2i, Array] = {}
    var holds := SaTyped.positions(layer.chunks)
    var stroke := _stroke_of(layer)
    if stroke != null:
        holds.merge(SaTyped.positions(stroke.chunks))
    for held: Vector2i in holds:
        for grid_pos: Vector2i in SaLiveKernel.reached(_quad(_part(held, SaDocument.WHOLE_CHUNK)), grid):
            if not found.has(grid_pos):
                found[grid_pos] = []
            (found[grid_pos] as Array).append(held)
    return found


## Resamples *region* of the cache chunk at *grid_pos* from the chunks of
## *layer* at *sources*, the paint and the height weighted by the layer's mask,
## and a source the stroke buffer holds a stroke at read with the stroke over it.
func _draw(layer: SaLayer, grid_pos: Vector2i, region: Rect2i, sources: Array) -> void:
    var chunk := _cache.get_or_create_chunk(grid_pos)
    for field_id: StringName in [SaFieldSpec.ALBEDO, SaFieldSpec.HEIGHT]:
        _resample(chunk, layer, field_id, grid_pos, region, sources, true, 0.0)


## Resamples *region* of *chunk*'s field *field_id*, at *grid_pos*, from that
## field of *layer*'s chunks at *sources*, through the kernel,
## each over the part of the region it reaches through the map. The cache,
## *masked*, reads a stroke painted through the map over the paint while the
## stroke buffer holds it, over the part of each source the region reads.
func _resample(
    chunk: SaChunk,
    layer: SaLayer,
    field_id: StringName,
    grid_pos: Vector2i,
    region: Rect2i,
    sources: Array,
    masked: bool,
    rest: float
) -> void:
    var origin := Vector2(grid_pos * SaLayer.CHUNK_SIZE)
    var here := Rect2i(grid_pos, Vector2i.ONE)
    var stroke: SaLayer = _stroke_of(layer) if masked and field_id == SaFieldSpec.ALBEDO else null
    var parts: Dictionary[Vector2i, Rect2i] = {}
    var under: Dictionary[Vector2i, Rect2] = {}
    for held: Vector2i in sources:
        var got: Rect2i = SaLiveKernel.reached(_quad(_part(held, SaDocument.WHOLE_CHUNK)), here).get(grid_pos, Rect2i())
        var part := got.intersection(region)
        if part.has_area():
            parts[held] = part
        if part.has_area() and stroke != null:
            under[held] = layer_area(Rect2(origin + Vector2(part.position), Vector2(part.size)))
    _kernel.resample(chunk, layer, field_id, grid_pos, region, parts, stroke, under, masked, rest)


## Takes *region* into *found* at *grid_pos*, the union where it holds one.
static func _add(found: Dictionary[Vector2i, Rect2i], grid_pos: Vector2i, region: Rect2i) -> void:
    found[grid_pos] = (found[grid_pos] as Rect2i).merge(region) if found.has(grid_pos) else region


## *region*, chunk-local at the layer's *held* position, in document pixels.
static func _part(held: Vector2i, region: Rect2i) -> Rect2:
    return Rect2(Vector2(held * SaLayer.CHUNK_SIZE + region.position), Vector2(region.size))


## [method _footprint] of the part of *area* inside the crop, which is what
## the layer draws of it, and empty when no part is.
func _quad(area: Rect2) -> PackedVector2Array:
    var kept := area.intersection(Rect2(crop.kept()))
    if not kept.has_area():
        return PackedVector2Array()
    return _footprint(kept)


## The four corners of *area* through the map, grown first by what a read
## reaches past it, `SaLiveKernel.reach`: a texel whose centre the map takes
## back within that reach of *area* reads something of it. Empty when a corner
## is past the horizon, which only paint outside the canvas can be, since a
## map whose horizon crosses the canvas is refused.
func _footprint(area: Rect2) -> PackedVector2Array:
    var grown := area.grow(_kernel.reach(area))
    var corners := [grown.position, Vector2(grown.end.x, grown.position.y), grown.end, Vector2(grown.position.x, grown.end.y)]
    var quad := PackedVector2Array()
    for corner: Vector2 in corners:
        if (matrix * Vector3(corner.x, corner.y, 1.0)).z <= HORIZON:
            return PackedVector2Array()
        quad.append(map_point(corner))
    return quad


## The canvas of *document* in grid positions.
static func _grid(document: SaDocument) -> Rect2i:
    if document == null:
        return Rect2i()
    var side := float(SaLayer.CHUNK_SIZE)
    return Rect2i(Vector2i.ZERO, Vector2i(ceili(document.canvas_size.x / side), ceili(document.canvas_size.y / side)))


static func _project(map: Basis, point: Vector2) -> Vector2:
    var h := map * Vector3(point.x, point.y, 1.0)
    return Vector2(h.x, h.y) / h.z


## The matrix whose rows are *x*, *y* and *w*.
static func _rows(x: Vector3, y: Vector3, w: Vector3) -> Basis:
    return Basis(Vector3(x.x, y.x, w.x), Vector3(x.y, y.y, w.y), Vector3(x.z, y.z, w.z))


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        if _cache != null:
            _cache.free()
            _cache = null
        _kernel = null
