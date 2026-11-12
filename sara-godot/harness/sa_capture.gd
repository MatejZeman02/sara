## Scripted screenshots and UI state dumps, for diagnosing the running app.
##
## Why this exists
## ---------------
## The QA gate proves logic, not appearance. It has already passed while the UI
## was twice its intended size, and the cursor bugs it cannot see at all are
## exactly the ones that reach a user first. This node drives the real app with a
## real RenderingDevice, captures what it looks like, and dumps the numbers behind
## what it looks like.
##
## It is inert unless `--capture` appears after `--` on the command line, so a
## normal launch pays for one array lookup.
##
## What a capture can and cannot see
## ---------------------------------
## The viewport image contains everything Sara draws, including the software
## cursor ring and every embedded docker. It does NOT contain the OS hardware
## cursor, which the compositor draws. So "is the pointer visible" is answered by
## `mouse_mode` in the state dump, never by looking at the PNG.
##
## Pointer movement is best-effort. Wayland does not let a client place the
## pointer freely, so `move` records both the requested and the resulting
## position and every dump carries `pointer_warp_works`. Trust that flag before
## trusting a screenshot that depends on where the pointer is. A door asks it at
## its first injected motion rather than at its settle, so opening one leaves the
## painter's pointer where it is.
##
## What this file is
## -----------------
## The runner and nothing else: the scenario loader, the frame loop, the settle,
## the warp probe, the door and the done marker `scripts/sara_shot.py` scrapes.
## `SaStepTable` answers what a step *does*, and `SaCaptureRun` is what a run
## *is*: the output folder, the steps and what the last of them came to.
##
## No verb that reads as a step lives here, `wait`, `shoot`, `save_document`,
## `set_prefs`, `resize_window` or `texel`, because each would write a field this
## node owned and the table would reach back for it through the runner. The
## fields are the run's and each verb lives with the driver it belongs to, so the
## table, the drivers and the door are handed the run and none of them sees this
## node.
extends Node

class_name SaCapture

## The step table, and through it the drivers. By path, so no class rescan is
## needed between a fresh checkout and a capture.
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const InputDriver := preload("res://harness/drivers/sa_input_driver.gd")
const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const LocalServerDialog := preload("res://ui/dialogs/sa_local_server_dialog.gd")

## Frames to wait before the first step, so the compositor has mapped the window
## and DockerLayoutStore has finished re-asserting geometry against it. The brush
## presets are waited for after them, by [method _boot_presets_read].
const SETTLE_FRAMES: int = 45

## Hard ceiling on a capture's lifetime, so a scenario that stalls reports itself
## rather than hanging whatever launched it.
const MAX_FRAMES: int = 3600

## The run: the folder, the steps, the index and what the last steps came to.
## Built in [method _init] and handed to the table and the door, which is how
## everything else in the harness reaches it.
var run: CaptureRun = null
var _frames_alive: int = 0

## Whether the door closed on idle and the quit waits for the recovery copy,
## during which the frame loop runs no step and ends nothing. See
## [method _close_on_idle].
var _keeping_the_work: bool = false

## Whether the boot has read the brush presets it held back, which loads the
## first brush slot. See [method _boot_presets_read].
var _presets_were_read: bool = false

## The table this hands every step to. Built in [method _init] rather than in
## `_ready`, so a suite that never enters the tree can still run a step.
var _steps_table: StepTable = null

## Whether this node stops the marching ants for as long as it is in the tree.
## True for a run the command line started for captures, `--capture` or a door
## asked for there, and for the suites' nodes. False for a door the Local Server
## command opens in a painter's Sara, whose ants march, and there a shot holds
## them only while it is drawn, in [method hold_for_a_shot].
var _holds_the_ants: bool = true


