## Cropping the document to a rectangle, and growing it about an anchor, as
## one undoable step.
##
## A crop moves the document's origin, so every texel moves with it and the
## chunk grid has to be rebuilt: a chunk wholly outside the rectangle is
## dropped, one across the edge is kept as the part that survived, and where
## the origin is not a multiple of the chunk edge every destination chunk is
## assembled out of up to four source chunks. `crop.gmacs` copies one overlap
## at a time and the arithmetic here decides what the overlaps are.
##
## Undo restores the size and the chunks together, because either alone is a
## document that disagrees with itself. The step therefore holds every layer's
## whole chunk dictionary rather than a per-chunk delta: the chunks that were
## released have nowhere else to be kept, and they are what undo has
## to bring back.
##
## The selection is dropped rather than moved. Its own chunks are in the old
## coordinates, and a selection that survived a crop by a hundred pixels while
## pointing a hundred pixels off would be worse than none.
##
## No clip makes this a crop only. A rectangle whose origin is negative, or
## which reaches past the canvas, is a legal request: `_retile` walks the
## *destination* grid, so a grow is the same pass. `crop_to` has no clip either,
## because the crop tool's rectangle is what the painter dragged and a hand that
## pulled a corner off the canvas was asking for the ground beyond it. Crop to
## Selection clips on its own line instead: its rectangle is the selection's
## bounds rather than a gesture, and a menu entry that quietly grew the document
## would be a different operation under the same name.
##
## The Crop tool's Canvas choice keeps everything: `crop_to` with
## *keep_outside* walks the destination grid over every source chunk as well as
## over the new canvas, so a chunk wholly outside the rectangle is moved with the
## rest to a grid position past the new edge, negative ones included, where
## nothing composites it and the `.sad` saves it. Image > Canvas Size growing the
## document back then finds it, because its retile reads the source grid by
## position whatever the sign. Without the flag a chunk wholly outside is dropped,
## which is what Crop to Selection and a trim by Canvas Size still do.
##
## A crop leaves the last chunk of a row or a column holding whatever fell past
## the new edge. A chunk is 256 texels wide and a canvas edge almost never
## lands on that grid, so the overhang is copied across with everything else,
## invisible until Image > Canvas Size grows the document back and hands the
## painter a band of the picture they thought they had thrown away. Clearing it
## is what the crop tool's Canvas and Delete Outside choice asks for, and the
## other choices keep it because the overhang is also what makes a crop cheap to
## undo by growing.
##
## A grow lays the ground down before it copies the old picture over. Left to
## allocate only where a source overlaps, a grow gave the canvas back nothing at
## all in the region it added, and a document whose background stores its pixels
## covers the rectangle it was made at and no more, so every side the canvas
## gained read as transparent. The ground goes into the destination chunk first
## and the old texels land on top of it, which is also the only way a chunk
## straddling the old edge comes out whole: allocating by overlap alone left a
## transparent strip up to a chunk wide along it.
class_name SaCrop
extends RefCounted

## The history step both the tool and Image > Crop to Selection leave behind.
const ACTION_NAME := "Crop"

## What Image > Canvas Size leaves behind instead. A separate name because the
## undo menu is where a painter looks to find out what they just did, and a
## dialog they opened off the Image menu is not the crop tool. The name follows
## the command and not the direction the size moved, which is why the crop tool
## still writes "Crop" when its rectangle grew the canvas.
const RESIZE_ACTION_NAME := "Canvas Size"

var _document: SaDocument
var _compute: SaCompute = null
var _blank_compute: SaCompute = null
## How many chunks this object's steps have worked out for layers, a user of a
## shared source that took another user's set counting none. Read by a suite.
var chunks_made := 0


func _init(document: SaDocument) -> void:
    _document = document


