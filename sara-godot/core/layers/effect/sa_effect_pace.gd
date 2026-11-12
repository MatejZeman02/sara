## How much of a stroke's landing one frame refreshes the effect layers over,
## and the rest of the same refresh carried to the frames after it.
##
## [SaEffectLayer] waits out a live stroke and refreshes every region it
## dirtied once the stroke commits. On a large painting, whose mirrors are
## effect layers, that refresh wrote 131 chunks of eight mirrors for 72 ms
## after a fast 4 px stroke, in the commit's frame. Its cost is in those
## chunks and not in the regions the stroke dirtied: one region of the twelve
## spread through the mirrors' records to the same chunks the twelve did, so a
## refresh cut by region wrote them all again every frame.
##
## So a landing's refresh is a [Job] that stops between two chunks once
## [constant FRAME_USEC] is spent and goes on in the next frame where it
## stopped, with what it found and spread kept, until it ends. What it owes
## the walk, the commit's regions and every chunk it wrote, is gathered once a
## grid position and walked [constant WALK_CHUNKS] chunks a frame, so the
## picture after its last frame is the one a refresh in one frame draws. The
## composite backlog keeps the frames coming: the job holds back one small
## region of the frame's walk, which brings the easel's next frame, as a
## region the budget held does.
##
## An open's refresh is a landing too: the effect layers wait while it fills
## in its chunks, and refresh the whole view once the last is in, which on the
## large painting held a frame for over a second.
##
## Every refresh in a frame given a backlog is paced, which the easel's own
## frame is and a reader's flush is not: a reader finishes the job first. Only
## a landing's first frame waits, [method run] says why, and any other walks
## what it wrote in the frame it started. A backlog that holds nothing, because the root's filters read their
## neighbours, finishes it too.
class_name SaEffectPace
extends RefCounted

## What one frame of a landing's refresh may cost, in microseconds, and how
## many of the chunks it owes the walk one frame draws. A large painting's
## frames after a stroke drew the window for 15 to 25 ms while the GPU caught
## up with ten chunks walked, and walked a chunk for about a millisecond, so
## a frame of both stays under the 50 ms a painter feels. At 10 ms and ten
## chunks a fifth of the sweep's takes still went over it by up to 9 ms, at
## 6 ms and six chunks two of twelve by up to 13 ms, and at 4 ms and four
## three of twelve by up to 9 ms, those frames drawing the window for 12 to
## 33 ms beside a refresh of 8 to 12 ms.
const FRAME_USEC := 4000
const WALK_CHUNKS := 4

## The side of the region held back to bring the next frame, in pixels: one
## texel, a walk of next to nothing.
const KEEP := Vector2i(1, 1)

## What one frame of a landing's refresh may cost here, [constant FRAME_USEC]
## unless a suite sets it to nought, which stops every frame after its first
## chunk.
var frame_usec := FRAME_USEC

## The refresh not finished yet, or null.
var _job: Job = null
## Whether a stroke's regions waited and are not all refreshed yet.
var _landing := false
## The grid positions held back to bring this frame, read as a set, which the
## next frame's refresh does not take as a change.
var _kept: Dictionary[Vector2i, bool] = {}


## Notes that a live stroke held regions back, or that an open is filling,
## so the refresh after it is a landing.
func waited() -> void:
    _landing = true


## Notes that the landing is refreshed whole.
func landed() -> void:
    _landing = false


## Whether a refresh of *document* goes on from an earlier frame. A job of
## another document, or one holding a layer since freed, goes no further, and
## what it owed the walk goes to *dirty*.
func running(document: SaDocument, dirty: Dictionary[Vector2i, Rect2i]) -> bool:
    if _job != null and _job.document != document:
        _job = null
    if _job != null and _job.stale():
        abort(dirty)
    return _job != null


## Whether *grid_pos* came into the walk only because this pace held it back.
func kept(grid_pos: Vector2i) -> bool:
    return _kept.has(grid_pos)


## Drops the refresh that goes on, ends the landing, hands what it owed the
## walk to *dirty*, and answers the regions it was started over, for a refresh
## that takes them whole at once. A chunk it wrote already is written again,
## which costs time and changes nothing.
func abort(dirty: Dictionary[Vector2i, Rect2i]) -> Dictionary[Vector2i, Rect2i]:
    var regions: Dictionary[Vector2i, Rect2i] = {}
    if _job != null:
        regions = _job.regions
        _job.release(dirty, -1)
    _job = null
    _landing = false
    _kept.clear()
    return regions


