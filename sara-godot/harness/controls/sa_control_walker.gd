## Reads and moves any control `SaMake` made, by its name and its kind, so a
## screen writes no capture hook for a control a walker can read.
##
## Every control `SaMake` makes carries its kind under `SaMake.KIND_META`, and
## its name is the one the call gave it. This walks a tree for them. It prints
## any kind, and it moves the plain ones, a slider, a spin box, a toggle, a
## choice and a text field, the way a hand would: the value is written and the
## signal a hand's move fires is fired, so what the screen does next is its own
## wiring and not a second copy of it here.
##
## A control a walker cannot read keeps its hook on its screen, such as the
## layer list's rows, whose state is a layer rather than a value. So does a
## control no `SaMake` call made, which carries no kind to walk by.
##
## Reached by path from the step table and the drivers, like the rest of the
## harness, so no editor rescan stands between a fresh checkout and a step.
class_name SaControlWalker
extends RefCounted

## Where a docker named by its id is asked for, through the registry.
const CaptureRun := preload("res://harness/sa_capture_run.gd")
## The labels and buttons whose words a window cuts, the `cut_labels` step's.
const CutLabels := preload("res://harness/controls/sa_cut_labels.gd")
## Every text a window shows, the `cut_labels` step's `texts` form.
const VisibleTexts := preload("res://harness/controls/sa_visible_texts.gd")


## Lists the labels a window cuts.
##
## The `cut_labels` step, which [code]sa_cut_labels.gd[/code] beside this file
## measures and describes in full: `{"cut_labels": {"list": true}}` names the
## Preferences pages, dockers and menus, and `{"cut_labels": {"docker":
## "LayersDocker"}}` lists the labels and buttons of that window whose words do
## not fit. With `"texts": true` it lists every text the window shows instead,
## [code]sa_visible_texts.gd[/code]'s, and `{"texts": true, "windows": true}`
## reads every open dialog.
static func cut_labels(tree: SceneTree, spec: Variant) -> String:
    if spec is Dictionary and (spec as Dictionary).get("texts", false):
        return VisibleTexts.capture(tree, spec as Dictionary)
    return CutLabels.capture(tree, spec)


## Moves or reads a control: it moves the control and answers what it now reads,
## and without `"value"` only reads it, `{"control": {"name": "ChooserThumb",
## "value": "tip"}}`. `{"control": {"list": "BrushPresetsDocker"}}` prints every
## made control under the node of that name, in tree order.
##
## A name that finds nothing and a value the control cannot take are both a line
## carrying `failed`, which `scripts/sara_shot.py` reads as a problem.
static func capture(tree: SceneTree, spec: Dictionary) -> String:
    if spec.has("list"):
        var holder_name := String(spec["list"])
        var holder := CaptureRun.DockerLookup.named(tree.root, holder_name)
        if holder == null:
            return "SaCapture: control failed, nothing called '%s' to list" % holder_name
        return "SaCapture: controls under '%s' %s" % [holder_name, JSON.stringify(describe_all(holder))]
    var wanted := String(spec.get("name", ""))
    var control := find(tree.root, wanted)
    if control == null:
        return "SaCapture: control failed, no made control called '%s'" % wanted
    if not spec.has("value"):
        return "SaCapture: control '%s' reads %s" % [wanted, JSON.stringify(describe(control))]
    if not move(control, spec["value"]):
        return "SaCapture: control failed, '%s' (%s) cannot take %s" % [wanted, kind_name(control), JSON.stringify(spec["value"])]
    return "SaCapture: control '%s' moved, %s" % [wanted, JSON.stringify(describe(control))]


## The made control called *control_name* under *under*, or null, asked of the
## door's lookup, `SaAppDrive.find_made`, so the harness keeps no copy of it.
static func find(under: Node, control_name: String) -> Control:
    return SaAppDrive.find_made(under, control_name)


## What the made control called *control_name* under *under* holds, or null
## when there is none, because a closed window is not a switch that is off.
static func read(under: Node, control_name: String) -> Variant:
    var control := find(under, control_name)
    return value_of(control) if control != null else null


## The kind *control* was made as, in the words a dump prints, or an empty
## string for a control `SaMake` did not make.
static func kind_name(control: Control) -> String:
    var kind := SaMake.kind_of(control)
    if kind < 0:
        return ""
    return String(SaMake.Kind.keys()[kind]).to_lower()