## Crops to *rect*, in the document's current pixels. True when it happened.
##
## A rectangle reaching past the canvas takes the ground with it. The painter
## dragged the rectangle they wanted, and clipping it here threw away the half
## of the gesture that was outside, so a crop can now also grow. What the
## canvas gains is the document's own background, `resize_to`'s rule and not
## transparency, because a transparent margin is a defect. A rectangle wholly
## inside the canvas asks for no ground, so a plain crop still allocates only
## where a source chunk was found and hard rule 3 holds.
##
## The step is `ACTION_NAME` either way. The name follows the command the
## painter used and not the direction the size moved: they pressed Crop, in the
## crop tool, and an undo entry reading "Canvas Size" would send them looking
## for a dialog they never opened.
##
## *clear_outside* is the crop tool's Canvas and Delete Outside: every layer
## loses what falls past the new edge as well as what falls outside the new
## grid, so nothing survives that growing the canvas back could show. It rides
## the same history step, because a painter who asked for one crop is offered
## one undo. *keep_outside* is its Canvas: no chunk is dropped, and what falls
## outside stays in the layers unseen. The two together keep nothing, since
## deleting wins.
func crop_to(rect: Rect2i, clear_outside: bool = false, keep_outside: bool = false) -> bool:
    if _document == null:
        return false
    var canvas := Rect2i(Vector2i.ZERO, _document.canvas_size)
    var ground := Color(0, 0, 0, 0) if canvas.encloses(rect) else _document.background_fill()
    return _reshape_to(rect, ACTION_NAME, ground, clear_outside, keep_outside and not clear_outside)


## Image > Canvas Size: the document becomes *size*, with the old picture placed
## by *anchor*, a cell of the nine-cell grid where each component is 0, 1 or 2
## for near edge, centre and far edge. True when it happened.
##
## Growing lays *margin_fill* into the ground the canvas gains, and a
## `margin_fill` with no alpha means the grey a fresh document's background
## holds, in this document's own coordinates. There is deliberately no way to
## ask for a transparent margin: that was a defect, and nothing in Sara wants
## one. Trimming throws away what falls outside, and undo brings it back,
## because the step holds every layer's whole chunk dictionary.
func resize_to(size: Vector2i, anchor: Vector2i, margin_fill: Color = Color(0, 0, 0, 0)) -> bool:
    if _document == null:
        return false
    if size.x <= 0 or size.y <= 0:
        return false
    var bounded := size.min(Vector2i(SaResample.MAX_DIMENSION, SaResample.MAX_DIMENSION))
    var ground := margin_fill if margin_fill.a > 0.0 else _document.background_fill()
    return _reshape_to(Rect2i(-offset_for(_document.canvas_size, bounded, anchor), bounded), RESIZE_ACTION_NAME, ground)


## Where the old picture's origin lands inside the new canvas, for an anchor of
## 0, 1 or 2 per axis. The new canvas's own rectangle in old document pixels is
## this negated, which is what `resize_to` passes down.
##
## `floori` on a float rather than an integer division, because a trim makes the
## difference negative and an integer division truncates towards zero: a
## centred trim of an odd number of pixels would take the extra column off the
## other side from a centred grow of the same number.
static func offset_for(from_size: Vector2i, to_size: Vector2i, anchor: Vector2i) -> Vector2i:
    var cell := Vector2i(clampi(anchor.x, 0, 2), clampi(anchor.y, 0, 2))
    var difference := to_size - from_size
    return Vector2i(floori(float(difference.x) * float(cell.x) / 2.0), floori(float(difference.y) * float(cell.y) / 2.0))


## *chunks*, a store of *schema* at *scale*, moved *offset* document pixels with
## every texel kept wherever it lands, past any canvas and at negative grid
## positions too. Fresh chunks, so *chunks* is left as it was, and the same
## re-tile a crop runs, overlap by overlap on the GPU (rule 1). A Paste from
## another document centres what it holds this way.
func shifted(
    chunks: Dictionary[Vector2i, SaChunk], schema: Array[SaFieldSpec], scale: float, offset: Vector2i
) -> Dictionary[Vector2i, SaChunk]:
    if _compute_or_null() == null:
        return {}
    return _retile(chunks, schema, scale, -offset, Vector2i.ZERO, Color(0, 0, 0, 0), false, {}, true)


