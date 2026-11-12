## A PNG export over frames, so the painter goes on painting while the file is
## written. File > Export and the door's `export` step write a PNG this way.
##
## **Why.** An export that read the picture back and wrote it in the frame it
## was asked in held that frame for over a second on a large painting: about half
## a second asking the card which colour a save would round
## (`SaSadSnapshot.round_live`), and 0.42 s in the PNG encoder for a 2160 by
## 720 picture. Every frame of an export is to stay under a tenth of a second.
##
## **How.** Each frame the queue turns, the oldest export takes one step:
## the rounding, `SaSadSnapshot.round_live_in_turns`, a share of the card's
## pass a turn and the rounding and the redraw once its words are in, then
## the composite of whatever the rounding marked in a turn of its own, then
## the read of the picture off the card, which hard rule 1 keeps on the main
## thread, and last the narrowing, the encoder, both splices and the write on
## a worker, as `SaExportTargets` writes a target. The picture is the one
## `SaExport.export_png` reads, the same calls with the same options, so the
## file is the same to the byte.
##
## **What the painter does meanwhile is in it.** The picture is read once the
## rounding has ended, so a stroke laid between the ask and the read is in the
## file, as it would be in an export asked for a moment later. The rounding
## lists the textures again when the history moved before its words came
## back, so what the file holds is rounded as a save would round it.
##
## **One at a time.** An export asked for while another runs waits in the
## queue behind it. [method finish_all] drives every export to its end without
## a frame, for a suite and for a quit, and [method after_all] runs a callable
## once none is left, which is how a quit waits for one.
class_name SaExportInTurns
extends RefCounted

## The exports not yet whole, the oldest first.
static var _queue: Array[SaExportInTurns] = []
## What waits for every export to be whole.
static var _after: Array[Callable] = []

## The file written.
var path: String
## How the export ended, read once [member ended] says so.
var error: Error = OK
## Whether the file is whole, or failed.
var ended := false

var _easel: SaEasel
var _options: SaImageFormat.Write
var _then: Callable
var _rounding: SaSadSnapshot.LiveRounding.InTurns = null
var _composited := false
var _picture: Image = null
var _gamut: SaGamut = null
var _metadata: SaExportMetadata = null
var _task := -1
var _ticket := -1
var _began_usec := 0


func _init(easel: SaEasel, to: String, options: SaImageFormat.Write, then: Callable) -> void:
    _easel = easel
    path = to
    _options = options
    _then = then
    _began_usec = Time.get_ticks_usec()


## Writes *easel* to *path* as a PNG under *options*, over frames, after any
## export already running, and calls *then* with the error once the file is
## whole or has failed. A PNG format's writer over turns, which
## `SaImageFormat.write_picture_in_turns` calls.
static func png(easel: SaEasel, to: String, options: SaImageFormat.Write, then := Callable()) -> SaExportInTurns:
    var made := SaExportInTurns.new(easel, to, options, then)
    _queue.append(made)
    _hear_the_loop(true)
    if _queue.size() == 1:
        made._begin()
    return made


## Whether an export is running or waiting.
static func running() -> bool:
    return not _queue.is_empty()


## Runs *then* once every export has ended, at once when none runs.
static func after_all(then: Callable) -> void:
    if _queue.is_empty():
        then.call()
        return
    _after.append(then)


## Drives every export to its end without a frame. False when a worker is
## still writing after *longest_msec*.
static func finish_all(longest_msec := 60000) -> bool:
    var until := Time.get_ticks_msec() + longest_msec
    for waiting: SaExportInTurns in _queue.duplicate():
        waiting._hurry()
    turn()
    while not _queue.is_empty() and Time.get_ticks_msec() < until:
        OS.delay_usec(500)
        turn()
    return _queue.is_empty()


