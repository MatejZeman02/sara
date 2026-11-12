## The bar's tool options as views another docker can hold: one per option key,
## the key's control for the tool in the hand.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## What can be placed is exactly the registered layout elements, and the bar
## registers every option key it builds a control for under "TopMenuBar", the
## brush's and the eraser's shared size as `radius`. A placed element is a
## second view of the same state as at home: a placed Size is the Size of the
## tool in the hand, in step with the bar's. So a view is built fresh, with
## controls of its own that build the one key from the same specs the bar builds
## it from, and it follows the bar it was built from rather than holding a value
## of its own.
##
## Registered through `SaSettings.register_layout_element`, the call a module
## makes for an element of its own, which is hard rule 6, from
## `ToolOptionsBar._register_titles`, the call that already named each key.
##
## The bar's own controls, the preset group, Keep, the symmetry three, the
## stabiliser's toggle, Edit Brush and the rotation pair, are views of
## `SaBarControlViews`, registered by [method register_controls].
class_name SaToolOptionViews
extends RefCounted

## The rotation pair's element names, as the top bar stores them.
const ROTATION := "Rotation"
const RESET_ROTATION := "Reset Rotation"

## The bar's own elements, in the bar's order, each a view of `SaBarControlViews`.
const OWN_ELEMENTS: Array[String] = [
    ToolOptionsBar.ELEMENT_PRESETS,
    ToolOptionsBar.ELEMENT_KEEP_BLEND,
    ToolOptionsBar.ELEMENT_EDIT_BRUSH,
    ToolOptionsBar.ELEMENT_MIRROR_H,
    ToolOptionsBar.ELEMENT_MIRROR_V,
    ToolOptionsBar.ELEMENT_RADIAL,
    ToolOptionsBar.ELEMENT_STABILIZER,
]

## The symmetry field each of the three switches stands for.
const SYMMETRY_FIELDS := {
    ToolOptionsBar.ELEMENT_MIRROR_H: &"mirror_horizontal",
    ToolOptionsBar.ELEMENT_MIRROR_V: &"mirror_vertical",
    ToolOptionsBar.ELEMENT_RADIAL: &"radial",
}


## What the door builds a view of *key* with: a fresh [OptionView] following
## *bar*. The bar is held weakly, so the door keeps no bar a suite has freed
## alive, and a bar built again registers again, its views replacing the last
## one's.
static func builder(bar: ToolOptionsBar, key: StringName) -> Callable:
    var held: WeakRef = weakref(bar)
    return func() -> Control: return OptionView.new(key, held.get_ref() as ToolOptionsBar)


## Hands the door a view of each of the bar's own controls: the seven of *bar*
## and the two of *rotation*, the top bar's element map of its rotation pair,
## `{"Rotation": slider, "Reset Rotation": button}`. *view_source* answers the
## canvas's `SaView`, the one the bar's slider turns.
##
## Called from `TopMenuBar.add_tool_options`, the one place that holds both the
## bar and the rotation pair, once the pair is built. Each element keeps the
## title it already had, so Preferences reads the same. Edit Brush, which no
## default order names, becomes a Preferences row through this call as well,
## at the end of the order, which is where the top bar already put it.
static func register_controls(bar: ToolOptionsBar, rotation: Dictionary, view_source: Callable) -> void:
    if bar == null:
        return
    # Every one of the seven, built or not: the running app hands the top bar
    # its tool options before the bar has built its controls, so each view
    # finds its home when it is built rather than when it is registered.
    var held: WeakRef = weakref(bar)
    for element: String in OWN_ELEMENTS:
        _register(element, func() -> Control: return own_view(element, held.get_ref() as ToolOptionsBar))
    var turn: WeakRef = weakref(rotation.get(ROTATION, null))
    if turn.get_ref() != null:
        _register(ROTATION, func() -> Control: return SaBarControlViews.RotationView.new(ROTATION, turn.get_ref(), view_source))
    var reset: WeakRef = weakref(rotation.get(RESET_ROTATION, null))
    if reset.get_ref() != null:
        _register(RESET_ROTATION, func() -> Control: return SaBarControlViews.ButtonView.new(RESET_ROTATION, reset.get_ref()))


## A fresh view of the bar's own *element*, standing for its control on *bar*.
## The preset group is the preset button, which is the group's face and its
## press. A gone bar gives a view with nothing behind it.
static func own_view(element: String, bar: ToolOptionsBar) -> Control:
    var home: Button = bar.layout_elements().get(element) as Button if bar != null else null
    if element == ToolOptionsBar.ELEMENT_PRESETS:
        return SaBarControlViews.PresetView.new(element, bar.preset_menu if bar != null else null)
    if element == ToolOptionsBar.ELEMENT_KEEP_BLEND:
        return SaBarControlViews.KeepBlendView.new(element, home)
    if element == ToolOptionsBar.ELEMENT_STABILIZER:
        return SaBarControlViews.StabilizerView.new(element, home, bar)
    if SYMMETRY_FIELDS.has(element):
        return SaBarControlViews.SymmetryView.new(element, home, bar, SYMMETRY_FIELDS[element])
    return SaBarControlViews.ButtonView.new(element, home)