## The pass both of the above are: re-tile every paint layer onto *rect*, put the
## result on the document, and record one history step called *action*.
func _reshape_to(
    rect: Rect2i, action: String, ground: Color = Color(0, 0, 0, 0), clear_outside: bool = false, keep_outside: bool = false
) -> bool:
    var wanted := rect
    if wanted.size.x <= 0 or wanted.size.y <= 0:
        return false
    wanted.size = wanted.size.min(Vector2i(SaResample.MAX_DIMENSION, SaResample.MAX_DIMENSION))
    if wanted == Rect2i(Vector2i.ZERO, _document.canvas_size):
        # Nothing to do, and recording a step for it would put an undo on the
        # stack that changes nothing when it fires.
        return false
    if _compute_or_null() == null:
        return false

    # Keyed by Variant, because a typed key refuses a layer that was freed.
    var before: Dictionary[Variant, Dictionary] = {}
    var layers := _paint_layers()
    for layer: SaLayer in layers:
        before[layer] = layer.chunks.duplicate()

    # Asked before the walk, for the reason `SaDrawnLayer.Remap` gives. Delete
    # Outside keeps nothing past the edge, so a recipe reaching past it is cut.
    var map := Transform2D(Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(-wanted.position))
    var inside := Rect2i(Vector2i.ZERO, wanted.size) if clear_outside else Rect2i()
    var geometry := SaDrawnLayer.Remap.new(layers, map, action, inside)

    var carrier := _ground_carrier(ground)
    var after: Dictionary[Variant, Dictionary] = {}
    for layer: SaLayer in before:
        if not geometry.moves_chunks(layer):
            after[layer] = {}
            continue
        # The ground goes under one layer only, so a user of a shared source
        # takes another user's set only when the two would be cut alike.
        var twin := done_user(layer, after)
        if twin != null and (twin == carrier) == (layer == carrier):
            after[layer] = after[twin]
            continue
        after[layer] = _retile(
            layer.chunks,
            layer.schema,
            layer.resolution_scale,
            wanted.position,
            wanted.size,
            ground if layer == carrier else Color(0, 0, 0, 0),
            clear_outside,
            {},
            keep_outside
        )
        chunks_made += after[layer].size()

    # A group's mask and an attached filter's hold chunks of their own, which no
    # layer walk above reaches, so they are carried beside the layers on the
    # same grid. The canvas a grow gains reads the mask's rest, which is what a
    # position it holds nothing at read before, so no ground goes under them.
    var masks_before: Dictionary[Variant, Dictionary] = {}
    for mask: SaMask in own_masks(_document):
        masks_before[mask] = mask.chunks.duplicate()
    var masks_after: Dictionary[Variant, Dictionary] = {}
    for mask: SaMask in masks_before:
        masks_after[mask] = _retile(
            mask.chunks,
            SaMask.schema(),
            1.0,
            wanted.position,
            wanted.size,
            Color(0, 0, 0, 0),
            clear_outside,
            at_rest(mask),
            keep_outside
        )

    # The undo puts the old document back, and from where the cropped one is
    # standing the old origin is at minus the rectangle's origin over the whole
    # of it: the inverse of the move this crop is about to make.
    var put := _put_back.bind(geometry)
    var exchange := SaCanvasExchange.new(
        _document, _document.canvas_size, before, masks_before, put, Rect2i(-wanted.position, _document.canvas_size), true
    )
    _apply(wanted.size, after, wanted, masks_after, geometry)
    exchange.commit(action)
    return true


## Crops to the selection's bounds. True when there was a selection to use.
##
## Clipped here rather than in `crop_to`, which grows. A wand or a lasso can
## hand back bounds that touch the edge, and Image > Crop to Selection is a menu
## entry a painter reads as taking away.
func crop_to_selection() -> bool:
    if _document == null or not _document.selection.active:
        return false
    return crop_to(_document.selection.bounds.intersection(Rect2i(Vector2i.ZERO, _document.canvas_size)))


## Every layer that stores texels. A generated layer is skipped: it evaluates
## a kernel over whatever the canvas is now, so the new size is all it needs.
func _paint_layers() -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    _collect_layers(_document, found)
    return found


