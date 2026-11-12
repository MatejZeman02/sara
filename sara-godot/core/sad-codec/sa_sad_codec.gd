## The codec's side of a `.sad` blob: which blobs a save asked for by a codec's
## name codes with it, the pool that codes them, and the read of one back.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Asked for by name.** File > Save as JPEG XL starts `SaSadSave` with the
## codec's name, `&"jxl"`, and the save asks `SaCodecRegistry` for it, so no
## line here names the library. Ctrl+S and the autosave to the working file
## ask for the codec the file they write over holds, `SaSadSnapshot.codec_at`,
## so a file saved as JPEG XL stays one and every other stays Zstd. The
## recovery copy is always Zstd. A save in a codec copies each blob coded in it
## that did not change, rather than coding it again.
##
## **What is coded.** A chunk's colour and height fields at full scale, the
## blobs the walk of `SaSadFile.header_of` writes as `coded`. A mask, a
## simulation's seed and the preview stay on Zstd, since JPEG XL codes a mask
## larger than Zstd does, and so does a chunk the codec refuses.
##
## **The slot names the codec.** A coded blob's slot carries [constant KEY]
## beside `offset`, `size` and `raw_size`, and a blob without it is Zstd. A file
## holding any coded blob is stamped [constant VERSION], which an older build
## refuses by name, and one holding none keeps the stamp its features ask.
##
## **The pool.** [SaSadCodec.Pool] codes on a `WorkerThreadPool` group of at
## most the processor's cores less [constant CORES_KEPT], so the window and the
## brush keep a core each, one chunk a call, taking each chunk's bytes as the
## save's worker hands them over. The worker places each blob as it finishes,
## since only one thread may append to the save's region.
class_name SaSadCodec
extends RefCounted

## The key of a coded blob's slot, holding the codec's name.
const KEY := "codec"
## Channels, and bytes a channel, of every format a codec takes, which are
## the formats the blob's kernels take too: the four a bare image binds at,
## `GlobalShaderCompiler`'s storage formats. A tip's `rg32f` is not one, and
## no `.sad` holds a tip.
const LAYOUT := {
    RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT: Vector2i(4, 4),
    RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT: Vector2i(4, 2),
    RenderingDevice.DATA_FORMAT_R32_SFLOAT: Vector2i(1, 4),
    RenderingDevice.DATA_FORMAT_R16_SFLOAT: Vector2i(1, 2),
}
## The cores the pool leaves to the window and the brush.
const CORES_KEPT := 2

## The codec of the save whose walk runs, null outside one and for a Zstd save.
## Written by [method during] alone.
static var walking: SaCodecRegistry.Codec = null


## Runs *walk*, a save's walk of the document, with *codec* asked for, and
## answers what it answered. With no codec the walk writes Zstd.
static func during(codec: SaCodecRegistry.Codec, walk: Callable) -> Variant:
    walking = codec
    var answered: Variant = walk.call()
    walking = null
    return answered


## The name of the codec the running walk codes *texture* with, or an empty
## name for Zstd. Only a blob the walk calls *coded* is, and only in a format
## whose layout [constant LAYOUT] knows.
static func asked(texture: SaTexture, coded: bool) -> StringName:
    if walking == null or not coded or texture == null or not LAYOUT.has(texture.format):
        return &""
    return walking.name


## Names the codec *codec_name* in *slot*, a blob the save's worker fills, so
## it is coded there. Nothing for an empty name or an empty slot.
static func name_in(slot: Dictionary[String, Variant], codec_name: StringName) -> Dictionary[String, Variant]:
    if not codec_name.is_empty() and not slot.is_empty():
        slot[KEY] = String(codec_name)
    return slot


## *raw*, a texture of *size* and *format* as it lies, coded by *codec*, or an
## empty array when the codec refused it or the bytes do not fill the texture.
static func encode(codec: SaCodecRegistry.Codec, raw: PackedByteArray, size: Vector2i, format: int) -> PackedByteArray:
    var layout: Vector2i = LAYOUT.get(format, Vector2i.ZERO)
    if codec == null or raw.is_empty() or raw.size() != size.x * size.y * layout.x * layout.y:
        return PackedByteArray()
    return codec.encode(raw, size.x, size.y, layout.x, layout.y)


## *raw*, *texture*'s bytes, coded by the running walk's codec, for a save
## that reads back at once, or an empty array when the codec refused it and
## the caller stores Zstd.
static func encoded(raw: PackedByteArray, texture: SaTexture) -> PackedByteArray:
    return encode(walking, raw, texture.size, texture.format)


