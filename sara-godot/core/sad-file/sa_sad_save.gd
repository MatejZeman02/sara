## A save that runs while the painter goes on painting: the snapshot in one
## frame, the readback a few textures a frame, and Zstd and the file on a
## worker thread, so the window never lags while a file is written.
##
## The snapshot: [method start] walks the document as a save at once does,
## through `SaSadFile.header_of`, with [member taking] set, so every texture the
## walk would read back is copied on the card instead, a `texture_copy` into a
## texture of its own, and its slot in the header is left for the worker. What
## the painter changes after the copies is not in this file.
##
## A painter's save (a Ctrl+S, or an autosave, which writes no preview) asks for
## the hashes of `SaSadSnapshot` and walks once their words are in, because
## hashing every chunk of a deep document in the frame of the key was most of that
## frame. The walk starts only when the document stands where it stood at the
## ask: the history where it was, nothing raised its mark, no stroke open. The
## hashes go out in shares (`SaSadHashShares`) and the walk (`SaSadWalk`) writes a
## share of the layers a turn, asking before each share whether the document still
## stands and dropping the walk when it does not. After [constant HASH_ASKS] asks
## the walk hashes and waits in its own frame as a save at once does. Any other
## save walks at its start, which a caller that changes the document at once and
## wants the file without the change counts on. The preview,
## `SaExport.PreviewShot`, is taken on the card at the key.
##
## The readback: each turn asks the device for [constant READS_A_FRAME] copies, at
## most [constant READS_OWED] owed at once, through `texture_get_data_async`, and
## for a copy that may be stored as planes, the forward kernel into a buffer of a
## small pool and `buffer_get_data_async` of that too, since which form is smaller
## is known only once both are compressed. No copy is asked for before the sweep
## of `SaSadSnapshot` says which chunks hold nothing. The answers are methods of
## this object with an index bound, never a lambda (the pitfall "Quitting with a
## read of the card still owed aborts the engine's teardown"), and an answer sends
## the device nothing: the copy it frees waits in [member _spent] for the next
## turn (the pitfall "A texture updated from inside the device's answer to an
## asynchronous read never reaches the screen").
##
## The worker: one `WorkerThreadPool` task a save takes the bytes as they arrive,
## compresses each into the region, and once the last is in writes the file
## through the side file and the rename, so a save that fails leaves the old file
## whole. A save asked for while another runs waits in [member _saves] and takes
## its snapshot when its turn comes. [method after_all] runs a callable once every
## save has ended, which is how quitting, File > New and File > Open wait for one.
## Off the main device a save is written at once by `SaSadFile.save_file`.
class_name SaSadSave
extends RefCounted

## Copies asked for in one turn of the loop. A copy is a chunk's field, a
## megabyte for a 32-bit colour, so a turn moves sixteen at most.
const READS_A_FRAME := 16
## Copies owed at once. An answer comes two or three frames after its ask.
const READS_OWED := 48
## A turn longer than this, in microseconds, is told in the journal.
const TURN_TOLD_USEC := 10000
## The asks for the hashes a document that will not stand still is given
## before the walk hashes in its own frame.
const HASH_ASKS := 3

## The save whose snapshot is being taken, which `SaSadBlob.write` hands each
## texture to. Set and cleared inside [method _snapshot] and around a share
## of [method _walk_on] alone.
static var taking: SaSadSave = null
## Every save asked for and not ended, in order. The first runs, the rest wait.
## One queue for every document, because quitting, File > New and File > Open
## wait for every save, and each save holds its own document, path and blobs.
static var _saves: Array[SaSadSave] = []
## What waits for every save to end, run in the order given.
static var _after: Array[Callable] = []

## The document, the file and the older copies kept, as `save_file` takes them.
var document: SaDocument
var path: String
var keep_versions: int
var preview: Image
## Whether the file becomes the document's own, false for a recovery copy.
var claims: bool
## Whether the save rounds full precision colour, `SaSadSnapshot`, true for a
## save the painter asked for and both autosaves, false for the harness's copy.
var rounds: bool
## The codec the save codes chunks' fields with, `SaSadCodec`, null for Zstd:
## the one asked for by name, or for a save that claims its file and asked for
## none, the one that file holds, `SaSadSnapshot.codec_at`, read as the save
## begins. A recovery copy and the harness's copy claim nothing and stay Zstd.
var codec: SaCodecRegistry.Codec
## What the walk reused and wrote, `SaSadSnapshot.Reuse`, the save's report of
## the blobs it compressed and copied, and the textures its snapshot copied.
var reuse: SaSadSnapshot.Reuse = null
var taken := 0
## Called with the save's error once it has ended, on the main thread.
var done: Callable
## What the save came to, OK until something failed.
var error: Error = OK
## When the save was asked for, for its end line.
var asked_usec: int = 0