## One frame of a refresh, *job* when it starts here and the one that goes on
## when null, by *effect* through *compositor*, adding to *dirty* what the
## walk draws. Answers the job once it has ended, and null while it goes on
## into the next frame.
##
## **The frame the stroke lands in only starts it.** That frame carries the
## commit's own work, so its refresh, the search for what the change reached,
## 11 ms on a large painting, and its walk move into the job, and the picture
## it shows is the live stroke's last, which is the same paint.
func run(
    effect: SaEffectLayer,
    compositor: SaCompositor,
    job: Job,
    dirty: Dictionary[Vector2i, Rect2i],
    held: SaCompositeBacklog,
    room := -1,
) -> Job:
    if job != null:
        _job = job
    if _job == null:
        return null
    var paced := held != null
    var near: Array[Vector2i] = []
    near.assign(dirty.keys())
    near.append_array(_kept.keys())
    var walked := dirty.size()
    for grid_pos: Vector2i in _kept:
        walked -= 1 if dirty.has(grid_pos) else 0
    _kept.clear()
    if paced and job != null:
        _job.paced = true
    if paced and job != null and _landing:
        for grid_pos: Vector2i in dirty:
            SaCompositeBacklog.merge(_job.walk, grid_pos, dirty[grid_pos])
        dirty.clear()
    elif paced and room == 0:
        pass
    elif paced:
        _job.step(effect, compositor, dirty, Time.get_ticks_usec() + frame_usec)
        _job.release(dirty, owed_a_frame(room, walked))
    else:
        _job.step(effect, compositor, dirty, -1)
        _job.release(dirty, -1)
    if not _job.ended() and not _keep(near, held):
        _job.step(effect, compositor, dirty, -1)
        _job.release(dirty, -1)
    if not _job.ended():
        return null
    var ended := _job
    _job = null
    return ended


## How many of the chunks the job owes the walk go into a frame whose walk
## holds *walked* chunks already, the one this pace held back left out, when
## the composite budget pays for *room*, below nought for any: what the
## budget leaves, [constant WALK_CHUNKS] at most, and one when the walk holds
## nothing else, so the job always moves. A *room* of nought is a frame the
## budget gave to the fold, which [method run] leaves the job's search out of
## as well. Both are walked in the same frame,
## and a season's switch of a large painting walked the budget's one chunk and
## four of these for 68 ms a frame.
static func owed_a_frame(room: int, walked: int) -> int:
    if room < 0:
        return WALK_CHUNKS
    if walked <= 0:
        return clampi(room, 1, WALK_CHUNKS)
    return clampi(room - walked, 0, WALK_CHUNKS)


## Holds back a region at a grid position of *near*, the frame's walk, or of
## the job's own regions when the frame walks nothing, as an open's last frame
## may whose regions waited while it filled, so the easel composites again in
## the next frame, and answers whether the backlog took it. When it did not,
## the job is finished in this frame.
func _keep(near: Array[Vector2i], held: SaCompositeBacklog) -> bool:
    if near.is_empty():
        near.assign(_job.regions.keys())
    if held == null or near.is_empty():
        return false
    var at := near[0]
    var region: Dictionary[Vector2i, Rect2i] = {at: Rect2i(Vector2i.ZERO, KEEP)}
    held.hold(region, [at] as Array[Vector2i], _job.document)
    if region.has(at):
        return false
    _kept[at] = true
    return true


