## A scenario's hand on one `FactorSlider`: the `slider_edit` step that opens
## its value field and types, reads it, cancels it, or drags the box.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `{"slider_edit": {"name": "SizeSlider", "type": "99"}}` opens a named
## slider's value field and types into it, and `{"read": true}` says what
## happened.
##
## **The only door into this control from a scenario.** The field is a `LineEdit`
## inside a `Control` inside a `Window`, and an injected click does not route
## into a window, which is the same wall `tablet_calibration.gd` and
## `sa_color_picker.gd` describe. So the step opens the field the way a double
## click does and types the way a keyboard does, and then the scenario sends a
## real `{"key": "escape"}` so the cancel is proved through Godot's own
## dispatch rather than by calling the handler.
##
## The slider is found by node name anywhere in the tree, windows included,
## because every one of them lives in a docker or a dialog rather than in the
## main viewport.
##
## `"window": "SaBrushEditorWindow"` looks only inside the window node of that
## name. The Brush Editor builds its rows with the same `ToolOptionControls` the
## Tool Options docker uses, so both call their Hardness slider `HardnessSlider`,
## and the docker is in the tree first, so a bare name always found the docker's.
## A key rather than a rule such as "prefer a shown window", because seven
## committed steps name `RadiusSlider` or `Radius`, which both windows carry, and
## a rule would move them off the slider they drag today without a line in any
## scenario saying so. With no `window` the lookup is exactly what it was.
##
## This was the scenario half of `factor_slider.gd`, and it lives here because
## the harness's hand belongs with the harness rather than the widget. One
## instance per step, holding the slider it found and what the step reads of
## it, and the slider never names this class.
class_name SaSliderEdit
extends RefCounted

## The slider the step found.
var _slider: FactorSlider

## The name the step asked for, which every line it prints quotes.
var _wanted: String

## The slider's value field, read once from the slider.
var _field: LineEdit

## The label over the slider's box, read once from the slider.
var _label: Label

## The window the slider sits in, or null, read once from the slider.
var _window: Window

## Where the slider is on screen when the step began.
var _rect: Rect2

## The slider's value when the step began.
var _before: float


func _init(slider: FactorSlider, wanted: String) -> void:
    _slider = slider
    _wanted = wanted
    _field = slider._line_edit
    _label = slider._label
    _window = slider.get_window()
    _rect = slider.get_global_rect()
    _before = slider.value


## Types into a slider: the step itself, what `SaStepTable` calls, answering the
## one `SaCapture:` line it prints.
static func capture_edit(tree: SceneTree, raw: Variant) -> String:
    var spec: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
    var wanted := String(spec.get("name", ""))
    if tree == null or tree.root == null or wanted.is_empty():
        return "SaCapture: a slider_edit needs a 'name'"
    var window_name := String(spec.get("window", ""))
    var slider := find_named(tree.root, wanted, window_name)
    if slider == null:
        if not window_name.is_empty():
            return "SaCapture: no FactorSlider called '%s' in a window called '%s'" % [wanted, window_name]
        return "SaCapture: no FactorSlider called '%s'" % wanted
    return SaSliderEdit.new(slider, wanted)._apply(spec)


## The slider named *wanted* under *root*, or inside the window node named
## *window_name* when one is given, or null. Static and taking any node, so a
## suite can hand it a detached pair of windows rather than the scene tree.
static func find_named(root: Node, wanted: String, window_name: String = "") -> FactorSlider:
    if root == null or wanted.is_empty():
        return null
    var scope := root
    if not window_name.is_empty():
        scope = root.find_child(window_name, true, false) as Window
        if scope == null:
            return null
    return scope.find_child(wanted, true, false) as FactorSlider