func _collect_layers(from: Node, into: Array[SaLayer]) -> void:
    for child: Node in from.get_children():
        var layer := child as SaLayer
        if layer == null:
            continue
        if layer != _document.stroke_layer and not layer.is_generated():
            into.append(layer)
        _collect_layers(layer, into)


## Every mask in *document* that holds chunks of its own: a group's, and the one
## of every filter attached to the document, to a layer or to a group. A
## layer's own mask is a field of its chunks and moves with them, so it is not
## here. `SaResample` asks the same question.
static func own_masks(document: SaDocument) -> Array[SaMask]:
    var found: Array[SaMask] = []
    for record: SaAttachedFilter in every_record(document):
        if record.mask != null:
            found.append(record.mask)
    _collect_group_masks(document, document, found)
    return found


## Every filter record attached anywhere in *document*, the root's first.
static func every_record(document: SaDocument) -> Array[SaAttachedFilter]:
    var found: Array[SaAttachedFilter] = document.root_filters.duplicate()
    _collect_records(document, document, found)
    return found


static func _collect_records(document: SaDocument, from: Node, into: Array[SaAttachedFilter]) -> void:
    for child: Node in from.get_children():
        var layer := child as SaLayer
        if layer == null or layer == document.stroke_layer:
            continue
        into.append_array(layer.filters)
        _collect_records(document, layer, into)


static func _collect_group_masks(document: SaDocument, from: Node, into: Array[SaMask]) -> void:
    for child: Node in from.get_children():
        var layer := child as SaLayer
        if layer == null or layer == document.stroke_layer:
            continue
        if layer.mask != null and layer.mask.is_own():
            into.append(layer.mask)
        _collect_group_masks(document, layer, into)


## The blank a fresh chunk of *mask* opens at, its rest, so the part of it no
## source chunk reaches reads what the position read before.
static func at_rest(mask: SaMask) -> Dictionary[StringName, Color]:
    return {SaFieldSpec.MASK: Color(mask.rest, mask.rest, mask.rest, mask.rest)}


## Puts every mask's chunks of *masks* into its own store, and tells every
## filter record of *document* that evaluates to something else now that it
## does: one holding a mask that moved, and every one on a canvas *resized*,
## because a pass is recorded against the canvas it ran on and a kaleidoscope's
## centre stays the old one until its record runs again. A layer flip keeps
## the size and says false. `SaResample`, `SaOrient` and
## `SaProjectionConversion` put their masks back through here too.
static func put_masks(document: SaDocument, masks: Dictionary[Variant, Dictionary], resized: bool = true) -> void:
    for mask: SaMask in masks:
        var wanted := SaTyped.chunks(masks[mask])
        mask.chunks.clear()
        for grid_pos: Vector2i in wanted:
            mask.chunks[grid_pos] = wanted[grid_pos]
    for record: SaAttachedFilter in every_record(document):
        if resized or (record.mask != null and masks.has(record.mask)):
            record.touch()


## The layer a grow carries into the ground the canvas gains, or null.
##
## The bottom-most top-level layer, and only when it stores texels and holds a
## chunk at every grid position of the canvas as it stands. That is what a
## background is in a document whose background stores its pixels, and it is the
## only layer a grow may extend: a paint layer that happens to cover the canvas
## is a painting rather than a ground, and giving it a margin would be inventing
## brushwork nobody made. A generated background needs nothing, because its
## kernel fills whatever the canvas is now, which is what `SaGeneratedLayer` was
## built for and why a document with one takes this branch out.
func _ground_carrier(ground: Color) -> SaLayer:
    if ground.a <= 0.0:
        return null
    for child: Node in _document.get_children():
        var layer := child as SaLayer
        if layer == null or layer == _document.stroke_layer:
            continue
        if layer.is_generated():
            return null
        return layer if _covers_canvas(layer) else null
    return null


