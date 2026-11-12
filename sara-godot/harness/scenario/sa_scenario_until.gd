## The `until` step: waits on a condition the app can be asked rather than on a
## count of frames, up to a bound past which the run goes on and its log says
## so.
##
## **Why a condition.** A summoned docker goes back once the pointer has been
## away for a dwell the painter sets in milliseconds, and a wait of a count of
## frames for it fails on a loaded machine, where the frames come slower than
## the milliseconds. Frames and milliseconds are two clocks, and a
## wait for something measured on the second cannot be written in the first. So
## the step asks the summon itself whether anything is still out.
##
## **Why the step splices itself.** One frame's look, then `{"wait": 1}` and the
## step again with one frame fewer to go, which is the shape the `shot` step
## already uses when a thumbnail is unsettled. The runner's loop stays a counter
## of frames and needs no second kind of wait.
extends RefCounted

const CaptureRun := preload("res://harness/sa_capture_run.gd")
const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")

## The bound when a step names none: ten seconds at sixty frames, ten times
## the default dwell.
const DEFAULT_FRAMES: int = 600

## The conditions a step can name, each a method of this class.
const CONDITIONS: Array[String] = ["dockers_back", "saves_ended", "composited", "settled"]

var _run: CaptureRun = null

## The composites the canvas in front had run when the step first looked, so
## `composited` waits for the one the step before it asked for.
var _composites_at_start: int = 0


func _init(run_state: CaptureRun) -> void:
    _run = run_state


## Waits on a condition, up to a bound.
##
## `{"until": "dockers_back", "frames": 600}` looks once a frame until
## *condition* holds, for at most *frames* frames.
##
## **Arguments.**
## - `until` string, the condition. `dockers_back` holds when no docker is out
##   on a summon, so every docker a chord brought up has gone back.
##   `saves_ended` holds when no save is running and no export target a save
##   started is still being written. `composited` holds once the canvas in
##   front has composited since the step began and owes no composite where its
##   view reaches, so it follows a step that changed the canvas in one batch.
##   `settled` holds once the canvas in front owes no composite where its view
##   reaches and its fold holds no picture back, whether or not a composite
##   came after the step began, so it follows a request whose own answer may
##   have waited for the composite already.
## - `frames` int, optional, the bound, 600 when left out.
##
## Prints one line when the condition holds, with the frames it took, and one
## line when the bound ran out first, after which the next step runs anyway: a
## shot taken then shows what was still out, which is what a reader of a failed
## check needs, where a run that waited for ever shows nothing. An unknown
## condition is an error, and the run goes on at once.
func until(condition: String, frames: int, waited: int = 0) -> void:
    if not CONDITIONS.has(condition):
        push_error("SaCapture: until names no condition called %s, the known ones are %s" % [condition, ", ".join(CONDITIONS)])
        return
    if waited == 0:
        _composites_at_start = _composites()
    if bool(call(condition)):
        print("SaCapture: until %s held after %d frame(s)" % [condition, waited])
        return
    if waited >= frames:
        print("SaCapture: until %s still not met after %d frame(s), the run goes on" % [condition, waited])
        return
    _run.splice([{"wait": 1}, {"until": condition, "frames": frames, "waited": waited + 1}])


## Whether no docker is out on a summon. True in a host with no summon at all,
## since nothing there can be out.
func dockers_back() -> bool:
    var tree := _run.tree()
    var summon := tree.root.find_child("DockerSummon", true, false) as DockerSummon if tree != null else null
    return summon == null or not summon.docker_out()


## Whether no save is running and every export target a save started is whole.
func saves_ended() -> bool:
    return not SaSadFile.saving()


## True when the canvas in front owes no composite where its view reaches, so
## the picture on the screen is the settled one.
func composited() -> bool:
    var canvas := CanvasDriver.main_canvas()
    if canvas == null or canvas.easel == null:
        return true
    var easel := canvas.easel
    if easel.composite_count == _composites_at_start:
        return false
    return not easel.needs_composite and not easel.needs_full_composite and not easel.backlog.reaches(easel.composed_area())


## True when the canvas in front owes no composite where its view reaches and
## no show or hide is still folding the picture it holds back, which a
## composite before the fold is paid does not say.
func settled() -> bool:
    var canvas := CanvasDriver.main_canvas()
    if canvas == null or canvas.easel == null:
        return true
    var debt := canvas.document.fold.debt if canvas.document.fold != null else null
    if debt != null and (debt._draws_when_paid or debt.owes_whole()):
        return false
    var easel := canvas.easel
    return not easel.needs_composite and not easel.needs_full_composite and not easel.backlog.reaches(easel.composed_area())


## The composites the easel in front has run, 0 with no canvas.
func _composites() -> int:
    var canvas := CanvasDriver.main_canvas()
    return canvas.easel.composite_count if canvas != null and canvas.easel != null else 0
