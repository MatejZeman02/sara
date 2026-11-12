## Every tip picture already on the card, kept across presets, and the loads
## that put it there off the stroke.
##
## **Why it exists.** A tip that is a GIMP pipe of hundreds of cells, loaded
## whole inside the first dab each time the tip's path moves, the file read,
## every cell parsed and every cell uploaded, and kept nowhere once the tool
## lets go of it, freezes Sara for seconds at the press, and again each time the
## preset is chosen back.
##
## **Kept.** A loaded picture stays here under its path, beside the stamp of the
## file it was read from, so a preset chosen again binds textures already on the
## card. The stamp is the file's modified time with its size and its two ends,
## because the time counts whole seconds and a file written twice in one second,
## which every suite that rewrites a scratch tip does, would otherwise read as
## unchanged, the lesson `sa_pattern_store.gd` records. What is kept is bounded
## by the bytes its textures hold, [member bound_bytes], and the picture asked
## for least recently goes first. The one just asked for stays even alone past
## the bound, because dropping it would load it again at the next press, which
## is the freeze this class is for.
##
## **Loaded before the press.** [method ahead] starts a load off the stroke at
## the next frame: the file read and the cells parsed on a worker thread, then
## the textures made on the main thread, [constant UPLOAD_BYTES_PER_FRAME] a
## frame, so the window keeps its frame rate,
## with a frame drawn between two when the window draws none of its own,
## [method _move_the_device_on]. A press that comes first finishes the load
## inside itself, [method mask_for], which costs what is left of it and so never
## more than the whole load would. It says so twice: the stroke's line names
## the load in its longest frame, and a stall line while it ran names it as the
## place Sara was.
##
## **What it hands out is a view, never the mask it keeps.**
## [method SaBrushTipMask.view] says why. The textures are `RefCounted`, so a
## picture dropped from here that a tool still holds stays on the card until the
## tool lets go of it (hard rule 4).
class_name SaTipCache
extends RefCounted

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## What the kept pictures' textures may hold, half a gibibyte, before the one
## asked for least recently goes.
##
## A pick, and reversible. Three knife pipes of 360, 252 and 198 cells are
## about 400 MiB at the 256 by 256 the suite builds its pipe at, so all three
## stay and a fourth pushes out whichever was bound longest ago. Not a setting,
## because nothing measured gives a painter a reason to move it.
const BOUND_BYTES: int = 512 * 1024 * 1024

## What one frame makes of a load off the stroke, four mebibytes of tip
## texture, which is eight cells of 256 by 256 at the eight bytes a texel the
## tip texture holds. A pipe's cells go up as their own bytes, an eighth of that
## for a grey pipe and half for a colour one. A load that has more left goes on
## at the next frame, and one cell larger than this is made alone in a frame of
## its own.
const UPLOAD_BYTES_PER_FRAME: int = 4 * 1024 * 1024

## How many bytes of each end of a file go into its stamp.
const STAMP_END_BYTES: int = 4096

static var _shared: SaTipCache = null

## How far [member held_bytes] may go, [constant BOUND_BYTES] for the app and
## less for a suite's own cache, set by the constructor.
var bound_bytes: int = BOUND_BYTES
## The bytes the kept pictures' textures hold. Written here only.
var held_bytes: int = 0
## Every file read this cache began, by either road, so a suite can say a press
## read nothing.
var reads: int = 0
## The loads a press had to finish because it came before their end.
var finished_at_press: int = 0

## Path to a picture on the card.
var _kept: Dictionary[String, Picture] = {}
## Path to a picture still loading off the stroke.
var _loading: Dictionary[String, Picture] = {}
## How many times a picture was asked for, the clock [member Picture.asked] is
## read on, so the least recently asked is the smallest.
var _asked: int = 0
## The engine's count of drawn frames when the last frame's share uploaded
## anything, or -1 when it uploaded nothing.
var _uploaded_at_drawn: int = -1


func _init(bound: int = BOUND_BYTES) -> void:
    bound_bytes = bound


## The one cache the app's tools share, made at the first ask.
static func shared() -> SaTipCache:
    if _shared == null:
        _shared = SaTipCache.new()
    return _shared