func _apply(spec: Dictionary) -> String:
    if bool(spec.get("read", false)):
        return _read()
    if spec.has("drag_to"):
        return _drag(float(spec["drag_to"]))
    if bool(spec.get("escape", false)):
        return _escape()

    _slider.start_editing()
    if spec.has("type"):
        _field.text = String(spec["type"])
    if bool(spec.get("submit", false)):
        _field.text_submitted.emit(_field.text)
    return (
        "SaCapture: slider_edit '%s' was %.4f, field shows '%s', editing=%s"
        % [_wanted, _before, _field.text, str(_field.visible)]
    )


func _read() -> String:
    var window := _window
    # `declines_escape` stood in this last column and asked the dialog base
    # whether a text field held the keyboard. The close is gone and the
    # check with it, so the window's own focus owner is read instead, which
    # is the same question without a method to hang it on.
    var focused: Control = window.gui_get_focus_owner() if window != null else null
    return (
        (
            "SaCapture: slider_edit '%s' value=%.4f label='%s' label_filter=%s editing=%s focused=%s"
            + " rect=%s window_at=%s window='%s' shown=%s window_focus='%s'"
        )
        % [
            _wanted,
            _before,
            _label.text,
            _filter_name(_label.mouse_filter),
            str(_field.visible),
            str(_field.has_focus()),
            str(_rect),
            str(window.position) if window != null else "<none>",
            window.title if window != null else "<none>",
            str(window.visible) if window != null else "<none>",
            String(focused.name) if focused != null else "<none>",
        ]
    )


func _escape() -> String:
    # **Godot's own handler, called the way Godot would call it.** An
    # injected key reaches a control inside an embedded subwindow only while
    # the embedder has given that window the keyboard, and Wayland will not
    # let a capture do that, which is the same wall an injected click meets. So the routing is what this
    # substitutes and nothing else: the event is a real `InputEventKey`, the
    # handler is the one connected to `gui_input`, reached by emitting that
    # signal on the field, and the control is the
    # live one in the live window. What the dump reads afterwards is the
    # value, the field and the window, none of which this touches.
    var key := InputEventKey.new()
    key.keycode = KEY_ESCAPE
    key.physical_keycode = KEY_ESCAPE
    key.pressed = true
    _field.gui_input.emit(key)
    return "SaCapture: slider_edit '%s' escaped, value=%.4f editing=%s" % [_wanted, _slider.value, str(_field.visible)]


## `{"slider_edit": {"name": "Radius", "drag_to": 0.5}}` presses on the box,
## drags to *fraction* of its width and releases, through the window's own
## dispatch rather than the handler.
##
## The events are pushed into the slider's `Window`, which hit-tests its
## controls the way a real press is hit-tested, and that routing is the whole
## claim: a Label over the box can eat every press before `_gui_input` sees
## one, and a step that called `_gui_input` directly would prove the handler
## while the painter's hand still met the Label. `push_input` on the
## embedded window itself, because the root viewport only forwards an injected
## event into a subwindow the compositor gave the keyboard, which Wayland will
## not do for a capture.
func _drag(fraction: float) -> String:
    var window := _window
    if window == null:
        return "SaCapture: slider_edit '%s' is in no window" % _wanted
    var rect := _rect
    var start := rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.5)
    var end := rect.position + Vector2(rect.size.x * clampf(fraction, 0.0, 1.0), rect.size.y * 0.5)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = start
    press.global_position = start
    window.push_input(press, true)
    var motion := InputEventMouseMotion.new()
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    motion.position = end
    motion.global_position = end
    motion.relative = end - start
    window.push_input(motion, true)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.position = end
    release.global_position = end
    window.push_input(release, true)
    return (
        "SaCapture: slider_edit '%s' dragged from %.4f to %.4f, label_filter=%s slider_filter=%s"
        % [_wanted, _before, _slider.value, _filter_name(_label.mouse_filter), _filter_name(_slider.mouse_filter)]
    )


static func _filter_name(filter: int) -> String:
    match filter:
        Control.MOUSE_FILTER_IGNORE:
            return "ignore"
        Control.MOUSE_FILTER_PASS:
            return "pass"
    return "stop"