## Where a shot lands, `captures` under the data root unless the caller names another,
## the steps and the door all arrive here rather than being written on the node
## afterwards, because a private member is written by its own class only. Every one is defaulted,
## so `SaCapture.new()` alone still builds the resting node the suites use. The
## first two are the run's, and the run is built from them here. *holds_the_ants*
## is false for a door the Local Server command opens in a painter's Sara, see
## [member _holds_the_ants].
func _init(
    out_dir: String = SaDataRoot.path(CaptureRun.DEFAULT_FOLDER),
    scenario: Array = [],
    door: AgentDoor = null,
    holds_the_ants: bool = true
) -> void:
    run = CaptureRun.new(out_dir, scenario)
    _door = door
    _holds_the_ants = holds_the_ants
    _steps_table = StepTable.new(run)


## The live session, when `--agent-socket` or `--agent-port-file` asked for
## one. Null otherwise, and everything about it is one
## branch in `_process` and one in `_finish`.
##
## Typed by the preloaded const rather than by the `class_name`, which is not a
## style choice: a `class_name` added in the same commit as its first use is not
## in the class cache until an editor has looked, and the harness starts Sara
## directly. Naming the type `SaAgentDoor` here would make every run before
## that editor pass die with "Could not find type", `main.gd` failing to compile
## behind it.
var _door: AgentDoor = null


## Builds a capture node when the command line asks for one, otherwise null.
##
## Reads user arguments (everything after `--`), so it cannot collide with
## Godot's own flags.
static func from_command_line() -> SaCapture:
    var args := OS.get_cmdline_user_args()
    var wanted := false
    var scenario_path := ""
    var out_dir := ""
    for arg in args:
        if arg == "--capture":
            wanted = true
        elif arg.begins_with("--capture="):
            wanted = true
            scenario_path = arg.substr("--capture=".length())
        elif arg.begins_with("--capture-out="):
            out_dir = arg.substr("--capture-out=".length())
    # A door is a capture with no scenario, so either way in alone builds the
    # node the same way `--capture` does. Both together run the file first and
    # then answer the socket, which is how a session starts from a known state.
    if not wanted and not AgentDoor.asked_for(args):
        return null

    # The door is opened before the node exists, because it is a constructor
    # argument, a private member being written by its own class only, rather
    # than a field the factory writes afterwards. A door that will not open is null. Which way
    # in, and the idle timeout, are the door's own arguments and it reads them
    # itself.
    var door: AgentDoor = AgentDoor.from_command_line(args)

    var node := SaCapture.new(
        out_dir if out_dir != "" else SaDataRoot.path(CaptureRun.DEFAULT_FOLDER),
        SaCapture._load_scenario(scenario_path) if wanted else [],
        door
    )
    node.name = "SaCapture"
    # A scenario lays one move a frame, so its pen is timed by frames rather
    # than by how long this run's frames took, and the speed sensor reads the
    # same stroke in every run. Here rather than in `_ready`,
    # because a suite adds a capture node to the tree too, and the suites after
    # it want the wall clock.
    SaPenClock.pin_to_frames()
    return node


## Modules › Local Server pressed in a running Sara: closes the door listening
## under *parent* when there is one, and opens one otherwise.
static func flip_the_local_server(parent: Node, known_path: String = "") -> void:
    if _listening_under(parent) != null:
        close_the_local_server(parent)
    else:
        connect_an_agent(parent, known_path)