## The header, handed to the worker once the snapshot is whole.
var _header: Dictionary[String, Variant] = {}
## The region the blobs are written to, the preview's picture first.
var _region := PackedByteArray()
## The older copies to keep, read from the settings on the main thread.
var _versions := 0
## Each copy on the card, null once read, whether it is read as planes too for
## the worker to keep the smaller form, and the header's slot its blob fills.
var _copies: Array[SaTexture] = []
var _compares: Array[bool] = []
var _slots: Array[Dictionary] = []
## Each copy's size, for a codec, which takes the bytes with their shape.
var _shapes: Array[Vector2i] = []
## Each blob copied from the file the save replaces, as [slot, old entry].
var _reused: Array = []
## The answers each copy still waits on, one or two.
var _awaited: Array[int] = []
## The next copy to ask for, and the answers owed.
var _next := 0
var _owed := 0
## Copies whose every answer is in, of [member _slots].
var _answered := 0
## Plane buffers by the copy they wait on, and the ones free again.
var _buffers_owed: Dictionary[int, SaCompute.Buffer] = {}
var _buffers_free: Array[SaCompute.Buffer] = []
## Copies read in an answer, let go at the next turn rather than inside it.
var _spent: Array[SaTexture] = []
## The worker's task, and what it wrote.
var _task := -1
var _written: Error = OK
## Puts the worker's side file in place and says what failed on the way.
var _landing := Landing.new()
## Bytes handed to the worker, as [index, bytes, whether planes], -1 to stop.
var _inbox: Array = []
var _lock := Mutex.new()
var _arrived := Semaphore.new()
## Where the document stood at the snapshot, to be marked saved if it still is.
var _position := 0
var _base := 0
var _raises := 0
var _path_before := ""
## The share last shown on the progress line, so it is sent once a step.
var _shown := -1
## The frames drawn at the last turn, so a turn that saw none draws one.
var _drawn_seen := -1
## The preview taken at the key, its cells as `SaExport.PreviewShot` cut it,
## the next to ask for, each scratch owed by the cell it holds, each cell's
## bytes once in, and how many are. The worker reads the shape and the bytes,
## the bytes under the lock, and waits on the semaphore for the last of them.
var shot: SaExport.PreviewShot = null
var _shot_size := Vector2i.ZERO
var _shot_cells: Array[Rect2i] = []
var _shot_format := 0
var _shot_next := 0
var _shot_owed: Dictionary[int, SaTexture] = {}
var _shot_bytes: Array[PackedByteArray] = []
var _shot_in := 0
var _shot_failed := false
var _shot_ready := Semaphore.new()
## The textures whose hashes were asked for, the ask in shares, how many asks
## there were, whether the walk has run, and the walk in shares while it runs.
var _hashed: Array[SaTexture] = []
var _shares: SaSadSnapshot.HashShares = null
var _asks := 0
var _snapped := false
var _walk: SaSadWalk = null
## Whether the walk waits for hashes asked for at the start, which a save
## handed a preview taken on the card does, and so does an autosave.
var _later := false


func _init(
    _document: SaDocument,
    _path: String,
    _keep_versions: int,
    _preview: Object,
    _claims: bool,
    _done: Callable,
    _rounds: bool,
    _codec: StringName,
    _waits: bool,
) -> void:
    var taken_on_card := _preview as SaExport.PreviewShot
    _later = taken_on_card != null or _waits
    if taken_on_card != null and taken_on_card.picture != null:
        shot = taken_on_card
        _shot_size = taken_on_card.size
        _shot_cells = taken_on_card.cells
        _shot_format = taken_on_card.picture.format
        _shot_bytes.resize(_shot_cells.size())
    document = _document
    rounds = _rounds
    codec = SaCodecRegistry.shared().named(_codec)
    path = _path
    keep_versions = _keep_versions
    preview = _preview as Image
    claims = _claims
    done = _done
    asked_usec = Time.get_ticks_usec()


## Saves *doc* to *to* in the background, after any save already running,
## and answers the save. *then* is called with its error once it has ended.
## With *owns*, the file becomes the document's own at the end when
## nothing changed after the snapshot, and otherwise only its path does.
## With *rounded*, the painter asked for it and its colour is rounded.
## *image* is the preview as an `Image`, or an `SaExport.PreviewShot` taken
## on the card and read over the frames of the save, whose walk then waits for
## its hashes, as the class's page says. *by* names the codec of a save the
## painter asked for in one by name, `SaSadCodec`, and is empty for Zstd.
## With *waits*, the autosave's, the walk waits for its hashes all the same.
static func start(
    doc: SaDocument,
    to: String,
    kept := -1,
    image: Object = null,
    owns := true,
    then := Callable(),
    rounded := false,
    by := &"",
    waits := false,
) -> SaSadSave:
    var save := SaSadSave.new(doc, to, kept, image, owns, then, rounded, by, waits)
    _saves.append(save)
    _hear_the_loop(true)
    if _saves.size() == 1:
        save._begin()
    else:
        SaTrail.note("a save of %s waits for the one before it" % to.get_file())
        EventBus.save_progressed.emit(TranslationServer.translate("Saving %s after the save before it") % to.get_file())
    return save


## Whether a save is running or waiting.
static func is_running() -> bool:
    return not _saves.is_empty()


