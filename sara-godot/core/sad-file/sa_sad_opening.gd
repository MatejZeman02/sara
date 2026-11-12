## The v4 container's open, which may take more than one frame: a Zstd JSON
## header, then one independently compressed blob per field per chunk,
## addressed by the offset index in the header.
##
## **Let go of, read apart, then landed.** The header is read when this is
## made, and once it is one this build reads, the document lets go of its
## layers, history and caches by [SaSadLettingGo], before a blob is read, so an
## open over a painting never holds two. The layers are made from their
## entries outside the document, so nothing the window draws or the layers
## docker lists meets a stack half read. [method land] puts the stack into the
## document in one go: the header's keys, the layers, the record a first save
## copies blobs by, and the caches. A refused header leaves the document as the
## reader's caller decides, which `SaSadFile` makes an empty one, and a later
## open leaves it empty.
##
## **Over frames when it is long.** [method over_frames] reads until
## [constant STEP_USEC] has gone, and the rest a frame at a time, so a file of
## hundreds of layers keeps the window drawing while it opens. A file that
## reads within the first step lands in the call, so File > Open of a small
## file is as immediate as it ever was. A longer one reads the rest of its
## layers without their chunks, lands the stack with every chunk still to
## come, and then fills the chunks in, those the view shows first across the
## layers in the order they composite and the rest after, so the canvas fills
## in as they arrive. Until the last is in, [method still_filling]
## names the open, a tool's press is refused with [method refusal], and a save
## or an export fills the rest first, [method complete]. [method whole] reads
## every layer and chunk in one call, for the callers that need the document
## opened when it returns: the autosave's recovery, the suites and the door's
## `load`.
##
## One open runs at a time. A new one into the same document drops the one in
## flight with every layer it made, and its answer is never given. A new one
## into another document lets the one in flight finish filling first, since
## its stack is in a document the painter can see.
class_name SaSadOpening
extends RefCounted

## How long one frame of an open over frames reads for, in microseconds. At
## 50 ms a step that ran over met the frame's own work and the frame the window
## skips drawing while nothing on it changed, and frames of 0.12 to 0.18 s
## followed on the seasons file. At 30 ms a step still ran to 52 ms with its
## upload and its hashes, and a frame the window did not draw added it to the
## next one's, so it is held at 20 ms.
const STEP_USEC := 20000

## A file at least this long opens over frames from its first: the
## header is read in the call, the document's layers are taken out in the next
## frame and freed a share a frame after it, the blobs are read once they are
## gone, the space the header names is put in a frame of its own when it is
## another, and the layers are read without their chunks from the frame after,
## so no frame holds two of these. On the seasons file of 128 MB the call that
## did them held its frame for 0.2 to 0.35 s. A shorter file reads in the call,
## and so does one that reads within the first step.
const OVER_FRAMES_BYTES := 16 << 20

## The open over frames now in flight, which the next open drops or finishes.
static var _running: SaSadOpening = null
## The frame the last open over frames landed in, which [method busy] reads.
static var _landed_frame: int = -2

## What the read so far came to. Anything but OK stops the open.
var error: Error = OK

var _document: SaDocument
var _path: String
var _header: Dictionary[String, Variant] = {}
var _blobs := PackedByteArray()
var _layers: Array = []
## The header's entries read so far.
var _next := 0
## The layers read so far, in the header's order, outside the document.
var _built: Array[SaLayer] = []
var _opening: SaSadCodec.Open = null
var _color_format := 0
var _began := 0
## Called with the open's error once it is done, for an open over frames.
var _then := Callable()
## Called once the stack is in the document with chunks still to come, and
## answering the part of the document the view shows, for an open over frames.
var _landed := Callable()
var _tree: SceneTree = null
## Up once every layer is read, an open over frames waiting for its landing.
var _read_all := false
## The chunks still to read once the stack has landed, null until a step
## reads layers without their chunks.
var _fill: Fill = null
## Up while the stack is in the document with chunks still to come.
var _in_document := false
## How long a frame of this open over frames reads for.
var _step_usec := STEP_USEC
## The file, open from the header's read until its blobs are read.
var _file: FileAccess = null
## Up once the last chunk is in, and the frame after puts the open's last
## pieces in, [method _end_reads], which raises the second.
var _all_in := false
var _reads_ended := false
## The record of the open's blobs a first save copies by, built over the frames
## after the last chunk, [method SaSadSnapshot.opened_in_turns].
var _record: SaSadSnapshot.OpenedInTurns = null
## Up once the record is kept, whose frame gives no answer.
var _record_kept := false
## Up once the document's own layers are out of it, and those of them still
## to free, a share a frame.
var _let_go := false
var _leaving: Array[SaLayer] = []
## The process frame [method over_frames] was called in, whose own turn of
## the frames reads nothing.
var _called_frame := -1
## The last process frame the open's turn worked in and the last one that drew,
## so a turn after one that drew nothing waits a frame. A frame that draws
## nothing ends no gap on the screen, and the next frame's work joined its own
## in one gap: the last step's 17 ms and the end of the reads' 45 ms were one
## gap of 104 ms, and a step and the first mark one of 123 ms. The drawn
## frame stays -1 where nothing draws, as in a headless suite, which never waits.
var _worked_frame := -1
var _drew_frame := -1
## Up once the space the header names is in the document, a frame of its own
## when it was another.
var _space_read := false