## The layer in *done* whose `chunks` is *layer*'s own dictionary, or null.
##
## The users of one `SaSharedSource` hold one dictionary, so a crop, a turn, a
## resample or a projection conversion that worked it out for one user hands
## the same set to the next rather than making it again and throwing the first
## away. *done* is keyed by layer, as every such step's new chunks are,
## and the history still keeps an entry per layer, so one undo puts every user
## back on the one dictionary.
static func done_user(layer: SaLayer, done: Dictionary) -> SaLayer:
    for other: Variant in done:
        var user: SaLayer = other if is_instance_valid(other) and other is SaLayer else null
        if user != null and is_same(user.chunks, layer.chunks):
            return user
    return null


## Whether *layer* holds a chunk everywhere the canvas is.
func _covers_canvas(layer: SaLayer) -> bool:
    for grid_pos: Vector2i in _grid_over(_document.canvas_size):
        if layer.chunks.get(grid_pos, null) == null:
            return false
    return true


## The chunk dictionary a store of *chunks* should hold once the origin has
## moved to *origin* and the canvas is *size*, with *ground* under whatever
## survives. The store is a layer's, with its *schema* and its *scale*, or an own
## mask's, and *blanks* is what a fresh chunk of it opens at where it names a
## field: a mask's rest, so the part no source chunk reaches reads as before.
##
## The grid is walked in document pixels and every overlap is moved in the
## layer's own texels, its `resolution_scale` of them to a pixel. A double
## resolution layer holds 512 texels over the same 256 pixels as
## any other, so a crop at whole document pixels moves whole texels on it and
## stays exact, and every chunk made here is made at the layer's scale.
func _retile(
    chunks: Dictionary[Vector2i, SaChunk],
    schema: Array[SaFieldSpec],
    scale: float,
    origin: Vector2i,
    size: Vector2i,
    ground: Color = Color(0, 0, 0, 0),
    clear_outside: bool = false,
    blanks: Dictionary[StringName, Color] = {},
    keep_outside: bool = false
) -> Dictionary[Vector2i, SaChunk]:
    var edge := SaLayer.CHUNK_SIZE
    var fresh: Dictionary[Vector2i, SaChunk] = {}
    var canvas_grid := _grid_over(size)
    var canvas_cells := Rect2i(Vector2i.ZERO, Vector2i(ceili(size.x / float(edge)), ceili(size.y / float(edge))))
    # **Not an [SaChunkWalk].** The walk dispatches one kernel per chunk a
    # rectangle touches, and a retile's destination chunk straddles the old
    # grid: one position takes up to four dispatches, one per source chunk it
    # overlaps, and which four is the inner walk below. What the walk does
    # supply is the arithmetic of that inner walk, so the grid maths lives in
    # one file even where the dispatch cannot.
    for grid_pos: Vector2i in _destination_grid(chunks, origin, canvas_grid, keep_outside):
        var kept := Rect2i(origin + grid_pos * edge, Vector2i(edge, edge))
        var chunk: SaChunk = null
        # The ground is the canvas's, so a position kept past the new edge
        # holds only what was painted there.
        if ground.a > 0.0 and canvas_cells.has_point(grid_pos):
            chunk = _fresh(schema, scale, blanks)
            chunk.clear(ground)
        for source_pos: Vector2i in SaChunkWalk.positions_in(kept):
            var source: SaChunk = chunks.get(source_pos, null)
            if source == null:
                continue
            var source_origin := source_pos * edge
            var overlap := kept.intersection(Rect2i(source_origin, Vector2i(edge, edge)))
            if overlap.size.x <= 0 or overlap.size.y <= 0:
                continue
            # Allocated only once a source chunk has been found for it, so
            # a crop into empty space leaves no chunk behind (hard rule 3).
            if chunk == null:
                chunk = _fresh(schema, scale, blanks)
                chunk.clear(Color(0, 0, 0, 0))
            _carry_lazy(schema, source, chunk)
            var from := overlap.position - source_origin
            var to := overlap.position - kept.position
            var span := texels(from + overlap.size, scale) - texels(from, scale)
            _copy_part(source, chunk, texels(from, scale), texels(to, scale), span)
        if chunk != null:
            if clear_outside:
                _blank_overhang(chunk, texels(size - grid_pos * edge, scale))
            fresh[grid_pos] = chunk
    return fresh