## One turn of the queue, once a frame while it holds an export: the oldest
## takes a step, and one that has ended calls its `then` and lets the next
## begin in the same turn.
static func turn() -> void:
    while not _queue.is_empty() and _queue[0]._step():
        var whole: SaExportInTurns = _queue.pop_front()
        whole._end()
        if not _queue.is_empty():
            _queue[0]._begin()
            break
    if not _queue.is_empty():
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


## The first step, in the frame the export comes to the front: a file still
## opening is read whole, or the export draws its holes, and the card is asked
## which colour a save would round.
func _begin() -> void:
    if _ticket >= 0 or ended:
        return
    _ticket = SaTrail.enter("the export of %s" % path.get_file())
    if not is_instance_valid(_easel) or _easel.output == null or _easel.document == null:
        error = ERR_INVALID_PARAMETER
        return
    SaSadFile.finish_opening(_easel.document)
    _rounding = SaSadSnapshot.round_live_in_turns(_easel.document)


## One step of this export, and whether it has ended.
func _step() -> bool:
    if _ticket < 0:
        _begin()
    if error != OK or ended:
        return true
    if not is_instance_valid(_easel) or _easel.document == null:
        error = ERR_UNAVAILABLE
        return true
    if not _rounding.done:
        _rounding.turn()
        return false
    if not _composited:
        _composited = true
        # What the rounding marked is composited in a turn of its own, since the
        # read comes after it.
        if _rounding.moved > 0:
            _easel.process_pending_composite()
            return false
    if _picture == null and _task < 0:
        _read()
        return error != OK
    if _task >= 0 and not WorkerThreadPool.is_task_completed(_task):
        return false
    if _task >= 0:
        WorkerThreadPool.wait_for_task_completion(_task)
        _task = -1
    _picture = null
    return true


## Reads the picture off the card as `SaExport.export_png` does, and hands the
## encode and the write to a worker.
func _read() -> void:
    SaLocalView.flush_whole(_easel)
    var space := _easel.document.color_space
    var relief := SaExport.relief_of(_easel, _options.relief)
    var tonemap := SaExport.tonemap_of(_easel, _options.rolloff, _options.stops)
    var bits := _options.depth
    if bits != 8 and bits != 16:
        push_error("SaExportInTurns: a PNG holds 8 or 16 bits a channel, not %d" % bits)
        error = ERR_INVALID_PARAMETER
        return
    _picture = SaExport.png_picture(_easel.output, space, bits, tonemap, _options.mapping, relief, _options.dither)
    if _picture == null:
        error = ERR_CANT_ACQUIRE_RESOURCE
        return
    # Everything the worker reads that a setting or a lazy table would
    # otherwise give it, taken here, so the worker touches no setting and builds
    # no shared table.
    _gamut = SaExportGamut.gamut_named(space)
    _metadata = SaExportMetadata.now()
    SaExportGamut.crc32(PackedByteArray())
    _task = WorkerThreadPool.add_task(_write, false, "Sara exports %s" % path.get_file())


func _write() -> void:
    error = SaExport.write_bytes(path, SaExport.png_of_picture(_picture, _options.depth, _gamut, _metadata), "export_png")


## Ends every step left in this frame, for [method finish_all].
func _hurry() -> void:
    _begin()
    if _rounding != null and is_instance_valid(_easel):
        _rounding.finish()


## Says how the export ended on the trail, gives its place on the trail back
## and calls the caller's `then`.
func _end() -> void:
    ended = true
    var spent := roundi((Time.get_ticks_usec() - _began_usec) / 1000.0)
    if error == OK:
        var rounded := _rounding.moved if _rounding != null else 0
        SaTrail.mark("wrote the export %s over frames in %d ms, %d textures rounded" % [path.get_file(), spent, rounded])
    else:
        SaTrail.mark("the export %s failed (%s)" % [path.get_file(), error_string(error)])
    if _ticket >= 0:
        SaTrail.give_back(_ticket)
    if _then.is_valid():
        _then.call(error)
