## The files a document is exported to on every save, its export targets, which
## File > Export Target names: a game's art painted in Sara lands in the
## game's folder each time the painter saves, and the game's editor reimports it.
##
## **Where they are kept.** In the document's module data under [constant KEY],
## so the `.sad` header carries them through its `modules` object and
## `core/sad-file` never learns of them. Each target's path is kept relative
## to the folder of the `.sad`, so a game folder moved whole with the `.sad`
## inside it keeps working. A document never saved keeps an absolute path,
## and [method rebase] makes it relative at the first save, as it does again
## for a Save As into another folder.
##
## **How one is written.** As File > Export writes the format with the same
## options, because a target is a remembered File > Export. It keeps every
## option that dialog offers a PNG: the depth, Include impasto lighting, the
## dither and the highlight rolloff, and the gamut mapping Preferences names.
## A target starts at the dialog's own defaults, the lighting on, the dither
## off and the rolloff where View > Tonemap Highlights is. A target kept before
## these options named only its path and depth, so it takes those defaults for
## the rest and its next write lights the paper and the impasto in.
##
## **Off the main thread.** A PNG is read back from the card in the frame the
## save ended in, the one step hard rule 1 keeps on the main thread, and
## [SaExport]'s `png_picture` is that step. The narrowing, the encoder, both
## splices and the write are `png_of_picture` and `write_bytes`, which touch no
## device and no node, and a worker runs them while the window draws on, rather
## than the encoder holding the window for many seconds over a 16-bit PNG of a
## 4096 by 4096 picture. A format with no such split is written whole through
## its own writer in the registry.
##
## **One save's files at a time.** The saves whose targets are still being
## written wait in a queue, oldest first, and one file is written at a time, so
## two saves in a row never write one file at once. A save's `then`, the quit
## after a Save, runs once its files are whole, and [method after_writes] is
## how `SaSadFile.after_saves` waits for them too.
class_name SaExportTargets
extends RefCounted

## The key of the document's module data the targets are kept under.
const KEY := "export_targets"

## The saves whose files are still being written, the oldest first.
static var _batches: Array[Batch] = []
## What waits for every file to be whole, run once the queue is empty.
static var _after: Array[Callable] = []


## One target: the file, the format's id in the registry, the depth and the
## options File > Export offers beside it.
class Target:
    extends RefCounted

    ## The file written, an absolute path once read off a document.
    var path: String
    ## The id `SaImageFormatRegistry` knows the format by, `png`.
    var format: StringName
    ## The bits a channel, 8 or 16 for a PNG.
    var depth: int
    ## Whether the relief the view shows, the paper's tooth and the impasto,
    ## is lit into the picture, the export dialog's Include impasto lighting.
    var relief: bool
    ## Whether an eight-bit file is rounded through the dither.
    var dither: bool
    ## Whether a value above 1 is rolled off rather than clipped.
    var rolloff: bool

    func _init(
        at: String, format_id: StringName = &"png", bits: int = 8, lit: bool = true, dithered: bool = false, rolled: bool = false
    ) -> void:
        path = at
        format = format_id
        depth = bits
        relief = lit
        dither = dithered
        rolloff = rolled

    ## This target with the option called *key* at *value*, `depth`,
    ## `relief`, `dither` or `rolloff`, the rest as they are.
    func changed(key: StringName, value: Variant) -> Target:
        var made := Target.new(path, format, depth, relief, dither, rolloff)
        match key:
            &"depth":
                made.depth = type_convert(value, TYPE_INT)
            &"relief":
                made.relief = type_convert(value, TYPE_BOOL)
            &"dither":
                made.dither = type_convert(value, TYPE_BOOL)
            &"rolloff":
                made.rolloff = type_convert(value, TYPE_BOOL)
        return made

    ## The options File > Export writes the format with when its rows stand
    ## where this target's do: the rolloff and the mapping only where the depth
    ## clips, the dither only where the format offers it at this depth.
    func options() -> SaImageFormat.Write:
        var shown := SaImageFormatRegistry.shared().find(format)
        var clips := shown == null or shown.clips(depth)
        var chosen := SaImageFormat.Write.new()
        chosen.depth = depth
        chosen.rolloff = rolloff and clips
        chosen.mapping = SaGamutMapping.for_export(SaSettings.gamut_mapping, not clips)
        chosen.relief = relief and (shown == null or shown.rows.has(SaImageFormat.ROW_RELIEF))
        chosen.dither = dither and depth == 8 and (shown == null or shown.rows.has(SaImageFormat.ROW_DITHER))
        return chosen

    ## Writes the file off *easel* through the format's writer, which is what
    ## File > Export calls, all of it on this thread. A format with no split of
    ## its own is written this way, and a PNG goes through [Writing] instead.
    func write(easel: SaEasel) -> Error:
        var shown := SaImageFormatRegistry.shared().find(format)
        if shown == null or not shown.writer.is_valid():
            return ERR_UNAVAILABLE
        return shown.write_picture(easel, path, options())