## Starts loading the tip *settings* holds off the stroke, when it is a picture,
## and answers its path, or empty when there is no picture to load.
##
## The Brush Presets docker calls this for every preset loaded anywhere, a press
## on its grid, a chord, the Pop-up Palette or the bar, since each of them
## announces `EventBus.preset_loaded`, and the chooser before it draws a preset's
## picture, which waits on [method is_loading]. Read through `in`, because the
## settings belong to an engine and a tool with no tip has nothing to load.
static func load_ahead(settings: Resource) -> String:
    if settings == null or not "tip" in settings:
        return ""
    var held: Variant = settings.get("tip")
    if not held is SaBrushTipScript:
        return ""
    var tip: SaBrushTipScript = held
    if not tip.uses_image():
        return ""
    shared().ahead(tip.image_path)
    return tip.image_path


## Starts loading *path* off the stroke, and calls *then* once its picture is
## on the card or its load has failed.
##
## The read is handed to the workers at the next frame, because the frame a
## preset is chosen in is a long one whatever the preset, and workers begun
## inside it make it longer still.
##
## A picture kept and current is only marked as asked for, a load already
## under way is left to run, and a path no file answers is handed on at once,
## since the press's bind says why. A load whose file has changed since it
## began is waited for and dropped, because a worker cannot be stopped halfway.
func ahead(path: String, then: Callable = Callable()) -> void:
    var stamp := Stamp.of(path)
    if not stamp.found:
        _call(then)
        return
    var kept := _current(path, stamp)
    if kept != null:
        _mark(kept)
        _call(then)
        return
    var loading: Picture = _loading.get(path)
    if loading != null and loading.stamp.equals(stamp):
        loading.waiting.append(then)
        return
    if loading != null:
        loading.abandon()
    var picture := Picture.new(path, stamp)
    picture.waiting.append(then)
    reads += 1
    _loading[path] = picture
    _listen()


## The mask a tool binds for *path*, a view of the kept picture when there is
## one and the file has not changed, without reading anything.
##
## **The press's door.** A load under way is finished here, which is a press
## that came before its end, and anything else is loaded here, the whole of it.
## Either costs at most what loading the whole picture at the press would, and
## either is said: the stroke ledger hears how long it took, and the trail
## stands at it until the frame is drawn, so a stall line names it.
func mask_for(path: String) -> SaBrushTipMask:
    if path.is_empty():
        return SaBrushTipMask.new()
    var stamp := Stamp.of(path)
    var kept := _current(path, stamp)
    if kept != null:
        _mark(kept)
        return kept.mask.view()
    var started := Time.get_ticks_usec()
    var picture: Picture = _loading.get(path)
    var at_press := picture != null and picture.stamp.equals(stamp)
    var ticket := SaTrail.enter(
        ("the tip %s, its load finished at a press" if at_press else "the tip %s, loaded at a press") % path.get_file()
    )
    if at_press:
        finished_at_press += 1
    else:
        if picture != null:
            picture.abandon()
        picture = Picture.new(path, stamp)
        reads += 1
    var mask := picture.finish()
    _loading.erase(path)
    _settle(picture)
    SaStrokeLedger.tip_loaded(path.get_file(), Time.get_ticks_usec() - started)
    _give_back_after_this_frame(ticket)
    return mask.view()


## One frame's share of the loads off the stroke: a load asked for since the
## last frame is handed to the workers, every load whose workers are done
## uploads cells until the frame's [constant UPLOAD_BYTES_PER_FRAME] are spent,
## and a load with nothing left is kept.
##
## Connected to `SceneTree.process_frame` while a load is under way and
## disconnected when none is. A suite calls it by hand, because a test function
## cannot wait for a frame.
func pump() -> void:
    var started := Time.get_ticks_usec()
    _move_the_device_on()
    var budget := UPLOAD_BYTES_PER_FRAME
    var named := ""
    for path: String in _loading.keys():
        if budget <= 0:
            break
        var picture: Picture = _loading[path]
        if not picture.begun:
            picture.begin()
            continue
        if not picture.read():
            continue
        budget -= picture.upload(budget)
        named = path.get_file()
        if picture.uploaded():
            _loading.erase(path)
            picture.finish()
            _settle(picture)
    _uploaded_at_drawn = Engine.get_frames_drawn() if budget < UPLOAD_BYTES_PER_FRAME else -1
    if not named.is_empty():
        SaStrokeLedger.tip_loaded(named, Time.get_ticks_usec() - started)
    if _loading.is_empty():
        _unlisten()


