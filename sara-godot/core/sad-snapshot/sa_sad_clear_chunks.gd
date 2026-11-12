## The chunks of one save that hold nothing: found on the card, left out of the
## file, and let go of by the document.
##
## **What holds nothing.** A chunk every authoritative field of which reads as
## its own blank in every texel, compared bit for bit. Colour is zero in all
## four channels, so alpha 0 over colour is kept. A layer's mask is at the rest
## a chunk would open at, `SaMask.rest`, and an own mask's chunk, a group's or
## an attached filter's, at that mask's rest. A lazy field counts by its spec's
## blank where it has a texture and is blank where it has none. A derived field
## is rebuilt from the others and is not tested.
##
## **Found where the save reads back already.** Every chunk is a group with one
## word in a buffer on the card, and the `sad_snapshot_sweep` kernel sets the
## word wherever a texel differs from its blank. A save in the background runs
## it over each copy it takes, [constant SWEEPS_A_TURN] a turn in the turns after
## its snapshot, since a copy holds the snapshot however late it is swept and
## a large document's copies swept in one frame would stall it for a visible
## part of a second. Once every copy is swept it asks for the words alone, a
## word a chunk. It reads no copy back before they are in, and then asks for
## none of a chunk that holds nothing. A save at once, which reads every
## texture back in its own frame, sweeps the live textures before its walk and
## reads the words in that frame too.
##
## **Safe for paint.** A chunk is left out only once every authoritative
## texture it holds was swept, so a copy the device refused never empties one,
## and a texture two layers hold, or one this did not name, is kept. The file
## is of the snapshot, so leaving a chunk out of it is always safe. The
## document lets the chunk go only when it stands as the snapshot found it,
## the history where it was and no stroke open, and undo makes a chunk again
## where a step finds it gone (`SaDocument.swap_pixels`, `SaMask.swap_chunks`).
class_name SaSadClearChunks
extends RefCounted

## The kernel's file.
const SHADER := "sad_snapshot_sweep"
## The key a left out chunk's slots carry, so the worker drops their entries.
const LEFT_OUT := "sa_left_out"
## The channels of each format a field is stored at. A texture at a format not
## listed is kept, since the pass cannot say what it holds.
const CHANNELS := {
    RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT: 4,
    RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT: 4,
    RenderingDevice.DATA_FORMAT_R32G32_SFLOAT: 2,
    RenderingDevice.DATA_FORMAT_R32_SFLOAT: 1,
    RenderingDevice.DATA_FORMAT_R16_SFLOAT: 1,
}

## The copies a save in the background sweeps in one turn, about 25 ms of a
## frame's work.
const SWEEPS_A_TURN := 200

## The kernel, made at the first sweep and kept, as the rounding's is.
static var _compute: SaCompute = null

## The save this belongs to by its instance id, zero for a save at once.
var save_id: int = 0
## The chunks a save let go of, for its line in the journal and for a suite.
var let_go: int = 0

var _document: SaDocument = null
## Per group: the layer or the own mask that holds the chunk, its position, the
## chunk itself, the authoritative textures it holds and how many were swept,
## whether something about it says keep, and whether the walk reached it.
var _owners: Array[Object] = []
var _positions: Array[Vector2i] = []
var _chunks: Array[SaChunk] = []
var _needed: PackedInt32Array = PackedInt32Array()
var _swept: PackedInt32Array = PackedInt32Array()
var _kept: Array[bool] = []
var _reached: Array[bool] = []
## A texture's resource to its group, its blank, its channels to compare, none
## for a derived field, and the texture.
var _textures: Dictionary[RID, Array] = {}
## The words on the card, and as they came back.
var _flags: SaCompute.Buffer = null
var _words: PackedByteArray = PackedByteArray()
## The copies taken and not swept yet, each with what names its texture, in
## the order taken, and whether the walk is done, so the words may be asked for
## once the last is swept.
var _owed: Array[Array] = []
var _walked := false
var _asked := false
## Whether the next turn is the snapshot's own, which sweeps none.
var _fresh := false
## Whether the answer came, and whether this acted on it.
var _back := false
var _done := false
## The group of each copy a save in the background took, in order, -1 for one
## of no group, and the slot it fills.
var _taken: PackedInt32Array = PackedInt32Array()
var _slots: Array[Dictionary] = []
## Which copies, by the order taken, hold nothing, once the words are in.
var _left_out: Array[bool] = []
## Where the document stood at the walk: its history's position and base, and
## its raises.
var _position := 0
var _base := 0
var _raises := 0


