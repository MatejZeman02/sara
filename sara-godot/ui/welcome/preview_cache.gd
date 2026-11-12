## The card pictures for files that carry none of their own.
##
## **Why a cache exists at all.** A card draws its picture out of the file itself,
## through `SaSadFile.read_preview`, and every `.sad` saved by a recent build
## carries one. A document written before that, and a picture opened as a document,
## carry none, so the grid is a grid of placeholders on the day a build is installed
## and stays one until each file is saved again. The one moment a document's pixels
## are cheap to look at is while the document is live: they are already in VRAM, so
## a small picture of them costs one readback of the export's kind, at a moment that
## is not a stroke.
##
## **Named from the path and the file's time.** A file saved again has a new
## modification time, so the picture taken before that save stops matching and
## is dropped rather than shown, and nothing has to be invalidated by hand. The
## folder holds no more entries than the recent list holds, because a picture is
## only ever looked at through a card that is still on that list.
##
## **The readback goes through export's own door.** `SaExport.take_preview`
## is what a painter's save writes the file's own preview through, so a cached
## picture and a previewed one are the same picture of the same document, and
## the readback check is unchanged: this file reads no texture back itself.
##
## **Taken on the card, read over the frames after.** The
## picture is copied on the card in the frame that asks for it and its cells
## come back a few a frame, [WelcomePreviewCache.Reading], so neither the close
## of a document nor the open of a picture holds a frame for the read. The
## copy is the document as it stood, so a document that closes before its
## picture lands still gets it.
class_name WelcomePreviewCache
extends RefCounted

## Where the pictures are kept, under the data folder rather than the settings
## folder: this is a cache of pictures and not a preference, and losing the
## folder costs a painter one readback per document and no setting at all.
## Under the data root, so a scratch run never prunes the painter's.
const FOLDER_NAME := "preview_cache"

## The longest side of a stored picture, in pixels. The same 256 a `.sad`'s own
## preview is written at, so a card draws the same size of picture whichever of
## the two it read.
const LONG_SIDE: int = 256

## The pictures still coming back from the card, by the path they are for.
static var _readings: Dictionary[String, Reading] = {}


## The folder the pictures are kept in.
static func folder() -> String:
    return SaDataRoot.path(FOLDER_NAME)


## The picture cached for the file at *path*, or null when there is none for the
## file as it stands.
##
## Null is the ordinary answer rather than a fault: a file never open in this
## build, one whose card has been pruned, and one saved since its picture was
## taken all answer it the same way, and the card draws its placeholder.
static func read(path: String) -> Image:
    var where := cache_path(path)
    if where.is_empty() or not FileAccess.file_exists(where):
        return null
    # From the bytes rather than from the path, which is the only shape Godot
    # gives WebP: `SaSadFile.read_preview` reads the file's own blob the same way.
    var picture := Image.new()
    if picture.load_webp_from_buffer(FileAccess.get_file_as_bytes(where)) != OK:
        return null
    return picture


## Where the picture for the file at *path* is kept: the folder, the path's own
## digest, and the second the file was last written at. Empty for a path with no
## file behind it, because a card for a file that is gone draws no picture.
##
## Public because it is the whole of the naming rule and a test asks it of a
## path rather than of a picture: the file's time is in the name, which is what
## makes yesterday's picture of a file saved today unreachable.
static func cache_path(path: String) -> String:
    if path.is_empty() or not FileAccess.file_exists(path):
        return ""
    var when := FileAccess.get_modified_time(path)
    return "%s/%s-%d.%s" % [folder(), path.md5_text(), when, SaNoteImage.EXTENSION]


