## What a save does on the card to the textures it is about to read back: the
## rounding of colour, the chunks that hold nothing found, left out of the file
## and let go of, which `SaSadClearChunks` beside this owns, and the reuse of
## the chunks that are as the last save wrote them.
##
## A save the painter asked for rounds full precision colour once. Every channel
## of a colour field at `R32G32B32A32_SFLOAT`, alpha included and in an RGB or an
## Oklab document alike, keeps 12 significant bits, rounded to nearest with ties
## to even, so it moves by at most 2^-12 of itself, which no eye sees and which
## makes the file markedly smaller. Only the save's own copy of a texture is
## rounded, before either of its forms is read back, so the document keeps its
## float32 colour and a load changes nothing. Never rounded: half precision
## colour, every mask, the height and every other field that is not colour, a
## simulation's seed, and the capture harness's copy. `SaColorSpace.rounds_at_save`
## holds the painter's choice for each document and [method begin] reads it.
##
## A save rewrites only the chunks that changed. Before the walk, the
## `sad_snapshot_hash` kernel, which `SaSadHash` dispatches for every texture in
## one list, leaves a 128 bit hash of each field of every allocated chunk and of
## every chunk of a mask, and only the hashes are read back (for a painter's
## save, a share a turn, `SaSadHashShares`). A texture whose hash, format, size,
## form and rounding are those of a blob the last save wrote at the same path is
## not read back: its compressed bytes are copied from the file the save
## replaces and the header is built afresh. The hash reads the texels, so no
## writer of a chunk can be missed, and a chunk changed since is never copied.
##
## The copy is trusted only after a check. A [SaSadSnapshot.Record] keeps the
## path, the file's size and modified time, a digest of its header and every blob
## by its key. The next save to that path copies only when the file still has
## that size, time and header, and the document is the one that saved it with the
## place it was saved at still in its history. Otherwise, and for a Save As to a
## path with no record, the save is whole. A save that does not round keeps a
## record too, and the key of a blob says whether it is rounded, so a lossless
## save never takes a rounded colour blob for its own, nor the reverse.
##
## An open leaves a record too, so the first save after an open copies rather
## than writing the whole document: the loader notes each blob that filled a
## texture exactly through [method opening], and [method opened] hashes those
## textures as read and keeps the file's blobs by the keys the next save will
## compute. The open's record serves a save to any path.
##
## [method begin] names the textures of a document's colour and its chunks and
## hashes them before the walk, [method end] hands what the walk did to the
## save, and [method remember] keeps it once the file is written.
class_name SaSadSnapshot
extends RefCounted

## The kernel's file.
const SHADER := "sad_snapshot"
## The only format rounded, a full precision colour field's.
const FULL := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
## The significant bits a rounded channel keeps, the implicit one among them.
const KEPT_BITS := 12
## An exponent of all ones, an infinity or a NaN.
const EXPONENT := 0x7F800000

## The textures the walk of the running save rounds, by their resource, empty
## when the save rounds nothing.
static var _colour: Dictionary[RID, bool] = {}
## The kernel, made at the first rounding and kept.
static var _compute: SaCompute = null
## The formats the hash kernel is made for, the four a bare image binds at, so
## a field of any other format is never hashed and always written.
const HASHED: Array[int] = [
    RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,
    RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
    RenderingDevice.DATA_FORMAT_R32_SFLOAT,
    RenderingDevice.DATA_FORMAT_R16_SFLOAT,
]
## The hashes of a save from the key sent and read in shares, named through
## the facade so the save sees the door only.
const HashShares := preload("res://core/sad-snapshot/sa_sad_hash_shares.gd")
## The rounding of the live textures before an export, named through the
## facade so an export sees the door only.
const LiveRounding := preload("res://core/sad-snapshot/sa_live_rounding.gd")

## The records a save keeps, at most this many paths.

const RECORDS_KEPT := 8
## The magic, the version and the header's two sizes, ahead of the header.
const HEAD_BYTES := 16

## What the last saves wrote, by path, those that round and those that do not.
static var _records: Dictionary[String, Record] = {}
## What the last opens of a `.sad` read, by path, kept apart from the saves'
## records so a file opened into a second document leaves the first its own.
static var _opens: Dictionary[String, Record] = {}
## The textures the running open filled exactly, each with the entry of its
## blob and whether it is planes, by their resource, which [method opened]
## takes and empties.
static var _opening: Dictionary[RID, Array] = {}
## The hashes [method hash_noted] took of what the open noted so far, by
## [method _hash_key], which [method opened] takes instead of hashing again.
static var _opening_hashes: Dictionary[String, String] = {}
## The notes of the running open not yet hashed by [method hash_noted].
static var _unhashed: Dictionary[RID, Array] = {}
## What the running walk reuses and writes, null outside a walk.
static var _reuse: Reuse = null
## The chunks of the save whose walk runs, null outside a walk.
static var _walk: SaSadClearChunks = null
## The chunks of the save in the background that runs or ran last, kept past
## its walk for the frames its words take to come back.
static var _running: SaSadClearChunks = null
## The copies a save as JPEG XL takes, made and cleared on the card a share a
## turn before its snapshot, by size and format, so the snapshot's frame makes
## none, where a large document's copies made in one frame stall it visibly.
static var _spares: Dictionary[String, Array] = {}
## The textures still owed a spare, and the save they are made for.
static var _sparing: Array[SaTexture] = []
static var _spared_for := 0
## How many spares a turn makes.
const SPARES_A_TURN := 200


