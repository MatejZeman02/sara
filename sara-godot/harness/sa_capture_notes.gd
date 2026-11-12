## The two steps that carry a sentence rather than an action: the `note`
## capture step, split out of `sa_note_mode.gd` to sit beside
## `sa_capture.gd`'s other step helpers, and the `comment` step beside it.
##
## They are separate on purpose. JSON has no comment of its
## own, so three committed scenarios had been putting theirs in a `note`, which
## answered every one of them with a refusal, a `note` string being a command
## and not prose. Widening `note` would have bought that sentence at
## the price of a command whose typos stop being errors.
class_name SaCaptureNotes
extends RefCounted

## The run, by path like every other harness file that names it, so no editor
## rescan stands between a fresh checkout and a step.
const CaptureRun := preload("res://harness/sa_capture_run.gd")


## Prints a sentence in the run log: the sentence a JSON array cannot otherwise
## carry, `{"comment": "why this scenario does what it does"}`. It drives
## nothing and changes nothing, and it is a step of its own rather than a free
## string in a `note` so that a `note` with a typo in its command keeps failing
## loudly.
##
## Printed rather than dropped, because a run log a reader is being asked to
## read is the one place the sentence is worth having, and a step that produced
## no line at all would read as a step that did not run.
static func comment(text: String) -> String:
    return "SaCapture: %s" % text


## Drives the take-a-note mode: the way the keys do, `{"note": "on"}`, `"off"`,
## `"save"`, `"export"` or `"cancel"`. `{"note": {"target": "SecondRowCheck",
## "text": "..."}}` freezes on the control of that name as a click would,
## photographs it and opens the box with the text in it, so a shot afterwards
## shows both and `"save"` writes the entry. `"into"` names the directory, the
## capture's own by default, and `"save": true` writes without a second step.
##
## **A target that two surfaces answer to resolves to the docker's copy**,
## since the top bar builds its own copy of the tool options it shows. `in`
## narrows the walk to one node's subtree, for the step that means the other
## copy: `{"target": "RadiusSlider", "in": "CustomTitleBar"}`.
static func run(capture: CaptureRun, spec: Variant, out_dir: String) -> void:
    var tree := capture.tree()
    var mode := SaNoteMode.find_in(tree)
    if mode == null:
        mode = SaNoteMode.install(tree.current_scene)
    if mode == null:
        push_warning("SaCapture: no Main to put the note mode under")
        return
    # The capture's own directory, whichever form the step takes: a scenario
    # that turns the mode on and saves from a press would otherwise write into
    # the inbox the sort step reads, beside the painter's real notes.
    mode.notes_dir = out_dir
    if spec is String:
        match String(spec):
            "on":
                mode.start()
            "off":
                mode.stop()
            "save":
                print("SaCapture: note saved to %s" % mode.save(mode.box_text()))
            "export":
                print("SaCapture: note exported to %s" % mode.export_notes())
            "cancel":
                mode.cancel()
            _:
                push_warning("SaCapture: no note command '%s'" % spec)
        return
    var options: Dictionary = spec if spec is Dictionary else {}
    mode.notes_dir = String(options.get("into", out_dir))
    var target := String(options.get("target", ""))
    var candidates := capture.nodes_named(tree.root, target, String(options.get("in", "")))
    var node: Node = candidates[0] if not candidates.is_empty() else null
    var complaint := target_complaint(target, node)
    if not complaint.is_empty():
        push_warning(complaint)
        return
    var control := node as Control
    mode.start()
    await mode.freeze(control, String(options.get("text", "")))
    print("SaCapture: note frozen on %s" % control.get_path())
    if bool(options.get("save", false)):
        print("SaCapture: note saved to %s" % mode.save(mode.box_text()))


## What a `note` step's target earns, and `""` when it names a Control the mode
## can freeze on.
##
## Two complaints rather than one. A docker is a `Window`, and a bare cast to
## Control would answer null for `ToolBoxDocker` with the message "no control
## called 'ToolBoxDocker' to note", which sends the reader looking for a typo in
## a name that is correct and that `docker`, `docker_resize` and `hide` all
## take. The name being wrong and the node being the wrong kind are different
## problems and read as different sentences.
##
## A string a caller can read rather than a `push_warning` inside the lookup,
## the shape `brush_editor_capture.shape_complaint` uses, so a test can assert
## what a step says without a tree to say it in.
static func target_complaint(target: String, node: Node) -> String:
    if node == null:
        return "SaCapture: no node called '%s' to note" % target
    if node is Control:
        return ""
    return "SaCapture: '%s' is a %s, and a note freezes on a Control, so there is nothing to outline" % [target, _kind_of(node)]


## What *node* is, in the words a reader needs to act on the refusal: the
## `class_name` its script declares and the engine class under it, because
## knowing a `ToolBoxDocker` is a `Window` is the half that explains the answer.
static func _kind_of(node: Node) -> String:
    var script := node.get_script() as Script
    var declared := String(script.get_global_name()) if script != null else ""
    if declared.is_empty() or declared == node.get_class():
        return node.get_class()
    return "%s, which is a %s" % [declared, node.get_class()]