## Reads the header of *file*, whose magic has been read, the `.sad` at
## *path* to open into *document*, and drops or finishes any open still in
## flight, as the class comment says.
func _init(document: SaDocument, file: FileAccess, path: String) -> void:
    if _running != null:
        if _running._in_document and _running._document != document:
            _running.finish_filling()
        else:
            _running.drop()
    _began = Time.get_ticks_usec()
    _document = document
    _path = path
    var traced := SaFrameTrace.now()
    _file = file
    error = _read_header(file)
    if error != OK:
        _close_file()
    SaFrameTrace.spent("open header", traced)
    # A short file lets go and reads its blobs here, in the call, and a long one
    # in the frames [method over_frames] steps.
    if _file != null and _file.get_length() < OVER_FRAMES_BYTES:
        _take_blobs()


## Opens the file in one call, and answers how it went.
func whole() -> Error:
    _take_blobs()
    if error == OK:
        step(-1)
    return land()


## Opens the file over as many frames as it takes, *then* called with the
## error once every chunk is in the document: within this call when the first
## step reads every layer or the header refused, and from a later frame
## otherwise. *landed*, when valid, is called once the stack is in the
## document and the chunks are still to come, and answers the part of the
## document the view shows, which is read first. Without it nothing lands
## before every chunk is read, since only the caller can make
## its window ready for a document of another size. *step_usec* is how long
## each frame reads for, [constant STEP_USEC] but in a suite.
func over_frames(then: Callable, landed: Callable = Callable(), step_usec: int = STEP_USEC) -> void:
    _then = then
    _landed = landed
    _step_usec = step_usec
    _tree = Engine.get_main_loop() as SceneTree
    var long := _file != null and _file.get_length() >= OVER_FRAMES_BYTES
    if not long or _tree == null:
        _take_blobs()
        if error != OK or step(step_usec):
            then.call(land())
            return
    if _tree == null:
        step(-1)
        then.call(land())
        return
    # The rest of the layers are read without their chunks, which wait for
    # the stack to land and the view to say which come first.
    if _landed.is_valid() and _opening != null:
        defer_chunks()
    _running = self
    _called_frame = Engine.get_process_frames()
    _tree.process_frame.connect(_on_frame)
    if not RenderingServer.frame_post_draw.is_connected(_on_drawn):
        RenderingServer.frame_post_draw.connect(_on_drawn)
    SaTrail.stage("SaSadOpening: reading %s over frames, %d of %d layers read" % [_path, _next, _layers.size()])


## Whether an open over frames is reading, or landed in this frame or the one
## before, where the easel draws the opened stack first. Each of those frames
## is long already, so a layer's picture, which takes a quarter of a second
## over a deep stack of adjustments, waits them out.
static func busy() -> bool:
    return _running != null or Engine.get_process_frames() <= _landed_frame + 1


## The open whose stack is in *document* with chunks still to come, or null
## when none is.
static func still_filling(document: SaDocument) -> SaSadOpening:
    if _running == null or document == null or _running._document != document or not _running._in_document:
        return null
    return _running


## The sentence the corner says when a press of *gesture*, the translated noun
## for what did nothing, meets *document* still opening, empty when it is not.
## It carries the open's progress, the share of the file's chunks that are in.
static func refusal(document: SaDocument, gesture: String) -> String:
    var running := still_filling(document)
    if running == null:
        return ""
    var share := running.percent_in()
    var line := "The file is still opening, %d%% of it is in, so the %s did nothing."
    return TranslationServer.translate_plural(line, line, share) % [share, gesture]