## What *control* holds: the value of a slider, a spin box, a toggle or a choice,
## the text of a text field, a label or a button, and null for a container.
static func value_of(control: Control) -> Variant:
    match SaMake.kind_of(control):
        SaMake.Kind.SLIDER:
            return (control as FactorSlider).value
        SaMake.Kind.SPIN:
            return (control as SpinBox).value
        SaMake.Kind.TOGGLE:
            return (control as BaseButton).button_pressed
        SaMake.Kind.CHOICE:
            return (control as SaChoiceButton).selected_value()
        SaMake.Kind.TEXT:
            return (control as LineEdit).text
        SaMake.Kind.LABEL:
            return (control as Label).text
        SaMake.Kind.BUTTON:
            return (control as Button).text
    return null


## One control as a dump prints it: its name, its kind, what it holds, and
## whether a hand could reach it now. A choice adds the words it shows, because
## its value is what the caller wrote and not what the painter reads. A slider
## that names the value it moves adds that name under `moves`.
static func describe(control: Control) -> Dictionary:
    var out := {
        "name": String(control.name),
        "kind": kind_name(control),
        "value": value_of(control),
        "visible": control.is_visible_in_tree(),
        "enabled": _enabled(control),
    }
    if control is SaChoiceButton:
        out["shows"] = (control as SaChoiceButton).text
    var moves := SaAppDrive.name_of(control)
    if not moves.is_empty():
        out["moves"] = String(moves)
    return out


## Every made control under *under*, in tree order, each as [method describe]
## prints it. Containers are left out, because what they hold is listed anyway,
## and so is what a listed control is built from, such as the text field inside
## a slider, which is the slider's and not a control of the screen.
static func describe_all(under: Node) -> Array:
    var out: Array = []
    for child in under.get_children():
        var control := child as Control
        if control != null and _holds_a_value(control):
            out.append(describe(control))
        else:
            out.append_array(describe_all(child))
    return out


static func _holds_a_value(control: Control) -> bool:
    return (
        SaMake.kind_of(control)
        in [
            SaMake.Kind.LABEL,
            SaMake.Kind.BUTTON,
            SaMake.Kind.TOGGLE,
            SaMake.Kind.TEXT,
            SaMake.Kind.SPIN,
            SaMake.Kind.SLIDER,
            SaMake.Kind.CHOICE,
        ]
    )


## Moves *control* to *value* the way a hand would, and answers whether it took
## it. False for a kind a hand does not move, for a control a hand cannot reach
## because it is switched off, and for a value the control does not offer.
##
## A slider and a choice fire their signal only when the value moved, which is
## what a drag and a press on the marked row do. A text field fires
## `text_changed` as typing does, and `text_submitted` as well when the caller
## asks for the Enter key.
static func move(control: Control, value: Variant, submit: bool = false) -> bool:
    if control == null or not _enabled(control):
        return false
    match SaMake.kind_of(control):
        SaMake.Kind.SLIDER:
            return _move_slider(control as FactorSlider, value)
        SaMake.Kind.SPIN:
            if not (value is int or value is float):
                return false
            (control as SpinBox).value = float(value)
            return true
        SaMake.Kind.TOGGLE:
            if not value is bool:
                return false
            (control as BaseButton).button_pressed = bool(value)
            return true
        SaMake.Kind.CHOICE:
            return _move_choice(control as SaChoiceButton, value)
        SaMake.Kind.TEXT:
            var field := control as LineEdit
            field.text = str(value)
            field.text_changed.emit(field.text)
            if submit:
                field.text_submitted.emit(field.text)
            return true
    return false


## The slider's own rounding and range, and the signal a drag fires when the
## value moved.
static func _move_slider(slider: FactorSlider, value: Variant) -> bool:
    if not (value is int or value is float):
        return false
    var target := clampf(slider.quantized(float(value)), slider.min_value, slider.max_value)
    if absf(target - slider.value) > 1e-6:
        slider.set_value_no_signal(target)
        slider.value_changed.emit(slider.value)
    return true


## The row whose value is *value*, or failing that the row whose words are
## *value*, pressed the way a hand presses it. A number from JSON arrives as a
## float, so a value is also matched by its text, which is how a list of whole
## numbers is reached from a scenario.
static func _move_choice(choice: SaChoiceButton, value: Variant) -> bool:
    var values := choice.choice_values()
    var index := values.find(value)
    if index < 0:
        for i in values.size():
            if str(values[i]) == str(value) or (value is float and str(values[i]) == str(int(value))):
                index = i
                break
    if index < 0:
        index = choice.choice_labels().find(str(value))
    if index < 0:
        return false
    return choice.pick_row(index)


static func _enabled(control: Control) -> bool:
    if control is BaseButton:
        return not (control as BaseButton).disabled
    if control is LineEdit:
        return (control as LineEdit).editable
    if control is SpinBox:
        return (control as SpinBox).editable
    return true