## Modules › Local Server ticked: opens the door under *parent* when none
## listens there, as `--agent-door` would have at boot, and shows the dialog
## that says what it opened, whose button copies the paragraph of
## [SaAgentInvite]. Nothing reaches the clipboard here. Returns the dialog, or
## null when no door could open, which the corner says instead. *known_path*
## is the data root's known file when empty, and a suite's own otherwise.
##
## The door is a capture node with no scenario, the node `--agent-door` builds,
## so a door opened late answers every step a door opened at boot does, and
## closes and removes its known file when Sara quits, in [method _exit_tree].
## Two things `from_command_line` does are left out, because this is a
## painter's session: the pen keeps the wall clock, and nothing about the
## compositor is printed.
static func connect_an_agent(parent: Node, known_path: String = "") -> LocalServerDialog:
    var capture := _listening_under(parent)
    if capture == null:
        var holder := AgentDoor.known_holder(known_path)
        if holder > 0:
            SaMessage.notice("Sara %d already runs a Local Server, so this one opens none. Connect to that Sara." % holder)
            return null
        var started := Time.get_ticks_usec()
        var memory := OS.get_static_memory_usage()
        var door := AgentDoor.open_known(known_path)
        if door == null:
            SaMessage.notice("Local Server would not open, and the problems list says why.")
            return null
        capture = SaCapture.new(SaDataRoot.path(CaptureRun.DEFAULT_FOLDER), [], door, false)
        capture.name = "SaAgentDoor"
        parent.add_child(capture)
        # What opening a door in a painter's session costs, for the record.
        print(
            (
                "SaAgentDoor: opened in a running Sara in %.2f ms, static memory %+d KiB"
                % [(Time.get_ticks_usec() - started) / 1000.0, roundi((OS.get_static_memory_usage() - memory) / 1024.0)]
            )
        )
    _drop_the_dialog(parent)
    var dialog := LocalServerDialog.new(ProjectSettings.globalize_path(capture._door.where_file()))
    parent.add_child(dialog)
    dialog.popup_centered()
    return dialog


## Modules › Local Server unticked: closes the door listening under *parent*,
## which removes the known file and lets an attached client go, so its next
## call finds no door and meets the guide. False when none listened there.
static func close_the_local_server(parent: Node) -> bool:
    var capture := _listening_under(parent)
    if capture == null:
        return false
    capture.close_door()
    _drop_the_dialog(parent)
    print("SaAgentDoor: Local Server closed")
    SaMessage.notice("Local Server is closed, and nothing outside Sara can reach it now.")
    return true


## The dialog of an earlier tick under *parent*, gone, so it never names a
## file of a server that has closed.
static func _drop_the_dialog(parent: Node) -> void:
    for child: Node in parent.get_children():
        if child is LocalServerDialog:
            parent.remove_child(child)
            child.queue_free()


## The capture node under *parent* whose door listens, or null. A capture run
## with no door is not one, and a door opens beside it.
static func _listening_under(parent: Node) -> SaCapture:
    for child: Node in parent.get_children():
        if child is SaCapture and (child as SaCapture)._door != null and (child as SaCapture)._door.is_open():
            return child as SaCapture
    return null


## This node's door closed. A node that was a door and nothing else goes with
## it, because a capture with no door and no step left ends Sara in
## `_process`, and one still running a scenario runs it on and ends at its last
## step, as a scenario does. Out of the tree at once rather than at the frame's
## end, so `_process` never sees it doorless and the row's tick reads it gone.
func close_door() -> void:
    _door.close()
    _door = null
    remove_from_group(LocalServerDialog.LISTENING_GROUP)
    if run.step_index >= run.steps.size():
        get_parent().remove_child(self)
        queue_free()


## Steps from a JSON file, or a single default shot when no file was named.
static func _load_scenario(scenario_path: String) -> Array:
    if scenario_path == "":
        return [{"shot": "default"}, {"state": "default"}]

    var text := FileAccess.get_file_as_string(scenario_path)
    if text == "":
        push_error("SaCapture: could not read scenario %s" % scenario_path)
        return []
    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Array):
        push_error("SaCapture: scenario must be a JSON array of steps")
        return []
    return parsed as Array


func _ready() -> void:
    if _door != null and _door.is_open():
        add_to_group(LocalServerDialog.LISTENING_GROUP)
    DirAccess.make_dir_recursive_absolute(run.out_dir)
    run.wait_frames = SETTLE_FRAMES
    if _holds_the_ants:
        _hold_the_ants_still()
    set_process(true)