## Names the full precision colour textures of *document* a save is about to
## walk, to be rounded as the walk meets them. With *rounds* false, or no
## document, nothing is named and the save writes every texture as it lies.
## With *path*, the file the save writes, the save also reuses the chunks
## that are as the last save to it wrote them, rounded or not, since a key
## says whether its blob is rounded and a save takes only its own kind.
## Every chunk is named as well, for the sweep that finds what holds nothing:
## a save in the background, *save*, sweeps each copy it takes, and a save at
## once, with no *save*, sweeps the document here and learns now.
##
## With *said*, the hashes a save in the background asked for before the walk,
## by each texture's resource, [method hashed] answering which, nothing is
## hashed here.
static func begin(
    document: SaDocument, rounds: bool, path := "", save: Object = null, said: Dictionary[RID, String] = {}
) -> void:
    _colour.clear()
    _walk = null
    _reuse = Reuse.new(path, document != null and not path.is_empty(), document)
    if not _reuse.records and not path.is_empty():
        _records.erase(path)
        _opens.erase(path)
    if document == null:
        return
    for child in document.get_children():
        var layer := child as SaLayer
        if layer == null:
            continue
        # The walk resolves a derived colour before it reads it, which may make
        # its texture afresh, so it is resolved here first.
        layer.resolve_pending()
        # Every chunk of the layer is named, a superset of what the walk
        # stores, since a texture named and never met is never rounded.
        for chunk: SaChunk in layer.chunks.values():
            if chunk != null and rounds and rounds_at_save(document):
                _name_colour(layer, chunk)
    _walk = SaSadClearChunks.new(document, save)
    if save != null:
        _running = _walk
    else:
        _walk.sweep_now()
    if not _reuse.records:
        return
    if said.is_empty():
        _hash(document)
    else:
        _reuse.hashes = said
    _reuse.source = _source_for(document, path, save)


## The record a save of *document* to *path* copies from: the last save's to
## that path, else the open's of that path, else, for a copy that leaves the
## document's name as it is or for a save at once, the last save's to the
## document's own file, else the open's of the file the document was opened
## from, wherever the save writes. The blobs of an opened or a saved file are
## what that file holds on disk, so a save to another path copies them as well
## as a save over the file itself would. That lets the autosave after a Ctrl+S
## copy, and the door's first save at once to a new path after one copy rather
## than write a large painting afresh, 7.9 s against 2.0 s. A Save As in
## the background writes every blob afresh unless the document was opened.
## Null when no record holds the document or its file changed on disk since.
static func _source_for(document: SaDocument, path: String, save: Object) -> Record:
    var records: Array[Record] = [_records.get(path), _opens.get(path)]
    if save == null or not save.get("claims"):
        records.append(_records.get(document.file_path))
    records.append_array(_opens.values())
    for record in records:
        if record != null and record.holds(document) and record.still_on_disk():
            return record
    return null


## The codec the file at *path* holds its chunks in, read from the record of
## the last save to that path or of the open that read it, while the file is
## still as that record left it. Empty for Zstd and for a file with no record.
## A save that claims its file keeps that codec, so a Ctrl+S or an autosave over
## a file saved as JPEG XL codes in JPEG XL again.
static func codec_at(path: String) -> StringName:
    for record: Record in [_records.get(path), _opens.get(path)]:
        if record == null or not record.still_on_disk(false):
            continue
        for slot: Dictionary in record.blobs.values():
            if slot.has(SaSadCodec.KEY):
                return StringName(SaTyped.text_at(slot, SaSadCodec.KEY, ""))
        return &""
    return &""


## Forgets the textures [method begin] named, once the walk is done, and
## answers what the walk reused and wrote, for [method remember]. A save in
## the background asks for its words now, and a save at once lets go of the
## chunks it left out.
static func end() -> Reuse:
    _colour.clear()
    _drop_spares()
    if _walk != null:
        _walk.walked()
    _walk = null
    var reuse := _reuse
    _reuse = null
    return reuse