## The grid positions a retile fills: *canvas_grid*, the new canvas's, and
## with *keep_outside* every position a chunk of *chunks* lands on once the
## origin has moved to *origin*, so nothing painted is dropped.
static func _destination_grid(
    chunks: Dictionary[Vector2i, SaChunk], origin: Vector2i, canvas_grid: Array[Vector2i], keep_outside: bool
) -> Array[Vector2i]:
    if not keep_outside:
        return canvas_grid
    var edge := SaLayer.CHUNK_SIZE
    var found: Dictionary[Vector2i, bool] = {}
    for grid_pos: Vector2i in canvas_grid:
        found[grid_pos] = true
    for source_pos: Vector2i in chunks:
        if chunks[source_pos] == null:
            continue
        for grid_pos: Vector2i in SaChunkWalk.positions_in(Rect2i(source_pos * edge - origin, Vector2i(edge, edge))):
            found[grid_pos] = true
    var grid: Array[Vector2i] = []
    grid.assign(found.keys())
    return grid


## *pixels* in the texels of a layer at *scale*, rounded to the nearest one.
## Exact at 1.0 and 2.0, the two scales a layer is made at.
static func texels(pixels: Vector2i, scale: float) -> Vector2i:
    return Vector2i(roundi(pixels.x * scale), roundi(pixels.y * scale))


## Gives *chunk* the lazy fields *source* holds and it does not, height above
## all, so the copy that follows carries them. A destination chunk takes one
## only where a source chunk it is made of holds one (hard rule 3).
static func _carry_lazy(schema: Array[SaFieldSpec], source: SaChunk, chunk: SaChunk) -> void:
    for field_id: StringName in source.field_ids():
        if chunk.has_field(field_id):
            continue
        var spec := SaFieldSpec.find(schema, field_id)
        if spec != null and spec.lazy:
            chunk.add_sparse_field(spec)


## A chunk of *schema* at *scale*, whose fields named in *blanks* keep that
## value through a clear, the way `SaMask.get_or_create` opens one at its rest.
static func _fresh(schema: Array[SaFieldSpec], scale: float, blanks: Dictionary[StringName, Color]) -> SaChunk:
    var chunk := SaChunk.create(schema, scale)
    for field_id: StringName in blanks:
        chunk.blanks[field_id] = blanks[field_id]
    return chunk


## Clears whatever *chunk* holds past the canvas edge, given *kept*, how far the
## canvas reaches into it from its own origin, in the chunk's own texels.
##
## At most two dispatches, and only on the chunks the edge crosses: the column
## to the right of the canvas and the row below it, which together are the whole
## of the chunk that is outside. Every other chunk of the grid returns on the
## first line, so this is a dirty-rect pass over the edge rather than over the
## document (hard rule 2). The edge comes from the chunk rather than from
## `SaLayer.CHUNK_SIZE`, because hard rule 3 says to ask.
func _blank_overhang(chunk: SaChunk, kept: Vector2i) -> void:
    var edge := chunk.pixel_size()
    var inside := Vector2i(clampi(kept.x, 0, edge), clampi(kept.y, 0, edge))
    if inside.x >= edge and inside.y >= edge:
        return
    for field_id: StringName in chunk.fields:
        var target: SaTexture = chunk.fields[field_id]
        if target == null or not target.rid.is_valid():
            continue
        # The field's own blank and not zero: zero is no paint for colour and
        # fully hidden for a mask, and the chunk knows which.
        var value: Color = chunk.blanks.get(field_id, SaFieldSpec.NO_PAINT)
        _blank(target, Rect2i(inside.x, 0, edge - inside.x, edge), value)
        _blank(target, Rect2i(0, inside.y, inside.x, edge - inside.y), value)


## One rectangle of one field set to *value*, through the blank kernel rather
## than a transfer clear, for the reason `SaTransformSelection` gives about its
## own stitch: a transfer clear is not ordered against the copies that ran
## before it, and here the copies are what put the overhang there.
func _blank(target: SaTexture, local: Rect2i, value: Color) -> void:
    var compute := _blank_or_null()
    if compute == null or local.size.x <= 0 or local.size.y <= 0:
        return
    compute.use_storage_format(target.format)
    compute.set_texture(0, target.rid)
    compute.set_push_constant_float_array(
        PackedFloat32Array([value.r, value.g, value.b, value.a, local.position.x, local.position.y, local.size.x, local.size.y])
    )
    compute.dispatch_kernel("blank_region", SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)


