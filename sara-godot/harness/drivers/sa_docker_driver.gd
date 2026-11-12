## Where a docker window is: shown, placed, sized, or parked off the canvas.
##
## Its own class because a docker window is not a menu and not a dialog: it is
## a `Window` a scenario positions, and every question here is about a
## rectangle. `scripts/scenario_dockers.py` reads [constant PARK_AT] out of
## this file, so a scenario that parks has declared its layout and the scan can
## say what that layout covers.
##
## Reached by path from the step table rather than by class name, so no editor
## rescan stands between a fresh checkout and a step.
class_name SaDockerDriver
extends RefCounted

## The run, by path like every other harness file this one names.
const CaptureRun := preload("res://harness/sa_capture_run.gd")

## The run, read for its tree.
var _run: CaptureRun = null

## The registry a suite hands in, since a suite has no `Main` to own one. Null
## in the app, where each step asks the tree's `Main` for its own.
var _registry: SaUIRegistry = null


func _init(run: CaptureRun, registry: SaUIRegistry = null) -> void:
    _run = run
    _registry = registry


## Where `{"docker": "park"}` puts every docker: the right edge of the host, so
## no docker rectangle contains any point of the viewport.
##
## A number rather than "off the screen somewhere", because
## `scripts/scenario_dockers.py` has to know it: a scenario that parks has
## declared its layout, and the scan is only worth anything if it can say what
## that layout covers. 1920 is the width every capture runs at unless a `window`
## step says otherwise, and a wider run parks further left than its own edge,
## which costs nothing since the point is only that the canvas is clear.
const PARK_AT := Vector2i(1920, 78)


## Shows a docker: a registered one by its id, at a place a scenario can name with
## `"at": [x, y]`, `{"docker": "MinimapDocker"}`.
##
## **The id is asked of the registry**, never of the tree by a node's
## name. A name no docker registered is refused with a warning that lists the
## ids that are, which the door carries back in the step's answer, and the
## step answers with that line as well, so a suite reads it too. The one
## exception is a window that is no docker at all, the curve option's bare host,
## which [method SaDockerLookup.host_window] finds by its name.
##
## `{"docker": "park"}` is the whole layout in one step. A scenario places the
## dockers that existed when it was written and inherits whatever the profile
## says about the rest, so a docker added later can land over its strokes and
## nothing says so. Parking is per docker rather than per scenario:
## every registered docker goes to `PARK_AT`, including the ones a
## default profile keeps shut, so opening one later finds it parked too.
func docker(spec: Variant) -> String:
    var docker_id := String(spec.get("id", "")) if spec is Dictionary else String(spec)
    if docker_id == "park":
        return _park_every_docker()
    var registry := _ui_registry()
    var refused := CaptureRun.DockerLookup.refusal(registry, docker_id)
    var window := CaptureRun.DockerLookup.window_in(registry, docker_id)
    if not refused.is_empty():
        window = CaptureRun.DockerLookup.host_window(_run.tree(), docker_id)
        if window == null:
            push_warning("SaCapture: " + refused)
            return "SaCapture: " + refused
    elif window == null:
        var unbuilt := "SaCapture: no window yet for docker '%s', which is registered" % docker_id
        push_warning(unbuilt)
        return unbuilt
    window.visible = true
    if spec is Dictionary and spec.has("at"):
        var at := spec["at"] as Array
        if at != null and at.size() >= 2:
            window.position = Vector2i(int(at[0]), int(at[1]))
    # A docker that reflows with its width cannot be photographed narrow
    # without this, and the reflow is what such a shot is for.
    if spec is Dictionary and spec.has("size"):
        var wanted := spec["size"] as Array
        if wanted != null and wanted.size() >= 2:
            window.size = Vector2i(int(wanted[0]), int(wanted[1]))
    # Told to the layout store, or the settle loop puts the window back inside
    # the sixty frames after a restore and this line reports a placement that
    # did not happen. A door session's first steps are always inside that
    # window, and a scenario has no way to know it is.
    var noted := _note_placement(window)
    var shown := (
        "SaCapture: docker %s shown at %s, size %s%s"
        % [docker_id, window.position, window.size, "" if noted else ", not noted by the layout store"]
    )
    print(shown)
    return shown


## Fakes a docker's pointer: at a point, the pointer a docker summon and its
## leave read, in the host's logical units, `{"docker_pointer": [x, y]}`, and
## `{"docker_pointer": null}` hands the real pointer back.
##
## Wayland will not let a client place the pointer, so an injected `move`
## reaches the event path and leaves the pointer a summon asks about where it
## was. This is the seam `DockerDragHandle` already keeps for the ALT-drag, set
## from a step, so a scenario can summon a docker at a named point and walk the
## pointer away from it.
func pointer(spec: Variant) -> void:
    if spec is Array and (spec as Array).size() >= 2:
        DockerDragHandle.capture_pointer = Vector2(float(spec[0]), float(spec[1]))
    else:
        DockerDragHandle.capture_pointer = null
    print("SaCapture: docker pointer %s" % str(DockerDragHandle.capture_pointer))


## Tells the docker layout store where a `docker` step has just put a window, so
## its settle loop re-asserts that rather than the stored position.
##
## Through `MainDockers` by name for the same reason `capture_layout_preset` is,
## and answering false rather than pushing a warning when there is none: a test
## host has no dockers node and a step that placed a window in one is not wrong
## to have done so.
func _note_placement(window: Window) -> bool:
    var tree := _run.tree()
    var dockers := tree.root.find_child("MainDockers", true, false)
    if dockers == null or not dockers.has_method("note_docker_placement"):
        return false
    return bool(dockers.call("note_docker_placement", window))


## Every registered docker at [constant PARK_AT], shut ones included.
##
## The walk is over the UI registry, where it was over every `DockerWindow`
## in the tree. A registered docker's Window is built at startup whether or not
## the profile opens it, so the two are the same list, and the registry is the
## one that names a module's docker by the id the module gave it.
##
## Each one is noted the way a single `docker` step's placement is. Without the
## note nothing records where the dockers went while `_layout_save_allowed` is
## false, so a park inside the first 1500 milliseconds would move every window
## and leave `stored_positions` holding the layout the park had just undone, and
## a scenario that parks early would disagree with itself between a file and a
## socket.
func _park_every_docker() -> String:
    var parked: Array[String] = []
    var unnoted: Array[String] = []
    for window in CaptureRun.DockerLookup.windows_in(_ui_registry()):
        if window.is_queued_for_deletion():
            continue
        window.position = PARK_AT
        parked.append(String(window.name))
        if not _note_placement(window):
            unnoted.append(String(window.name))
    parked.sort()
    unnoted.sort()
    var said := (
        "SaCapture: docker park -> %d at %s: %s%s"
        % [
            parked.size(),
            PARK_AT,
            ", ".join(parked),
            "" if unnoted.is_empty() else ", not noted by the layout store: " + ", ".join(unnoted),
        ]
    )
    print(said)
    return said


## The registry this driver was handed, or the running app's.
func _ui_registry() -> SaUIRegistry:
    return _registry if _registry != null else CaptureRun.DockerLookup.registry_of(_run.tree())