## Fills in every chunk *document* still waits for, in this call, so a save
## or an export of it holds the whole file. Nothing for a document no open is
## filling.
static func complete(document: SaDocument) -> void:
    # The open's record too, which a save copies the file's blobs by.
    if _running != null and document != null and _running._document == document and _running._in_document:
        _running.finish_filling()


## The share of the file's chunks in the document, in whole per cent.
func percent_in() -> int:
    return 100 if _fill == null else _fill.percent()


## Reads the header's entries into layers until *budget_usec* has gone, or
## all of them when it is negative, and answers whether every one is read.
## Their chunks are read with them, or kept for the fill once an open over
## frames has one.
func step(budget_usec: int) -> bool:
    if _opening == null:
        _take_blobs()
    var began := Time.get_ticks_usec()
    var traced := SaFrameTrace.now()
    while error == OK and _next < _layers.size():
        var layer_data := SaTyped.strings(_layers[_next])
        var layer := SaSadLayerEntry.read(layer_data, _blobs, _color_format)
        # Deliberately no layer.setup(): allocating the whole grid before the
        # stored chunks is what defeated sparseness, every field of every chunk.
        _built.append(layer)
        var entries := SaTyped.list(layer_data.get("chunks"))
        if _fill != null and Fill.waits(layer):
            _fill.add(layer, entries)
        else:
            _opening.layer(layer, entries)
        _next += 1
        if budget_usec >= 0 and Time.get_ticks_usec() - began >= budget_usec:
            break
    var marked := SaFrameTrace.now()
    if _opening != null:
        _opening.upload()
    SaFrameTrace.spent("open upload", marked)
    # Each frame's chunks hashed in it, so the landing frame hashes none. One
    # call has nothing to spread.
    marked = SaFrameTrace.now()
    if budget_usec >= 0:
        SaSadSnapshot.hash_noted()
    SaFrameTrace.spent("open hash", marked)
    SaFrameTrace.spent("open layers", traced)
    return error != OK or _next >= _layers.size()


## Reads the layers from here on without their chunks, which wait for the
## stack to land, [method begin_filling] and [method fill]. An open over
## frames with a window to land in asks it after its first step.
func defer_chunks() -> void:
    if _fill == null and _opening != null:
        _fill = Fill.new(_opening)


## Puts the chunks still to come that meet *view*, the document's pixels the
## window shows, before the rest. An empty *view* is the whole document.
func begin_filling(view: Rect2i) -> void:
    if _fill == null or not is_instance_valid(_document):
        return
    var unbuilt: Array[SaLayer] = []
    for layer: SaLayer in SaStaleSpread.bearers(_document):
        if SaFilterChain.has_enabled(layer.filters):
            unbuilt.append(layer)
    # The easel's walk in the frame after the landing would build them all at
    # once, so the chain leaves them to the fill's first steps.
    if _document.compositor != null:
        _document.compositor.filter_chain.hold_back(unbuilt)
    _fill.order(view if view.has_area() else Rect2i(Vector2i.ZERO, _document.canvas_size), unbuilt)


## Reads the chunks still to come into the landed stack until *budget_usec*
## has gone, or all of them when it is negative, and answers whether every
## one is in. A step that brings the last of the view's chunks in ends there,
## so the window draws the view whole before the rest are read.
func fill(budget_usec: int) -> bool:
    if _fill == null or not is_instance_valid(_document):
        return true
    var view_was := _fill.in_view()
    var filled := _fill.step(budget_usec, _document)
    if view_was > 0 and _fill.in_view() == 0:
        var took := roundi((Time.get_ticks_usec() - _began) / 1000.0)
        SaTrail.stage("SaSadOpening: the view's chunks of %s in at %d ms" % [_path, took])
    return filled


## Lets go of the open in flight without landing it: every layer it made is
## freed and its answer never given. The document stays as empty as the open
## left it. A stack already in the document is the document's, and is left
## as far as it is filled.
func drop() -> void:
    _stop_frames()
    _close_file()
    for layer in _leaving:
        layer.free()
    _leaving.clear()
    if _opening != null:
        _opening.finish()
    for layer in _built:
        layer.free()
    _built.clear()
    if is_instance_valid(_document) and _document.compositor != null:
        _document.compositor.filter_chain.hold_back([])
    # The blobs it noted belong to no document now.
    SaSadSnapshot.opened(null, "")
    _in_document = false
    error = ERR_SKIP


## Reads every chunk still to come in this call and gives the open's answer,
## for a save or an export that needs the whole file, or a later open.
func finish_filling() -> void:
    if not _in_document:
        return
    _stop_frames()
    if not _all_in:
        fill(-1)
        _all_in = true
    if not _reads_ended:
        _end_reads(true)
    if _record != null:
        _record.step(-1)
    _done_filling()


