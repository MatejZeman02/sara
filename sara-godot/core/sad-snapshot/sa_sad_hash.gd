## The 128 bit hash of a texture's texels a save keys a blob by, taken on the
## card for many textures at once and read back as four words each. What
## `SaSadSnapshot` asks before a save's walk and after an open, a class apart
## from it because how the hash is dispatched is a concern of its own.
##
## **One list for every texture.** Each texture's dispatch is recorded and the
## lot is submitted as one compute list with no barrier between them, since each
## adds only to its own four words, rather than a list of its own a texture,
## which would cost a list, its barrier and the call's own work each time, a
## visible stall on a large document.
## A save in the background sends the same list in shares a turn apart,
## [method open_shares], [method share] and [method ask_shared], since on a
## stack of thousands of chunks even the one list held its frame too long.
##
## **A descriptor set a texture, kept.** Binding one texture and the hashes
## anew would build a set for every texture on every save, and the cache
## `SaCompute` holds drops its sets whenever any texture is freed, so it would
## never hold them from one save to the next. The hashes are written into one
## buffer kept for the session and each texture's set is kept by its resource, so a save after
## the first builds a set only for a texture that is new since. A set is asked
## whether it is still valid before it is bound, because freeing a texture
## frees every set made over it, and one gone is made again. The hash itself is
## taken afresh every time, of the texels as they stand, so what any writer did
## to a texture since is always in it and nothing is trusted that the card did
## not just read.
class_name SaSadHash
extends RefCounted

## The kernel's file and the kernel a hash is.
const SHADER := "sad_snapshot_hash"
## The kernel beside it that counts, in a texture's first word, the channels a
## save's rounding would move, so all four words are zero for a texture rounded
## already. `SaLiveRounding` asks it before an export.
const UNROUNDED := "sad_snapshot_unrounded"
## The rounded copies an open's hash keeps on the card at once, each a chunk
## of one size and format, so their hashes go out together in one list.
const SCRATCH_RING := 8
## Bytes of the hash of one texture in the buffer, four words.
const WORDS_BYTES := 16

## The kernel at each format it has hashed, made at the first texture of that
## format and kept. One instance a format, since an instance pointed at another
## format frees the pipelines it had, which a list recorded before it still
## names.
static var _hashers: Dictionary[int, SaCompute] = {}
## The buffer every hash adds into, kept and grown, so a set made over it
## stays valid from one save to the next.
static var _hashes: SaCompute.Buffer = null
## The set of each texture hashed, by the texture's resource.
static var _sets: Dictionary[RID, RID] = {}
## The shader each of [member _sets] was made against, by the same key, so a
## kernel built again is never bound a set of the one before.
static var _made_against: Dictionary[RID, RID] = {}
## How many asks have zeroed [member _hashes], so an ask in shares knows
## another took the words between two of its shares.
static var _opened := 0


## The hash of each of *textures*, in their order, as 32 hex digits. Where
## *rounded* holds true at a texture's place the hash is of a copy rounded as a
## save rounds it, made in one of [constant SCRATCH_RING] textures of its size
## that the copies take in turn, so an open asks for no more memory than a few
## chunks. An empty answer when there is no device.
static func of(textures: Array[SaTexture], rounded: Array[bool], kernel := SHADER) -> PackedStringArray:
    if not _dispatch(textures, rounded, kernel):
        return PackedStringArray()
    return words_of(_hashes.read(0, textures.size() * WORDS_BYTES), textures.size())


## Whether *words*, one texture's as [method words_of] reads them, say that
## [constant UNROUNDED] found a channel the rounding moves.
static func moves(words: String) -> bool:
    return not words.is_empty() and words.lstrip("0").length() > 0


## Dispatches the hash of each of *textures* as [method of] does and asks the
## device for the words without waiting for them, *then* called with the bytes
## a frame or two later, which [method words_of] reads. A save asks in the
## frame of the key and walks once they are in, since waiting for them in that
## frame would be a wait for the card to read every chunk of the document. Anything
## but OK means nothing was asked and *then* is never called.
static func ask(textures: Array[SaTexture], then: Callable) -> Error:
    if not _dispatch(textures, []):
        return FAILED
    return _hashes.ask(then, 0, textures.size() * WORDS_BYTES)