## A refresh of the effect layers over regions, in runs of effects that read
## one input, each run chunk by chunk, which can stop between two chunks and
## go on from there. [SaEffectLayer] fills it and writes it, through
## [method SaEffectLayer.share_over], [method SaEffectLayer.share_open],
## [method SaEffectLayer.share_cell] and [method SaEffectLayer.share_close].
class Job:
    extends RefCounted

    ## No compositor is held, which holds the effect layer holding this.
    var document: SaDocument
    ## The regions the refresh was started over.
    var regions: Dictionary[Vector2i, Rect2i] = {}
    ## Effect -> grid position -> Rect2i, what the change reached.
    var reached: Dictionary[SaLayer, Dictionary] = {}
    ## The runs of effects, in the order they are refreshed.
    var shares: Array[Array] = []
    ## The run [member over] holds is the one before this index.
    var at := 0
    var renderer: SaTreeRender
    var reaches: SaEffectLayer.Reaches
    ## Layer -> the effects reading it.
    var readers: Dictionary[SaLayer, Array] = {}
    ## Effect -> grid position -> Rect2i, what refreshes before it spread.
    var spread: Dictionary[SaLayer, Dictionary] = {}
    ## The open run: effect -> grid position -> Rect2i.
    var over: Dictionary[SaLayer, Dictionary] = {}
    ## The open run's input, whether it is read as paint alone, and where it
    ## shows something.
    var source: SaLayer
    var alone := false
    var reach: Dictionary[Vector2i, bool] = {}
    ## Effect -> grid position -> Rect2i, the chunks the open run made and
    ## the chunks it wrote.
    var made: Dictionary[SaLayer, Dictionary] = {}
    var wrote: Dictionary[SaLayer, Dictionary] = {}
    ## The open run's chunks, and the next to write.
    var cells: Array[Vector2i] = []
    var cell := 0
    ## Whether a run of effects a fold holds moved.
    var folded := false
    ## Whether it is paced, so what it owes the walk gathers in [member walk].
    var paced := false
    ## Grid position -> Rect2i, what a paced job owes the walk.
    var walk: Dictionary[Vector2i, Rect2i] = {}
    ## Whether every run is written.
    var done := false
    ## Whether [method SaEffectLayer.fill] found what the regions reach.
    var _filled := false
    ## Whether a run is open.
    var _open := false

    ## The middle of the grid positions the refresh was started over, which
    ## its chunks are written and walked outwards from. An open's regions are
    ## the view's, the backlog holding the rest, so this is the view's middle.
    var middle := Vector2.ZERO

    func _init(of: SaDocument, over_regions: Dictionary[Vector2i, Rect2i]) -> void:
        document = of
        regions = over_regions
        if regions.is_empty():
            return
        var first: Vector2i = regions.keys()[0]
        var box := Rect2i(first, Vector2i.ONE)
        for grid_pos: Vector2i in regions:
            box = box.expand(grid_pos).expand(grid_pos + Vector2i.ONE)
        middle = Vector2(box.position) + Vector2(box.size) / 2.0

    ## Sorts *positions*, grid positions, from [member middle] outwards, the
    ## nearest chunk first and a tie by row and then column.
    func outwards(positions: Array[Vector2i]) -> void:
        var from := middle
        positions.sort_custom(
            func(a: Vector2i, b: Vector2i) -> bool:
                var da := (Vector2(a) + Vector2(0.5, 0.5)).distance_squared_to(from)
                var db := (Vector2(b) + Vector2(0.5, 0.5)).distance_squared_to(from)
                if da != db:
                    return da < db
                return a.y < b.y or (a.y == b.y and a.x < b.x)
        )

    ## Writes on from where the last frame stopped, adding to *dirty* what the
    ## walk draws, until every run is written or *ends*, a tick in
    ## microseconds, is past, never before one piece of work, the search for
    ## what the regions reach, a chunk, or the close of a run, and with *ends*
    ## below nought until the end. Answers whether every run is written.
    func step(effect: SaEffectLayer, compositor: SaCompositor, dirty: Dictionary[Vector2i, Rect2i], ends: int) -> bool:
        var moved := false
        if not _filled:
            _filled = true
            var traced := SaFrameTrace.now()
            effect.fill(self, compositor)
            SaFrameTrace.spent("effect search", traced)
            moved = true
        while not done:
            if not _open:
                if at >= shares.size():
                    done = true
                    break
                if moved and _past(ends):
                    return false
                over = effect.share_over(self, shares[at])
                at += 1
                if over.is_empty():
                    continue
                effect.share_open(self, compositor)
                _open = true
            while cell < cells.size():
                if moved and _past(ends):
                    return false
                var written := SaFrameTrace.now()
                effect.share_cell(self, compositor, cells[cell])
                SaFrameTrace.spent("effect chunk", written)
                cell += 1
                moved = true
            effect.share_close(self, dirty)
            _open = false
            moved = true
        return true

    ## Whether *ends*, a tick in microseconds, is past, never when below
    ## nought.
    static func _past(ends: int) -> bool:
        return ends >= 0 and Time.get_ticks_usec() >= ends

    ## Whether a layer this job holds was freed, as an open's reading frees
    ## the stack it replaces. Read untyped, since a typed variable refuses a
    ## freed instance.
    func stale() -> bool:
        if source != null and not is_instance_valid(source):
            return true
        for effect: Variant in over:
            if not is_instance_valid(effect):
                return true
        for index in range(at, shares.size()):
            for effect: Variant in shares[index]:
                if not is_instance_valid(effect):
                    return true
        return false

    ## Whether every run is written and walked.
    func ended() -> bool:
        return done and walk.is_empty()

    ## Moves *count* of the regions owed the walk into *dirty*, from
    ## [member middle] outwards, and all of them when *count* is below
    ## nought.
    func release(dirty: Dictionary[Vector2i, Rect2i], count: int) -> void:
        var order: Array[Vector2i] = []
        order.assign(walk.keys())
        if count >= 0 and order.size() > count:
            outwards(order)
            order = order.slice(0, count)
        for grid_pos in order:
            SaCompositeBacklog.merge(dirty, grid_pos, walk[grid_pos])
            walk.erase(grid_pos)