func _on_frame() -> void:
    if not is_instance_valid(_document):
        drop()
        return
    # The door's own handler of the frame runs before this one, so a load it
    # asked for heard this one in the frame of the call, and the header's read
    # and the letting go held one frame of 144 ms.
    var frame := Engine.get_process_frames()
    if frame == _called_frame:
        return
    if _drew_frame >= 0 and _worked_frame == frame - 1 and _drew_frame < _worked_frame:
        return
    _worked_frame = frame
    # The answer waits for the frame after the one that kept the record,
    # since the Layers docker builds its first rows in the frame the open
    # answers in, and the two held one frame of 104 ms.
    if _record_kept:
        _stop_frames()
        _done_filling()
        return
    if _reads_ended:
        var traced := SaFrameTrace.now()
        _record_kept = _record == null or _record.step(_step_usec)
        SaFrameTrace.spent("fill record", traced)
        return
    if _all_in:
        _end_reads()
        return
    if _in_document:
        # The open's last pieces wait for the next frame, as the record waits
        # for the ones after it, since the last step's reads and either of
        # them held one frame for 0.3 to 0.4 s.
        _all_in = fill(_step_usec)
        return
    if not _let_go and error == OK:
        # Out of the document in this frame, and freed a share a frame in the
        # ones after, before the blobs are read, so the old painting and the
        # new file are not held at once.
        var marked := SaFrameTrace.now()
        _let_go = true
        _leaving = SaSadLettingGo.taken_out(_document)
        SaFrameTrace.spent("letting go", marked)
        return
    if not _leaving.is_empty():
        var marked := SaFrameTrace.now()
        var began := Time.get_ticks_usec()
        while not _leaving.is_empty() and Time.get_ticks_usec() - began < _step_usec:
            var layer: Node = _leaving.pop_back()
            layer.free()
        SaFrameTrace.spent("letting go", marked)
        return
    if _opening == null:
        _take_blobs()
        if error != OK:
            _stop_frames()
            _give(land())
        elif _landed.is_valid():
            defer_chunks()
        return
    if not _space_read:
        _space_read = true
        var traced := SaFrameTrace.now()
        var another := _read_space(_document, _header)
        SaFrameTrace.spent("open space", traced)
        if another:
            return
    if not _read_all:
        _read_all = step(_step_usec)
        return
    # Still the running open until it lands, which keeps it alive, as a
    # timer's call holds no reference, and lets a later open drop it.
    _tree.process_frame.disconnect(_on_frame)
    # Lands in the frame after the last layers were read, so it adds nothing to
    # that one, and late in it, from a timer, which the tree runs after every
    # node's process. The easel has had its turn by then, so its first
    # composite of the opened stack is the next frame's and not this one's,
    # where the two longest pieces of the open held one frame of 2 s.
    _tree.create_timer(0.0).timeout.connect(_land_late)


func _land_late() -> void:
    # A later open dropped this one, whose answer is never given.
    if _running != self:
        return
    # Before the landing, which is the first of the frames busy() names.
    _landed_frame = Engine.get_process_frames()
    if not is_instance_valid(_document):
        _running = null
        drop()
        return
    if _fill == null or _fill.left() == 0:
        _running = null
        _give(land())
        return
    var traced := SaFrameTrace.now()
    var landed := land()
    SaFrameTrace.spent("open landing", traced)
    if landed != OK:
        _running = null
        _in_document = false
        _give(landed)
        return
    # The caller's window is made ready for the document, and says what of it
    # shows, which is read first.
    traced = SaFrameTrace.now()
    var shown: Rect2i = _landed.call()
    begin_filling(shown)
    SaFrameTrace.spent("landed view", traced)
    var took := roundi((Time.get_ticks_usec() - _began) / 1000.0)
    var line := "SaSadOpening: %s landed in %d ms, %d chunks to fill, %d in the view"
    SaTrail.stage(line % [_path, took, _fill.left(), _fill.in_view()])
    _tree.process_frame.connect(_on_frame)
    if not RenderingServer.frame_post_draw.is_connected(_on_drawn):
        RenderingServer.frame_post_draw.connect(_on_drawn)