## Runs *then* once every save has ended, at once when none runs. *why* is
## what waits, "quitting" or "opening a file", and the progress line says so.
static func after_all(then: Callable, why: String) -> void:
    if _saves.is_empty():
        then.call()
        return
    var last: SaSadSave = _saves.back()
    SaTrail.stage("%s waits for the save of %s to end" % [why, last.path.get_file()])
    EventBus.save_progressed.emit(TranslationServer.translate("Saving, %s once the file is written") % why)
    _after.append(then)


## Takes *texture* into the snapshot and answers its slot, filled by the worker
## once the bytes are in. Called by `SaSadBlob.write` while [member taking] is
## this save. With *old*, the entry of the file the save replaces that holds
## the texture as it is, nothing is copied on the card and the worker copies
## the blob from that file.
func take(texture: SaTexture, planes: bool, old: Dictionary[String, Variant] = {}) -> Dictionary[String, Variant]:
    var slot: Dictionary[String, Variant] = {}
    if not old.is_empty():
        slot["size"] = 0
        _reused.append([slot, old])
        return slot
    var copy := SaSadSnapshot.spare(texture)
    if not copy.rid.is_valid():
        error = ERR_OUT_OF_MEMORY
        return slot
    texture.rd.texture_copy(
        texture.rid, copy.rid, Vector3.ZERO, Vector3.ZERO, Vector3(texture.size.x, texture.size.y, 1), 0, 0, 0, 0
    )
    SaSadSnapshot.take(texture, copy, slot)
    # A slot is filled by the worker, and an empty one tells the walk the
    # texture gave nothing back, so it holds the size to come until then.
    slot["size"] = 0
    _copies.append(copy)
    taken += 1
    _compares.append(planes)
    _awaited.append(2 if planes else 1)
    _slots.append(slot)
    _shapes.append(texture.size)
    return slot


## Writes the document at once off the main device, and otherwise asks for
## the hashes the walk waits for, or walks now when there are none to ask for.
func _begin() -> void:
    if codec == null and claims:
        codec = SaCodecRegistry.shared().named(SaSadSnapshot.codec_at(path))
    var rd := GlobalShaderCompiler.get_rd()
    if document == null or rd == null or rd != RenderingServer.get_rendering_device():
        if preview == null and shot != null:
            preview = shot.read_now()
        _drop_shot()
        _note_where_it_stood()
        SaSadSnapshot.begin(document, rounds, path)
        _written = SaSadCodec.during(codec, SaSadFile.save_file.bind(document, path, keep_versions, preview))
        reuse = SaSadSnapshot.end()
        _end()
        return
    if not _later or not _ask_hashes():
        _take(rd, {})
    _say_how_far()


## Asks the card for the hashes of the document's textures, noting where the
## document stands, false when nothing was asked.
func _ask_hashes() -> bool:
    var began := Time.get_ticks_usec()
    _note_where_it_stood()
    _hashed = SaSadSnapshot.hashed(document)
    _asks += 1
    _shares = SaSadSnapshot.HashShares.new(_hashed)
    if not _shares.is_open():
        return false
    var parts := [path.get_file(), _hashed.size(), _ms(Time.get_ticks_usec() - began), SaSadSnapshot.HashShares.a_turn]
    SaTrail.mark("the save of %s listed the hashes of %d textures in %d ms, to send %d a turn" % parts)
    return true


## Takes the save's next step before its snapshot is whole, one a turn: a
## share of the hashes sent, the words read once in, the walk begun or a share
## of it. The walk begins only when the document still stands where it did at
## the ask, and otherwise the save asks again. Answers whether it goes on.
func _settle(rd: RenderingDevice) -> bool:
    if _walk != null:
        return _walk_on(rd)
    if not _shares.all_sent():
        return _shares.send() or _again(rd)
    if not is_instance_valid(document):
        _fail(ERR_UNAVAILABLE)
        _end()
        return false
    if not _shares.read():
        return true
    if not _stands() or _shares.said.is_empty():
        return _again(rd)
    _note_where_it_stood()
    _versions = keep_versions if keep_versions >= 0 else SaSettings.sad_versions
    taking = self
    SaSadSnapshot.begin(document, rounds, path, self, _shares.said)
    _walk = SaSadWalk.new(document, path, _region, rd, codec)
    taking = null
    return true


## Asks for the hashes again, or past [constant HASH_ASKS] walks hashing in
## this frame. Answers whether the save goes on.
func _again(rd: RenderingDevice) -> bool:
    if _asks < HASH_ASKS and _ask_hashes():
        return true
    return _take(rd, {})