## One overlap, one dispatch per colour field the chunks share.
func _copy_part(source: SaChunk, into: SaChunk, from: Vector2i, to: Vector2i, size: Vector2i) -> void:
    var compute := _compute_or_null()
    var push := PackedFloat32Array([to.x, to.y, from.x, from.y, size.x, size.y, 0.0, 0.0])
    for field_id: StringName in into.fields:
        var target: SaTexture = into.fields[field_id]
        var origin_texture: SaTexture = source.fields.get(field_id, null)
        if target == null or origin_texture == null or not target.rid.is_valid() or not origin_texture.rid.is_valid():
            continue
        compute.use_storage_format(target.format)
        compute.set_texture(0, origin_texture.rid)
        compute.set_texture(1, target.rid)
        compute.set_push_constant_float_array(push)
        compute.dispatch_kernel("shift", SaCompute.groups_for(size.x), SaCompute.groups_for(size.y), 1)


## Puts *size* and *chunks* on the document and tells everything that draws it.
##
## *source* is the part of the document that was which the document that is now
## is made of, in the old coordinates, and it rides on `SaDocument.resize_source`
## rather than on the signal because `document_resized` has six listeners and one
## of them wants it. Set immediately before the emit and cleared immediately
## after, so no listener of any later resize can read a stale rectangle.
## *masks* puts the own masks' chunks back the same way, keyed by the mask, and
## *geometry* swaps the drawn layers' recipes once their chunks are on.
func _apply(
    size: Vector2i,
    chunks: Dictionary[Variant, Dictionary],
    source: Rect2i,
    masks: Dictionary[Variant, Dictionary] = {},
    geometry: SaDrawnLayer.Remap = null
) -> void:
    # The size's setter puts the side a brush is read against at the new shorter
    # one, and a crop keeps the size of a pixel, so the side goes back.
    var side := _document.brush_side
    _document.canvas_size = size
    _document.brush_side = side
    for layer: SaLayer in chunks:
        # Emptied and refilled by key rather than assigned: `SaLayer.chunks` is
        # a typed `Dictionary[Vector2i, SaChunk]` and refuses a plain one, so
        # the whole exchange silently did nothing and every crop read as a
        # no-op with the size already changed.
        var wanted := SaTyped.chunks(chunks[layer])
        layer.chunks.clear()
        for grid_pos: Vector2i in wanted:
            layer.chunks[grid_pos] = wanted[grid_pos]
        layer.mark_all_unresolved()
    if geometry != null:
        geometry.swap()
    put_masks(_document, masks)
    _document.selection.deselect_and_forget()
    _document.modified = true
    _document.update_caches()
    _document.invalidate_all_allocated_chunks()
    _document.resize_source = source
    EventBus.document_resized.emit(_document, size)
    _document.resize_source = Rect2i()
    _document.document_changed.emit()


## What `SaCanvasExchange` puts back at an undo or a redo.
func _put_back(
    size: Vector2i,
    chunks: Dictionary[Variant, Dictionary],
    masks: Dictionary[Variant, Dictionary],
    source: Rect2i,
    _projection: SaProjection,
    geometry: SaDrawnLayer.Remap
) -> void:
    _apply(size, chunks, source, masks, geometry)


## The grid positions covering a canvas of *size*, as `SaLayer` counts them.
static func _grid_over(size: Vector2i) -> Array[Vector2i]:
    return SaLayer.grid_positions(size)


func _compute_or_null() -> SaCompute:
    if _compute == null and GlobalShaderCompiler.get_rd() != null:
        _compute = SaCompute.new("crop")
    return _compute


func _blank_or_null() -> SaCompute:
    if _blank_compute == null and GlobalShaderCompiler.get_rd() != null:
        _blank_compute = SaCompute.new("blank")
    return _blank_compute