## Puts the open's last pieces in once every chunk has arrived: the hashes
## of the record a first save copies blobs by, whose keys the frames after
## build, the derived fields and the whole canvas's composite. The caches are
## not built again here, since each step folded them over what it brought.
## *now* draws the canvas in this call, for a save or an open that needs the
## file whole.
func _end_reads(now := false) -> void:
    _reads_ended = true
    if not is_instance_valid(_document):
        return
    var traced := SaFrameTrace.now()
    _opening.finish()
    _record = SaSadSnapshot.opened_in_turns(_document, _path)
    for child in _document.get_children():
        var layer := child as SaLayer
        if layer != null:
            layer.mark_all_unresolved()
    # Each step folded the caches again over what it brought, so they hold
    # every chunk already. Building the fold whole here again, and drawing
    # every chunk after it, held one frame for 1.2 s on the winter seasons file
    # of 563 layers.
    _fill.settle(_document, now)
    _document.composite_requested.emit()
    SaFrameTrace.spent("fill end", traced)


## Gives the open's answer once its record is kept.
func _done_filling() -> void:
    if _running == self:
        _running = null
    _in_document = false
    if not is_instance_valid(_document):
        return
    var took := roundi((Time.get_ticks_usec() - _began) / 1000.0)
    SaTrail.stage("SaSadOpening: %s filled in %d ms, %d blobs decoded on a pool" % [_path, took, _opening.pooled])
    var traced := SaFrameTrace.now()
    _give(OK)
    SaFrameTrace.spent("open answer", traced)


func _give(answer: Error) -> void:
    if _then.is_valid():
        _then.call(answer)


func _stop_frames() -> void:
    if _running == self:
        _running = null
    if _tree != null and _tree.process_frame.is_connected(_on_frame):
        _tree.process_frame.disconnect(_on_frame)
    if RenderingServer.frame_post_draw.is_connected(_on_drawn):
        RenderingServer.frame_post_draw.disconnect(_on_drawn)


func _on_drawn() -> void:
    _drew_frame = Engine.get_process_frames()


## Puts what was read into the document, then reads every link it holds from
## its file again, and answers the open's error.
func land() -> Error:
    if error != OK:
        var refused := error
        drop()
        return refused
    return SaLinkedFile.opened(_document, _path, _land_now)


# Gives *document* the space *header* names and answers whether it was
# another. Absent means unspecified, never sRGB, and from_header carries that
# distinction. The same space is not assigned again, because the setter's
# announcement warms every brush for it, 55 ms of the landing's frame on the
# seasons file. An open over frames gives it a frame of its own before its
# steps, and the landing then finds it there.
static func _read_space(document: SaDocument, header: Dictionary[String, Variant]) -> bool:
    var space := SaColorSpace.from_header(header)
    var held := document.color_space
    if held != null and held.is_specified == space.is_specified and held.to_header() == space.to_header():
        return false
    document.color_space = space
    return true


func _land_now() -> Error:
    var document := _document
    var header := _header
    SaLinkedFile.reading(document, _blobs)
    _read_space(document, header)

    # Read before anything can fail on it, and never inspected. Sara does not
    # know what any of this means and does not have to: an uninstalled module's
    # data is data, and dropping it would destroy it in the owner's own file.
    document.module_data = SaTyped.strings(header.get("modules"))
    SaSadAssistants.read_header(header, document)

    # Absent means off, every file written before the infinite canvas's switch.
    SaInfiniteCanvas.read_header(document, header)

    # Absent means no board, which is every file written before boards
    # existed and the empty docker a document with no board opens with.
    document.reference_boards = SaSadReferencePictures.boards_from(header, _blobs)

    # Each read as absent when it has no meaning, SaSadHeaderNumbers says why.
    document.blend_reference_white = SaSadHeaderNumbers.white(header)
    document.dpi = SaSadHeaderNumbers.dpi(header)

    # Absent means Preferences' light, the one a file saved before the key was
    # seen under on the machine that opens it.
    document.relief_light.read_header(header.get(SaReliefLight.HEADER_KEY))
    # Absent means off, which is every file written before the switch.
    document.double_resolution.read_header(header.get(SaDoubleResolution.HEADER_KEY))

    SaSadFile.replace_layers(document, SaSadHeaderNumbers.size(header))
    # After the size, whose setter puts the axes back, so the file's own are
    # the last word. Absent means at rest with every switch off, which is how
    # every file without the key was saved as far as anyone can tell.
    document.symmetry.read_header(header.get("symmetry"), Vector2(document.canvas_size))
    # After the size too, whose setter puts the side at the shorter one. A side
    # of zero or less has nothing to read a brush against, so it reads as absent.
    var stored_side := SaTyped.float_at(header, "brush_side", document.brush_side)
    document.brush_side = stored_side if stored_side > 0.0 else document.brush_side
    # After the size as well, where every version went back to flat, so absent
    # reads as flat, which is every file written before the key.
    document.projection = SaProjection.from_header(header.get(SaProjection.HEADER_KEY), SaSadFile.running_kinds())
    document.root_filters = SaSadFile.read_filters(header.get("filters", null), _blobs)

    SaSadLettingGo.add_in_one_notice(document, _built)
    var first_layer: SaLayer = _built[0] if not _built.is_empty() else null
    _built.clear()
    _opening.finish()

    # The record a first save copies blobs by is taken once every chunk is in,
    # so with chunks still to come it waits for the fill's end.
    _in_document = _fill != null and _fill.left() > 0
    if _in_document:
        # Running until the last chunk is in, which still_filling reads.
        _running = self
    else:
        SaSadSnapshot.opened(document, _path)
    var loaded := SaSadFile.finish_load(document, SaSadActiveLayer.read_header(document, header, first_layer))
    if _in_document:
        return loaded
    var took := roundi((Time.get_ticks_usec() - _began) / 1000.0)
    SaTrail.stage("SaSadFile: opened %s in %d ms, %d blobs decoded on a pool" % [_path, took, _opening.pooled])
    return loaded