## Walks the next share of the layers, every layer left with *whole*, while
## the document stands where it stood as the walk began, and starts the worker
## once the walk is done. Drops the walk and asks again when it does not.
func _walk_on(rd: RenderingDevice, whole := false) -> bool:
    if not is_instance_valid(document) or not _stands():
        _walk = null
        SaSadSnapshot.drop()
        _region = PackedByteArray()
        for each: Array in [_copies, _compares, _slots, _shapes, _reused, _awaited]:
            each.clear()
        taken = 0
        return _again(rd)
    taking = self
    var walked := _walk.go_on(-1 if whole else SaSadWalk.usec_a_turn)
    taking = null
    if error == OK and not walked:
        return true
    var walk := _walk
    _walk = null
    reuse = SaSadSnapshot.end()
    if error != OK:
        _end()
        return false
    _header = walk.header
    _snapped = true
    _hashed.clear()
    _start_worker(walk.began_usec, walk.turns)
    return true


## Ends the running save's walk in shares in this frame, so a save at once,
## which walks with the same names in `SaSadSnapshot`, never meets one half
## done. `SaExport.save_sad` calls it first.
static func walk_out() -> void:
    if not _saves.is_empty() and _saves[0]._walk != null:
        _saves[0]._walk_on(GlobalShaderCompiler.get_rd(), true)


## Whether the document stands where [method _note_where_it_stood] found it,
## the test `SaSadClearChunks` makes before it lets a chunk go.
func _stands() -> bool:
    return SaSadSnapshot.stands(document, _position, _base, _raises)


## Takes the snapshot with the hashes *said*, hashing now when it is empty,
## and starts the worker. Answers whether the save goes on.
func _take(rd: RenderingDevice, said: Dictionary[RID, String]) -> bool:
    var began := Time.get_ticks_usec()
    _snapped = true
    _hashed.clear()
    _snapshot(rd, said)
    if error != OK:
        _end()
        return false
    _start_worker(began, 1)
    return true


## Hands the snapshot taken since *began*, over *turns* turns, to the worker.
func _start_worker(began: int, turns: int) -> void:
    _task = WorkerThreadPool.add_task(_work, false, "Sara writes %s" % path.get_file())
    var parts := [path.get_file(), _copies.size(), _reused.size(), _ms(Time.get_ticks_usec() - began), turns]
    SaTrail.note("the save of %s took its snapshot of %d textures, copying %d blobs, in %d ms over %d turns" % parts)


## The header and a copy on the card of every texture, in this frame, with
## the hashes *said* or, when it is empty, hashing here.
func _snapshot(rd: RenderingDevice, said: Dictionary[RID, String] = {}) -> void:
    var began := Time.get_ticks_usec()
    _note_where_it_stood()
    _versions = keep_versions if keep_versions >= 0 else SaSettings.sad_versions
    taking = self
    SaSadSnapshot.begin(document, rounds, path, self, said)
    var begun := Time.get_ticks_usec()
    # The preview is shrunk and encoded on the worker, the first blob there.
    var walk := SaSadFile.header_of.bind(document, _region, rd)
    _header = SaSadCodec.during(codec, SaLinkedFile.beside.bind(document, path, walk, _region))
    var walked := Time.get_ticks_usec()
    reuse = SaSadSnapshot.end()
    taking = null
    var parts := [_ms(begun - began), "the hashes in" if not said.is_empty() else "hashing", _ms(walked - begun)]
    parts.append(_ms(Time.get_ticks_usec() - walked))
    SaTrail.mark("the snapshot's parts: %d ms naming, %s, %d ms walking and copying, %d ms ending" % parts)


## Where the document stood at the snapshot.
func _note_where_it_stood() -> void:
    if document == null:
        return
    var history := document.history
    _position = history.position() if history != null else 0
    _base = history.base_serial if history != null else 0
    _raises = document.raises
    _path_before = document.file_path


## One turn of the main loop for the running save: lets go of the copies read
## last turn, asks for more, draws a frame while answers are owed, and ends the
## save once the worker is done.
func _turn() -> void:
    var began := Time.get_ticks_usec()
    _spent.clear()
    var freed := Time.get_ticks_usec()
    var this_turn := _ask_shot()
    if SaSadSnapshot.turned(self) and not _snapped and not _settle(GlobalShaderCompiler.get_rd()):
        return
    while _snapped and error == OK and _next < _copies.size() and _owed < READS_OWED and _next - _answered < READS_OWED:
        if this_turn >= READS_A_FRAME or not _ask(_next):
            break
        _next += 1
        this_turn += 1
    var asked := Time.get_ticks_usec()
    var drawn := Engine.get_frames_drawn()
    var waits := _owed + SaSadSnapshot.owed(self) + (0 if _snapped else 1)
    if waits > 0 and drawn == _drawn_seen and RenderingServer.get_rendering_device() != null:
        # The device hands an answer over only as frames are drawn, and the
        # window in low processor mode draws one only when something on screen
        # changed (the pitfall "A read asked of the main device answers only as
        # a frame is drawn, and an idle window draws none"). Never a present.
        RenderingServer.force_draw(false, 0.0)
    var forced := Time.get_ticks_usec()
    _drawn_seen = drawn
    _say_how_far()
    if SaTrail.journal and forced - began > TURN_TOLD_USEC:
        var parts := [_ms(forced - began), _ms(freed - began), _ms(asked - freed), _next, _ms(forced - asked)]
        SaTrail.mark("the save's turn took %d ms: %d ms freeing, %d ms asking up to read %d, %d ms drawing" % parts)
    if _owed == 0 and _task >= 0 and WorkerThreadPool.is_task_completed(_task):
        _end()


