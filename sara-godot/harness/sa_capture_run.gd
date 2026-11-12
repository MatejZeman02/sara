## One run of the harness: where it writes, what is left to do, and what the
## last steps came to.
##
## Why this exists
## ---------------
## The step table was cut from the runner, and handing it the runner back would
## hand it on to every driver, each typed `Node` because a `class_name` on
## either side of that pair is a cycle the class cache resolves late. A driver's
## file could then not say what it needed, most wanting the tree and nothing
## else and the rest the run's state, and it breaks the second rule of
## structure: a cut takes no reference back to the class it was cut from.
##
## This is what they were reaching for, as a class of its own. The runner builds
## one and hands it to the table, the table hands it to every driver, and no
## driver sees the runner again.
##
## **It holds no node.** The tree is asked of the engine, so a run is the same
## object in a suite that never entered a tree as it is in the app, and nothing
## here keeps a node alive or is kept alive by one.
##
## **Every member is public**, because every one of them is written from outside
## on purpose: the runner counts the frames and the index, the stroke and the
## gesture drivers splice the steps, the input driver and the wheel move the
## pointer, the document driver and the texel probe leave their answers. The
## privates rule is about a member that has one writer, and none of these does.
class_name SaCaptureRun
extends RefCounted

## The folder a run lands in when nobody names one, under the data root, so a
## capture with its own settings folder leaves nothing in the painter's.
const DEFAULT_FOLDER: String = "captures"

## Where a shot, a dump and every log line of the run land.
var out_dir: String = SaDataRoot.path(DEFAULT_FOLDER)

## The steps of the scenario. `SaScenarioStroke` and the gesture driver expand
## one step into the several it stands for, through [method splice] (f13).
var steps: Array = []

## The step the loop runs next.
var step_index: int = 0

## Drawn frames the loop still holds for before its next step.
var wait_frames: int = 0

## Where the last injected event was aimed, in logical units.
##
## `press` and `release` read this rather than DisplayServer.mouse_get_position(),
## which is the *real* pointer. Wayland refuses to warp a client pointer, so that
## is wherever the user's hand left the mouse: a scenario asking for a press at
## (600, 400) would press somewhere else entirely, and a stroke that never
## started would look like a broken brush.
##
## The run's rather than the input driver's, because the wheel writes it too.
var last_pointer: Vector2 = Vector2.ZERO

## What the last `save` step came to, folded into the next state dump.
var last_save: Dictionary = {}

## What the last `load` step came to, its `path` and an `error` when it failed.
var last_load: Dictionary = {}

## What the last `export` step came to, the path, the size and the depth, and
## an `error` when no file was written, which the door turns into ok false.
var last_export: Dictionary = {}

## What the last `shot` step came to: `owed` while `SaShotSettle` holds it
## for a later frame, the `path` once it is written, and an `error` when
## nothing could be written. The door holds its answer while the shot is
## owed, and names the file this shot wrote rather than one an earlier shot of
## the same label left.
var last_shot: Dictionary = {}

## The answer of the last `texel` step, folded into the next state dump.
var last_texel: Array = []

## Whether the compositor let the runner's probe move the pointer. Trust this
## before trusting a screenshot that depends on where the pointer is. False
## until [member pointer_warp_probed] says the probe has run.
var pointer_warp_works: bool = false

## Whether the warp probe has run. A scenario runs it at its settle and a door
## at its first injected motion, so a door nobody has moved the pointer through
## has not asked yet.
var pointer_warp_probed: bool = false

## How many changes the painter has made by hand since the door opened, as the
## door counted them when the step now running was taken. Written by the door
## and read by `rewind`, which refuses to undo past them unasked. Nought for a
## run with no door, which has no painter beside it.
var painter_changes: int = 0


func _init(folder: String = SaDataRoot.path(DEFAULT_FOLDER), scenario: Array = []) -> void:
    out_dir = folder
    steps = scenario


## The tree the app runs in, or null in a host whose main loop is not one.
func tree() -> SceneTree:
    return Engine.get_main_loop() as SceneTree


## Puts *expanded* in front of the step the loop runs next, which is how one
## `stroke` or one `transform` becomes the presses and moves it stands for.
func splice(expanded: Array) -> void:
    steps = steps.slice(0, step_index) + expanded + steps.slice(step_index)