func _read_header(file: FileAccess) -> Error:
    var version: int = file.get_32()
    if version > SaSadFile.SAD_VERSION:
        push_error("SaExport.load_sad: '%s' is version %d, newer than this build understands" % [_path, version])
        return ERR_FILE_UNRECOGNIZED
    var header_packed_size: int = file.get_32()
    var header_raw_size: int = file.get_32()
    var header_bytes := file.get_buffer(header_packed_size).decompress(header_raw_size, SaSadFile.SAD_BLOB_COMPRESS)
    if header_bytes.is_empty():
        push_error("SaExport.load_sad: header decompression failed for '%s'" % _path)
        return ERR_FILE_CORRUPT

    var json := JSON.new()
    if json.parse(header_bytes.get_string_from_utf8()) != OK:
        push_error("SaExport.load_sad: header parse error in '%s'" % _path)
        return ERR_FILE_CORRUPT

    _header = SaTyped.strings(json.data)
    if _header.get("format", "") != "sad":
        push_error("SaExport.load_sad: unexpected format field in '%s'" % _path)
        return ERR_FILE_UNRECOGNIZED
    # Before anything of the document is touched, so a refusal leaves it whole.
    var refused := SaSadHeaderNumbers.refusal(_header, _path)
    if not refused.is_empty():
        push_error(refused)
        return ERR_FILE_CORRUPT

    return OK


## Lets go of what the document holds and reads the file's blobs, once its
## header is one this build reads. The file is a `.sad` this build reads, so
## what the document holds goes before the blobs are read, and the open never
## holds two paintings.
func _take_blobs() -> void:
    if error != OK or _file == null:
        return
    var traced := SaFrameTrace.now()
    if not _let_go:
        SaSadLettingGo.before_reading(_document)
    _let_go = true
    _blobs = _file.get_buffer(_file.get_length() - _file.get_position())
    _close_file()
    SaFrameTrace.spent("letting go", traced)
    if GlobalShaderCompiler.get_rd() == null:
        push_error("SaExport.load_sad: RenderingDevice unavailable during load")
        error = ERR_CANT_ACQUIRE_RESOURCE
        return
    _color_format = SaColorSpace.from_header(_header).texel_format()
    _layers = _header.get("layers", [])
    _opening = SaSadCodec.Open.new(_blobs, SaSadBlob.read, SaSadFile.put_blob, SaSadCoarseLayer.chunk_scale)


func _close_file() -> void:
    if _file != null:
        _file.close()
        _file = null