## Names every chunk of *document* a save may write, the save in the background
## being *save*, or none for a save at once.
func _init(document: SaDocument, save: Object) -> void:
    _document = document
    save_id = save.get_instance_id() if save != null else 0
    for child in document.get_children():
        var layer := child as SaLayer
        if layer == null:
            continue
        for grid_pos: Vector2i in layer.chunks:
            _name_chunk(layer, grid_pos, layer.chunks[grid_pos])
        _name_mask(layer.mask)
        for record: SaAttachedFilter in layer.filters:
            _name_mask(record.mask)
    for record: SaAttachedFilter in document.root_filters:
        _name_mask(record.mask)
    _words.resize(4 * maxi(_chunks.size(), 1))
    _words.fill(0)
    if not _chunks.is_empty() and GlobalShaderCompiler.get_rd() != null:
        _flags = SaCompute.Buffer.new(_words)
    var history := document.history
    _position = history.position() if history != null else 0
    _base = history.base_serial if history != null else 0
    _raises = document.raises


func _name_chunk(layer: SaLayer, grid_pos: Vector2i, chunk: SaChunk) -> void:
    if chunk == null:
        return
    var group := _open(layer, grid_pos, chunk)
    for field_id: StringName in chunk.fields:
        var spec := SaFieldSpec.find(layer.schema, field_id)
        var blank := spec.blank if spec != null else SaFieldSpec.NO_PAINT
        if field_id == SaFieldSpec.MASK and layer.mask != null and not layer.mask.is_own():
            blank = _rest(layer.mask)
        _name_texture(group, chunk.fields[field_id], blank, spec == null, spec != null and spec.is_derived())


func _name_mask(mask: SaMask) -> void:
    if mask == null or not mask.is_own():
        return
    for grid_pos: Vector2i in mask.chunks:
        var chunk: SaChunk = mask.chunks[grid_pos]
        if chunk != null:
            _name_texture(_open(mask, grid_pos, chunk), chunk.field(SaFieldSpec.MASK), _rest(mask), false, false)


static func _rest(mask: SaMask) -> Color:
    return Color(mask.rest, mask.rest, mask.rest, mask.rest)


func _open(owner: Object, grid_pos: Vector2i, chunk: SaChunk) -> int:
    _owners.append(owner)
    _positions.append(grid_pos)
    _chunks.append(chunk)
    _needed.append(0)
    _swept.append(0)
    _kept.append(false)
    _reached.append(false)
    return _chunks.size() - 1


## Notes *texture* of *group*. A texture of no spec, of a format the pass
## cannot read, or named twice, by two layers that hold one chunk, keeps its
## group, and a texture of each.
func _name_texture(group: int, texture: SaTexture, blank: Color, unknown: bool, derived: bool) -> void:
    if texture == null or not texture.rid.is_valid():
        return
    if _textures.has(texture.rid):
        _kept[group] = true
        _kept[_textures[texture.rid][0]] = true
        return
    var channels: int = 0 if derived else CHANNELS.get(texture.format, -1)
    _textures[texture.rid] = [group, blank, channels, texture]
    if unknown or channels < 0:
        _kept[group] = true
    elif channels > 0:
        _needed[group] += 1


## Owes the pass over *copy*, the save's copy of *texture* taken into *slot*,
## to the turns after the snapshot, and notes which group the copy is of.
func sweep(texture: SaTexture, copy: SaTexture, slot: Dictionary) -> void:
    var named: Array = _textures.get(texture.rid, [])
    var group: int = named[0] if not named.is_empty() else -1
    _taken.append(group)
    _slots.append(slot)
    if not named.is_empty():
        _owed.append([copy, named])


func _dispatch(texture: SaTexture, named: Array) -> void:
    var channels: int = named[2]
    if channels <= 0 or _flags == null:
        return
    if _compute == null:
        _compute = SaCompute.new(SHADER)
    var blank: Color = named[1]
    var params := {"blank": blank, "width": texture.size.x, "height": texture.size.y, "channels": channels, "slot": named[0]}
    _compute.run("sad_snapshot_sweep", {"field": texture, "flags": _flags}, params, Rect2i(Vector2i.ZERO, texture.size))
    _swept[named[0]] += 1


## Sweeps every texture named, in place, and reads the words back now, for a
## save at once, whose walk then leaves out what holds nothing.
func sweep_now() -> void:
    for named: Array in _textures.values():
        var texture: SaTexture = named[3]
        _dispatch(texture, named)
    _words = _flags.read() if _flags != null else _words
    _back = true


## Whether the walk leaves out the chunk *texture* belongs to, which it asks
## once a chunk and once an own mask's chunk. The question marks the group
## reached, so only a chunk a save wrote or left out is ever let go of. Before
## the words are in, nothing is left out.
func leaves_out(texture: SaTexture) -> bool:
    if texture == null:
        return false
    var named: Array = _textures.get(texture.rid, [])
    if named.is_empty():
        return false
    var group: int = named[0]
    _reached[group] = true
    return _back and _holds_nothing(group)