## Draws a frame without presenting it when the window drew none since the last
## frame's uploads, because the device takes its staging memory back only once
## a frame is drawn. Without it the staging grows with every upload in a window
## nobody touches and some upload frames stall for tens of milliseconds, where a
## frame drawn here costs far less than the stall. Never a present, which can
## wait for ever on a compositor that does not answer.
func _move_the_device_on() -> void:
    if _uploaded_at_drawn == Engine.get_frames_drawn() and RenderingServer.get_rendering_device() != null:
        RenderingServer.force_draw(false, 0.0)


## Whether a load is under way off the stroke.
func busy() -> bool:
    return not _loading.is_empty()


## Whether *path* is still loading off the stroke.
func is_loading(path: String) -> bool:
    return _loading.has(path)


## What a state dump says about the cache: what it holds against its bound,
## what is still loading, and the reads and the loads a press finished.
func report() -> Dictionary[String, Variant]:
    return {
        "held_bytes": held_bytes,
        "bound_bytes": bound_bytes,
        "kept": _kept.keys(),
        "loading": _loading.keys(),
        "reads": reads,
        "finished_at_press": finished_at_press,
    }


## Whether *path*'s picture is on the card, current or not.
func holds(path: String) -> bool:
    return _kept.has(path)


## Waits for every load and drops every picture, at the tree's leaving so no
## worker or texture outlives it, and in a suite to start from nothing.
func forget() -> void:
    for picture: Picture in _loading.values():
        picture.abandon()
    _loading.clear()
    _kept.clear()
    held_bytes = 0
    _unlisten()


## The kept picture for *path* when its file is the one it was read from.
func _current(path: String, stamp: Stamp) -> Picture:
    var kept: Picture = _kept.get(path)
    if kept == null or not kept.stamp.equals(stamp) or not kept.mask.has_image():
        return null
    return kept


func _mark(picture: Picture) -> void:
    _asked += 1
    picture.asked = _asked


## Keeps *picture* when it loaded, drops the least recently asked for while the
## bound is passed, and calls whoever waited on it.
func _settle(picture: Picture) -> void:
    if picture.mask.error.is_empty() and picture.mask.has_image():
        if _kept.has(picture.path):
            held_bytes -= _kept[picture.path].bytes
        _kept[picture.path] = picture
        held_bytes += picture.bytes
        _mark(picture)
        _drop_past_the_bound(picture)
    for then: Callable in picture.waiting:
        _call(then)
    picture.waiting.clear()


func _drop_past_the_bound(keep: Picture) -> void:
    while held_bytes > bound_bytes and _kept.size() > 1:
        var oldest: Picture = null
        for picture: Picture in _kept.values():
            if picture != keep and (oldest == null or picture.asked < oldest.asked):
                oldest = picture
        _kept.erase(oldest.path)
        held_bytes -= oldest.bytes


func _listen() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    if not tree.process_frame.is_connected(pump):
        tree.process_frame.connect(pump)
    if tree.root != null and not tree.root.tree_exiting.is_connected(forget):
        tree.root.tree_exiting.connect(forget)


func _unlisten() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null and tree.process_frame.is_connected(pump):
        tree.process_frame.disconnect(pump)


static func _call(then: Callable) -> void:
    if then.is_valid():
        then.call()


## Gives the trail's place back at the next frame's start, after the watch has
## timed the frame the load was in. Static, so the lambda belongs to the script
## rather than to a cache a suite may drop before the frame comes.
static func _give_back_after_this_frame(ticket: int) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        SaTrail.give_back(ticket)
        return
    tree.process_frame.connect(func() -> void: SaTrail.give_back(ticket), CONNECT_ONE_SHOT)


## Which file a picture was read from: its modified time, its size and the
## bytes at its two ends.
class Stamp:
    extends RefCounted

    ## Whether the file could be opened at all.
    var found: bool = false
    var modified: int = 0
    var size: int = 0
    var ends: PackedByteArray = PackedByteArray()

    ## *path*'s stamp now, a stat and two short reads. A file that cannot be
    ## opened stamps as nothing, which no loaded picture carries.
    static func of(path: String) -> Stamp:
        var stamp := Stamp.new()
        var file := FileAccess.open(path, FileAccess.READ) if not path.is_empty() else null
        if file == null:
            return stamp
        stamp.found = true
        stamp.modified = FileAccess.get_modified_time(path)
        stamp.size = file.get_length()
        stamp.ends = file.get_buffer(STAMP_END_BYTES)
        if stamp.size > STAMP_END_BYTES:
            file.seek(maxi(STAMP_END_BYTES, stamp.size - STAMP_END_BYTES))
            stamp.ends.append_array(file.get_buffer(STAMP_END_BYTES))
        file.close()
        return stamp

    func equals(other: Stamp) -> bool:
        return other != null and modified == other.modified and size == other.size and ends == other.ends