## The targets *document* names, each path made absolute against the folder of
## its `.sad`.
static func of(document: SaDocument) -> Array[Target]:
    var out: Array[Target] = []
    if document == null:
        return out
    var kept: Variant = document.module_data.get(KEY)
    if not kept is Array:
        return out
    for entry: Variant in kept:
        if not entry is Dictionary:
            continue
        var fields: Dictionary = entry
        if str(fields.get("path", "")).is_empty():
            continue
        var at := resolved(str(fields["path"]), document.file_path)
        out.append(
            Target.new(
                at,
                StringName(str(fields.get("format", "png"))),
                SaTyped.int_at(fields, "depth", 8),
                SaTyped.bool_at(fields, "relief", true),
                SaTyped.bool_at(fields, "dither", false),
                SaTyped.bool_at(fields, "rolloff", starting_rolloff())
            )
        )
    return out


## Where a new target's rolloff starts, where File > Export's check starts:
## on while View > Tonemap Highlights is.
static func starting_rolloff() -> bool:
    return SaSettings.tonemap_highlights


## Makes *targets* the ones *document* names, relative to the folder of its
## `.sad` where it has one.
static func name_all(document: SaDocument, targets: Array[Target]) -> void:
    _keep(document, targets, document.file_path)


## Keeps *document*'s targets relative to *sad_path*, the file a save is about
## to write, so a Save As into another folder writes the same files the last save wrote.
static func rebase(document: SaDocument, sad_path: String) -> void:
    if document == null or not document.module_data.has(KEY):
        return
    _keep(document, of(document), sad_path)


static func _keep(document: SaDocument, targets: Array[Target], sad_path: String) -> void:
    if targets.is_empty():
        document.module_data.erase(KEY)
        return
    var kept: Array = []
    for target: Target in targets:
        (
            kept
            . append(
                {
                    "path": relative(target.path, sad_path),
                    "format": String(target.format),
                    "depth": target.depth,
                    "relief": target.relief,
                    "dither": target.dither,
                    "rolloff": target.rolloff,
                }
            )
        )
    document.module_data[KEY] = kept


## One target's file on its way to disk: the picture read back when this is
## made, and the encode and the write on a worker once [method start] is called.
class Writing:
    extends RefCounted

    ## The file written.
    var path: String
    ## How the write ended, set by the worker and read once [method ended].
    var error: Error = OK
    ## The milliseconds the read back held the frame, zero for a format
    ## written whole.
    var read_msec := 0
    var _depth := 8
    var _picture: Image = null
    var _gamut: SaGamut = null
    var _metadata: SaExportMetadata = null
    var _begun := false
    var _task := -1

    ## Reads *target*'s picture off *easel* now, on the main thread, or writes
    ## the whole file now for a format with no split of its own.
    func _init(target: Target, easel: SaEasel) -> void:
        path = target.path
        _depth = target.depth
        if easel == null or easel.output == null:
            error = ERR_UNAVAILABLE
            return
        if target.format != &"png":
            error = target.write(easel)
            return
        var began := Time.get_ticks_usec()
        SaExport.flush_for_export(easel)
        var space := easel.document.color_space if easel.document != null else null
        # The relief, the rolloff and the dither as `SaExport.export_png` takes
        # them, so the pixels are the ones File > Export writes.
        var chosen := target.options()
        var relief := SaExport.relief_of(easel, chosen.relief)
        var tonemap := SaExport.tonemap_of(easel, chosen.rolloff, chosen.stops)
        _picture = SaExport.png_picture(easel.output, space, _depth, tonemap, chosen.mapping, relief, chosen.dither)
        read_msec = roundi((Time.get_ticks_usec() - began) / 1000.0)
        SaTrail.mark("the export target %s read back from the card in %d ms" % [path.get_file(), read_msec])
        if _picture == null:
            error = ERR_CANT_ACQUIRE_RESOURCE
            return
        # Everything the worker reads that settings or a lazy table would
        # otherwise give it, taken here, so the worker touches no setting and
        # builds no shared table.
        _gamut = SaExportGamut.gamut_named(space)
        _metadata = SaExportMetadata.now()
        SaExportGamut.crc32(PackedByteArray())

    ## Hands the encode and the write to a worker, once.
    func start() -> void:
        if _begun:
            return
        _begun = true
        if _picture != null:
            _task = WorkerThreadPool.add_task(_write, false, "Sara writes the export target %s" % path.get_file())

    ## Whether the file is whole, or failed. False before [method start].
    func ended() -> bool:
        return _begun and (_task < 0 or WorkerThreadPool.is_task_completed(_task))

    ## Waits for the worker, which has ended once [method ended] said so, and
    ## lets the picture go.
    func finish() -> void:
        start()
        if _task >= 0:
            WorkerThreadPool.wait_for_task_completion(_task)
            _task = -1
        _picture = null

    func _write() -> void:
        error = SaExport.write_bytes(path, SaExport.png_of_picture(_picture, _depth, _gamut, _metadata), "export_png")