## Asks for the preview's next cells, ahead of every copy and before the walk,
## a frame's share at most, and answers how many it asked for. Lets go of the
## copy of the output once every cell has a scratch of its own.
func _ask_shot() -> int:
    var asked := 0
    while shot != null and error == OK and _shot_next < _shot_cells.size() and asked < READS_A_FRAME and _owed < READS_OWED:
        var scratch := shot.cell(_shot_next)
        if scratch == null or not SaExport.ask_texture_bytes(scratch, _shot_back.bind(_shot_next)):
            _fail(ERR_CANT_ACQUIRE_RESOURCE)
            break
        _shot_owed[_shot_next] = scratch
        _shot_next += 1
        _owed += 1
        asked += 1
    if shot != null and _shot_next >= _shot_cells.size():
        shot.let_go()
        shot = null
    return asked


## The device's answer for preview cell *index*. Hands the bytes to the
## worker, and the last of them wakes it.
func _shot_back(bytes: PackedByteArray, index: int) -> void:
    _owed -= 1
    var scratch: SaTexture = _shot_owed.get(index)
    _shot_owed.erase(index)
    if scratch != null:
        _spent.append(scratch)
    if bytes.is_empty():
        _fail(ERR_FILE_CANT_READ)
        return
    _lock.lock()
    _shot_bytes[index] = bytes
    _shot_in += 1
    var whole := _shot_in == _shot_cells.size()
    _lock.unlock()
    if whole:
        _shot_ready.post()


## Lets go of the preview on the card, which a save off the main device has
## read already.
func _drop_shot() -> void:
    if shot != null:
        shot.let_go()
    shot = null
    _shot_cells = []
    _shot_bytes.clear()


## The preview, once every cell is in, on the worker. False when the save
## failed while the worker waited.
func _preview_in() -> bool:
    if _shot_cells.is_empty():
        return true
    _shot_ready.wait()
    _lock.lock()
    var failed := _shot_failed
    _lock.unlock()
    if failed:
        return false
    preview = SaExport.PreviewShot.image_of(_shot_size, _shot_cells, _shot_format, _shot_bytes)
    return true


## Microseconds as whole milliseconds.
static func _ms(usec: int) -> int:
    return roundi(usec / 1000.0)


## Asks for copy *index*, its planes too when it compares, false when refused or
## before the sweep's words are in. A chunk holding nothing hands the worker none.
func _ask(index: int) -> bool:
    if not SaSadSnapshot.flags_in(self):
        return false
    if SaSadSnapshot.leaves_out_copy(index):
        _awaited[index] = 1
        _owed += 1
        _heard(index, PackedByteArray(), false)
        return true
    var copy := _copies[index]
    var rd := copy.rd
    if _compares[index]:
        var buffer := _buffer_of(SaSadBlob.plane_bytes(copy))
        SaSadBlob.planes_into(copy, buffer)
        _buffers_owed[index] = buffer
        var planes_asked := rd.buffer_get_data_async(buffer.rid, _planes_back.bind(index))
        if planes_asked != OK:
            _buffers_owed.erase(index)
            _fail(planes_asked)
            return false
        _owed += 1
    var asked := rd.texture_get_data_async(copy.rid, 0, _texels_back.bind(index))
    if asked != OK:
        _fail(asked)
        return false
    _owed += 1
    return true


## A free plane buffer of *bytes*, or a new one.
func _buffer_of(bytes: int) -> SaCompute.Buffer:
    for i in _buffers_free.size():
        if _buffers_free[i].size == bytes:
            var buffer := _buffers_free[i]
            _buffers_free.remove_at(i)
            return buffer
    return SaSadBlob.planes_buffer(bytes)


## The device's answer for copy *index* read as planes.
func _planes_back(bytes: PackedByteArray, index: int) -> void:
    var buffer: SaCompute.Buffer = _buffers_owed.get(index)
    _buffers_owed.erase(index)
    if buffer != null:
        _buffers_free.append(buffer)
    _heard(index, bytes, true)


## The device's answer for copy *index* read as it lies.
func _texels_back(bytes: PackedByteArray, index: int) -> void:
    _heard(index, bytes, false)


## Hands *bytes* of copy *index*, its planes or its texels, to the worker, and
## lets the copy go once every answer for it is in.
func _heard(index: int, bytes: PackedByteArray, planes: bool) -> void:
    _owed -= 1
    _awaited[index] -= 1
    if _awaited[index] == 0 and _copies[index] != null:
        _spent.append(_copies[index])
        _copies[index] = null
    if error != OK:
        return
    if bytes.is_empty() and not SaSadSnapshot.leaves_out_copy(index):
        _fail(ERR_FILE_CANT_READ)
        return
    if _awaited[index] == 0:
        _answered += 1
    _lock.lock()
    _inbox.append([index, bytes, planes])
    _lock.unlock()
    _arrived.post()