## One tip picture, loading or loaded: the file read and its texels built on
## workers, the textures made on the main thread, and the mask they make.
##
## **Every cell of a pipe at load rather than the chosen one per dab.** A pipe
## is hundreds of `r32g32f` textures in a painter's brush. Uploading the one a
## dab asked for would put a file read, a decode and an upload in the dab loop,
## the hot path, again each time a stroke came round to the cell. So the cost
## is the load's, and the load is what this class moves.
##
## **A pipe's cells are made on the card from their own bytes.** One worker
## reads the file, its head, `SaGihPipe.read_head`, and each cell's header, and
## keeps each cell's texels as the file holds them, one byte a texel for a grey
## pipe and four for a colour one. `SaTipCells` sends them and a kernel makes
## the `r32g32f` tip from them, so no loop over a texel runs on the CPU. In one
## measurement the knife's two loops took 0.31 s on fourteen workers, and its 180 MiB
## of texels 66 to 113 ms to upload, where its 23 MiB of bytes now go up in 35
## to 41 ms with their textures made.
class Picture:
    extends RefCounted

    var path: String = ""
    var stamp: Stamp = null
    ## The mask the textures make, once [method finish] has made it.
    var mask: SaBrushTipMask = null
    ## The bytes the textures hold, which the bound counts.
    var bytes: int = 0
    ## When it was last asked for, on the cache's clock.
    var asked: int = 0
    ## Whoever [method SaTipCache.ahead] was asked by, called when it settles.
    var waiting: Array[Callable] = []
    ## Whether the read has begun, on a worker or, when a press came first, in
    ## [method finish] on the press's own thread.
    var begun: bool = false

    ## What the worker leaves: the pipe or the picture's size, every cell's
    ## texels and whether any carries colour, or why it could not. A picture's
    ## texels are the texture's own, its depth nought, and a pipe's cell's are
    ## the file's, its depth one or four.
    var _pipe: SaGihPipe.Pipe = null
    var _sizes: Array[Vector2i] = []
    var _texels: Array[PackedByteArray] = []
    var _depths: PackedInt32Array = PackedInt32Array()
    var _colourful: bool = false
    var _error: String = ""
    ## The read's task, or -1 when there is none to wait for.
    var _task: int = -1
    ## Whether the worker's half is done and waited for.
    var _read: bool = false
    ## The textures made so far, in cell order.
    var _cells: Array[SaTexture] = []
    var _upload_failed: bool = false

    func _init(from_path: String, read_stamp: Stamp = null) -> void:
        path = from_path
        stamp = read_stamp

    ## Hands the read to a worker.
    func begin() -> void:
        begun = true
        _task = WorkerThreadPool.add_task(_read_file, false, "Sara reads the tip %s" % path.get_file())

    ## Whether the worker's half is done, without waiting for anything.
    func read() -> bool:
        if _read:
            return true
        if _task >= 0 and not WorkerThreadPool.is_task_completed(_task):
            return false
        _wait()
        return true

    ## Makes textures from the texels in hand until *budget* bytes are spent,
    ## at least one, and answers the bytes it made.
    func upload(budget: int) -> int:
        var made := 0
        var cells := SaTipCells.new()
        while _cells.size() < _texels.size() and not _upload_failed and (made == 0 or made < budget):
            var at := _cells.size()
            var texture := (
                SaTipImage.upload_texels(_sizes[at], _texels[at])
                if _depths[at] == 0
                else cells.expand(_sizes[at], _depths[at], _texels[at])
            )
            if texture == null:
                _upload_failed = true
                break
            _cells.append(texture)
            # The texels are on the card now, and keeping them would be the
            # picture twice, once on each side of the bus.
            _texels[at] = PackedByteArray()
            made += texture.bytes
        cells.send()
        return made

    ## Whether every cell is on the card, or never will be.
    func uploaded() -> bool:
        return _read and (not _error.is_empty() or _upload_failed or _cells.size() == _texels.size())

    ## Does whatever is left, here and now, and answers the mask: the worker
    ## waited for, or the read made on this thread when none was asked, and
    ## every cell not yet on the card made there.
    func finish() -> SaBrushTipMask:
        if mask != null:
            return mask
        # A read never handed to a worker is made here, and one handed over is
        # waited for rather than made again.
        if not begun:
            begun = true
            _read_file()
        _wait()
        upload(1 << 62)
        mask = _assemble()
        _pipe = null
        _texels.clear()
        _cells.clear()
        return mask

    ## Waits for the worker and lets go of what it read, for a load nobody
    ## wants any more, whose file changed under it or whose cache is going.
    func abandon() -> void:
        _wait()
        _pipe = null
        _texels.clear()
        _cells.clear()

    ## Waits for the read.
    func _wait() -> void:
        if _task >= 0:
            WorkerThreadPool.wait_for_task_completion(_task)
            _task = -1
        _read = true

    ## A picture let go of while its worker runs waits for it first, because it
    ## is writing this object's own fields.
    func _notification(what: int) -> void:
        if what == NOTIFICATION_PREDELETE and _task >= 0:
            WorkerThreadPool.wait_for_task_completion(_task)

    ## The read's half: the file read, and a picture's texels built or a pipe's
    ## head and its cells' headers read and their texels kept as they stand. It
    ## touches no device and writes nothing but this picture's own fields, which
    ## the main thread reads only after waiting for the task.
    func _read_file() -> void:
        if not SaBrushTipMask.is_pipe_path(path):
            var tip := SaTipImage.load_from(path)
            if not tip.ok():
                _error = tip.error
                return
            _sizes.append(tip.size)
            _texels.append(SaTipImage.texels(tip))
            _depths.append(0)
            _colourful = tip.colourful
            return
        var file := FileAccess.get_file_as_bytes(path)
        if file.is_empty():
            _error = TranslationServer.translate("%s could not be read.") % path.get_file()
            return
        var head := SaGihPipe.read_head(file, path.get_file())
        if not head.error.is_empty():
            _error = head.error
            return
        # The first cell that refuses is the pipe's refusal, as
        # `SaGihPipe.read_bytes` has it.
        for index in head.cell_count:
            var tip := SaGihPipe.read_cell(file, head, index, path.get_file(), false)
            if not tip.ok():
                _error = tip.error
                return
            var depth := 4 if tip.colourful else 1
            var ends: int = head.offsets[index] + tip.bytes_read
            var texels := file.slice(ends - tip.size.x * tip.size.y * depth, ends)
            # A storage buffer is read a word at a time, so a grey cell whose
            # texels are not a whole number of words is padded to one.
            texels.resize((texels.size() + 3) & ~3)
            head.tips.append(tip)
            _sizes.append(tip.size)
            _texels.append(texels)
            _depths.append(depth)
            # Every cell of one pipe is one brush's animation, so the first
            # cell that carries colour is the answer for all of them: a pipe
            # whose cells disagree would be a stroke whose lightness row
            # applied to half of it.
            _colourful = _colourful or tip.colourful
        _pipe = head

    ## The mask the cells make, or one whose `error` says why there is none.
    ##
    ## The first cell of a pipe is [member SaBrushTipMask.texture] as well, so a
    ## pipe answers `has_image` and a `size` before any dab has chosen anything,
    ## and a `report` of a pipe never painted with says its first picture.
    func _assemble() -> SaBrushTipMask:
        var made := SaBrushTipMask.new()
        made.path = path
        if not _error.is_empty():
            made.error = _error
            return made
        if _upload_failed or _cells.is_empty():
            var shape := (
                TranslationServer.translate("%s loaded but a cell of it could not be uploaded to the GPU.")
                if _pipe != null
                else TranslationServer.translate("%s loaded but could not be uploaded to the GPU.")
            )
            made.error = shape % path.get_file()
            return made
        for cell: SaTexture in _cells:
            bytes += cell.bytes
        made.colourful = _colourful
        made.texture = _cells[0]
        made.size = _sizes[0]
        if _pipe != null:
            made.pipe = _pipe
            made.pipe_cells.assign(_cells)
            made.pipe_cell = 0
        return made