## The hashes of *count* textures in *words*, as [method of] answers them.
static func words_of(words: PackedByteArray, count: int) -> PackedStringArray:
    var said := PackedStringArray()
    if words.size() < count * WORDS_BYTES:
        return said
    for slot in count:
        var at := slot * WORDS_BYTES
        var one := ""
        for word in 4:
            one += "%08x" % words.decode_u32(at + word * 4)
        said.append(one)
    return said


## Zeroes the words of *count* textures for an ask in shares, which
## [method share] dispatches and [method ask_shared] reads, and answers the
## ask's number, which both take, or -1 when there is no device. A save asks
## so on a deep stack, where recording every texture's dispatch in the frame
## of the key held it past a tenth of a second.
static func open_shares(count: int) -> int:
    return _opened if _open(count) else -1


## Dispatches the hashes of *textures* from *from* up to *to*, each into its
## own place, for the ask numbered *opened*. False when another ask zeroed the
## words since, and the ask has to begin again.
static func share(textures: Array[SaTexture], from: int, to: int, opened: int, kernel := SHADER) -> bool:
    return opened == _opened and _record(textures, [], from, to, kernel)


## Asks for the words of the *count* textures the ask numbered *opened* hashed,
## as [method ask] does. Anything but OK means *then* is never called.
static func ask_shared(count: int, opened: int, then: Callable) -> Error:
    if opened != _opened or _hashes == null:
        return FAILED
    return _hashes.ask(then, 0, count * WORDS_BYTES)


## Records and submits the hash of each of *textures* into [member _hashes],
## false when there is nothing to hash or no device.
static func _dispatch(textures: Array[SaTexture], rounded: Array[bool], kernel := SHADER) -> bool:
    return not textures.is_empty() and _open(textures.size()) and _record(textures, rounded, 0, textures.size(), kernel)


## Holds the buffer for *count* hashes and zeroes them, counting the ask in
## [member _opened]. False when there is no device.
static func _open(count: int) -> bool:
    if GlobalShaderCompiler.get_rd() == null:
        return false
    _opened += 1
    _hold_buffer(count)
    var zeroes := PackedByteArray()
    zeroes.resize(count * WORDS_BYTES)
    _hashes.update(zeroes)
    return true


## Records and submits *kernel*, the hash unless it names another, for each of
## *textures* from *from* up to *to*, each into its own place, rounded where
## *rounded* says.
static func _record(textures: Array[SaTexture], rounded: Array[bool], from: int, to: int, kernel := SHADER) -> bool:
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null:
        return false
    var layout := GlobalShaderCompiler.push_constant_layout(SHADER)
    var slot_at := _offset_of(layout, "slot")
    var blocks: Dictionary[Vector2i, PackedByteArray] = {}
    var scratch: Dictionary[Vector3i, Array] = {}
    var recorded: Array[SaCompute.Recorded] = []
    var made := 0
    var groups := _by_format(textures, from, to)
    for format: int in groups:
        var hasher := _hasher_for(format)
        var index := hasher.index_of_kernel(kernel)
        if slot_at < 0 or index < 0 or not hasher.pipelines.holds(index):
            continue
        var shader := hasher.pipelines.shader_id
        var pipeline := hasher.pipelines.kernels[index]
        var field := hasher.slots.slot_for("field", "image")
        var words_at := hasher.slots.slot_for("hashes", "buffer")
        for slot: int in groups[format]:
            var texture := textures[slot]
            if slot < rounded.size() and rounded[slot]:
                texture = _rounded_copy(texture, scratch, recorded)
            var held: RID = _sets.get(texture.rid, RID())
            if _made_against.get(texture.rid, RID()) != shader or not rd.uniform_set_is_valid(held):
                GlobalShaderCompiler.queue_free_uniform_set(held)
                held = _set_for(rd, texture, shader, field, words_at)
                _sets[texture.rid] = held
                _made_against[texture.rid] = shader
                made += 1
            if not held.is_valid():
                continue
            var size := texture.size
            if not blocks.has(size):
                blocks[size] = SaCompute.pack_block(layout, {"width": size.x, "height": size.y, "slot": 0})
            var bytes := blocks[size].duplicate()
            bytes.encode_s32(slot_at, slot)
            recorded.append(SaCompute.Recorded.new(pipeline, held, bytes, Vector3i(1, size.y, 1), kernel, false))
    SaCompute.uniform_sets += made
    SaCompute.submit(recorded, SHADER)
    if made > 0:
        _forget_the_freed(rd)
    return true