## Stops the save with *why*. The worker hears it and writes nothing.
func _fail(why: Error) -> void:
    if error == OK:
        error = why
    _lock.lock()
    _inbox.append([-1, PackedByteArray(), false])
    _shot_failed = true
    _lock.unlock()
    _arrived.post()
    _shot_ready.post()


## The worker: compresses each blob once every form of it has arrived, and
## once the last is in writes the file. Reads nothing the main thread writes but the inbox, which
## it reads under the lock, and the header and the slots, which the main
## thread leaves alone once the snapshot is whole.
func _work() -> void:
    if not _preview_in():
        _written = FAILED
        return
    SaSadFile.preview_into(_header, _region, preview)
    for pair: Array in _reused:
        var slot: Dictionary[String, Variant] = pair[0]
        var old: Dictionary[String, Variant] = pair[1]
        var packed := reuse.read(old)
        if packed.is_empty():
            _written = ERR_FILE_CANT_READ
            return
        SaSadBlob.copy_into(slot, old, packed, _region)
    if reuse != null:
        reuse.close()
    var pool := SaSadCodec.Pool.new(codec, _slots, SaSadBlob.fill, SaSadBlob.place)
    var compressed := 0
    # A copy that compares, by its index, as [planes, texels] until both are in.
    var halves: Dictionary[int, Array] = {}
    while compressed < _slots.size():
        _arrived.wait()
        _lock.lock()
        var item: Array = _inbox.pop_front()
        _lock.unlock()
        var index: int = item[0]
        if index < 0:
            pool.stop()
            _written = FAILED
            return
        var bytes: PackedByteArray = item[1]
        if _slots[index].has(SaSadCodec.KEY):
            pool.code(_slots[index], bytes, _shapes[index], _region)
            compressed += 1
            continue
        if not _compares[index] or bytes.is_empty():
            SaSadBlob.fill(_slots[index], bytes, _region)
            compressed += 1
            continue
        var pair: Array = halves.get(index, [PackedByteArray(), PackedByteArray()])
        pair[0 if item[2] else 1] = bytes
        var planes: PackedByteArray = pair[0]
        var plain: PackedByteArray = pair[1]
        if planes.is_empty() or plain.is_empty():
            halves[index] = pair
            continue
        halves.erase(index)
        SaSadBlob.fill_smaller(_slots[index], planes, plain, _region)
        compressed += 1
    pool.finish(_region)
    _written = write_out(path, SaSadSnapshot.leave_out(_header), _region, _versions, _landing)


## Ends the running save: says how it went, marks the document, calls who
## asked, and starts the next save or what waited for them all.
func _end() -> void:
    if _task >= 0:
        WorkerThreadPool.wait_for_task_completion(_task)
        _task = -1
    if error == OK:
        error = _written
    if reuse != null:
        reuse.close()
    SaSadSnapshot.remember(reuse, error == OK)
    preview = null
    _drop_shot()
    _shot_owed.clear()
    _hashed.clear()
    _copies.clear()
    _spent.clear()
    _buffers_free.clear()
    _buffers_owed.clear()
    _header = {}
    _region = PackedByteArray()
    var took := roundi((Time.get_ticks_usec() - asked_usec) / 1000.0)
    if error == OK:
        _mark()
        var blobs := [reuse.encoded, reuse.copied] if reuse != null else [0, 0]
        SaTrail.stage("SaSadSave: wrote %s in %d ms, %d blobs compressed and %d copied" % ([path, took] + blobs))
        if _landing.copied:
            SaTrail.stage("SaSadSave: %s was copied into place, the move failed (%s)" % [path, error_string(_landing.move_error)])
        EventBus.save_progressed.emit(TranslationServer.translate("Saved %s") % path.get_file())
    else:
        SaTrail.stage("SaSadSave: the save of %s failed (%s) after %d ms" % [path, error_string(error), took])
        EventBus.save_progressed.emit("")
        var why := " ".join([_landing.why(), SaSadFile.why_not_saved(path, _landing.side).strip_edges()]).strip_edges()
        why = " " + why if not why.is_empty() else why
        SaProblems.report(
            "SaSadSave", TranslationServer.translate("Could not save '%s' (%s).") % [path, error_string(error)] + why
        )
    _saves.erase(self)
    if done.is_valid():
        done.call(error)
    if not _saves.is_empty():
        _saves[0]._begin()
        return
    _hear_the_loop(false)
    var waiting := _after.duplicate()
    _after.clear()
    for then: Callable in waiting:
        if then.is_valid():
            then.call()


## Marks the document saved when nothing changed after the snapshot. When
## something did, only a Save As's new path is kept, and the document stays
## unsaved. A document opened or made new meanwhile has a history reset since,
## and is left alone.
func _mark() -> void:
    var history := document.history if is_instance_valid(document) else null
    if not claims or history == null:
        return
    if history.base_serial != _base or document.file_path != _path_before:
        return
    # The position says an undo or a redo, which may clear the mark rather
    # than raise it, and the raises every other change.
    var still := history.position() == _position and document.raises == _raises
    if still:
        document.mark_saved(path)
    else:
        document.file_path = path


