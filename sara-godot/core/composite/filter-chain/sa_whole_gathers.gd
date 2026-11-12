## The gathers a whole-node pass reads, one per stored node, kept from one
## composite to the next and told by [method SaFilterChain.spilled] where the
## document was painted in between.
##
## Its own file because it is one thing the chain keeps: the gathers, what each
## still owes, and the one decision of when they all start anew. The gathering
## itself is the chain's runner, handed in, so it dispatches nothing of its own.
class_name SaWholeGathers
extends RefCounted

## Stored layer instance id -> the [SaNeighbourhoodPass.Whole] a whole-node
## pass reads over it.
var _wholes: Dictionary[int, SaNeighbourhoodPass.Whole] = {}
## Stored layer instance id -> the [SaGatherLedger] of its node in [member _wholes].
var _ledgers: Dictionary[int, SaGatherLedger] = {}
## The ids of [member _wholes] brought up to date in the evaluation
## [member _frame] names, each -> the id of the layer whose chunks it was
## gathered from, the node's own or a halo's over it, so every chunk after the
## first reads the node without asking what it owes.
var _current: Dictionary[int, int] = {}
## Stored layer instance id -> the texture of a gather let go since, which the
## next gather over that node copies every chunk into again rather than making
## its own. Freeing it drops every uniform set `SaCompute` has cached, and the
## frames that showed a large painting's group let a gather go each.
var _spare: Dictionary[int, SaTexture] = {}
## The process frame of the last composite, so a flatten a frame after it
## gathers anew rather than reading a node no composite has told of what
## changed since.
var _frame: int = -1
## The document the kept nodes were last told of and its consume count then.
var _document: int = 0
var _consumed: int = -1


## *stored*'s allocated chunks gathered at *format* by *runner* for the current
## evaluation, brought up to date once and read by every chunk of it. Null
## when *stored* is null.
##
## The node is kept between composites and copies again only the chunks
## [method SaFilterChain.spilled] marked as painted since, so a stroke under a
## kaleidoscope copies the chunks its dabs touched and not every chunk of the
## layer a frame. The gather itself starts anew when the chunks the node holds
## span another rectangle.
##
## With *under*, *stored* is a halo over it, see [method SaFilterHalo.lies_over],
## and the gather is *under*'s own kept one, a position read from the halo where
## it holds a chunk and from *under* everywhere else. The ledger keeps the chunk
## last copied to each position, so a live stroke's first frame copies the
## halo's chunks over the layer's and nothing more, and the frame after it ends
## copies the layer's own back over them.
func of(stored: SaLayer, format: int, runner: SaNeighbourhoodPass.Runner, under: SaLayer = null) -> SaNeighbourhoodPass.Whole:
    if stored == null:
        return null
    var frame := Engine.get_process_frames()
    if frame != _frame:
        _start_anew()
        _current.clear()
        _frame = frame
    var node := under if under != null else stored
    var id := node.get_instance_id()
    var kept: SaNeighbourhoodPass.Whole = _wholes.get(id, null)
    if kept == null and _spare.has(id):
        # An origin no gather has, so this one copies every chunk anew.
        kept = SaNeighbourhoodPass.Whole.new()
        kept.texture = _spare[id]
        kept.origin = Vector2i(-(1 << 30), -(1 << 30))
        _spare.erase(id)
    var current := kept != null and kept.texture != null and kept.texture.format == format
    if current and _current.get(id, 0) == stored.get_instance_id():
        return kept
    if not _ledgers.has(id):
        _ledgers[id] = SaGatherLedger.new()
    var ledger: SaGatherLedger = _ledgers[id]
    var positions: Array = stored.chunks.keys()
    var field := stored.get_field
    if node != stored:
        var both: Dictionary[Vector2i, bool] = {}
        for grid_pos: Vector2i in node.chunks:
            both[grid_pos] = true
        for grid_pos: Vector2i in stored.chunks:
            both[grid_pos] = true
        positions = both.keys()
        field = func(grid_pos: Vector2i) -> SaTexture:
            var over := stored.get_field(grid_pos)
            return over if over != null else node.get_field(grid_pos)
    kept = runner.gather(positions, field, format, kept, ledger.owed)
    _wholes[id] = kept
    _current[id] = stored.get_instance_id()
    return kept


## Opens an evaluation for the kept nodes: each is told where *document* was
## painted since the last composite, a node whose layer is gone is let go, and
## every one of them is let go when *whole* says the composite covers
## everything, which is what a filter's attach, a touch of its parameters, an
## undo of the tree and every other change no dirty region names redraw with. A
## node whose document another composite named in between gathers anew, since
## what was painted there was never marked on it. True when they all start
## anew, which the root's gather does with them.
func keep(document: SaDocument, whole: bool) -> bool:
    _current.clear()
    _frame = Engine.get_process_frames()
    var anew := whole or document.consumed != _consumed + 1 or document.get_instance_id() != _document
    if anew:
        _start_anew()
    _consumed = document.consumed
    _document = document.get_instance_id()
    for id: int in _spare.keys():
        if not is_instance_id_valid(id):
            _spare.erase(id)
    for id: int in _ledgers.keys():
        if not is_instance_id_valid(id):
            _wholes.erase(id)
            _ledgers.erase(id)
            continue
        (_ledgers[id] as SaGatherLedger).mark(document.painted)
    return anew


## Lets every gather go, their textures with them.
func let_go() -> void:
    _wholes.clear()
    _ledgers.clear()
    _spare.clear()


# Lets every gather go and keeps its texture for the next gather over its node.
func _start_anew() -> void:
    for id: int in _wholes:
        var whole: SaNeighbourhoodPass.Whole = _wholes[id]
        if whole.texture != null:
            _spare[id] = whole.texture
    _wholes.clear()
    _ledgers.clear()