## Stops the marching ants on every selection overlay in the tree and on every
## one that joins it later, which a document opened by a step does. Two runs of
## a scenario would shoot the outline at two phases of its walk, and the
## difference `scripts/shot_diff.py` counted there would hide the real one beside
## it. Here rather than behind a preference, so the painter cannot reach it.
func _hold_the_ants_still() -> void:
    var scene_tree := get_tree()
    for overlay: Node in scene_tree.root.find_children("*", "SaSelectionOverlay", true, false):
        _hold_ants_on(overlay)
    if not scene_tree.node_added.is_connected(_hold_ants_on):
        scene_tree.node_added.connect(_hold_ants_on)


func _hold_ants_on(node: Node) -> void:
    if node is SaSelectionOverlay:
        (node as SaSelectionOverlay).hold_the_ants()


## Stops the ants of every overlay under *scene_tree* that still marches, for
## the one frame a shot draws, so a shot of a painter's Sara through its Local
## Server is as steady as a capture run's. Returns the overlays it stopped, which
## [method let_the_ants_march] gives back once the picture is read. An overlay a
## capture run already holds is not among them, so its hold outlives the shot.
static func hold_for_a_shot(scene_tree: SceneTree) -> Array[SaSelectionOverlay]:
    var stopped: Array[SaSelectionOverlay] = []
    if scene_tree == null or scene_tree.root == null:
        return stopped
    for node: Node in scene_tree.root.find_children("*", "SaSelectionOverlay", true, false):
        var overlay := node as SaSelectionOverlay
        if overlay.ants_march():
            overlay.hold_the_ants()
            stopped.append(overlay)
    return stopped


## Gives back the ants [method hold_for_a_shot] stopped.
static func let_the_ants_march(stopped: Array[SaSelectionOverlay]) -> void:
    for overlay: SaSelectionOverlay in stopped:
        if is_instance_valid(overlay):
            overlay.let_the_ants_march()


func _exit_tree() -> void:
    if _door != null:
        _door.close()  # A painter's Sara closed by its window leaves no known file behind.
    var scene_tree := get_tree()
    if scene_tree != null and scene_tree.node_added.is_connected(_hold_ants_on):
        scene_tree.node_added.disconnect(_hold_ants_on)
    # Whatever this node held is given back as it goes, so a door a capture run
    # opened and then closed leaves the ants marching.
    if _holds_the_ants and scene_tree != null and scene_tree.root != null:
        for overlay: Node in scene_tree.root.find_children("*", "SaSelectionOverlay", true, false):
            (overlay as SaSelectionOverlay).let_the_ants_march()


func _process(_delta: float) -> void:
    # A capture that never quits is the same failure the test runner already
    # learned to bound: the process lingers until whatever launched it gives up,
    # and the reason is never obvious from the outside. Quit and say so instead.
    _frames_alive += 1
    if _keeping_the_work:
        return
    if _door == null and _frames_alive > MAX_FRAMES:
        var unread := "" if _presets_were_read else ", the boot's brush presets still unread"
        push_error(
            "SaCapture: gave up after %d frames at step %d of %d%s" % [MAX_FRAMES, run.step_index, run.steps.size(), unread]
        )
        _finish()
        return

    if run.wait_frames > 0:
        run.wait_frames -= 1
        return
    if not _boot_presets_read():
        return
    # A scenario places the pointer, so it asks at once. A door in a painter's
    # session never moves the pointer by itself, and asks at its first
    # injected motion instead.
    if not run.steps.is_empty():
        InputDriver.know_the_warp(run, get_window())
    if run.step_index >= run.steps.size():
        # A live session runs on when the step list is empty, and is not
        # bounded by MAX_FRAMES: that ceiling is a scenario's guard against a
        # stall, and a door waiting quietly for two minutes is doing its job.
        # The idle timeout is the door's own guard. The settle above still
        # applies, so the first request meets a window the compositor has
        # mapped rather than one still being sized.
        if _door != null and _door.is_open():
            run.forget_the_steps_run()
            if not _door.poll(_steps_table, run):
                if _door_went_idle():
                    _close_on_idle()
                else:
                    _finish()
            return
        _finish()
        return

    var step: Dictionary = run.steps[run.step_index] as Dictionary
    run.step_index += 1
    if step == null:
        return
    # The same executor a door request goes through, so a step does the same
    # from a scenario file and from a door.
    SaPerfWindow.hold_step(step, _steps_table.run)