## The kernel at *format*, made the first time.
static func _hasher_for(format: int) -> SaCompute:
    if not _hashers.has(format):
        var made := SaCompute.new(SHADER)
        made.use_storage_format(format)
        _hashers[format] = made
    return _hashers[format]


## Keeps [member _hashes] large enough for *count* hashes, made afresh larger
## when it is not, which takes every set made over the old one with it.
static func _hold_buffer(count: int) -> void:
    if _hashes != null and _hashes.rid.is_valid() and _hashes.size >= count * WORDS_BYTES:
        return
    var room := PackedByteArray()
    room.resize(maxi(count, 1024) * 2 * WORDS_BYTES)
    for held: RID in _sets.values():
        GlobalShaderCompiler.queue_free_uniform_set(held)
    _sets.clear()
    _made_against.clear()
    _hashes = SaCompute.Buffer.new(room)


## A set binding *texture* at *field* and the hashes at *words_at*, made against
## *shader*.
static func _set_for(rd: RenderingDevice, texture: SaTexture, shader: RID, field: int, words_at: int) -> RID:
    var image := RDUniform.new()
    image.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
    image.binding = field
    image.add_id(texture.rid)
    var buffer := RDUniform.new()
    buffer.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    buffer.binding = words_at
    buffer.add_id(_hashes.rid)
    return rd.uniform_set_create([image, buffer], shader, 0)


## Lets go of the entries whose set went with its texture, so the table holds
## no more than the textures alive.
static func _forget_the_freed(rd: RenderingDevice) -> void:
    for rid: RID in _sets.keys():
        if not rd.uniform_set_is_valid(_sets[rid]):
            _sets.erase(rid)
            _made_against.erase(rid)


## The byte *name* starts at in the params block *layout* declares, or -1.
static func _offset_of(layout: Array, name: String) -> int:
    for entry: Dictionary in layout:
        if str(entry.get("name", "")) == name:
            var at: int = entry["offset"]
            return at
    return -1


## The places of *textures* from *from* up to *to* by format, each format's in their order, so the
## kernel's format changes once a format and not at every other chunk.
static func _by_format(textures: Array[SaTexture], from: int, to: int) -> Dictionary[int, PackedInt32Array]:
    var groups: Dictionary[int, PackedInt32Array] = {}
    for slot in range(from, mini(to, textures.size())):
        var format := textures[slot].format
        if not groups.has(format):
            groups[format] = PackedInt32Array()
        groups[format].append(slot)
    return groups


## *texture* copied into the next of the textures of its size and format in
## *scratch*, made as the ring first reaches each, and rounded there. Each
## time the ring comes round to its first texture again, what *recorded* holds
## is submitted first and emptied, so a copy never lands under a hash that has
## not run.
static func _rounded_copy(
    texture: SaTexture, scratch: Dictionary[Vector3i, Array], recorded: Array[SaCompute.Recorded]
) -> SaTexture:
    var shape := Vector3i(texture.size.x, texture.size.y, texture.format)
    if not scratch.has(shape):
        scratch[shape] = [0]
    var ring: Array = scratch[shape]
    var turn: int = ring[0]
    ring[0] = turn + 1
    var at := turn % SCRATCH_RING + 1
    if at >= ring.size():
        ring.append(SaTexture.new(texture.size, texture.format))
    elif turn % SCRATCH_RING == 0 and not recorded.is_empty():
        SaCompute.submit(recorded, SHADER)
        recorded.clear()
    var copy: SaTexture = ring[at]
    var size := Vector3(texture.size.x, texture.size.y, 1)
    texture.rd.texture_copy(texture.rid, copy.rid, Vector3.ZERO, Vector3.ZERO, size, 0, 0, 0, 0)
    SaSadSnapshot.round_in_place(copy)
    return copy
