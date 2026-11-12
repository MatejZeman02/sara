## What a change of the canvas makes stale through the filters the layer tree
## carries, and where the composite under the root may have changed since the
## last time the dirty set was consumed.
##
## A node carrying a neighbourhood filter makes every texel within its halo of
## a changed one stale, so each region grows by a halo first and spills into
## the chunks beside it. A change named at a layer grows by the halos of what
## reads that layer alone: the layer, the groups it is in, an adjustment layer
## over it in its scope, a clip base it is clipped to, an effect layer reading
## any of these, and the root. A change named at no layer grows by the widest
## halo of every node that shows, since a region does not say which layer
## moved it. A hidden layer shows nothing and adds no halo, unless an effect
## layer reads it.
##
## A node carrying a filter that reads the whole node makes stale where a
## change of it lands, when its one such filter says where: a wrap by its
## displacement, a kaleidoscope by its fold. Any other makes every chunk the
## node holds stale. A layer asks when a region lands on a chunk it holds, and
## the root on every region, since everything painted is beneath it.
##
## The spread reads the tree it is handed and nothing else of the document: the
## root node, the filters on the root and the canvas's size are arguments, and
## no reference to the document is kept. What it keeps is its own, the set of
## positions beneath the root, gathered over every spread since the last
## [method take_beneath], and each spread region by the layer it moved at,
## gathered since the last [method take_moved], so that `SaAdjustmentCache`
## counts a change only above the layer it moved at.
##
## The nodes asked are the bearers, [method bearers], the layers carrying a
## filter and the effect layers, and while a stroke is being painted the list
## is kept for it rather than walked again over the whole stack at every dab.
class_name SaStaleSpread
extends RefCounted


## The bearers of one document, kept for the stroke [member stroke] counts and
## the stack of [member count] nodes they were found in.
class Bearers:
    extends RefCounted
    var stroke: int
    var count: int
    var layers: Array[SaLayer]

    func _init(opened: int, children: int, found: Array[SaLayer]) -> void:
        stroke = opened
        count = children
        layers = found


## Document instance id -> the bearers kept for the stroke painted on it.
static var _kept: Dictionary[int, Bearers] = {}

## Grid positions, read as a set, where the composite under the root may have
## changed: every changed region and what every node but the root added to it,
## since the last [method take_beneath].
var _beneath: Dictionary[Vector2i, bool] = {}
## Layer instance id -> the regions spread at that layer since the last
## [method take_moved], grid position -> Rect2i in chunk-local pixels.
var _moved_at: Dictionary[int, Dictionary] = {}
## Grid positions, read as a set, spread at no layer since the last
## [method take_moved].
var _at_none: Dictionary[Vector2i, bool] = {}


## *regions*, grid position -> Rect2i in chunk-local pixels, grown by the widest
## halo under *root* and with every chunk a whole-node filter makes stale added
## whole. *root_filters* are the filters on *root*, and *canvas* is the
## canvas's size in pixels. A tree with no filter attached gets *regions* back
## as they are. *at* is the layer the change moved at, null for one that names
## none, and what is answered is kept under it for [method take_moved].
##
## On an axis *wrapping* joins, the document's projection's, a halo that grows
## past the canvas's edge makes stale what it reaches at the far side, since a
## halo there reads across the seam (`SaChunkPadding`).
func spread(
    root: Node,
    root_filters: Array[SaAttachedFilter],
    regions: Dictionary[Vector2i, Rect2i],
    canvas: Vector2i,
    at: SaLayer = null,
    wrapping: SaProjection.Wrap = SaProjection.Wrap.NONE
) -> Dictionary[Vector2i, Rect2i]:
    var readers := _readers(root, at)
    var reach := SaNeighbourhoodPass.halo_of(root_filters)
    for reader: SaLayer in readers:
        reach = maxi(reach, SaNeighbourhoodPass.halo_of(reader.filters))
    var grown := SaNeighbourhoodPass.grown(regions, reach)
    if reach > 0:
        grown = _across_seam(grown, SaChunkPadding.period_of(canvas, wrapping))
    var out := _spread_whole(root, root_filters, readers, grown, canvas)
    if at == null:
        _at_none.merge(SaTyped.positions(out))
        return out
    var named: Dictionary = _moved_at.get_or_add(at.get_instance_id(), {})
    for grid_pos: Vector2i in out:
        var region: Rect2i = out[grid_pos]
        if region.has_area():
            var was: Rect2i = named.get(grid_pos, region)
            named[grid_pos] = was.merge(region)
    return out


## The regions spread since the last call by the layer each moved at, layer
## instance id -> grid position -> Rect2i in chunk-local pixels, and an empty
## record started for the next ones. A position spread at no layer as well is
## in no layer's regions, since what moved there may have moved at any layer.
func take_moved() -> Dictionary[int, Dictionary]:
    var taken: Dictionary[int, Dictionary] = {}
    for id: int in _moved_at:
        var named: Dictionary = _moved_at[id]
        var regions: Dictionary[Vector2i, Rect2i] = {}
        for grid_pos: Vector2i in named:
            if not _at_none.has(grid_pos):
                regions[grid_pos] = named[grid_pos]
        if not regions.is_empty():
            taken[id] = regions
    _moved_at = {}
    _at_none = {}
    return taken