func _holds_nothing(group: int) -> bool:
    if _kept[group] or _needed[group] == 0 or _swept[group] != _needed[group]:
        return false
    return _words.size() >= 4 * (group + 1) and _words.decode_u32(4 * group) == 0


## Once the walk is done: a save in the background asks for the words, and a
## save at once lets go of the chunks it left out.
func walked() -> void:
    if save_id == 0:
        _act()
        return
    _walked = true
    _fresh = true
    if _owed.is_empty():
        _ask_words()


## Sweeps a turn's share of the copies owed, once a turn of the save after the
## snapshot's own, and asks for the words once none is owed.
func turned() -> void:
    if not _walked or _asked:
        return
    if _fresh:
        _fresh = false
        return
    var share := mini(_owed.size(), SWEEPS_A_TURN)
    for at in share:
        var copy: SaTexture = _owed[at][0]
        var named: Array = _owed[at][1]
        _dispatch(copy, named)
    _owed = _owed.slice(share)
    if _owed.is_empty():
        _ask_words()


func _ask_words() -> void:
    _asked = true
    if _flags == null or _swept.count(0) == _swept.size():
        _back = true
        return
    _back = _flags.rd.buffer_get_data_async(_flags.rid, _words_back) != OK


## The device's answer. It sends the device nothing, so it only keeps the words.
func _words_back(bytes: PackedByteArray) -> void:
    if bytes.size() == _words.size():
        _words = bytes
    _back = true


## Whether the words of the save in the background are in, acting on them the
## first time they are: marks the slots of what holds nothing and lets go of
## those chunks when the document stands where the walk found it.
func is_in() -> bool:
    if not _back:
        return false
    if not _done:
        for index in _taken.size():
            var empty := _taken[index] >= 0 and _reached[_taken[index]] and _holds_nothing(_taken[index])
            _left_out.append(empty)
            if empty:
                _slots[index][LEFT_OUT] = true
        _act()
    return true


## Lets go of each chunk reached that holds nothing, when the document stands
## where the walk found it, and then forgets the chunks, so their textures go.
func _act() -> void:
    _done = true
    if _stands():
        for group in _chunks.size():
            if _reached[group] and _holds_nothing(group):
                _let_go(group)
    if let_go > 0:
        SaTrail.note("the save let go of %d chunks that held nothing" % let_go)
    _owners.clear()
    _chunks.clear()
    _textures.clear()
    _flags = null
    _document = null


func _stands() -> bool:
    return SaSadSnapshot.stands(_document, _position, _base, _raises)


func _let_go(group: int) -> void:
    var owner := _owners[group]
    var grid_pos := _positions[group]
    if owner is SaLayer and is_instance_valid(owner) and (owner as SaLayer).chunks.get(grid_pos, null) == _chunks[group]:
        (owner as SaLayer).set_chunk(grid_pos, null)
        let_go += 1
    elif owner is SaMask and (owner as SaMask).chunks.get(grid_pos, null) == _chunks[group]:
        (owner as SaMask).set_chunk(grid_pos, null)
        let_go += 1


## Whether the copy at *index*, in the order taken, holds nothing.
func leaves_out_copy(index: int) -> bool:
    return index >= 0 and index < _left_out.size() and _left_out[index]


## *header* with every chunk entry and own mask slot marked as left out taken
## out of its list. Touches nothing but the header, so the save's worker runs it.
static func prune(header: Dictionary) -> Dictionary:
    var nodes: Array = header.get("layers", []) + header.get("filters", [])
    for node: Variant in nodes:
        if not node is Dictionary:
            continue
        var entry: Dictionary = node
        _prune_list(entry.get("chunks", null))
        var owners: Array = [entry] + entry.get("filters", [])
        for owner: Variant in owners:
            if not owner is Dictionary:
                continue
            var held: Dictionary = owner
            var mask: Variant = held.get("mask", null)
            if mask is Dictionary:
                var masked: Dictionary = mask
                _prune_list(masked.get("chunks", null))
    return header


static func _prune_list(list: Variant) -> void:
    if not list is Array:
        return
    var entries: Array = list
    var kept: Array = entries.filter(func(item: Variant) -> bool: return not _left_out_entry(item))
    entries.assign(kept)


static func _left_out_entry(item: Variant) -> bool:
    if not item is Dictionary:
        return false
    var entry: Dictionary = item
    if entry.has(LEFT_OUT):
        return true
    var fields: Variant = entry.get("fields", null)
    if not fields is Dictionary:
        return false
    var by_field: Dictionary = fields
    for slot: Variant in by_field.values():
        if slot is Dictionary:
            var field: Dictionary = slot
            if field.has(LEFT_OUT):
                return true
    return false