## Stores *picture* as the picture of the file at *path*, and leaves the folder
## no larger than the recent list.
##
## False when there is nothing to store against: no file behind the path, no
## picture, or a folder that cannot be written. A caller that gets false has
## lost a thumbnail and nothing else, which is why this is not an error.
static func write(path: String, picture: Image) -> bool:
    if picture == null:
        return false
    var where := cache_path(path)
    if where.is_empty():
        return false
    # Before the write rather than after it, so the prune cannot take the entry
    # that was just written: a picture is taken while a document is live, and
    # the path reaches the recent list on the open that put it there.
    prune()
    if not DirAccess.dir_exists_absolute(folder()):
        DirAccess.make_dir_recursive_absolute(folder())
    return SaNoteImage.save(SaNoteImage.shrink(picture, LONG_SIDE), where) == OK


## Takes the picture of the document on *easel* as it closes, and says whether
## one was stored.
##
## **Why the close has a moment of its own.** The grid takes a picture when a
## document opens, but only a grid that exists: the welcome window is built on
## first ask, so a document opened and closed in a session with no grid would
## leave nothing to draw the next time. The close is the last moment its
## pixels are in VRAM, and one readback per closed document is the export's
## kind of read the rule against reading the canvas back allows.
## The quit is not a close here, because the quit is a prompt the painter can
## still cancel.
##
## **Only a document that is its file.** A modified document at a close is one
## whose painter chose Discard, since Save marks it saved before the close
## goes on, and a picture of paint that was thrown away would be a picture of a
## file that holds none of it. It keeps the picture it had, or its placeholder.
##
## **Only when the file changed since its last picture.** The name carries the
## file's time, so a file written since its picture was taken has none under
## its current name and gets one, and a file that has not changed keeps the
## picture it has and costs no readback. A file with a preview of its own, and
## a nameless document, have nothing to gain from the cache.
##
## True when a picture was taken, which is stored as it lands, see [method take].
static func keep_closing(easel: SaEasel) -> bool:
    if easel == null or easel.document == null or easel.output == null:
        return false
    var document := easel.document
    if document.modified or document.file_path.is_empty():
        return false
    var path := document.file_path
    if SaSadFile.read_preview(path) != null or read(path) != null:
        return false
    return take(path, easel)


## Takes the picture of the document on *easel* on the card for the file at
## *path*, and stores it once its cells are back, a few frames on. *landed* is
## called then, with the picture stored or not. True when a picture was taken,
## false when the easel has none to take or one for *path* is on its way.
##
## Off the main device, which hands no answer back as a frame is drawn, the
## picture is read at once and stored before this returns.
static func take(path: String, easel: SaEasel, landed: Callable = Callable()) -> bool:
    if path.is_empty() or reading(path):
        return false
    var shot := SaExport.take_preview(easel)
    if shot == null:
        return false
    if not Reading.on_the_main_device():
        var picture := shot.read_now()
        shot.let_go()
        write(path, picture)
        if landed.is_valid():
            landed.call()
        return picture != null
    _readings[path] = Reading.new(path, shot)
    if landed.is_valid():
        after(path, landed)
    _hear_the_loop(true)
    return true


## Whether a picture for the file at *path* is still coming back from the card.
static func reading(path: String) -> bool:
    return _readings.has(path)


## Calls *then* once the picture on its way for the file at *path* lands, for
## a card drawn before it did. False when none is on its way.
static func after(path: String, then: Callable) -> bool:
    var on_its_way: Reading = _readings.get(path)
    if on_its_way == null:
        return false
    on_its_way.tell(then)
    return true


## Runs every picture on its way to its end, for a suite, which cannot await a
## frame. True when none is left.
static func finish_all(longest_msec := 60000) -> bool:
    var until := Time.get_ticks_msec() + longest_msec
    while not _readings.is_empty() and Time.get_ticks_msec() < until:
        turn()
        OS.delay_usec(500)
    return _readings.is_empty()


## One turn of every picture on its way. The loop calls it each frame while
## one is.
static func turn() -> void:
    for path: String in _readings.keys():
        var each: Reading = _readings[path]
        if each.turn():
            _readings.erase(path)
    if _readings.is_empty():
        _hear_the_loop(false)