## Sends the share of the running save's textures read so far, once a tenth.
func _say_how_far() -> void:
    var count := maxi(_copies.size(), 1)
    var tenth := floori(10.0 * _answered / count)
    if tenth == _shown:
        return
    _shown = tenth
    var said := TranslationServer.translate_plural("Saving %s, %d%%", "Saving %s, %d%%", tenth * 10)
    EventBus.save_progressed.emit(String(said) % [path.get_file(), tenth * 10])


## Turns the loop until every save has ended or *longest_msec* went by, and
## answers whether they all ended. For a suite, which cannot await a frame,
## and for a caller that has to have the file before it goes on.
static func finish_all(longest_msec := 60000) -> bool:
    var until := Time.get_ticks_msec() + longest_msec
    while not _saves.is_empty() and Time.get_ticks_msec() < until:
        turn()
        OS.delay_usec(500)
    return _saves.is_empty()


## One turn of the loop for the save that runs. The loop calls it, and so does
## a suite, which cannot await a frame.
static func turn() -> void:
    if _saves.is_empty():
        _hear_the_loop(false)
        return
    _saves[0]._turn()


static func _hear_the_loop(hear: bool) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    var each := turn
    if hear and not tree.process_frame.is_connected(each):
        tree.process_frame.connect(each)
    elif not hear and tree.process_frame.is_connected(each):
        tree.process_frame.disconnect(each)


## Writes *header* and the blob region *blobs* to *target* in the v4 container,
## through the side file *landing* names, and *landing* puts it in place keeping *versions*
## older copies, a fresh [SaSadSave.Landing] on the file system when null.
## When the side file cannot be put in place it stays, a target moved aside
## comes back, and *landing* says which step failed and why.
##
## Safe on a worker thread, which is where [method _work] calls it: it touches no
## device, no node and no setting, only the file system, and the header is
## read only by it once handed over.
static func write_out(
    target: String, header: Dictionary[String, Variant], blobs: PackedByteArray, versions: int, landing: Landing = null
) -> Error:
    var version := SaTyped.int_at(SaSadCodec.stamped(header, SaSadFile.SAD_VERSION_CODED), "version", SaSadFile.SAD_VERSION)
    var header_raw := JSON.stringify(header).to_utf8_buffer()
    var header_packed := header_raw.compress(SaSadFile.SAD_BLOB_COMPRESS)

    landing = landing if landing != null else Landing.new()
    var temp_path := landing.side_of(target)
    var file := FileAccess.open(temp_path, FileAccess.WRITE)
    if file == null:
        var open_err := FileAccess.get_open_error()
        push_error("SaExport.save_sad: cannot open '%s' for writing (err %d)" % [temp_path, open_err])
        return open_err

    file.store_buffer(SaSadFile.SAD_MAGIC_V4.to_ascii_buffer())
    file.store_32(version)
    file.store_32(header_packed.size())
    file.store_32(header_raw.size())
    file.store_buffer(header_packed)
    file.store_buffer(blobs)
    var write_err := file.get_error()
    file.close()
    if write_err != OK:
        push_error("SaExport.save_sad: writing '%s' failed (err %d)" % [temp_path, write_err])
        DirAccess.remove_absolute(temp_path)
        return write_err
    return landing.land(temp_path, target, versions)