## Under the title the element already has, which for a shipped one is the
## title Preferences gives it, "Symmetry H" for "Mirror H".
static func _register(element: String, view: Callable) -> void:
    SaSettings.register_layout_element("TopMenuBar", element, SaSettings.element_title("TopMenuBar", element), false, "", view)


## One option key's view: its control for the tool the bar shows, which is the
## tool in the hand and never one held on a key for a moment, the bar's own rule.
##
## Hidden while that tool declares no such key for the bar, so a view of Size
## with the eyedropper in the hand shows nothing rather than a brush row that
## reads as the eyedropper's.
##
## **It follows what the bar follows.** A change of tool, a preset load, the
## brackets and the eraser switch, through the same announcements the bar
## hears, and a write on either surface through the bar's controls: the bar's
## own writes as `option_written`, and the Tool Options docker's, which reach
## the bar's controls through `show_value`, as `value_shown`. Each reads the
## tool again rather than taking the value it carries, because the tool is
## what both surfaces wrote to.
##
## **A move on it is a write through the bar's door.** Its own controls write
## the shown tool, as the docker's do, and `ToolOptionsBar.write_option` then
## writes the same value to the same tool, puts it on the bar's control and
## announces it, which is how the docker and every other view hear it.
class OptionView:
    extends HBoxContainer

    ## The option key this view stands for, `radius`.
    var key: StringName = &""

    ## The view's own controls, which build this key's control alone from the
    ## specs the bar's are built from.
    var controls: ToolOptionControls

    ## The bar this view follows, weakly, so a freed bar leaves the view empty
    ## rather than reading a freed object.
    var _home: WeakRef

    func _init(for_key: StringName, home: ToolOptionsBar) -> void:
        key = for_key
        _home = weakref(home)
        name = String(for_key).capitalize().replace(" ", "") + "OptionView"
        set_meta(SaMake.KIND_META, SaMake.Kind.ROW)
        controls = ToolOptionControls.new(self)
        controls.only_flagged_for_bar = true
        controls.only_key = for_key
        controls.place = _place
        controls.option_written.connect(_on_own_written)
        if home != null:
            home.options.option_written.connect(_on_home_moved)
            home.options.value_shown.connect(_on_home_moved)
            home.options.binding.tools_changed.connect(_on_home_rebuilt)
            controls.binding.follow_blend_modes(home.options.binding.blend_registry)
        EventBus.tool_changed.connect(_on_tool_changed)
        EventBus.tool_options_moved.connect(sync)
        EventBus.preset_loaded.connect(_on_preset_loaded)
        EventBus.brush_eraser_toggled.connect(_on_eraser_toggled)
        EventBus.document_resized.connect(_on_document_resized)
        sync()

    func _notification(what: int) -> void:
        if what == NOTIFICATION_ENTER_TREE:
            sync()

    ## The bar this view follows, or null once it is gone.
    func home_bar() -> ToolOptionsBar:
        return _home.get_ref() as ToolOptionsBar

    ## The control this view shows, or null before the key's tool is loaded.
    func control() -> Control:
        return controls.control(key)

    ## The tool the bar shows, which is the one this view reads and writes.
    func shown_tool_id() -> StringName:
        var home := home_bar()
        return home.shown_tool_id() if home != null else &""

    ## Reads the shown tool's value onto the control, with the tool's own range,
    ## and hides the view while that tool declares no such key. Dimmed the way the
    ## bar dims its twin when the option another one decides is off.
    func sync() -> void:
        var home := home_bar()
        var machine: ToolMachine = home.target_tool_machine if home != null else null
        controls.binding.follow(machine)
        var tool_id := shown_tool_id()
        var tool: ToolState = machine.get_tool(tool_id) if machine != null and not String(tool_id).is_empty() else null
        var spec := controls.spec_for(key, tool_id)
        visible = tool != null and spec != null
        if not visible:
            return
        controls.muted = true
        controls.sync(tool, tool_id, controls.binding.canvas_min_dimension())
        controls.muted = false
        var rule: Variant = home.read_option(spec.enabled_when) if not String(spec.enabled_when).is_empty() else null
        SaOptionSpec.apply_enabled(control(), null, spec, rule)

    ## A slider takes the column's width, as a Tool Options row does. Every other
    ## kind keeps the size the bar gives it.
    func _place(spec: SaOptionSpec, built: Control) -> void:
        if spec.kind == SaOptionSpec.Kind.FLOAT or spec.kind == SaOptionSpec.Kind.INT:
            built.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        add_child(built)

    func _on_own_written(written: StringName, value: Variant) -> void:
        var home := home_bar()
        if home != null:
            home.write_option(written, value)

    func _on_home_moved(_written: StringName, _value: Variant) -> void:
        sync()

    ## The bar's controls were built again or its blend modes moved: a view built
    ## before the bar was handed the blend registry takes it now.
    func _on_home_rebuilt(_rebuilt: bool) -> void:
        var home := home_bar()
        if home != null and home.options.binding.blend_registry != controls.binding.blend_registry:
            controls.binding.follow_blend_modes(home.options.binding.blend_registry)
        sync()

    func _on_tool_changed(_tool_name: String) -> void:
        sync()

    func _on_preset_loaded(_preset_name: String) -> void:
        sync()

    func _on_eraser_toggled(_active: bool) -> void:
        sync()

    func _on_document_resized(_document: SaDocument, _size: Vector2i) -> void:
        sync()