static func _hear_the_loop(hear: bool) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    var each := turn
    if hear and not tree.process_frame.is_connected(each):
        tree.process_frame.connect(each)
    elif not hear and tree.process_frame.is_connected(each):
        tree.process_frame.disconnect(each)


## The picture of the image file at *path*, read out of the file itself when the
## cache holds none, and stored so the next card costs no second decode. Null for
## a path that is not a picture Sara opens, or one no decoder reads.
##
## **Why the card reads the file.** A picture opened as a document is nameless and
## modified from its first frame, because there is no `.sad` behind it, so the
## close cannot tell a painter's Discard from a picture never touched and takes
## none. Its card would have a picture only when the welcome grid was built
## before the open. The file is what the card names, and a PNG or EXR is a picture already,
## so it is read here with no `RenderingDevice` and no readback at all. Paint that
## was saved went to a `.sad` of its own, which carries its own preview, and paint
## that was discarded never reached the file, so the file is the right picture in
## both cases.
##
## An EXR is linear light, as is any format whose registration says so, and a
## card is drawn as sRGB bytes, so its small copy
## is encoded to sRGB before it is stored. The values above one are clipped in
## the thumbnail only, never in the document.
static func of_picture_file(path: String) -> Image:
    var cached := read(path)
    if cached != null:
        return cached
    if not SaImageImport.is_image_path(path) or not FileAccess.file_exists(path):
        return null
    # The file's first bytes first, so a card for a file no decoder knows stays a
    # placeholder quietly rather than reporting a problem on every rebuild.
    var format := SaImageImport.sniff_format(path)
    if format.is_empty():
        return null
    var image := SaImageImport.read(path)
    if image == null or image.is_empty():
        return null
    var small := Image.new()
    small.copy_from(SaSadFile.shrink(image, LONG_SIDE))
    if SaImageImport.formats().find(StringName(format)).linear:
        _encode_srgb(small)
    if small.get_format() != Image.FORMAT_RGBA8:
        small.convert(Image.FORMAT_RGBA8)
    write(path, small)
    return small


## Encodes a small linear picture as sRGB in place, one pixel at a time, which
## is cheap at a thumbnail's size and happens once per file and file time.
static func _encode_srgb(small: Image) -> void:
    if small.is_compressed():
        small.decompress()
    if small.get_format() != Image.FORMAT_RGBAF:
        small.convert(Image.FORMAT_RGBAF)
    for y in small.get_height():
        for x in small.get_width():
            var linear := small.get_pixel(x, y)
            var alpha := linear.a
            var encoded := linear.clamp().linear_to_srgb()
            encoded.a = clampf(alpha, 0.0, 1.0)
            small.set_pixel(x, y, encoded)


## Drops every entry the recent list does not name.
##
## The bound: the folder holds one picture per recent path and
## no more, so a session that opens forty documents leaves ten pictures behind
## and not forty. An entry for a file that is gone leaves with the others, since
## the list stops naming it the moment the card is removed.
static func prune() -> void:
    var dir := DirAccess.open(folder())
    if dir == null:
        return
    var keep: Array[String] = []
    for path: Variant in SaSettings.recent_files():
        keep.append(cache_path(str(path)).get_file())
    for name in dir.get_files():
        if not keep.has(name):
            dir.remove(name)