## Lets go of the steps the loop has run, so the list holds only what is still
## to come. A door session sends every request through this list and a stroke
## splices a step a frame into it, so a long session would keep every run step
## and [method splice] would copy them all at every stroke, slowing a big
## brush's strokes after the first few thousand. The runner calls this as it
## hands a frame to the door.
func forget_the_steps_run() -> void:
    if step_index == 0:
        return
    steps = steps.slice(step_index)
    step_index = 0


## Waits drawn frames: the runner holds for them before the next step, `{"wait":
## 20}`.
##
## Frames rather than milliseconds, because everything a scenario waits for is
## drawn: a compositor settling a window, a compute dispatch landing on the
## easel, a docker laying itself out. A wall-clock wait would be the same
## sentence on this machine and a different one on the next.
##
## **A function of its own rather than an assignment in the branch**.
## The catalogue reads the doc comment above the handler the executor dispatches
## to, and a branch that only assigns has no handler, so `scripts/sara_steps.py`
## would report the most-used step kind as undocumented. A handler is cheaper
## than teaching the catalogue to read a `##` above an inline branch, which is a
## second rule in the parser for one key, where this is one rule for all of
## them.
func wait(frames: int) -> void:
    wait_frames = frames


## Saves the window as a PNG: the root viewport, which for embedded subwindows
## contains the dockers too.
##
## **Arguments.**
## - `shot` string, the PNG's name, and the answer says where.
##
## Forces the frame rather than waiting for one. `await frame_post_draw`
## only resumes once something has queued a redraw, and the low-processor
## mode means a quiet scenario, or a quiet painter, can leave the app with no
## redraw queued for as long as nothing moves: the await then never resumes,
## and a step after a long `wait` wrote no file and printed nothing at all.
## `force_draw` draws and presents synchronously, so the viewport's texture is
## current the moment this line returns.
##
## **Every layer thumbnail and every Brush Presets tile is settled first**, by
## `SaShotSettle`, which says why. When that had to read the preset store a
## boot still held, the shot is taken a frame later than the step said, and
## [member last_shot] says it is owed until then.
func shoot(label: String) -> void:
    var scene_tree := tree()
    var vp: Viewport = scene_tree.root if scene_tree != null else null
    if vp == null:
        last_shot = {"error": "no viewport to shoot %s" % label}
        push_error("SaCapture: %s" % last_shot["error"])
        return
    if SaShotSettle.settle(vp, label):
        last_shot = {"owed": label}
        splice([{"wait": 1}, {"shot": label}])
        return
    var stopped := SaCapture.hold_for_a_shot(scene_tree)
    RenderingServer.force_draw()
    var image := SaNoteMode.picture_of(vp)
    SaCapture.let_the_ants_march(stopped)
    if image == null:
        last_shot = {"error": "the viewport produced no image for %s" % label}
        push_error("SaCapture: %s" % last_shot["error"])
        return
    var target := shot_file(label)
    var err := image.save_png(target)
    if err != OK:
        last_shot = {"error": "failed to write %s (%s)" % [ProjectSettings.globalize_path(target), error_string(err)]}
        push_error("SaCapture: %s" % last_shot["error"])
    else:
        last_shot = {"path": target}
        print("SaCapture: wrote %s" % ProjectSettings.globalize_path(target))


## Where the shot *label* is written: a label that already ends in `.png` is
## the file's name as it stands, so `x.png` is never `x.png.png`.
func shot_file(label: String) -> String:
    return out_dir.path_join(label if label.ends_with(".png") else "%s.png" % label)


## The layer types the main scene registered, or null in a host without them.
func layer_types() -> SaLayerTypeRegistry:
    var scene_tree := tree()
    var main_node := scene_tree.current_scene if scene_tree != null else null
    if main_node == null or not ("registries" in main_node):
        return null
    return main_node.registries.layer_types


## The brush fields the main scene registered, or null in a host without them.
func brush_fields() -> SaBrushFieldRegistry:
    var scene_tree := tree()
    var main_node := scene_tree.current_scene if scene_tree != null else null
    if main_node == null or not ("registries" in main_node):
        return null
    return main_node.registries.brush_fields


