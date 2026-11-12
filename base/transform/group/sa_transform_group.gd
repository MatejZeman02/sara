## The transform tool's pass over a group: every layer inside it, nested groups
## included, moved by the one box and put down as one history step.
##
## **The box is the union of what the layers show.** Each paint layer inside
## the group is measured the way the tool measures a layer alone, its painted
## box by the reduce, and a smart layer's box is taken through the map it is
## drawn by, so the handles stand round every stroke as it is seen. A layer
## with no position of its own, an adjustment, a generated fill or an effect,
## is neither measured nor moved, and a nested group is a door to its members.
##
## **With nothing selected each layer is drawn through a live map while the
## hand moves**, the group's map composed after the one the layer already had,
## so a frame costs one cache redraw a layer and no texel is written. Enter
## puts each composed map as `SaLiveTransform.put` puts one, and an ordinary
## layer, one that came to the session with no live transform, is then baked
## into its chunks the way a layer alone is baked, so it leaves the session
## ordinary. A smart layer keeps its map live. The group's own mask and every
## nested group's move with the paint through `MaskCarry`, and all of it is
## one step under `SaHistory.as_one`, so one undo puts every layer back.
##
## **A selection is the box, as it is for a layer**, and only what it covers
## moves in each layer: at Enter each layer is lifted and landed by an
## `SaTransform` of its own in turn, since the lift's preview is the document's
## one stroke layer and two layers cannot share it. So while the hand moves
## the box and the outline follow it and the pixels land at Enter. The
## selection is put back between the layers, so each lifts what the painter
## selected, and the last landing carries it, as a lift of one layer does.
## The group masks stay with a selection, since the group as a whole has not
## moved.
##
## **A locked layer inside refuses the whole transform**, named, with the
## sentence a locked layer alone gets, and so does any other refusal a layer's
## live transform would give, one open in Edit Smart Layer Contents or at
## another resolution.
##
## **Several layers picked in the Layers docker are opened the same
## way**: the tool hands the picked set here, each picked group is a door to
## its members as one group alone is, and the box is the union of what they
## all show. A locked or hidden layer among the picked is left out with its
## sentence in the corner and the rest move, where a locked layer inside one
## group refuses the group, because the painter picked the set row by row and
## a group is one row. Freehand and Cage, which a live map cannot hold, land
## at Enter the way a selection does, each layer lifted and put through the
## mesh by a pass of its own, the grid following the hand until then.
##
## Krita's transform of a group applies one transform to every child at once
## through its transform mask machinery and keeps the mask of the group with
## the group, which is what this does too. It differs in that Krita resamples
## every child into pixels at the end, where a smart layer here keeps its map
## live, and that Krita's warp, cage and liquify reach a group, where Freehand
## and Cage here refuse it, since a live map is a 3 by 3 matrix.
extends SaTransform

## What the corner says when Freehand or Cage is asked of a group.
const BENDS_LINE := "Freehand and Cage bend one layer at a time. Pick a layer inside the group, or Normal for the whole group."

## Whether a session is open, on a group or on a picked set.
var _open_now: bool = false
## The groups whose masks move with the paint: the group the session is open
## on and every group inside it, or every group a picked set reaches.
var _groups: Array[SaLayer] = []
## The paint layers inside it, and the live transform each had when the session
## opened, null for an ordinary layer, index for index.
var _members: Array[SaLayer] = []
var _from: Array[SaLiveTransform] = []
## Whether the session lands at Enter, a selection's or a picked set's under
## Freehand or Cage, rather than drawing each layer through a live map.
var _selected: bool = false
## Whether the session is a picked set's, which alone takes a mesh.
var _picked: bool = false


## The layers inside *group* that have paint to move, in the document's order:
## every layer at any depth that is not a group itself and not an adjustment,
## a generated fill or an effect.
static func members(document: SaDocument, group: SaLayer) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    if document == null or group == null:
        return found
    for child: Node in document.get_children():
        var layer := child as SaLayer
        if layer == null or layer == group or layer == document.stroke_layer or not SaLayerStack.is_inside(layer, group):
            continue
        if not (layer.is_group or layer.is_generated() or layer.is_adjustment() or layer.is_effect()):
            found.append(layer)
    return found


## *group* and every group inside it, whose masks move with the paint.
static func groups(document: SaDocument, group: SaLayer) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child: Node in document.get_children():
        var layer := child as SaLayer
        if layer != null and layer.is_group and SaLayerStack.is_inside(layer, group):
            found.append(layer)
    return found