## The texels of *packed*, a blob whose *slot* names a codec, decoded to fill
## *texture*, or none when no module registered the codec, which is said by its
## name as a chunk that will not decompress is, or the stream is not that
## picture. Nothing reaches the card that is not the picture, so no noise shows.
static func decode(slot: Dictionary[String, Variant], packed: PackedByteArray, texture: SaTexture) -> PackedByteArray:
    var codec_name := SaTyped.text_at(slot, KEY, "")
    var codec := SaCodecRegistry.shared().named(StringName(codec_name))
    if codec == null:
        push_warning("SaExport.load_sad: a chunk is coded in '%s', and no module registered that codec" % codec_name)
        return PackedByteArray()
    if texture == null:
        return PackedByteArray()
    return decoded(codec, slot, packed, texture.size, texture.format)


## *packed*, a blob *slot* addresses, decoded by *codec* to a texture of *size*
## in the format the slot names or else *format*, or none when the stream is
## not that picture. It touches no texture, so [SaSadCodec.Open]'s pool calls
## it from any thread.
static func decoded(
    codec: SaCodecRegistry.Codec, slot: Dictionary[String, Variant], packed: PackedByteArray, size: Vector2i, format: int
) -> PackedByteArray:
    var layout: Vector2i = LAYOUT.get(SaTyped.int_at(slot, "format", format), Vector2i.ZERO)
    if codec == null or layout == Vector2i.ZERO:
        return PackedByteArray()
    var raw := codec.decode(packed, size.x, size.y, layout.x, layout.y)
    return raw if raw.size() == SaTyped.int_at(slot, "raw_size", -1) else PackedByteArray()


## *header* stamped *version*, the newest a build writes, when any chunk's
## field in it is coded, and as it was otherwise, answered for the writer to
## read its version.
static func stamped(header: Dictionary[String, Variant], version: int) -> Dictionary[String, Variant]:
    for layer: Dictionary in header.get("layers", []):
        for chunk: Dictionary in layer.get("chunks", []):
            var fields: Dictionary = chunk.get("fields", {})
            for slot: Dictionary in fields.values():
                if slot.has(KEY):
                    header["version"] = maxi(SaTyped.int_at(header, "version", 0), version)
                    return header
    return header


## The threads the pool codes on: the processor's cores less
## [constant CORES_KEPT], and one at least.
static func threads() -> int:
    return maxi(1, OS.get_processor_count() - CORES_KEPT)