## Forgets what [method begin] named and swept for a walk in shares that is
## dropped half done, because the document moved under it, and asks for no
## words, so nothing it noted is let go of and the next walk begins afresh.
static func drop() -> void:
    _colour.clear()
    _walk = null
    _running = null
    _reuse = null


## Whether the walk leaves out the chunk *texture* is of, a layer's chunk by
## any of its fields or an own mask's. Asked by `SaSadFile.header_of` and
## `SaSadFile.write_mask`.
static func leaves_out(texture: SaTexture) -> bool:
    return _walk != null and _walk.leaves_out(texture)


## Takes *texture* into a save in the background: sweeps *copy*, its copy for
## *slot*, and rounds it when the save rounds *texture*.
static func take(texture: SaTexture, copy: SaTexture, slot: Dictionary) -> void:
    if _walk != null:
        _walk.sweep(texture, copy, slot)
    round_copy(texture, copy)


## Whether *save*'s words are in, so it may ask for its copies, and it skips
## those of chunks that hold nothing. The first time they are, the chunks that
## hold nothing are let go of if the document stands as the snapshot found it.
static func flags_in(save: Object) -> bool:
    return _running == null or _running.save_id != save.get_instance_id() or _running.is_in()


## Sweeps a turn's share of *save*'s copies, once a turn of the save, and
## before the snapshot of a save in a codec over a file that holds another,
## a whole save, makes a turn's share of its copies. Answers whether every copy
## is made.
static func turned(save: Object) -> bool:
    if _running != null and _running.save_id == save.get_instance_id():
        _running.turned()
    var hashes: Array = save.get(&"_hashed")
    if save.get(&"codec") == null or save.get(&"_snapped") or hashes.is_empty():
        return true
    # A save over a file in its own codec copies what did not change, so its
    # snapshot makes few copies and is given no spares.
    var codec: SaCodecRegistry.Codec = save.get(&"codec")
    if codec_at(SaTyped.text(save.get(&"path"), "")) == codec.name:
        return true
    if _spared_for != save.get_instance_id():
        _drop_spares()
        _spared_for = save.get_instance_id()
        _sparing.assign(hashes)
    for i in mini(SPARES_A_TURN, _sparing.size()):
        var texture: SaTexture = _sparing.pop_back()
        var copy := SaTexture.new(texture.size, texture.format)
        if copy.rid.is_valid():
            copy.rd.texture_clear(copy.rid, Color(), 0, 1, 0, 1)
            var key := "%s/%d" % [texture.size, texture.format]
            if not _spares.has(key):
                _spares[key] = []
            _spares[key].append(copy)
    return _sparing.is_empty()


## A copy for *texture* to hold: a spare [method turned] made, when there is
## one of its size and format, and otherwise a new texture.
static func spare(texture: SaTexture) -> SaTexture:
    var made: Array = _spares.get("%s/%d" % [texture.size, texture.format], [])
    return made.pop_back() if not made.is_empty() else SaTexture.new(texture.size, texture.format)


## Lets go of the spares no snapshot took.
static func _drop_spares() -> void:
    _spares.clear()
    _sparing.clear()
    _spared_for = 0


## One while *save*'s words are owed by the device, so it draws a frame for
## them, and otherwise none.
static func owed(save: Object) -> int:
    return 0 if flags_in(save) else 1


## Whether the copy at *index* of the running save holds nothing, so it is
## never read back.
static func leaves_out_copy(index: int) -> bool:
    return _running != null and _running.leaves_out_copy(index)