## The paint layers a picked set moves, in the document's order: each picked
## paint layer and every member of each picked group, once, less a layer the
## transform leaves out, which [method left_out] names.
static func movable(document: SaDocument, picked: Array[SaLayer]) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for layer: SaLayer in reached(document, picked):
        if left_out(document, layer).is_empty():
            found.append(layer)
    return found


## Every paint layer *picked* reaches, in the document's order, each picked
## paint layer and every member of each picked group, once.
static func reached(document: SaDocument, picked: Array[SaLayer]) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    if document == null:
        return found
    for child: Node in document.get_children():
        var layer := child as SaLayer
        if layer == null or layer == document.stroke_layer or layer.is_group:
            continue
        if layer.is_generated() or layer.is_adjustment() or layer.is_effect():
            continue
        var inside := picked.has(layer)
        for each: SaLayer in picked:
            inside = inside or (each.is_group and SaLayerStack.is_inside(layer, each))
        if inside:
            found.append(layer)
    return found


## Why *layer* stays where it is while the rest of a picked set moves, the
## reason the tool gives when it is the one layer it opens on, or empty. A
## hidden layer is left out with the sentence a stroke on it gets, since a
## painter who cannot see a layer has not seen it moved.
static func left_out(document: SaDocument, layer: SaLayer) -> String:
    if SaContext.hidden(layer):
        return SaContext.hidden_layer_line(layer, TranslationServer.translate(SaContext.TRANSFORM_GESTURE))
    return SaLiveTransform.refusal(document, layer, Basis.IDENTITY)


## Every group *picked* reaches, the picked groups and the groups inside them,
## whose masks move with the paint.
static func groups_of(document: SaDocument, picked: Array[SaLayer]) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for each: SaLayer in picked:
        if not each.is_group:
            continue
        for group: SaLayer in groups(document, each):
            if not found.has(group):
                found.append(group)
    return found


## Why the layers inside *group* cannot all be transformed, as the sentence of
## the first that refuses, or empty when every one can. A selection's lift asks
## only for the padlock, since it resamples the way a lift of one layer does.
static func refusal(document: SaDocument, group: SaLayer, selected: bool) -> String:
    for layer: SaLayer in members(document, group):
        if selected and layer.is_locked:
            return TranslationServer.translate("'%s' is locked. Unlock it in the Layers docker first.") % layer.name
        if not selected:
            var why := SaLiveTransform.refusal(document, layer, Basis.IDENTITY)
            if not why.is_empty():
                return why
    return ""


## Opens a live session on *layer*, a group, over *box*. False, with the
## refusal in the corner, when a layer inside refuses.
func hold(layer: SaLayer, box: Rect2i) -> bool:
    cancel()
    return _open(layer, box, false)


## Opens a selection's session on *layer*, a group, over *box*, which lands at
## Enter. False when a layer inside is locked.
func lift(layer: SaLayer, box: Rect2i) -> bool:
    cancel()
    return _open(layer, box, true)


## Opens a session on the layers the painter *picked*, over *box*, live or,
## when *lands*, put down at Enter. Each layer left out is named in the corner.
## False when no picked layer is left to move.
func open_set(picked: Array[SaLayer], box: Rect2i, lands: bool) -> bool:
    cancel()
    if _document == null or not box.has_area():
        return false
    for layer: SaLayer in reached(_document, picked):
        var why := left_out(_document, layer)
        if not why.is_empty():
            SaProblems.refuse(ACTION_NAME, TranslationServer.translate("The transform tool cannot open on this layer. %s") % why)
    var inside := movable(_document, picked)
    if inside.is_empty():
        return false
    _start(inside, groups_of(_document, picked), box, lands)
    _picked = true
    return true


func _open(layer: SaLayer, box: Rect2i, selected: bool) -> bool:
    if _document == null or layer == null or not layer.is_group or not box.has_area():
        return false
    var why := refusal(_document, layer, selected)
    if not why.is_empty():
        SaProblems.refuse(ACTION_NAME, TranslationServer.translate("The transform tool cannot open on this group. %s") % why)
        return false
    var inside := members(_document, layer)
    if inside.is_empty():
        return false
    _start(inside, groups(_document, layer), box, selected)
    return true