## Whether the brush presets the boot holds back have been read, which is the
## last part of the settle: the first step waits for it after the settle's
## frames, a scenario's step and a door's request alike.
##
## **A count of frames cannot stand for it.** The boot reads the presets in
## slices of [constant ToolOptionsPresets.PREPARE_SLICE_USEC] a frame, so the
## frames it takes are its time divided by the machine's speed, and it loads the
## first brush slot at its end. On a busy machine a wait in frames runs into a
## scenario's first stroke, which then begins in the Brush's defaults and goes
## on in the slot's brush.
##
## Once true it stays true, since nothing holds the presets a second time, and a
## tree with no bar holds nothing, which is a suite's.
func _boot_presets_read() -> bool:
    if not _presets_were_read:
        var presets := ToolOptionsPresets.in_tree(self)
        _presets_were_read = presets == null or not presets.scan_held
    return _presets_were_read


## Whether the door's false was its idle close rather than a `quit`. A quit
## restarts the door's clock as its line is read, so only a close on idle finds
## the timeout passed. An attached door drops its client on idle and never
## answers false for it.
func _door_went_idle() -> bool:
    if _door.idle_timeout <= 0.0 or _door._keeps_listening:
        return false
    return float(Time.get_ticks_usec() - _door._last_request_usec) / 1_000_000.0 >= _door.idle_timeout


## The idle close of a launched door, which keeps the unsaved work where the
## next load finds it.
##
## A door that outlived its client still ends the session, so it holds no GPU
## for the night, but a quit that passed by `main.gd`'s question and its
## discard alike would lose a client's last steps. With the
## document modified, the recovery copy the autosave keeps is written once more,
## beside the file or under the recovery folder for an untitled one, the quit
## waits for it, and one line names it. The document's own file is never
## written here, whatever the autosave's target, because a close nobody asked
## for must not overwrite what the painter saved, and a tree with no main has
## no autosave to ask where the copy goes and quits at once. The `load` step names a copy
## newer than its file, which is how the work is found again.
func _close_on_idle() -> void:
    _door.close()
    _door = null
    var document := _main_document()
    var autosave := _main_autosave()
    if document == null or not document.modified or autosave == null:
        _finish()
        return
    _keeping_the_work = true
    var copy: String = autosave.recovery_path()
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(copy.get_base_dir()))
    SaSadFile.save_in_background(document, copy, 0, null, false, _on_kept.bind(copy))


## The recovery copy is on disk, or the save says why not, and the quit goes on.
func _on_kept(err: Error, copy: String) -> void:
    if err == OK:
        print("SaCapture: the door closed on idle with unsaved changes, kept in %s" % ProjectSettings.globalize_path(copy))
    else:
        push_error("SaCapture: the door closed on idle with unsaved changes, and %s failed (%s)" % [copy, error_string(err)])
    _finish()


## The document the painter is working on, the front surface's, or null before
## one is built. The run answers the same, and this file holds no run while it
## closes the door on idle, which is the one place it asks.
func _main_document() -> SaDocument:
    var canvas := SaCanvasView.front_canvas()
    return canvas.document if canvas != null else null


## Main's autosave, which knows where the document's recovery copy goes, beside
## the file or under the recovery folder for an untitled one, or null in a tree
## with no main. Read off main's node as the state report reads it, since the
## autosave's class is inside `core/sad-file` and its facade does not answer it.
func _main_autosave() -> Node:
    var main_node := get_tree().current_scene
    if main_node == null or not ("autosave" in main_node):
        return null
    return main_node.autosave


func _finish() -> void:
    if _door != null:
        _door.close()
        _door = null
    print("SaCapture: done")
    SaTrail.hand_over(get_tree(), "the scenario is done, quit called")