## Puts a side file written in full in place of its target, and says which
## step failed and the engine's error. The keep moves the
## target to `.sad1`, the move renames the side file onto it, and a failed move
## is followed by a copy, the side file going only once the copy reads back
## the same, so when both fail it stays beside the document, whole.
##
## A content address, what Android's picker hands for a file in a shared
## folder, names no folder a side file can go into and takes no rename. Its
## side file is written in Sara's own storage instead and poured into the
## address in one write, with no numbered copies kept. A pour that fails leaves
## the side file whole where [member side] says, and the address as far as
## the pour got, which Android truncates when it opens it for the write.
class Landing:
    ## The scheme of an address Android's picker hands, which no rename reaches.
    const CONTENT := "content://"
    ## Where the side file of a content address is written, under Sara's data.
    const POURED := "saving"
    ## The step that failed, `keep`, `move` or `copy`, and each one's error. A
    ## failed keep alone does not fail the save.
    var step: StringName = &""
    var keep_error: Error = OK
    var move_error: Error = OK
    var copy_error: Error = OK
    ## The error of the pour onto a content address.
    var pour_error: Error = OK
    ## Whether the side file was gone when the move failed, and whether the copy took.
    var side_gone := false
    var copied := false
    var side := ""
    var target := ""
    var _rename: Callable
    var _copy: Callable
    var _content := false

    ## *rename* and *copy* stand in for `DirAccess`'s in a suite, and
    ## *content* lands every target as a content address, which a suite's
    ## stand-in for one needs because its path is an ordinary one.
    func _init(rename := Callable(), copy := Callable(), content := false) -> void:
        _rename = rename
        _copy = copy
        _content = content

    ## Whether *to* is landed as a content address.
    func pours(to: String) -> bool:
        return _content or to.begins_with(CONTENT)

    ## The side file a save of *to* is written to before it lands.
    func side_of(to: String) -> String:
        side = to + SaSadFile.SAD_TEMP_SUFFIX
        if pours(to):
            var folder := SaDataRoot.path(POURED)
            DirAccess.make_dir_recursive_absolute(folder)
            side = folder.path_join(to.md5_text() + "." + to.get_extension() + SaSadFile.SAD_TEMP_SUFFIX)
        return side

    ## Puts *from* in place of *to* keeping *versions* older copies, and
    ## answers the error of the step that failed, OK once the picture is at *to*.
    func land(from: String, to: String, versions: int) -> Error:
        side = from
        target = to
        if pours(to):
            return _pour(from, to)
        var moved := _keep(versions)
        if keep_error != OK:
            push_warning("SaSadSave: keeping '%s' as '%s1' failed (%s)" % [to, to, error_string(keep_error)])
        move_error = _move(from, to)
        if move_error == OK:
            return OK
        step = &"move"
        side_gone = not FileAccess.file_exists(from)
        copy_error = _copy_whole(from, to)
        copied = copy_error == OK
        var copy_said := "copied in its place" if copied else "the copy failed too (%s)" % error_string(copy_error)
        push_warning("SaSadSave: moving '%s' onto '%s' failed (%s), %s" % [from, to, error_string(move_error), copy_said])
        if copied:
            return OK
        step = &"copy"
        for i in range(1, versions + 1 if moved else 1):
            _move("%s%d" % [to, i], "%s%s" % [to, "" if i == 1 else str(i - 1)])
        return move_error

    ## Writes the whole of *from* into the content address *to* in one write,
    ## and removes *from* once the write took.
    func _pour(from: String, to: String) -> Error:
        var bytes := FileAccess.get_file_as_bytes(from)
        pour_error = FileAccess.get_open_error() if bytes.is_empty() else OK
        var file := FileAccess.open(to, FileAccess.WRITE) if pour_error == OK else null
        if pour_error == OK and file == null:
            pour_error = FileAccess.get_open_error()
        if file != null:
            file.store_buffer(bytes)
            pour_error = file.get_error()
            file.close()
        if pour_error == OK:
            DirAccess.remove_absolute(from)
            return OK
        step = &"pour"
        push_warning("SaSadSave: writing '%s' into '%s' failed (%s)" % [from, to, error_string(pour_error)])
        return pour_error

    ## What failed, in the painter's words, empty while nothing did.
    func why() -> String:
        var said := PackedStringArray()
        if pour_error != OK:
            said.append(TranslationServer.translate("Writing it into '%s' failed (%s).") % [target, error_string(pour_error)])
        if keep_error != OK:
            said.append(TranslationServer.translate("Keeping the previous version failed (%s).") % error_string(keep_error))
        if move_error != OK:
            var moving := TranslationServer.translate("Moving '%s' onto '%s' failed (%s).")
            said.append(moving % [side, target, error_string(move_error)])
        if side_gone:
            said.append(TranslationServer.translate("The side file was gone before it could be moved."))
        if copy_error != OK:
            said.append(TranslationServer.translate("Copying it into place failed too (%s).") % error_string(copy_error))
        return " ".join(said)

    func _move(from: String, to: String) -> Error:
        return _rename.call(from, to) if _rename.is_valid() else DirAccess.rename_absolute(from, to)

    ## Copies *from* over *to* and removes *from* once *to* reads back the same,
    ## and otherwise removes a *to* the copy began to write, which is neither file.
    func _copy_whole(from: String, to: String) -> Error:
        var before := FileAccess.get_sha256(to) if FileAccess.file_exists(to) else ""
        var err: Error = _copy.call(from, to) if _copy.is_valid() else DirAccess.copy_absolute(from, to)
        var sum := FileAccess.get_sha256(from)
        err = ERR_FILE_CORRUPT if err == OK and (sum.is_empty() or FileAccess.get_sha256(to) != sum) else err
        if err == OK:
            DirAccess.remove_absolute(from)
        elif FileAccess.file_exists(to) and FileAccess.get_sha256(to) != before:
            DirAccess.remove_absolute(to)
        return err

    ## Shifts `.sad<n-1>` to `.sad<n>` from the top down and the target to
    ## `.sad1`, for a count above zero and a target that exists, and answers
    ## whether the target moved.
    func _keep(count: int) -> bool:
        if count <= 0 or not FileAccess.file_exists(target):
            return false
        for i in range(count, 1, -1):
            if FileAccess.file_exists("%s%d" % [target, i - 1]):
                DirAccess.rename_absolute("%s%d" % [target, i - 1], "%s%d" % [target, i])
        keep_error = DirAccess.rename_absolute(target, "%s1" % target)
        step = &"keep" if keep_error != OK else step
        return keep_error == OK