func _start(inside: Array[SaLayer], carried: Array[SaLayer], box: Rect2i, lands: bool) -> void:
    _open_now = true
    _groups = carried
    _selected = lands
    _members = inside
    _from = []
    for member: SaLayer in inside:
        _from.append(SaLiveTransform.of(member))
    bounds = box
    matrix = Transform2D.IDENTITY


func is_held() -> bool:
    return _open_now and not _selected


func is_lifted() -> bool:
    return _open_now and _selected


func has_moved() -> bool:
    return _open_now and (is_perspective() or is_warped() or not matrix.is_equal_approx(Transform2D.IDENTITY))


## A homography the group takes only when every layer inside takes it composed
## after its own map, so the frame keeps the last map that worked.
func preview_homography(to: PackedFloat32Array) -> bool:
    if to.size() != 9 or is_zero_approx(to[8]):
        return false
    if is_held():
        var map: Variant = SaLiveTransform.map_of(Array(to))
        for i in _members.size():
            if not SaLiveTransform.refusal(_document, _members[i], _through(map, _from[i])).is_empty():
                return false
    return super.preview_homography(to)


## A mesh is no 3 by 3 map, so a group takes none. A picked set takes one
## while it lands at Enter, each layer then put through it by a pass of its own.
func preview_mesh(to: PackedVector2Array) -> void:
    if _picked and _selected:
        super.preview_mesh(to)


## Each layer drawn through the group's map after its own, or nothing for a
## selection's session, whose box and outline are the preview.
func _draw_preview() -> void:
    if not is_held():
        return
    var map: Variant = SaTransformLive.map_at(matrix, _homography)
    for i in _members.size():
        SaLiveTransform.preview(_document, _members[i], _through(map, _from[i]))


## Puts every layer down as one step named as a lift of one layer is. True when
## the box had moved.
func commit() -> bool:
    if not _open_now:
        return false
    tick()
    var moved := has_moved()
    var map: Variant = SaTransformLive.map_at(matrix, _homography)
    var landing: Array = [matrix, _homography, filter, bounds, mesh()]
    var selected := _selected
    var carried := _groups
    var inside := _members
    var from := _from
    _restore()
    _close()
    if not moved or _document.history == null:
        return false
    if selected:
        _document.history.as_one(ACTION_NAME, _land_selected.bind(inside, landing))
        return true
    _document.history.as_one(ACTION_NAME, _put.bind(carried, inside, from, map, landing))
    return true


## The live half: each composed map put, an ordinary layer baked, and the
## group masks carried.
func _put(carried: Array[SaLayer], inside: Array[SaLayer], from: Array[SaLiveTransform], map: Variant, landing: Array) -> void:
    for i in inside.size():
        SaLiveTransform.put(_document, inside[i], _through(map, from[i]))
        if from[i] == null:
            SaLiveTransform.bake(_document, inside[i])
    if map == null:
        return
    for each: SaLayer in carried:
        MaskCarry.carry(_document, each.mask, landing, _mask_kernels)


## The landing half: each layer lifted over the selection the painter made, or
## over the box with none, and landed through *landing*, the matrix, the
## homography, the filter, the box and the mesh, by a pass of its own.
func _land_selected(inside: Array[SaLayer], landing: Array) -> void:
    var selection := _document.selection
    var active := selection != null and selection.active
    var made: Dictionary = selection.chunks if active else {}
    var made_box: Rect2i = selection.bounds if active else Rect2i()
    var landed: Array = []
    for layer: SaLayer in inside:
        if active and not is_same(selection.chunks, made):
            # Back to what the painter selected, which the last landing carried.
            SaSelection.Swap.new(selection, made, made_box).exchange()
        var one := SaTransform.new(_document)
        one.filter = landing[2]
        if not one.lift(layer, landing[3]):
            continue
        var homography: PackedFloat32Array = landing[1]
        var bent: PackedVector2Array = landing[4]
        if not bent.is_empty():
            one.preview_mesh(bent)
        elif homography.size() == 9:
            one.preview_homography(homography)
        else:
            one.preview_matrix(landing[0])
        if one.commit() and active:
            landed = [selection.chunks, selection.bounds]
    if not landed.is_empty() and not is_same(selection.chunks, landed[0]):
        SaSelection.Swap.new(selection, landed[0], landed[1]).exchange()


## Draws every layer at the map it came to the session with.
func _restore() -> void:
    if not is_held():
        return
    for i in _members.size():
        var before: Variant = null
        if _from[i] != null:
            before = _from[i].matrix
        SaLiveTransform.preview(_document, _members[i], before)