## The coders of one save: a `WorkerThreadPool` group of [method threads]
## threads, one element a coded slot of the save, each element waiting for its
## chunk's bytes, coding them and handing the stream back. The save's worker
## hands each chunk over with [method code] and places what is coded, in the
## order it finishes, and [method finish] waits for the rest. A save that
## fails calls [method stop], which lets every element that never got its
## chunk end with nothing.
class Pool:
    extends RefCounted

    var _codec: SaCodecRegistry.Codec
    ## How a chunk is placed: `fill(slot, bytes, region)` stores Zstd, and
    ## `put(slot, stream, raw_size, region)` stores a coded stream.
    var _fill: Callable
    var _put: Callable
    ## The chunks handed over and not yet taken, as [slot, bytes, size,
    ## format], an empty job for an element told to stop. And what is coded, as
    ## [slot, stream, bytes], waiting to be placed.
    var _jobs: Array[Array] = []
    var _coded: Array[Array] = []
    var _lock := Mutex.new()
    var _queued := Semaphore.new()
    var _finished := Semaphore.new()
    ## The group's elements, the jobs handed to them, real or empty, the chunks
    ## among them, and the chunks placed.
    var _elements := 0
    var _sent := 0
    var _handed := 0
    var _placed := 0
    var _group := -1

    ## A pool for every slot of *slots* that names a codec, coding with
    ## *codec* and placing with *fill* and *put*. No group starts when none does.
    func _init(codec: SaCodecRegistry.Codec, slots: Array[Dictionary], fill: Callable, put: Callable) -> void:
        _codec = codec
        _fill = fill
        _put = put
        for slot in slots:
            if slot.has(KEY):
                _elements += 1
        if _elements > 0:
            var told := "Sara codes %d chunks" % _elements
            _group = WorkerThreadPool.add_group_task(_code_one, _elements, SaSadCodec.threads(), true, told)

    ## Hands *bytes* of the chunk *slot* fills, a texture of *size*, to the
    ## group, and places in *region* what the group finished meanwhile.
    func code(slot: Dictionary[String, Variant], bytes: PackedByteArray, size: Vector2i, region: PackedByteArray) -> void:
        _hand([slot, bytes, size, SaTyped.int_at(slot, "format", -1)])
        _handed += 1
        place(region)

    ## Places in *region* every chunk coded and not yet placed: the stream with
    ## the codec named, or Zstd when the codec refused, with the codec's name
    ## taken off.
    func place(region: PackedByteArray) -> void:
        _lock.lock()
        var ready := _coded
        _coded = []
        _lock.unlock()
        for done in ready:
            var slot: Dictionary[String, Variant] = done[0]
            var stream: PackedByteArray = done[1]
            var bytes: PackedByteArray = done[2]
            if stream.is_empty():
                slot.erase(KEY)
                _fill.call(slot, bytes, region)
            else:
                _put.call(slot, stream, bytes.size(), region)
            _placed += 1

    ## Waits for every chunk handed over, places each in *region* as it
    ## finishes, and lets the group go.
    func finish(region: PackedByteArray) -> void:
        place(region)
        while _placed < _handed:
            _finished.wait()
            place(region)
        stop()

    ## Tells every element that has no chunk to end with nothing, and waits
    ## for the group, so nothing of the save runs on after it.
    func stop() -> void:
        while _sent < _elements:
            _hand([])
        if _group >= 0:
            WorkerThreadPool.wait_for_group_task_completion(_group)
            _group = -1

    func _hand(job: Array) -> void:
        _lock.lock()
        _jobs.append(job)
        _lock.unlock()
        _sent += 1
        _queued.post()

    ## One element of the group: waits for a chunk and codes it.
    func _code_one(_element: int) -> void:
        _queued.wait()
        _lock.lock()
        var job: Array = _jobs.pop_front()
        _lock.unlock()
        if job.is_empty():
            return
        var bytes: PackedByteArray = job[1]
        var size: Vector2i = job[2]
        var format: int = job[3]
        var stream := SaSadCodec.encode(_codec, bytes, size, format)
        _lock.lock()
        _coded.append([job[0], stream, bytes])
        _lock.unlock()
        _finished.post()