## The chunks an open over frames reads once its stack has landed, in the
## order it reads them: those the view shows first, across the layers in the
## order they composite, and the rest after in the same order.
class Fill:
    extends RefCounted

    ## Each chunk still to read and each read, as [layer, entry, grid position].
    var _items: Array[Array] = []
    ## The positions the steps since the last mark changed, still unmarked.
    var _held: Dictionary[Vector2i, bool] = {}
    ## What the last step spent after its reads, waiting for the pool, folding
    ## the caches and hashing, for each microsecond of its reads, which the
    ## next one's reads leave room for. Three before the first, about what the
    ## seasons file's steps measure, where none at all let the first step read
    ## for its whole budget and run to 115 ms with its tail.
    var _tail_per_read := 3.0
    ## Up from the landing to the first step, which draws the landed stack
    ## whole before its reads, so the easel's own budgeted turn finds nothing
    ## of the landing to cut over the frames of the fill.
    var _owed := false
    ## How many of [member _items] are in.
    var _done := 0
    ## The end of the view's chunks in [member _items], 0 before
    ## [method order] has put them first.
    var _view_end := 0
    ## The layers whose filters the landing's first walk would build its
    ## passes for, built a share a frame before it, [method order].
    var _unbuilt: Array[SaLayer] = []
    var _opening: SaSadCodec.Open

    func _init(opening: SaSadCodec.Open) -> void:
        _opening = opening

    ## Whether *layer*'s chunks can wait for the stack to land: a layer that
    ## stores paint and nothing reads at the landing. A smart layer's chunks
    ## are its source, which the landing joins and maps and a link reads its
    ## file over, and an effect or a scene layer's are what it draws, so
    ## theirs are read with the layer.
    static func waits(layer: SaLayer) -> bool:
        return layer.live_transform == null and not layer.is_effect() and not layer.is_scene()

    ## Keeps *entries*, the header's chunks of *layer*, for the fill.
    func add(layer: SaLayer, entries: Array) -> void:
        for raw_entry: Variant in entries:
            var entry := SaTyped.strings(raw_entry)
            _items.append([layer, entry, Vector2i(SaTyped.int_at(entry, "x", 0), SaTyped.int_at(entry, "y", 0))])

    ## Puts the chunks still to come that meet *view*, the document's pixels
    ## the window shows, before the rest, each part in the order it was added,
    ## which is the order the layers composite in. *unbuilt* are the landed
    ## layers that carry a filter, whose passes the first steps build before
    ## the landed stack is drawn, since the walk that drew it built them all
    ## and held one frame for 0.1 s on the seasons file.
    func order(view: Rect2i, unbuilt: Array[SaLayer] = []) -> void:
        _owed = true
        _unbuilt = unbuilt
        var shown: Array[Array] = []
        var hidden: Array[Array] = []
        for at in range(_done, _items.size()):
            var item: Array = _items[at]
            var grid_pos: Vector2i = item[2]
            var rect := Rect2i(grid_pos * SaLayer.CHUNK_SIZE, Vector2i.ONE * SaLayer.CHUNK_SIZE)
            (shown if rect.intersects(view) else hidden).append(item)
        _items = _items.slice(0, _done) + shown + hidden
        _view_end = _done + shown.size()

    ## Reads chunks into their layers, now in *document*, until *budget_usec*
    ## has gone or, when it is negative, all of them, stopping where the
    ## view's end, and answers whether every chunk is in and drawn. Each step
    ## waits for the pool to upload what it handed, so a chunk the window
    ## draws is never one half read. The budget is the whole step's: its reads
    ## stop early by what the step before spent after them, which on the
    ## seasons file was as much again as the reads.
    ##
    ## **Drawn three times, not every step.** The first step draws the
    ## landed stack before it reads. What the steps bring is held, and marked
    ## and drawn by the step that brings the view's last chunk and by the one
    ## that brings the last of all, each as one composite of the whole
    ## canvas, the last left to the easel's budgeted turn. Left to the easel,
    ## the landing's composite was budgeted over twelve frames of the fill,
    ## 0.1 to 0.6 s each. On the seasons file, 625 layers and 217 of them
    ## effect layers, a mark each step cost every frame of the fill a
    ## composite of 0.2 s, since the effects spread each chunk a cut let
    ## through to fifteen: 25 frames over 0.1 s in an open of 7.5 s. The whole
    ## canvas at once is the one walk the effects do not spread, and the two
    ## left 4 or 5 frames over 0.1 s in an open of 5.8 s, the first walk 0.6 s
    ## and the last 1.1 s, nearly all of it the effects' refresh.
    func step(budget_usec: int, document: SaDocument) -> bool:
        var began := Time.get_ticks_usec()
        if _owed and not _unbuilt.is_empty():
            _build_filters(budget_usec, document)
            if budget_usec >= 0:
                return false
        var first := _owed
        if _owed:
            _owed = false
            var marked := SaFrameTrace.now()
            _mark(document)
            SaFrameTrace.spent("fill first mark", marked)
        var reads_usec := clampi(roundi(budget_usec / (1.0 + _tail_per_read)), budget_usec >> 3, budget_usec)
        var traced := SaFrameTrace.now()
        began = Time.get_ticks_usec()
        var arrived: Dictionary[SaLayer, Dictionary] = {}
        while _done < _items.size():
            var item: Array = _items[_done]
            _done += 1
            var layer: SaLayer = item[0] if is_instance_valid(item[0]) else null
            # A layer deleted while the open filled takes its chunks with it.
            if layer != null and layer.get_parent() == document:
                var grid_pos: Vector2i = item[2]
                _opening.layer(layer, [item[1]])
                if not arrived.has(layer):
                    arrived[layer] = {} as Dictionary[Vector2i, bool]
                arrived[layer][grid_pos] = true
                layer.mark_unresolved(grid_pos)
            if _done == _view_end and budget_usec >= 0:
                break
            if budget_usec >= 0 and Time.get_ticks_usec() - began >= reads_usec:
                break
        SaFrameTrace.spent("fill read", traced)
        var read := Time.get_ticks_usec()
        traced = SaFrameTrace.now()
        _opening.finish()
        SaFrameTrace.spent("fill upload", traced)
        # The chunks are marked below no layer, after every layer's refold.
        # Marking each layer named cost 4 s of the winter seasons file's fill
        # in the stale spread's search of readers.
        traced = SaFrameTrace.now()
        for layer: SaLayer in arrived:
            _held.merge(_moved(document, layer, arrived[layer]))
        SaFrameTrace.spent("fill refold", traced)
        # Each step's chunks hashed in it, inside its budget, where after the
        # step it added 40 to 50 ms to the last one.
        traced = SaFrameTrace.now()
        # Not in the step of the first mark, which walks the whole canvas on
        # the card: a hash after it waited for the walk, 58 ms of one frame.
        # The next step hashes what this one read.
        if budget_usec >= 0 and not first:
            SaSadSnapshot.hash_noted()
        SaFrameTrace.spent("fill hash", traced)
        _tail_per_read = float(Time.get_ticks_usec() - read) / maxi(read - began, 500)
        # The last chunk's mark is [method settle]'s, in the frame after.
        if _done < _items.size() and _done == _view_end:
            _mark(document)
        return _done >= _items.size()

    ## Marks what the last steps brought and asks for the whole canvas, drawn
    ## in this call when *now* says so and by the easel's budgeted turn
    ## otherwise, once every chunk is in.
    func settle(document: SaDocument, now: bool) -> void:
        _mark(document, now)

    # Builds the passes of the filters of [member _unbuilt] until *budget_usec*
    # has gone, or all of them when it is negative, as the walk of the whole
    # canvas would, so it finds them built.
    func _build_filters(budget_usec: int, document: SaDocument) -> void:
        var began := Time.get_ticks_usec()
        var traced := SaFrameTrace.now()
        var chain := document.compositor.filter_chain if document.compositor != null else null
        while not _unbuilt.is_empty():
            var layer: SaLayer = _unbuilt.pop_back()
            if chain != null and is_instance_valid(layer):
                chain.build(layer)
            if budget_usec >= 0 and Time.get_ticks_usec() - began >= budget_usec:
                break
        SaFrameTrace.spent("fill filters", traced)

    # Marks what the steps held and asks for the whole canvas rather than
    # the marked chunks, the cheaper of the two walks under effect layers and
    # the same picture. *now* composites it in this frame, which the landing
    # and the view's end want so the window is never drawn half. Otherwise
    # the easel's own budgeted turn draws it, which on the seasons file
    # spreads the last walk of 1.1 s over about six frames of 0.3 to 0.5 s
    # rather than one stall of 1.5 s with the answer's own frame on it.
    func _mark(document: SaDocument, now := true) -> void:
        if not _held.is_empty():
            document.invalidate_chunks(_held.keys(), null, false)
            _held.clear()
        var easel := document.get_parent() as SaEasel
        if easel != null:
            easel.request_full_composite()
            if now:
                easel.process_pending_composite()

    # Folds each cache that bakes *layer* again over *positions*, where it
    # took chunks, since a chunk marked alone is drawn from the caches as they
    # were before it came, and answers the positions to mark, those and what
    # the fold changed.
    static func _moved(document: SaDocument, layer: SaLayer, positions: Dictionary) -> Dictionary[Vector2i, bool]:
        var at: Dictionary[Vector2i, bool] = {}
        at.assign(positions)
        var stale := at.duplicate()
        if document.fold != null and document.compositor != null:
            stale.merge(document.fold.refold(document, document.compositor, layer, at))
        return stale

    func left() -> int:
        return _items.size() - _done

    func percent() -> int:
        return 100 if _items.is_empty() else floori(100.0 * _done / _items.size())

    func total() -> int:
        return _items.size()

    func in_view() -> int:
        return maxi(0, _view_end - _done)