func cancel() -> void:
    _restore()
    _close()
    super.cancel()


func _close() -> void:
    _open_now = false
    _groups = []
    _members = []
    _from = []
    _selected = false
    _picked = false
    _forget()


## *map*, the group's, a `Basis` or null for none, after *before*, the map the
## layer came with or null.
static func _through(map: Variant, before: SaLiveTransform) -> Variant:
    var own: Variant = null
    if before != null:
        own = before.matrix
    if map == null:
        return own
    if own == null:
        return map
    return (map as Basis) * (own as Basis)


## The box round what the tool would move, measured again only when the
## layers, their chunk counts or the history have moved, since the tool asks
## for it on every frame and the measure is a reduce on the GPU with a read
## back. One ordinary layer is measured in its own pixels, which the tool
## takes through the layer's live map itself, and several, a group's members
## or a picked set's, through each one's map, since their box stands as a
## plain rectangle.
##
## **Tight, by a reduction rather than a read.** A box round the pixels rather
## than the union of the chunks, 256-aligned, and no read of every chunk back
## to do it, which hard rule 1 forbids: `SaTransformKernels.painted_box` runs
## one kernel over the chunks a layer holds and reads four ints back, the read
## `SaSelection.measure_bounds` makes for the wand. So a small stroke gets a
## box that hugs it, and the handles sit on the stroke rather than up to 255
## pixels off it, far enough to put the right handle under a docker. The
## chunk union stays as the answer when there is no device to reduce on.
class Measure:
    var _box: Rect2i = Rect2i()
    var _against: Array = []
    var _kernels: SaTransformKernels = null

    ## Measures afresh on the next ask, after another tool may have painted
    ## without moving the history.
    func forget() -> void:
        _against = []

    ## The box round *layers* in *document*, one alone in its own pixels when
    ## *alone*, empty when none holds paint.
    func box_of(document: SaDocument, layers: Array[SaLayer], alone: bool) -> Rect2i:
        var history := document.history if document != null else null
        var against: Array = [alone, history.position() if history != null else 0]
        for layer: SaLayer in layers:
            against.append_array([layer.get_instance_id(), layer.chunks.size()])
        if against == _against:
            return _box
        if _kernels == null:
            _kernels = SaTransformKernels.new()
        _box = Rect2i()
        if alone and layers.size() == 1 and not layers[0].chunks.is_empty():
            _box = _kernels.painted_box(layers[0], SaTransformKernels.chunk_union(layers[0]))
        elif not alone:
            _box = union_of(layers, _kernels)
        _against = against
        return _box

    ## The union of what *layers* show, each paint layer's box by the reduce and a
    ## smart layer's taken through the map it is drawn by.
    static func union_of(layers: Array[SaLayer], kernels: SaTransformKernels) -> Rect2i:
        var out := Rect2i()
        for layer: SaLayer in layers:
            if layer.chunks.is_empty():
                continue
            var own := kernels.painted_box(layer, SaTransformKernels.chunk_union(layer))
            var live := SaLiveTransform.of(layer)
            if own.has_area() and live != null:
                var quad := SaHomography.corners_of(own)
                var area := Rect2(live.map_point(quad[0]), Vector2.ZERO)
                for corner: Vector2 in quad:
                    area = area.expand(live.map_point(corner))
                var low := Vector2i(area.position.floor())
                own = Rect2i(low, Vector2i(area.end.ceil()) - low)
            if own.has_area():
                out = own if not out.has_area() else out.merge(own)
        return out


