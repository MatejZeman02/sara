## The work a preset pick leaves for the frame after it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A pick has to put the settings on the brush in the frame it is made, since
## the next press paints with them. What the dockers redraw for it, the cells
## dimmed against the engine a pick switched to and the Recent Presets rows with
## their pictures, is only seen once a frame is drawn, and doing it in the pick's
## own frame held that frame past 100 ms. Each docker holds one of these
## and hands it that work under a key.
##
## **A key asked for twice before its frame runs once**, the work last handed
## for it, because a pick that switches engines is heard by the same docker
## twice, as a tool switch and as a load, and the second hand-over is the newer.
##
## **The frame after, never the frame asked in.** A press on a grid cell arrives
## as input, before the tick, and `process_frame` fires later in that same
## frame, so the work waits for a frame whose number is past the one it was
## asked in.
##
## **Or a frame later still, so the redraws take a frame each.** The Brush
## Presets docker's redim, the Tool Options docker's rows and the bar's values
## run 7 to 20 ms each, and all three in the one frame after a filter pick held
## it at 52 to 64 ms. A caller asks for *later* frames to spread them.
##
## **Out of the tree, at once.** A docker a suite builds and never adds to a tree
## has no frames to wait for, so a caller that hands no tree has the work run as
## it is asked. The tree is handed with each ask rather than the docker at the
## start, so this holds no reference back to the docker that holds it.
extends RefCounted

## The tree whose frame the waiting work runs in.
var _tree: SceneTree = null

## The work waiting, a `Callable` for each key, in the order first asked.
var _due: Dictionary[StringName, Callable] = {}

## The first frame each key's work may run in.
var _due_in: Dictionary[StringName, int] = {}


## Runs *work* in a frame of *tree* *later* frames after this one, once however
## often *key* is asked for before then, and at once with no tree.
func ask(key: StringName, work: Callable, tree: SceneTree, later: int = 1) -> void:
    if tree == null:
        _due.erase(key)
        _due_in.erase(key)
        work.call()
        return
    _due_in[key] = Engine.get_process_frames() + maxi(later, 1)
    # Still connected after a `settle` emptied the work, which leaves the
    # connection for the frame to drop.
    if _tree == null:
        _tree = tree
        _tree.process_frame.connect(_on_frame)
    _due[key] = work


## Whether work under *key* is still waiting for its frame.
func waits(key: StringName) -> bool:
    return _due.has(key)


## Runs the work under *key* now, if any waits, for a caller that needs it done
## before it goes on. It does not run again in its frame.
func settle(key: StringName) -> void:
    var work: Callable = _due.get(key, Callable())
    _due.erase(key)
    _due_in.erase(key)
    if work.is_valid():
        # Named on the frame trace, so a hitch in the frame after a pick says
        # whose redraw it was.
        var traced := SaFrameTrace.now()
        work.call()
        SaFrameTrace.spent("after a pick, %s" % key, traced)


## Runs every key still waiting now, for a suite that reads what the work left.
func settle_all() -> void:
    for key: StringName in _due.keys():
        settle(key)


## Runs the keys whose frame has come. Held connected until every key has run
## rather than one shot, so a frame too early to run in leaves the connection
## for the next.
func _on_frame() -> void:
    var now := Engine.get_process_frames()
    for key: StringName in _due.keys():
        if now >= _due_in.get(key, 0):
            settle(key)
    if not _due.is_empty():
        return
    if _tree != null and _tree.process_frame.is_connected(_on_frame):
        _tree.process_frame.disconnect(_on_frame)
    _tree = null