## The positions beneath the root gathered since the last call, as a set, and
## an empty set started for the next ones. The document hands them to the
## compositor as `beneath_root` when a frame consumes its dirty set.
func take_beneath() -> Dictionary[Vector2i, bool]:
    var taken := _beneath
    _beneath = {}
    return taken


## *regions* with the part of each that lies past an edge *period* joins added
## at the far side, a whole number of periods over, and split among the chunks
## it lands on. *regions* as they are when nothing wraps.
static func _across_seam(regions: Dictionary[Vector2i, Rect2i], period: Vector2i) -> Dictionary[Vector2i, Rect2i]:
    if period == Vector2i.ZERO:
        return regions
    var out := regions.duplicate()
    for grid_pos: Vector2i in regions:
        var local: Rect2i = regions[grid_pos]
        var rect := Rect2i(grid_pos * SaChunk.SIZE + local.position, local.size)
        for column: Vector3i in SaChunkPadding.across(rect.position.x, rect.end.x, period.x):
            for row: Vector3i in SaChunkPadding.across(rect.position.y, rect.end.y, period.y):
                if column.z == 0 and row.z == 0:
                    continue
                var far := Rect2i(column.x + column.z, row.x + row.z, column.y - column.x, row.y - row.x)
                for at: Vector2i in SaChunkWalk.positions_in(far):
                    var part := SaChunkWalk.local_rect(at, far, SaChunk.SIZE)
                    if part.size.x > 0 and part.size.y > 0:
                        var had: Rect2i = out.get(at, part)
                        out[at] = had.merge(part)
    return out


## Every layer under *root* that carries a filter or is an effect layer, found
## by a walk of the stack. While a stroke is being painted on *root*, a
## document, the list is kept for that stroke and the walk is not made again
## until the stack gains or loses a node, since nothing attaches a filter or
## adds an effect layer between two dabs of one stroke. Whether a bearer shows
## and how wide its halo is are asked of it at every call.
static func bearers(root: Node) -> Array[SaLayer]:
    var document := root as SaDocument
    var stroke := _stroke_of(document)
    if stroke != 0:
        var held: Bearers = _kept.get(document.get_instance_id(), null)
        if held != null and held.stroke == stroke and held.count == document.get_child_count():
            return held.layers
    var found: Array[SaLayer] = []
    var pending: Array[Node] = [root]
    while not pending.is_empty():
        var parent: Node = pending.pop_back()
        for child: Node in parent.get_children():
            var layer := child as SaLayer
            if layer != null:
                if not layer.filters.is_empty() or layer.is_effect():
                    found.append(layer)
                pending.append(layer)
    if stroke != 0:
        for id: int in _kept.keys():
            if not is_instance_id_valid(id):
                _kept.erase(id)
        _kept[document.get_instance_id()] = Bearers.new(stroke, document.get_child_count(), found)
    return found


## The count of the stroke being painted on *document*, nought when none is.
static func _stroke_of(document: SaDocument) -> int:
    if document == null or document.stroke_transaction == null:
        return 0
    var buffer := document.stroke_layer
    var live := (buffer != null and not buffer.chunks.is_empty()) or not document.stroke_transaction.before_chunks.is_empty()
    return document.stroke_transaction.opened if live else 0


## The bearers under *root* whose output a change at *at* moves, and that show
## or feed an effect layer that does. Null *at* names no layer, and every
## bearer that shows is answered.
static func _readers(root: Node, at: SaLayer) -> Array[SaLayer]:
    var document := root as SaDocument
    var all := bearers(root)
    var read: Array[SaLayer] = []
    if at == null:
        read = all
    else:
        read = Readers.new(document, all).of(at)
    if document == null:
        return read
    var inputs: Dictionary[SaLayer, bool] = {}
    for bearer: SaLayer in all:
        var input := SaEffectLayer.input_of(bearer)
        if input != null:
            inputs[input] = true
    var shown: Array[SaLayer] = []
    for bearer: SaLayer in read:
        if SaLayerStack.contributes(document, bearer) or _fed(bearer, inputs):
            shown.append(bearer)
    return shown


## Whether *bearer* is one of *inputs* or sits inside one, so an effect layer
## reads it whether it shows or not.
static func _fed(bearer: SaLayer, inputs: Dictionary[SaLayer, bool]) -> bool:
    for node: SaLayer in Readers.chain(bearer):
        if inputs.has(node):
            return true
    return false