## One picture on its way back from the card: its cells asked for a few a
## frame, as a save asks for its preview's (`SaSadSave`), put together and
## shrunk on a worker, and stored on the main thread, where the prune reads
## the recent list.
##
## The answers are methods of this object with an index bound, never a lambda
## (the pitfall "Quitting with a read of the card still owed aborts the
## engine's teardown"), and a scratch read in an answer is let go at the next
## turn rather than inside it.
class Reading:
    extends RefCounted

    ## The cells asked for in one frame, and owed at once, the save's numbers.
    const READS_A_FRAME := 16
    const READS_OWED := 48

    ## The file the picture is for, and what is called once it is stored.
    var path := ""
    var _landed: Array[Callable] = []
    ## The picture on the card, null once every cell has a scratch of its own.
    var shot: SaExport.PreviewShot = null
    var _size := Vector2i.ZERO
    var _cells: Array[Rect2i] = []
    var _format := 0
    var _bytes: Array[PackedByteArray] = []
    var _owed: Dictionary[int, SaTexture] = {}
    var _spent: Array[SaTexture] = []
    var _next := 0
    var _in := 0
    var _failed := false
    var _drawn_seen := -1
    var _task := -1
    var _picture: Image = null

    func _init(for_path: String, taken: SaExport.PreviewShot) -> void:
        path = for_path
        shot = taken
        _size = taken.size
        _cells = taken.cells
        _format = taken.picture.format
        _bytes.resize(_cells.size())

    ## Whether the card answers a read as frames are drawn, which only the
    ## main device does.
    static func on_the_main_device() -> bool:
        var rd := GlobalShaderCompiler.get_rd()
        return rd != null and rd == RenderingServer.get_rendering_device()

    ## One turn, and true once the picture is stored or given up on.
    func turn() -> bool:
        _spent.clear()
        if _task >= 0:
            if not WorkerThreadPool.is_task_completed(_task):
                return false
            WorkerThreadPool.wait_for_task_completion(_task)
            _task = -1
            _land()
            return true
        _ask()
        if _failed:
            _give_up()
            return true
        if _in == _cells.size():
            _task = WorkerThreadPool.add_task(_build, false, "the welcome picture of %s" % path.get_file())
            return false
        var drawn := Engine.get_frames_drawn()
        if not _owed.is_empty() and drawn == _drawn_seen:
            # The device answers only as a frame is drawn, and an idle window
            # draws none (the pitfall "A read asked of the main device answers
            # only as a frame is drawn, and an idle window draws none"). Never
            # a present.
            RenderingServer.force_draw(false, 0.0)
        _drawn_seen = Engine.get_frames_drawn()
        return false

    ## Asks for the next cells, a frame's share at most, and lets go of the
    ## copy on the card once every cell has a scratch.
    func _ask() -> void:
        var asked := 0
        while shot != null and not _failed and _next < _cells.size() and asked < READS_A_FRAME and _owed.size() < READS_OWED:
            var scratch := shot.cell(_next)
            if scratch == null or not SaExport.ask_texture_bytes(scratch, _back.bind(_next)):
                _failed = true
                break
            _owed[_next] = scratch
            _next += 1
            asked += 1
        if shot != null and _next >= _cells.size():
            shot.let_go()
            shot = null

    ## The device's answer for cell *index*.
    func _back(bytes: PackedByteArray, index: int) -> void:
        var scratch: SaTexture = _owed.get(index)
        _owed.erase(index)
        if scratch != null:
            _spent.append(scratch)
        if bytes.is_empty():
            _failed = true
            return
        _bytes[index] = bytes
        _in += 1

    ## The picture of the cells, shrunk to a card's size, on the worker.
    func _build() -> void:
        var whole := SaExport.PreviewShot.image_of(_size, _cells, _format, _bytes)
        _picture = SaSadFile.shrink(whole, WelcomePreviewCache.LONG_SIDE) if whole != null else null
        _bytes.clear()

    func _land() -> void:
        WelcomePreviewCache.write(path, _picture)
        _picture = null
        _tell()

    func _give_up() -> void:
        if shot != null:
            shot.let_go()
        shot = null
        _bytes.clear()
        _tell()

    ## Calls *then* once the picture is stored or given up on, once however
    ## often it is asked.
    func tell(then: Callable) -> void:
        if not _landed.has(then):
            _landed.append(then)

    ## Calls every asker still there that waited for the picture.
    func _tell() -> void:
        for then in _landed:
            if then.is_valid():
                then.call()
        _landed.clear()