## The document the painter is working on, the front surface's, or null before
## one exists.
##
## Through `render`'s own lookup rather than through the canvas driver's
## narrowing of it, which every other file of the harness asks: the driver
## preloads this file, and a preload back would be a cycle.
func main_document() -> SaDocument:
    var canvas := SaCanvasView.front_canvas()
    return canvas.document if canvas != null else null


## Every Window in the tree, from *node* down.
##
## The run's because two of its readers walk it: the drag step looks a docker up
## by title, and the dump reports one entry per window.
func all_windows(node: Node) -> Array:
    var found: Array = []
    if node is Window:
        found.append(node)
    for child in node.get_children():
        found.append_array(all_windows(child))
    return found


## The nodes called *name* under *root*, in the order a step should try them:
## the ones a docker holds first, then the rest, each in tree order.
##
## **A name is not an address, because the top bar has its own copy of the
## tool options.** The bar builds them from the same `SaOptionSpec` list,
## through the same `ToolOptionControls` the Tool Options docker builds from, so
## `RadiusSlider`, `OpacitySlider`, `StabilizerModeOpt` and the layers docker's
## `BlendModeOpt` each answer at two or three paths, and a popup opened from one
## of them carries that copy's row names again. `find_child` stops at the first
## in tree order, which is the top bar's, so a scenario would drive a control
## nobody wrote it against while its record and its picture were of the
## docker's.
##
## **A docker's copy wins**, and among those the first in tree order, because
## that is what a scenario means by a bare name: these names belong to the
## dockers, and the top bar's copies are the second ones. *in_node* narrows the walk to one node's subtree instead, which
## is what a step means when it wants a copy that is not a docker's.
##
## A name that several nodes answer to and that *in_node* did not narrow prints
## one line saying which is tried first, because a walk that takes the wrong
## answer silently is the failure this guards against.
##
## The run's rather than a driver's because three of its readers ask: the
## `dropdown` step, the pointer steps through [method SaInputDriver.point_of],
## and the `note` step.
func nodes_named(root: Node, name: String, in_node: String = "") -> Array[Node]:
    var scope := root
    if not in_node.is_empty():
        scope = DockerLookup.named(root, in_node)
        if scope == null:
            push_warning("SaCapture: no node called '%s' to look inside for '%s'" % [in_node, name])
            return []
    var inside: Array[Node] = []
    var outside: Array[Node] = []
    _named_under(scope, name, inside, outside)
    var found: Array[Node] = []
    found.append_array(inside)
    found.append_array(outside)
    if found.size() > 1:
        _say_which_name_wins(name, inside, found)
    return found


## Splits the nodes called *name* under *parent* into the ones a docker holds and
## the rest, in tree order, and recurses. Depth first and children in order, so
## the last is the first answer `find_child` would have given.
func _named_under(parent: Node, name: String, inside: Array[Node], outside: Array[Node]) -> void:
    for child in parent.get_children():
        if String(child.name) == name:
            if _inside_a_docker(child):
                inside.append(child)
            else:
                outside.append(child)
        _named_under(child, name, inside, outside)


## Whether *node* sits inside a docker's window, which is where a bare name a
## scenario writes resolves.
static func _inside_a_docker(node: Node) -> bool:
    var walk := node
    while walk != null:
        if walk is DockerWindow:
            return true
        walk = walk.get_parent()
    return false


## The one line an ambiguous name earns, printed rather than returned: it is read
## in a run log beside the step that asked, and a reader who has to know which
## copy was taken is reading the wrong file for it.
func _say_which_name_wins(name: String, inside: Array[Node], found: Array[Node]) -> void:
    var first := inside[0] if not inside.is_empty() else found[0]
    var why := "and the docker's is tried first" if not inside.is_empty() else "and no docker has one, so the first is tried"
    print("SaCapture: %d nodes are called '%s', %s: %s" % [found.size(), name, why, _where(first)])


## Where *node* is, for a line a reader follows. A node outside a tree has no
## path to give and the engine says so with an `ERROR`, which is what a suite
## building two detached copies would print on every lookup.
static func _where(node: Node) -> String:
    return String(node.get_path()) if node.is_inside_tree() else String(node.name)