## *header* with what holds nothing taken out, on the save's worker.
static func leave_out(header: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
    SaSadClearChunks.prune(header)
    return header


## Keeps what *reuse* wrote as the record of its path when the file is on
## disk, *saved*, whether the save rounded or not, and otherwise forgets the
## path's.
static func remember(reuse: Reuse, saved: bool) -> void:
    _drop_spares()
    if reuse == null or reuse.path.is_empty():
        return
    _records.erase(reuse.path)
    _opens.erase(reuse.path)
    if not saved or not reuse.records:
        return
    var record := Record.new(reuse, false)
    if not record.blobs.is_empty() and record.still_on_disk():
        _records[reuse.path] = record
    while _records.size() > RECORDS_KEPT:
        _records.erase(_records.keys()[0])


## Notes that *texture* holds what the blob of *slot*, planes or not, holds,
## filled from it by the open that runs, for [method opened]. The loader of a
## `.sad` notes a chunk only when its bytes filled it exactly, a layer's field
## or an own mask's, so a coarse chunk widened on the CPU is never noted and
## the next save writes it.
static func opening(texture: SaTexture, slot: Dictionary[String, Variant], planes: bool) -> void:
    if texture != null and texture.rid.is_valid() and HASHED.has(texture.format) and SaTyped.int_at(slot, "size", 0) > 0:
        _opening[texture.rid] = [texture, slot, planes]
        _unhashed[texture.rid] = _opening[texture.rid]


## Hashes what the open that runs noted since the last call, so an open spread
## over frames hashes each frame's chunks in that frame rather than every chunk
## of a deep file in the frame it lands. The textures are outside any document
## until it lands, so nothing touches them between their hash and
## [method opened].
static func hash_noted() -> void:
    var textures: Array[SaTexture] = []
    var rounded: Array[bool] = []
    _to_hash_noted(_unhashed, textures, rounded)
    _unhashed = {}
    var hashes := _hashes_of(textures, rounded, _opening_hashes)
    if hashes.size() != textures.size():
        return
    for at in textures.size():
        _opening_hashes[_hash_key(textures[at], rounded[at])] = hashes[at]


## Puts each texture of *read*, the open's notes, into *textures*, and once
## more rounded when it is full precision, with *rounded* saying which.
static func _to_hash_noted(read: Dictionary[RID, Array], textures: Array[SaTexture], rounded: Array[bool]) -> void:
    for rid: RID in read:
        var texture: SaTexture = read[rid][0]
        if not texture.rid.is_valid():
            continue
        textures.append(texture)
        rounded.append(false)
        if texture.format == FULL:
            textures.append(texture)
            rounded.append(true)


## The hash of each of *textures*, rounded where *rounded* says, taken from
## *taken* where it holds one and on the card for the rest. Empty when the card
## could not answer.
static func _hashes_of(textures: Array[SaTexture], rounded: Array[bool], taken: Dictionary[String, String]) -> PackedStringArray:
    var asked: Array[SaTexture] = []
    var asked_rounded: Array[bool] = []
    var asked_at: Array[int] = []
    var hashes := PackedStringArray()
    hashes.resize(textures.size())
    for at in textures.size():
        var key := _hash_key(textures[at], rounded[at])
        if taken.has(key):
            hashes[at] = taken[key]
            continue
        asked.append(textures[at])
        asked_rounded.append(rounded[at])
        asked_at.append(at)
    if asked.is_empty():
        return hashes
    var answered := SaSadHash.of(asked, asked_rounded)
    if answered.size() != asked.size():
        return PackedStringArray()
    for slot in asked.size():
        hashes[asked_at[slot]] = answered[slot]
    return hashes


static func _hash_key(texture: SaTexture, rounds: bool) -> String:
    return "%d/%d" % [texture.rid.get_id(), int(rounds)]


## Leaves a record of the `.sad` at *path*, just read into *document*, so the
## first save of the document copies the blobs the file already holds. Each
## blob [method opening] noted goes in under the key the next save gives the
## texture it filled, hashed here on the card before anything else touches it,
## so a texture changed since has another hash and is written. A blob goes in
## stored plain only when it is not planes, and rounded only when the texture
## is full precision and a rounded copy of it hashes as it does, so a file an
## autosave wrote is never copied where a save rounds. The record holds the
## file's size, modified time and header digest as opened. The loader calls it
## once every chunk is in and before the layers resolve.
static func opened(document: SaDocument, path: String) -> void:
    var turns := opened_in_turns(document, path)
    while turns != null and not turns.step(-1):
        pass


## [method opened] in turns, for an open over frames: the hashes are taken in
## this call, before the layers resolve, and the keys and the record are built
## by [method OpenedInTurns.step], a share a frame. On a large painting's 3147
## blobs the whole of it held one frame for 0.1 s. Null when there is nothing to
## keep. Until the last step the path has no record, so a save meanwhile writes
## every blob, which the loader avoids by finishing the steps first.
static func opened_in_turns(document: SaDocument, path: String) -> OpenedInTurns:
    var read := _opening
    _opening = {}
    var taken := _opening_hashes
    _opening_hashes = {}
    _unhashed = {}
    _opens.erase(path)
    if document == null or path.is_empty() or read.is_empty():
        return null
    var textures: Array[SaTexture] = []
    var rounded: Array[bool] = []
    _to_hash_noted(read, textures, rounded)
    var hashes := _hashes_of(textures, rounded, taken)
    if hashes.size() != textures.size():
        return null
    return OpenedInTurns.new(Reuse.new(path, true, document), read, textures, rounded, hashes)


## Keeps *record*, an open's, for its path, when its file is as the open read it.
static func _keep_opened(record: Record) -> void:
    if not record.blobs.is_empty() and record.still_on_disk():
        _opens[record.path] = record
    while _opens.size() > RECORDS_KEPT:
        _opens.erase(_opens.keys()[0])


## The keys and the record of an open's blobs, built a share at a time,
## [method opened_in_turns].
class OpenedInTurns:
    extends RefCounted

    var _reuse: SaSadSnapshot.Reuse
    var _read: Dictionary[RID, Array]
    var _textures: Array[SaTexture]
    var _rounded: Array[bool]
    var _hashes: PackedStringArray
    ## The next of the textures to key.
    var _at := 0

    func _init(
        reuse: SaSadSnapshot.Reuse,
        read: Dictionary[RID, Array],
        textures: Array[SaTexture],
        rounded: Array[bool],
        hashes: PackedStringArray
    ) -> void:
        _reuse = reuse
        _read = read
        _textures = textures
        _rounded = rounded
        _hashes = hashes

    ## Keys the blobs until *budget_usec* has gone, all of them when it is
    ## negative, and once every one is keyed keeps the record, in a step of its
    ## own when the budget is given, since the record reads the file's header.
    ## Answers whether the record is kept.
    func step(budget_usec: int) -> bool:
        var began := Time.get_ticks_usec()
        if _at >= _textures.size():
            SaSadSnapshot._keep_opened(SaSadSnapshot.Record.new(_reuse, true))
            return true
        while _at < _textures.size():
            var at := _at
            _at += 1
            if _rounded[at]:
                continue
            var texture := _textures[at]
            var slot: Dictionary = _read[texture.rid][1]
            var codec := SaTyped.text_at(slot, SaSadCodec.KEY, "")
            var invariant := at + 1 < _textures.size() and _rounded[at + 1] and _hashes[at + 1] == _hashes[at]
            for plain: bool in [false] if _read[texture.rid][2] else [false, true]:
                _reuse.wrote[SaSadSnapshot._key(_hashes[at], texture, plain, false, codec)] = slot
                if invariant:
                    _reuse.wrote[SaSadSnapshot._key(_hashes[at], texture, plain, true, codec)] = slot
            if budget_usec >= 0 and Time.get_ticks_usec() - began >= budget_usec:
                return false
        if budget_usec >= 0:
            return false
        SaSadSnapshot._keep_opened(SaSadSnapshot.Record.new(_reuse, true))
        return true


## Hashes every field of every chunk *document* has allocated on the card, and
## every chunk of a mask of its own a layer, an attached filter or the root
## holds, and reads back only the hashes, four words a texture.
static func _hash(document: SaDocument) -> void:
    var textures := hashed(document)
    _reuse.hashes = said_of(textures, SaSadHash.of(textures, []))


## The textures of *document* a save hashes before its walk, each once, in
## the order [method said_of] takes their hashes in. Every derived colour is
## resolved first, as [method begin] resolves it, so the walk meets the very
## textures hashed here.
static func hashed(document: SaDocument) -> Array[SaTexture]:
    var textures: Array[SaTexture] = []
    if document == null:
        return textures
    var seen: Dictionary[RID, bool] = {}
    _hash_masks(document.root_filters, null, textures, seen)
    for child in document.get_children():
        var layer := child as SaLayer
        if layer == null:
            continue
        layer.resolve_pending()
        for held: Dictionary[Vector2i, SaChunk] in [layer.chunks, stored_chunks(layer)]:
            for chunk: SaChunk in held.values():
                for texture: SaTexture in chunk.fields.values() if chunk != null else []:
                    _to_hash(texture, textures, seen)
        _hash_masks(layer.filters, layer.mask, textures, seen)
    return textures


## Whether *document* stands where a save noted it, at history *position*
## over base serial *base* with its mark raised *raises* times, and no stroke
## open, the autosave's test before it saves. A save's sweep lets a chunk go
## only then, and a save that asked for its hashes walks with them only then.
static func stands(document: SaDocument, position: int, base: int, raises: int) -> bool:
    var history := document.history if is_instance_valid(document) else null
    if history == null or history.position() != position or history.base_serial != base or document.raises != raises:
        return false
    var stroke := document.stroke_layer != null and not document.stroke_layer.chunks.is_empty()
    return not stroke and not (document.stroke_transaction != null and document.stroke_transaction.direct_paint)


## Asks the card for the hash of each of *textures* without waiting, as
## `SaSadHash.ask` does, *then* called with the words a frame or two later,
## which [method said_in] reads. Anything but OK means *then* is never called.
static func ask_hashes(textures: Array[SaTexture], then: Callable) -> Error:
    return SaSadHash.ask(textures, then)


## The hash of each of *textures* by its resource, from the *words* that
## [method ask_hashes] answered, or nothing when they do not hold one for each.
static func said_in(textures: Array[SaTexture], words: PackedByteArray) -> Dictionary[RID, String]:
    return said_of(textures, SaSadHash.words_of(words, textures.size()))


## The hash of each of *textures* by its resource, from *said* in their order,
## or nothing when *said* does not hold one for each.
static func said_of(textures: Array[SaTexture], said: PackedStringArray) -> Dictionary[RID, String]:
    var hashes: Dictionary[RID, String] = {}
    if said.size() != textures.size():
        return hashes
    for slot in textures.size():
        hashes[textures[slot].rid] = said[slot]
    return hashes


## Adds to *textures* the chunks of *mask* and of the mask of each of
## *records*, those of their own, as `SaSadFile.write_mask` meets them. A
## mask that is a field of its layer travels with the layer's chunks.
static func _hash_masks(
    records: Array[SaAttachedFilter], mask: SaMask, textures: Array[SaTexture], seen: Dictionary[RID, bool]
) -> void:
    var masks: Array[SaMask] = [mask]
    for record in records:
        masks.append(record.mask)
    for each in masks:
        if each == null or not each.is_own():
            continue
        for grid_pos: Vector2i in each.grid_positions():
            _to_hash(each.texture_for(grid_pos), textures, seen)


## Adds *texture* to *textures* when the kernel can hash it and nothing has.
static func _to_hash(texture: SaTexture, textures: Array[SaTexture], seen: Dictionary[RID, bool]) -> void:
    if texture != null and texture.rid.is_valid() and HASHED.has(texture.format):
        if not seen.has(texture.rid):
            seen[texture.rid] = true
            textures.append(texture)


## What a blob of *texture* is known by in a record: its hash, format, size,
## whether it is stored plain, whether it is rounded and the codec that codes
## it, *codec*, none for Zstd. Empty when the running save hashed no such
## texture, which is then always written.
static func key_of(texture: SaTexture, plain: bool, codec := &"") -> String:
    if _reuse == null or texture == null or not _reuse.hashes.has(texture.rid):
        return ""
    return _key(_reuse.hashes[texture.rid], texture, plain, is_rounded(texture), codec)


## The key of a blob of *texture* whose texels hash to *said*, stored plain or
## not, rounded or not, and coded by *codec*. A Zstd blob's key names no codec,
## and a coded one's names the codec, so a Ctrl+S never copies
## a coded blob and a save in a codec never copies a Zstd one.
static func _key(said: String, texture: SaTexture, plain: bool, rounded: bool, codec := "") -> String:
    var form := [said, texture.format, texture.size.x, texture.size.y, int(plain), int(rounded)]
    var key := "%s/%d/%dx%d/%d/%d" % form
    return key if codec.is_empty() else "%s/%s" % [key, codec]


## The entry the file the running save replaces holds for *key*, which the
## save copies, or an empty entry when the blob is to be written.
static func old_slot(key: String) -> Dictionary[String, Variant]:
    var none: Dictionary[String, Variant] = {}
    if key.is_empty() or _reuse == null or _reuse.source == null:
        return none
    return _reuse.source.blobs.get(key, none)


## Notes *slot*, the entry the walk gave a blob of *key*, copied or written, for
## the record of this save, and answers it.
static func noted(key: String, slot: Dictionary[String, Variant], copied: bool) -> Dictionary[String, Variant]:
    if _reuse == null or slot.is_empty():
        return slot
    if copied:
        _reuse.copied += 1
    else:
        _reuse.encoded += 1
    if not key.is_empty():
        _reuse.wrote[key] = slot
    return slot


## The packed bytes of the blob *old* names in the file the running save
## replaces, or none when they could not be read, so the texture is written
## instead. A save at once calls it, and closes the file after each blob.
static func read_now(old: Dictionary[String, Variant]) -> PackedByteArray:
    return _reuse.read(old, false) if _reuse != null else PackedByteArray()


## The chunks a save writes into *layer*'s entry, as `SaSadFile` writes them:
## none for an effect or a scene layer, whose chunks are what it draws, and
## none for a user of a shared source whose entry does not keep it,
## `SaSharedSource.keeps_chunks`. `SaLiveRounding` rounds these and no others.
static func stored_chunks(layer: SaLayer) -> Dictionary[Vector2i, SaChunk]:
    if not SaSharedSource.keeps_chunks(layer):
        var none: Dictionary[Vector2i, SaChunk] = {}
        return none
    return SaSceneLayer.stored_chunks(layer) if layer.is_scene() else SaEffectLayer.stored_chunks(layer)


static func _name_colour(layer: SaLayer, chunk: SaChunk) -> void:
    for field_id: StringName in chunk.fields:
        var texture: SaTexture = chunk.fields[field_id]
        var spec := SaFieldSpec.find(layer.schema, field_id)
        if texture != null and spec != null and spec.is_color and texture.format == FULL:
            _colour[texture.rid] = true


## Whether a save of *document* the painter asks for rounds its full
## precision colour, the painter's choice for the document.
static func rounds_at_save(document: SaDocument) -> bool:
    return document == null or document.color_space == null or document.color_space.rounds_at_save


## Turns the rounding at save of *document* on or off as one history step, and
## answers whether anything changed. Turning it off brings back no bit an
## earlier save already rounded, it only keeps every bit of later saves.
static func choose_rounding(document: SaDocument, on: bool) -> bool:
    if document == null or document.color_space == null or document.color_space.rounds_at_save == on:
        return false
    var before := document.color_space
    var after := before.with_rounding(on)
    # Bound to the document itself, which outlives every step of its history.
    var to_after := Callable(document, &"set").bind(&"color_space", after)
    var to_before := Callable(document, &"set").bind(&"color_space", before)
    document.color_space = after
    if document.history != null:
        document.history.commit_pair("Round Colour at Save" if on else "Keep Every Bit at Save", to_after, to_before)
    return true


## Whether the running save rounds *texture*.
static func is_rounded(texture: SaTexture) -> bool:
    return texture != null and _colour.has(texture.rid) and texture.format == FULL


## Rounds *copy*, the save's own copy of *texture*, on the card when the
## running save rounds *texture*. The background save's snapshot calls it.
static func round_copy(texture: SaTexture, copy: SaTexture) -> void:
    if is_rounded(texture):
        round_in_place(copy)


## *texture* as a save at once reads it: a rounded copy of its own when the
## running save rounds it, and otherwise *texture* itself.
static func to_read(texture: SaTexture) -> SaTexture:
    if not is_rounded(texture):
        return texture
    var copy := SaTexture.new(texture.size, texture.format)
    if not copy.rid.is_valid():
        return texture
    var size := Vector3(texture.size.x, texture.size.y, 1)
    texture.rd.texture_copy(texture.rid, copy.rid, Vector3.ZERO, Vector3.ZERO, size, 0, 0, 0, 0)
    round_in_place(copy)
    return copy


## Rounds the live full precision colour of *document* as a save the painter
## asks for rounds the file, where it is not rounded yet, and redraws what
## moved, so an export of the live document equals one of the same document
## saved and opened again. Answers how many textures moved. `SaLiveRounding`
## beside this holds how.
static func round_live(document: SaDocument) -> int:
    return SaLiveRounding.round_document(document)


## [method round_live] over turns: the card asked a share a turn which textures
## move, and the rounding and the redraw once the answer is in, so an export
## over frames holds no frame on a deep stack. The caller calls its `turn`
## each frame until it answers true, or `finish` to end it at once.
static func round_live_in_turns(document: SaDocument) -> LiveRounding.InTurns:
    return SaLiveRounding.InTurns.new(document)


## Rounds every channel of *texture*, a full precision field, to
## [constant KEPT_BITS] significant bits on the card, with nothing read back.
static func round_in_place(texture: SaTexture) -> void:
    if _compute == null:
        _compute = SaCompute.new(SHADER)
    var params := {"width": texture.size.x, "height": texture.size.y}
    _compute.run("sad_snapshot_round", {"field": texture}, params, Rect2i(Vector2i.ZERO, texture.size))


## The pattern of a float32, *bits* as an unsigned 32 bit integer, kept to
## [constant KEPT_BITS] significant bits, to nearest with ties to even, as the
## kernel keeps it. An infinity, a NaN and a value that would round to infinity
## are answered as they are. The reference a suite reads the file against.
static func round_bits(bits: int) -> int:
    if bits & EXPONENT == EXPONENT:
        return bits
    var dropped := 23 - (KEPT_BITS - 1)
    var half := (1 << (dropped - 1)) - 1
    var near := (bits + half + ((bits >> dropped) & 1)) & (0xFFFFFFFF ^ ((1 << dropped) - 1))
    if near & EXPONENT == EXPONENT:
        return bits
    return near


## What one save's walk reused and wrote. The walk fills it on the main thread,
## and a save in the background hands it to its worker, which reads the blobs
## it copies, and back to [method SaSadSnapshot.remember] at its end.
class Reuse:
    extends RefCounted

    ## The file the save writes, and whether the save keeps a record of it,
    ## which a save of a document to a path does, rounding or not.
    var path: String
    var records: bool
    ## The document that saves, the place in its history it stood at and its
    ## layers, by their instance ids.
    var document := 0
    var serial := 0
    var layers: Dictionary[int, bool] = {}
    ## The record of the file the save replaces, null for a whole save.
    var source: Record = null
    ## The hash of every texture of the document's chunks, by its resource.
    var hashes: Dictionary[RID, String] = {}
    ## Each blob the save wrote or copied by its key, its entry filled in place.
    var wrote: Dictionary[String, Dictionary] = {}
    ## The blobs the save compressed afresh and the ones it copied.
    var encoded := 0
    var copied := 0
    ## The file the blobs are copied from, opened at the first read.
    var _file: FileAccess = null
    var _failed := false

    func _init(_path: String, _records: bool, doc: SaDocument) -> void:
        path = _path
        records = _records
        if doc != null:
            document = doc.get_instance_id()
            serial = doc.history.position() if doc.history != null else 0
            for child in doc.get_children():
                if child is SaLayer:
                    layers[child.get_instance_id()] = true

    ## Whether the save writes the whole file, with nothing copied.
    func is_whole() -> bool:
        return source == null or copied == 0

    ## The compressed bytes of the blob *old* names in the file the save
    ## replaces, or none when that file is no longer as recorded.
    ## With *kept* false the file is closed again after the read, which a save
    ## at once asks for, since it renames over the file before it ends.
    func read(old: Dictionary[String, Variant], kept := true) -> PackedByteArray:
        if source == null or _failed:
            return PackedByteArray()
        if _file == null:
            if not source.still_on_disk(false):
                _failed = true
                return PackedByteArray()
            _file = FileAccess.open(source.path, FileAccess.READ)
            if _file == null:
                _failed = true
                return PackedByteArray()
        var size := SaTyped.int_at(old, "size", 0)
        _file.seek(source.region + SaTyped.int_at(old, "offset", 0))
        var bytes := _file.get_buffer(size)
        if not kept:
            close()
        return bytes if size > 0 and bytes.size() == size else PackedByteArray()

    ## Lets go of the file the blobs were copied from.
    func close() -> void:
        if _file != null:
            _file.close()
            _file = null


## What a save left at its path, or an open read there, which the
## next save to that path checks before it copies a blob.
class Record:
    extends RefCounted

    var path: String
    ## Whether an open made it, which holds the document at any place of its
    ## history, since the history an open starts is reset after the read.
    var opened := false
    ## The document that saved, the place in its history it was saved at and
    ## its layers then.
    var document := 0
    var serial := 0
    var layers: Dictionary[int, bool] = {}
    ## The file as the save left it: its size, modified time and a digest of
    ## its header, and where its blobs begin.
    var size := -1
    var modified := -1
    var digest := PackedByteArray()
    var region := 0
    ## Each blob by its key, as `offset`, `size`, `raw_size` and `transform`.
    var blobs: Dictionary[String, Dictionary] = {}

    func _init(reuse: Reuse, from_open: bool) -> void:
        path = reuse.path
        opened = from_open
        document = reuse.document
        serial = reuse.serial
        layers = reuse.layers
        for key: String in reuse.wrote:
            var slot: Dictionary = reuse.wrote[key]
            if SaTyped.int_at(slot, "size", 0) <= 0:
                continue
            var kept: Dictionary[String, Variant] = {}
            kept.assign(slot.duplicate())
            blobs[key] = kept
        var head := _head()
        region = HEAD_BYTES + head.size()
        size = _size()
        modified = FileAccess.get_modified_time(path)
        digest = _digest(head)

    ## Whether *doc* is the document that saved, still at a place of its
    ## history that holds the save and still holding a layer it saved, so a
    ## document opened since, whose layers are all new, is not.
    func holds(doc: SaDocument) -> bool:
        var history := doc.history if doc != null else null
        if doc == null or doc.get_instance_id() != document or history == null:
            return false
        if not opened and history.base_serial != serial and not history.step_serials.has(serial):
            return false
        for child in doc.get_children():
            if child is SaLayer and layers.has(child.get_instance_id()):
                return true
        return false

    ## Whether the file at the path still has the size and modified time the
    ## save left, and with *header*, the header it left too.
    func still_on_disk(header := true) -> bool:
        if size < 0 or not FileAccess.file_exists(path):
            return false
        if _size() != size or FileAccess.get_modified_time(path) != modified:
            return false
        return not header or _digest(_head()) == digest

    func _size() -> int:
        var file := FileAccess.open(path, FileAccess.READ)
        return file.get_length() if file != null else -1

    ## The header's compressed bytes as the file holds them, or none when the
    ## file is not a `.sad` of the v4 container.
    func _head() -> PackedByteArray:
        var file := FileAccess.open(path, FileAccess.READ)
        if file == null or file.get_length() < HEAD_BYTES:
            return PackedByteArray()
        if file.get_buffer(4).get_string_from_ascii() != SaSadFile.SAD_MAGIC_V4:
            return PackedByteArray()
        file.get_32()
        var packed := file.get_32()
        file.get_32()
        return file.get_buffer(packed)

    static func _digest(bytes: PackedByteArray) -> PackedByteArray:
        var context := HashingContext.new()
        context.start(HashingContext.HASH_SHA256)
        context.update(bytes)
        return context.finish()