## The open of a file's chunks: each layer's chunks made, each field's
## blob read and uploaded. A blob in Zstd, or in a codec some module
## registered, is decoded by a `WorkerThreadPool` task of its own and uploaded
## as it finishes, with at most [constant WINDOW] chunks handed over and not
## yet uploaded, so a large file never holds its decoded texels beside its
## textures. A blob in a codec nobody registered is read at once on the calling
## thread, where the read says so. The textures are touched on the calling
## thread alone: a task gets bytes and a size.
##
## **A task a blob, and never a waiting group.** An open may stop between two
## layers and go on a frame later, [SaSadOpening]'s, and a group whose elements
## wait for their chunk would hold its threads asleep across those frames. A
## task is low priority, so the pool keeps threads for the window and the
## brush, as the save's [constant CORES_KEPT] does.
##
## Zstd goes to the pool too, because it is what every file but a JPEG XL one
## holds, and a deep stack's blobs read on the main thread hold the window for
## seconds.
class Open:
    extends RefCounted

    ## The chunks handed to the pool and not yet uploaded, at most.
    const WINDOW := 48

    ## The fields decoded on the pool, read by the loader's line.
    var pooled := 0

    var _blobs: PackedByteArray
    ## `read(slot, blobs, texture)` answers a blob's bytes, `put(texture, slot,
    ## raw, stored, where)` uploads them or says why not, and `scale(stored)`
    ## answers the scale a chunk stored at *stored* is made at.
    var _read: Callable
    var _put: Callable
    var _scale: Callable
    ## Codecs by name, null for a name nobody registered.
    var _codecs: Dictionary[String, SaCodecRegistry.Codec] = {}
    ## What a handed chunk is uploaded with, by its job's number: [texture,
    ## slot, stored, where], kept on this thread.
    var _waiting: Dictionary[int, Array] = {}
    ## The pool's tasks not yet waited for.
    var _tasks: Array[int] = []
    ## What is decoded, as [number, texels], waiting to be uploaded.
    var _decoded: Array[Array] = []
    var _lock := Mutex.new()
    var _finished := Semaphore.new()
    var _sent := 0

    ## An open of *blobs*, the file's region after its header.
    func _init(blobs: PackedByteArray, read: Callable, put: Callable, scale: Callable) -> void:
        _blobs = blobs
        _read = read
        _put = put
        _scale = scale

    ## Makes the chunks of *entries*, the header's for *into*, and fills each
    ## field the file holds for them.
    func layer(into: SaLayer, entries: Array) -> void:
        for raw_entry: Variant in entries:
            var entry := SaTyped.strings(raw_entry)
            var grid_pos := Vector2i(SaTyped.int_at(entry, "x", 0), SaTyped.int_at(entry, "y", 0))
            # At its stored scale, then the layer's, so the bytes fill it
            # exactly, and at 1.0 when that is below, the bytes widened to fit.
            var stored := SaTyped.float_at(entry, "resolution_scale", into.resolution_scale)
            var made_at: float = _scale.call(stored)
            into.get_or_create_chunk(grid_pos, made_at)
            var fields := SaTyped.strings(entry.get("fields"))
            for field_name: String in fields:
                # Through the layer, so a lazy field such as height is
                # allocated in the chunks the file holds it for and in no other.
                var texture := into.get_or_create_field(grid_pos, StringName(field_name))
                if texture == null:
                    push_warning("SaExport.load_sad: '%s' holds no field '%s'" % [into.name, field_name])
                    continue
                var slot := SaTyped.strings(fields[field_name])
                var where := "chunk %s field '%s'" % [grid_pos, field_name]
                var offset := SaTyped.int_at(slot, "offset", 0)
                var size := SaTyped.int_at(slot, "size", 0)
                if size <= 0 or offset < 0 or offset + size > _blobs.size():
                    push_warning("SaExport.load_sad: %s is out of range" % where)
                    continue
                if slot.has(KEY) and _codec_of(slot) == null:
                    _put.call(texture, slot, _read.call(slot, _blobs, texture), stored, where)
                    continue
                _waiting[_sent] = [texture, slot, stored, where]
                var coded := _blobs.slice(offset, offset + size) if slot.has(KEY) else PackedByteArray()
                var job := [_sent, slot, coded, texture.size, texture.format, _codec_of(slot)]
                _tasks.append(WorkerThreadPool.add_task(_decode_one.bind(job), false, "Sara decodes a chunk"))
                _sent += 1
                pooled += 1
                _upload()
                while _waiting.size() >= WINDOW:
                    _finished.wait()
                    _upload()

    ## Uploads what the pool decoded since the last call, without waiting for
    ## the rest. An open spread over frames calls it at the end of each.
    func upload() -> void:
        _upload()

    ## Uploads every chunk still decoding as it finishes, and waits for every
    ## task, so none outlives the open.
    func finish() -> void:
        _upload()
        while not _waiting.is_empty():
            _finished.wait()
            _upload()
        for task in _tasks:
            WorkerThreadPool.wait_for_task_completion(task)
        _tasks.clear()

    ## Uploads what the pool decoded since the last call.
    func _upload() -> void:
        _lock.lock()
        var ready := _decoded
        _decoded = []
        _lock.unlock()
        for done in ready:
            var held: Array = _waiting[done[0]]
            _waiting.erase(done[0])
            _put.call(held[0], held[1], done[1], held[2], held[3])

    func _codec_of(slot: Dictionary[String, Variant]) -> SaCodecRegistry.Codec:
        if not slot.has(KEY):
            return null
        var codec_name := SaTyped.text_at(slot, KEY, "")
        if not _codecs.has(codec_name):
            _codecs[codec_name] = SaCodecRegistry.shared().named(StringName(codec_name))
        return _codecs[codec_name]

    ## One task of the pool: decodes *job*, [number, slot, bytes, size,
    ## format, codec], and hands the texels back. A Zstd blob has no codec and
    ## no bytes of its own, and takes the read the calling thread would have,
    ## which touches no texture when it is handed none.
    func _decode_one(job: Array) -> void:
        var codec: SaCodecRegistry.Codec = job[5]
        var slot: Dictionary[String, Variant] = job[1]
        var bytes: PackedByteArray = job[2]
        var size: Vector2i = job[3]
        var format: int = job[4]
        var texels: PackedByteArray = (
            _read.call(slot, _blobs, null) if codec == null else SaSadCodec.decoded(codec, slot, bytes, size, format)
        )
        _lock.lock()
        _decoded.append([job[0], texels])
        _lock.unlock()
        _finished.post()