## The tool the main canvas is on, which is what an unwanted click changes.
##
## The run's rather than a driver's because two of them ask: the click reports
## the tool either side of itself, and a stroke that painted nothing names the
## tool that drew nothing.
func active_tool_name() -> String:
    # The front surface's machine and no other: the canvas the painter is
    # working on is the one whose tool a click would change, and a second open
    # document has a machine of its own with a tool of its own in hand.
    var canvas := SaCanvasView.front_canvas()
    var machine := canvas.tool_machine() if canvas != null else null
    return String(machine.active_tool_name) if machine != null else "<none>"


## A docker's Window, asked of the registry the docker registered with.
##
## Rather than `find_child` on its id, which is the name its Window happens to
## take in the tree: a rename or a typo would find nothing, and a module's
## docker would be found only where its module gave the Window the same name as
## the id. The registry is where every docker, built-in
## or a module's, is filed under its id with the Window it built, so this asks
## that instead, and a name nobody registered is answered with the names that
## are.
class DockerLookup:
    extends RefCounted

    ## The registry the running app's dockers are filed in, or null in a host with
    ## no `Main`, a suite's among them.
    static func registry_of(tree: SceneTree) -> SaUIRegistry:
        var main_node := tree.current_scene if tree != null else null
        if main_node == null or not ("registries" in main_node):
            return null
        var held: Variant = main_node.get("registries")
        if not held is SaRegistries:
            return null
        var registries: SaRegistries = held
        return registries.ui

    ## The Window *docker_id* registered and built, or null when it is not
    ## registered, not built yet, or there is no registry to ask.
    static func window(tree: SceneTree, docker_id: StringName) -> Window:
        return window_in(registry_of(tree), docker_id)

    ## [method window] for a registry already in hand.
    static func window_in(registry: SaUIRegistry, docker_id: StringName) -> Window:
        if registry == null or not registry.has_docker(docker_id):
            return null
        var node: Variant = registry.get_docker_entry(docker_id).get("node")
        if not is_instance_valid(node) or not node is Window:
            return null
        var built: Window = node
        return built

    ## The node a step names, which a docker's id reaches through the registry and
    ## any other name through the tree: the `pen_in` window, the holder a `control`
    ## list walks and the node a `note` looks inside take a dialog's name as often
    ## as a docker's. Any other name is looked for under *under*, which a suite
    ## hands in outside any tree. Null when neither has it.
    static func named(under: Node, name: String) -> Node:
        if under == null or name.is_empty():
            return null
        var registry := registry_of(under.get_tree()) if under.is_inside_tree() else null
        if registry != null and registry.has_docker(name):
            return window_in(registry, name)
        return under.find_child(name, true, false)

    ## A Window by *name* that is not a docker: the bare host the `curve_option`
    ## step opens is placed by a `docker` step in `curve-graph-square`, and a
    ## window like it is no registry's to answer for. A `DockerWindow` is never
    ## answered here, whatever its name, so a docker is only ever found through the
    ## registry.
    static func host_window(tree: SceneTree, name: String) -> Window:
        if tree == null or name.is_empty():
            return null
        var found := tree.root.find_child(name, true, false)
        if not found is Window or found is DockerWindow:
            return null
        var host: Window = found
        return host

    ## Why *docker_id* names no docker, with every id that does, or an empty string
    ## when it is registered. A scenario's docker is a string in JSON that no parser
    ## reads, so this is where a typo in one is caught, and the answer carries the
    ## list so the next step can be written right.
    static func refusal(registry: SaUIRegistry, docker_id: StringName) -> String:
        if registry == null:
            return "no docker registry to find '%s' in" % docker_id
        if registry.has_docker(docker_id):
            return ""
        return "no docker registered as '%s', the registered ones are %s" % [docker_id, ", ".join(registered_ids(registry))]

    ## Every registered id, in registration order.
    static func registered_ids(registry: SaUIRegistry) -> PackedStringArray:
        var ids := PackedStringArray()
        for entry: Dictionary in registry.list_dockers():
            var docker_id: StringName = entry["id"]
            ids.append(docker_id)
        return ids

    ## Every Window the registry has built, in registration order.
    static func windows_in(registry: SaUIRegistry) -> Array[Window]:
        var out: Array[Window] = []
        if registry == null:
            return out
        for entry: Dictionary in registry.list_dockers():
            var docker_id: StringName = entry["id"]
            var win := window_in(registry, docker_id)
            if win != null:
                out.append(win)
        return out