## The bearers that read a changed layer, found by walking each changed node's
## own chain of groups once rather than every bearer against every node found
## so far. A bearer reads a node when it is the node or holds it, when it is an
## effect layer whose input is or holds it, when it is an adjustment layer above
## it in a scope that holds it, or when the node is clipped to it. Asking that
## of every bearer again for each node took 100 ms a call on the nights file's
## 593 layers, twice on every opacity step.
class Readers:
    extends RefCounted
    var _document: SaDocument
    var _all: Array[SaLayer]
    var _bearing: Dictionary[SaLayer, bool] = {}
    ## Input -> the effect layers that read it.
    var _by_input: Dictionary[SaLayer, Array] = {}
    ## Scope -> the adjustment layers in it, the top level under null.
    var _by_scope: Dictionary = {}

    func _init(document: SaDocument, all: Array[SaLayer]) -> void:
        _document = document
        _all = all
        for bearer: SaLayer in all:
            _bearing[bearer] = true
            var input := SaEffectLayer.input_of(bearer)
            if input != null:
                if not _by_input.has(input):
                    _by_input[input] = []
                _by_input[input].append(bearer)
            if bearer.is_adjustment():
                var scope := SaLayerStack.parent_of(bearer)
                if not _by_scope.has(scope):
                    _by_scope[scope] = []
                var scoped: Array = _by_scope[scope]
                scoped.append(bearer)

    ## The bearers a change at *at* moves, in the order of the bearers.
    func of(at: SaLayer) -> Array[SaLayer]:
        var read: Dictionary[SaLayer, bool] = {}
        var pending: Array[SaLayer] = [at]
        while not pending.is_empty():
            var node: SaLayer = pending.pop_back()
            for bearer: SaLayer in _reading(node):
                if not read.has(bearer):
                    read[bearer] = true
                    pending.append(bearer)
        var found: Array[SaLayer] = []
        for bearer: SaLayer in _all:
            if read.has(bearer):
                found.append(bearer)
        return found

    func _reading(node: SaLayer) -> Array[SaLayer]:
        var found: Array[SaLayer] = []
        var held := chain(node)
        for outer: SaLayer in held:
            if _bearing.has(outer):
                found.append(outer)
            for effect: SaLayer in _by_input.get(outer, []):
                found.append(effect)
        var scopes: Array = held.duplicate()
        scopes.append(null)
        for scope: Variant in scopes:
            for adjustment: SaLayer in _by_scope.get(scope, []):
                if node.get_index() < adjustment.get_index():
                    found.append(adjustment)
        if node.clip_to_below and _document != null:
            var base := SaLayerStack.clip_base(_document, node)
            if base != null and _bearing.has(base):
                found.append(base)
        return found

    ## *layer* and the groups that hold it, innermost first, as
    ## [method SaLayerStack.is_inside] walks them.
    static func chain(layer: SaLayer) -> Array[SaLayer]:
        var held: Array[SaLayer] = []
        var at := layer
        while at != null and held.size() < 64:
            held.append(at)
            at = SaLayerStack.parent_of(at)
        return held


## *regions* with every chunk a change of them makes stale on a node whose
## filters read the whole node added whole, for a layer that holds a chunk at
## one of the regions and for the root at any region, which
## `SaNeighbourhoodPass.stale_under` answers. *regions* as it is when no node
## carries such a filter. The regions and what every node but the root added
## are kept for [method take_beneath].
##
## The root's stale set was once every chunk the document held, because the
## chain gathered the canvas over it. `SaRootGather` gathers over
## its own positions now, so the root is made stale where a change lands, as a
## layer is.
func _spread_whole(
    root: Node,
    root_filters: Array[SaAttachedFilter],
    readers: Array[SaLayer],
    regions: Dictionary[Vector2i, Rect2i],
    canvas: Vector2i
) -> Dictionary[Vector2i, Rect2i]:
    if regions.is_empty():
        return regions
    var spread_to: Dictionary[Vector2i, bool] = {}
    var by_root: Dictionary[Vector2i, bool] = {}
    if SaNeighbourhoodPass.reads_whole(root_filters):
        # A root pass that carries a change says where it lands from the
        # regions alone, and gathering every chunk of the stack for it was a
        # walk of every layer at every dab.
        var everywhere: Dictionary[Vector2i, bool] = {}
        if not SaNeighbourhoodPass.carries_change(root_filters, canvas):
            everywhere = _held_under(root)
        by_root.merge(SaNeighbourhoodPass.stale_under(root_filters, everywhere, regions, canvas))
    for node: SaLayer in readers:
        if SaNeighbourhoodPass.reads_whole(node.filters):
            var held := _held_under(node)
            for grid_pos: Vector2i in regions:
                if held.has(grid_pos):
                    spread_to.merge(SaNeighbourhoodPass.stale_under(node.filters, held, regions, canvas))
                    break
    _beneath.merge(SaTyped.positions(regions))
    _beneath.merge(spread_to)
    spread_to.merge(by_root)
    if spread_to.is_empty():
        return regions
    var out := regions.duplicate()
    for grid_pos: Vector2i in spread_to:
        out[grid_pos] = SaDocument.WHOLE_CHUNK
    return out


## Every grid position *node* or a layer under it holds a chunk at, as a set.
static func _held_under(node: Node) -> Dictionary[Vector2i, bool]:
    var held: Dictionary[Vector2i, bool] = {}
    var pending: Array[Node] = [node]
    while not pending.is_empty():
        var at: Node = pending.pop_back()
        if at is SaLayer:
            for grid_pos: Vector2i in (at as SaLayer).chunks:
                held[grid_pos] = true
        for child in at.get_children():
            if child is SaLayer:
                pending.append(child)
    return held