## The files one save writes, in the order the document names them, and what
## runs once they are whole.
class Batch:
    extends RefCounted

    ## The `.sad` the save wrote, which the status line names.
    var sad_path: String
    ## Runs once every file has ended, the quit after a Save.
    var then: Callable
    var writings: Array[Writing] = []
    var _next := 0

    func _init(saved: String, files: Array[Writing], after: Callable) -> void:
        sad_path = saved
        writings = files
        then = after

    ## Starts the next file once the one before it is whole, and answers
    ## whether every file has ended.
    func turn() -> bool:
        while _next < writings.size():
            var writing := writings[_next]
            writing.start()
            if not writing.ended():
                return false
            writing.finish()
            _next += 1
        return true

    ## Says on the status line which files failed, and runs
    ## [member then].
    func end() -> void:
        var failed := PackedStringArray()
        for writing: Writing in writings:
            if writing.error == OK:
                SaTrail.stage("wrote the export target %s" % writing.path)
            else:
                SaTrail.stage("the export target %s failed (%s)" % [writing.path, error_string(writing.error)])
                failed.append(writing.path)
        if not failed.is_empty():
            var said := TranslationServer.translate("Saved %s, but could not write the export target %s")
            EventBus.save_progressed.emit(said % [sad_path.get_file(), ", ".join(failed)])
        if then.is_valid():
            then.call()


## Writes every target of *document* off the easel holding it, after a save of
## *sad_path* ended, and runs *then* once each file is whole. Each picture is
## read back now, and encoded and written on a worker after the files of any
## save before this one. The status line names each target that failed.
static func write_after_save(document: SaDocument, sad_path: String, then := Callable()) -> void:
    var easel := document.get_parent() as SaEasel if document != null else null
    var files: Array[Writing] = []
    for target: Target in of(document):
        files.append(Writing.new(target, easel))
    var batch := Batch.new(sad_path, files, then)
    if files.is_empty() and _batches.is_empty():
        batch.end()
        return
    _batches.append(batch)
    _hear_the_loop(true)
    turn()


## Whether a save's files are still being written or waiting to be.
static func writing() -> bool:
    return not _batches.is_empty()


## Runs *then* once every file a save started is whole, at once when none is
## being written. *why* is what waits, and the status line says so.
static func after_writes(then: Callable, why: String) -> void:
    if _batches.is_empty():
        then.call()
        return
    SaTrail.stage("%s waits for the export targets to be written" % why)
    EventBus.save_progressed.emit(TranslationServer.translate("Saving, %s once the file is written") % why)
    _after.append(then)


## Writes every file still owed without a frame, for a suite and for a caller
## that has to have them before it goes on. False when one is still being
## written after *longest_msec*.
static func finish_writes(longest_msec := 60000) -> bool:
    var until := Time.get_ticks_msec() + longest_msec
    turn()
    while not _batches.is_empty() and Time.get_ticks_msec() < until:
        OS.delay_usec(500)
        turn()
    return _batches.is_empty()


## One turn of the queue, once a frame while it holds a save: the files of the
## oldest save go on, and a save whose files have all ended says so and runs
## its `then`.
static func turn() -> void:
    while not _batches.is_empty() and _batches[0].turn():
        var ended: Batch = _batches.pop_front()
        ended.end()
    if not _batches.is_empty():
        return
    _hear_the_loop(false)
    var waiting := _after.duplicate()
    _after.clear()
    for then: Callable in waiting:
        if then.is_valid():
            then.call()


static func _hear_the_loop(hear: bool) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    var each := turn
    if hear and not tree.process_frame.is_connected(each):
        tree.process_frame.connect(each)
    elif not hear and tree.process_frame.is_connected(each):
        tree.process_frame.disconnect(each)


## *path* as written from the folder of *sad_path*, or *path* itself when there
## is no `.sad` yet or the two share no root.
static func relative(path: String, sad_path: String) -> String:
    if sad_path.is_empty() or not path.is_absolute_path():
        return path
    var from := sad_path.get_base_dir().simplify_path().split("/", false)
    var to := path.simplify_path().split("/", false)
    if path.begins_with("/") != sad_path.begins_with("/") or _drive(from) != _drive(to):
        return path
    var shared := 0
    while shared < from.size() and shared < to.size() - 1 and from[shared] == to[shared]:
        shared += 1
    var parts := PackedStringArray()
    for _up in range(shared, from.size()):
        parts.append("..")
    parts.append_array(to.slice(shared))
    return "/".join(parts)


## The drive a Windows path starts at, `C:`, or empty for any other path.
static func _drive(parts: PackedStringArray) -> String:
    return parts[0].to_lower() if not parts.is_empty() and parts[0].ends_with(":") else ""


## *kept* read from the folder of *sad_path*, or as it stands when absolute.
static func resolved(kept: String, sad_path: String) -> String:
    if kept.is_absolute_path() or sad_path.is_empty():
        return kept
    return sad_path.get_base_dir().path_join(kept).simplify_path()