## A group's mask, which holds chunks of its own, resampled through the map the
## group's paint moved by and put as part of the step.
##
## The gather is the selection's carry, `SaTransformSelection`: the coverage
## stitched into one texture and read back out of it through the inverse of the
## map by `SaResampleKernel`, at the mask's own `r32f` and with the pass's own
## kernels, so a commit builds no compute. A mask and a selection are the same
## single channel on the same grid, and one gather for the two is one answer
## rather than two that drift apart over a feathered or rotated edge.
##
## **The read box is grown to what the landed box reads back to.** The resample
## answers zero outside its source, so a mask resting at one would open the
## corners of a rotated landing at hidden rather than shown. The box the
## coverage is stitched into is therefore the mask's own extent merged with the
## preimage of the landed box, opened at the rest, and every texel the landing
## writes is then read from either coverage or the rest. For a translate or a
## scale that box is the extent itself, and a rotation grows each side by at
## most the other.
class MaskCarry:
    ## Moves *mask* through the map *landing* carries, as a step of *document*'s
    ## history. Nothing for no mask, a mask in the field form, which moves with
    ## the chunks it is a field of, or one that holds no chunk.
    ##
    ## *landing* is the commit's four, the matrix, the homography, the filter
    ## and the box, and the box is not read: the group's is its paint's and the
    ## mask's is its own.
    static func carry(document: SaDocument, mask: SaMask, landing: Array, kernels: SaTransformSelection.Kernels) -> void:
        if mask == null or not mask.is_own() or mask.chunks.is_empty() or not kernels.prepare():
            return
        var matrix: Transform2D = landing[0]
        var homography: PackedFloat32Array = landing[1]
        var forward := _forward(matrix, homography)
        var extent := _extent(mask)
        var landed := _image_of(forward, extent)
        if landed.size.x <= 0 or landed.size.y <= 0:
            return
        var read := extent.merge(_image_of(SaHomography.inverse_of(forward), landed)).grow(1)
        var stitched := SaTransformSelection.stitch(mask.chunks, read, mask.rest, kernels)
        if stitched == null:
            return
        var rows := SaHomography.kernel_rows(homography, matrix, Vector2(read.position))
        var nearest: bool = landing[2] == SaResampleKernel.Filter.NEAREST
        var state: Dictionary[Vector2i, Variant] = {}
        for grid_pos: Vector2i in SaChunkWalk.positions_in(landed):
            var local := SaChunkWalk.local_rect(grid_pos, landed, SaTransformSelection.EDGE)
            if local.size.x <= 0 or local.size.y <= 0:
                continue
            var chunk := _blank_chunk(mask.rest)
            var world := Vector2(grid_pos * SaTransformSelection.EDGE)
            SaResampleKernel.dispatch(kernels.resample, chunk.field(SaFieldSpec.MASK), stitched, rows, world, local, nearest)
            state[grid_pos] = chunk
        for held: Vector2i in mask.chunks:
            if not state.has(held):
                state[held] = null
        if state.is_empty():
            return
        mask.swap_chunks(state, document)
        if document.history != null:
            document.history.commit(SaTransform.ACTION_NAME, mask.swap_chunks.bind(state, document), state)

    ## One chunk of coverage reading *rest* everywhere, which the landing writes
    ## over where it reaches. Cleared rather than left as the device gave it,
    ## because the walk writes the part of the chunk inside the landed box and
    ## an edge chunk has the rest of itself outside it.
    static func _blank_chunk(rest: float) -> SaChunk:
        var chunk := SaChunk.create(SaMask.schema())
        var everywhere := Color(rest, rest, rest, rest)
        chunk.clear(everywhere)
        chunk.blanks[SaFieldSpec.MASK] = everywhere
        return chunk

    ## The map as nine numbers row by row, the homography when the gesture drove
    ## one and the matrix written out as one when it did not, so the box maths
    ## below has a single form to work in. The kernel is handed the two as they
    ## came, because `kernel_rows` inverts an affine exactly.
    static func _forward(matrix: Transform2D, homography: PackedFloat32Array) -> PackedFloat32Array:
        if homography.size() == 9:
            return homography
        var rows: Array[float] = [matrix.x.x, matrix.y.x, matrix.origin.x, matrix.x.y, matrix.y.y, matrix.origin.y]
        return PackedFloat32Array(rows + ([0.0, 0.0, 1.0] as Array[float]))

    ## The rectangle of canvas the mask's chunks cover, in document pixels.
    static func _extent(mask: SaMask) -> Rect2i:
        var side := SaTransformSelection.EDGE
        var box := Rect2i()
        for grid_pos: Vector2i in mask.chunks:
            var here := Rect2i(grid_pos * side, Vector2i(side, side))
            box = here if box.size.x == 0 else box.merge(here)
        return box

    ## The smallest whole-pixel rectangle holding the four corners of *box*
    ## through *map*. A fold, which the tool refuses before it gets here, would
    ## answer the box round what is left of the quad.
    static func _image_of(map: PackedFloat32Array, box: Rect2i) -> Rect2i:
        var first := SaHomography.through(map, Vector2(box.position))
        var low := first
        var high := first
        for corner: Vector2 in SaHomography.corners_of(box):
            var at := SaHomography.through(map, corner)
            low = low.min(at)
            high = high.max(at)
        return Rect2i(Vector2i(low.floor()), Vector2i((high - low).ceil()))
