## The controls the tool options bar builds from each tool's SaOptionSpec list,
## and the one place that reads and writes the values behind them.
##
## Its own file because the canvas right-click menu needs the same read and
## write path without a control in hand: `read` and `write` go through the
## spec's property, so a check item in the menu and a toggle on the bar move the
## same field the same way.
##
## One control per key, shared by every tool that declares the key. The brush
## and the eraser both declare `radius`, and a painter expects one Size
## control that follows whichever is active, each writing its own settings.
## The first tool to declare a key builds the control, and a later tool has to
## agree on its kind or its spec is refused with a warning.
##
## Two surfaces build from the same specs: the bar, which takes the options
## flagged `bar`, and the Tool Options docker, which takes all of them. Each has
## its own instance and its own controls, so the host is a plain `Control` here
## rather than the bar, and `place` lets the docker wrap a control
## in a labelled row instead of adding it bare.
##
## What the controls follow is `ToolOptionBinding`, one per instance as
## `binding`, so a surface hands the binding its machine and blend registry.
extends RefCounted

class_name ToolOptionControls

## By path, so no editor rescan of the class cache stands between a fresh
## checkout and a press.
const CurveOptionHost := preload("res://ui/brush_editor/preview/curve_option_host.gd")

## A control on this surface was moved and the value written to the tool. The
## other surface listens, because both show the same option and a slider that
## does not follow its twin reads as broken.
signal option_written(key: StringName, value: Variant)

## A value another surface wrote was put on a control here. A placed view hears it.
signal value_shown(key: StringName, value: Variant)

## The key the blend dropdown is shared under, whichever tool declared it.
const BLEND_KEY := &"blend_mode"

## Set on a control that wants the row's whole width under its label whatever
## the row's width, the Tip Image grid: beside the label its pictures would
## flow in the column a value takes, and the docker would stand twice as tall.
const UNDER_LABEL_META := &"sa_option_under_label"


## A built control and what it stands for.
class Entry:
    var key: StringName
    var kind: SaOptionSpec.Kind
    var control: Control
    ## tool id -> the spec that tool declared for this key.
    var specs: Dictionary = {}
    ## The spec the control was built from, so a tool whose spec differs can
    ## have its range applied on the way in.
    var applied: SaOptionSpec
    ## tool id -> what Backspace puts back on a slider while that tool is shown.
    ## The value the tool held when it was first shown here, and from then on
    ## the value its last loaded preset gave it. A key the brush and the eraser
    ## share keeps one each, so the eraser is not put back to the brush's preset.
    var defaults: Dictionary = {}
    ## The tool whose value the control showed through the last `sync`, which is
    ## the one `defaults` is read for when a preset moves them.
    var shown_for: StringName = &""

    func belongs_to(tool_id: StringName) -> bool:
        return specs.has(tool_id)


## The node the controls are built under, and where `tr()` comes from.
var _host: Control
## key -> Entry, in build order.
var _entries: Dictionary = {}
## The tools whose options have been built, so a registry that announces a
## change costs one pass over the descriptors rather than a rebuild.
var _built_tools: Dictionary = {}

## True while the host is the one moving a control, so mirroring a value onto
## a slider does not write it straight back to the tool.
var muted: bool = false

## What a `CURVE_OPTION` row's button opens, set by the brush editor window to
## `func(option: SaCurveOption, page: String) -> void`.
##
## A seam rather than a call into the editor, because the editor is a window
## this file must not know about: the docker builds a button from a spec, and
## whoever can open an editor says so by binding this. Empty until the editor
## binds it, and the button then falls back to the bare host.
static var open_curve_editor: Callable = Callable()

## Take only the options a tool flagged for the bar. The docker leaves this off
## and shows everything.
var only_flagged_for_bar: bool = false

## Leave out the options a tool marked `in_docker` false, which the docker sets.
var for_docker: bool = false

## Take the option of this key alone, which a view of one bar option does.
var only_key: StringName = &""

## `func(spec: SaOptionSpec, control: Control) -> void`, called instead of
## adding the control to the host directly. The docker uses it to put a label
## beside the control and keep the row it can hide.
var place: Callable = Callable()

## The tool the controls are showing, remembered from the last `sync` so a
## control that moves knows what to write to.
var _shown_tool: ToolState = null
var _shown_tool_id: StringName = &""

## What the controls follow, the machine, its registry, the blend registry and
## the document, and what says when they moved.
var binding: ToolOptionBinding


func _init(host: Control) -> void:
    _host = host
    binding = ToolOptionBinding.new(build_for, drop_missing, has_built, control.bind(BLEND_KEY))
    host.tree_entered.connect(_hear_presets)
    host.tree_exiting.connect(_stop_hearing_presets)
    if host.is_inside_tree():
        _hear_presets()


## Builds a control for every option of *descriptor* that has none yet, as
## the bar's children. True when something was added, which is the top bar's
## cue to apply the stored layout again.
func build_for(descriptor: SaToolDescriptor) -> bool:
    if descriptor == null or _built_tools.has(descriptor.id):
        return false
    _built_tools[descriptor.id] = true
    var added := false
    for spec: SaOptionSpec in descriptor.options:
        if spec == null or String(spec.key).is_empty():
            continue
        if (only_flagged_for_bar and not spec.bar) or (only_key != &"" and spec.key != only_key):
            continue
        if for_docker and not spec.in_docker:
            continue
        var entry: Entry = _entries.get(spec.key, null)
        if entry != null:
            if entry.kind != spec.kind:
                push_warning(
                    (
                        "ToolOptionControls: tool '%s' declares '%s' as a different kind from the control already built, ignored."
                        % [descriptor.id, spec.key]
                    )
                )
                continue
            entry.specs[descriptor.id] = spec
            continue
        var built := _build(spec)
        if built == null:
            continue
        entry = Entry.new()
        entry.key = spec.key
        entry.kind = spec.kind
        entry.control = built
        entry.applied = spec
        entry.specs[descriptor.id] = spec
        _entries[spec.key] = entry
        if place.is_valid():
            place.call(spec, built)
        else:
            _host.add_child(built)
        # The theme pass in `ui/main/main.gd` has already been over the bar by the
        # time a module's tools arrive, and it themes what exists then: a
        # control built afterwards kept the default font and drew visibly
        # smaller than its neighbours.
        DockerUtils.apply_ui_theme(built)
        added = true
    return added


## Drops the controls of tools *registry* does not hold now, and forgets the
## tools so a module loaded again builds afresh. True when something went.
func drop_missing(registry: SaToolRegistry) -> bool:
    if registry == null:
        return false
    var changed := false
    for tool_id: StringName in _built_tools.keys().duplicate():
        if registry.has(tool_id):
            continue
        _built_tools.erase(tool_id)
        for key: StringName in _entries.keys().duplicate():
            var entry: Entry = _entries[key]
            entry.specs.erase(tool_id)
            if entry.specs.is_empty():
                if entry.control != null:
                    entry.control.queue_free()
                _entries.erase(key)
                changed = true
    return changed


## Whether the controls of *tool_id* have been built.
func has_built(tool_id: StringName) -> bool:
    return _built_tools.has(tool_id)


## Stored element name -> control, for the top bar's layout pass.
func layout_elements() -> Dictionary:
    var out := {}
    for key: StringName in _entries:
        out[String(key)] = (_entries[key] as Entry).control
    return out


## What Preferences calls the row for *key*: the label, and the tools that
## declare it in brackets, so "Merged (Eyedropper)" says whose it is.
func title_for(key: StringName, registry: SaToolRegistry) -> String:
    var entry: Entry = _entries.get(key, null)
    if entry == null:
        return String(key)
    var names: Array[String] = []
    for tool_id: StringName in entry.specs:
        var descriptor := registry.get_descriptor(tool_id) if registry != null else null
        names.append(descriptor.display_name if descriptor != null else String(tool_id))
    return "%s (%s)" % [entry.applied.label, ", ".join(names)]


func keys() -> Array[StringName]:
    var out: Array[StringName] = []
    for key: StringName in _entries:
        out.append(key)
    return out


func control(key: StringName) -> Control:
    var entry: Entry = _entries.get(key, null)
    return entry.control if entry != null else null


## Whether *spec* is one the painter has asked to see.
##
## This is the one place that reads `SaOptionSpec.advanced`, so both surfaces
## ask the same question rather than each carrying a copy of the rule.
##
## The Tool Options docker asks it. The top bar does not, because a spec is only
## on the bar when its author set `bar`, which is already a judgement that this
## one belongs at hand.
static func shows_advanced(spec: SaOptionSpec) -> bool:
    return spec == null or not spec.advanced or SaSettings.advanced_options


func is_generated(node: Control) -> bool:
    for key: StringName in _entries:
        if (_entries[key] as Entry).control == node:
            return true
    return false


## Whether *node* is a control *tool_id* declared.
func belongs_to(node: Control, tool_id: StringName) -> bool:
    for key: StringName in _entries:
        var entry: Entry = _entries[key]
        if entry.control == node:
            return entry.belongs_to(tool_id)
    return false


## Whether the spec *tool_id* declared for *node* asks the bar to show it only
## while that tool is in hand, `SaOptionSpec.bar_own_tool`.
func own_tool_only(node: Control, tool_id: StringName) -> bool:
    for key: StringName in _entries:
        var entry: Entry = _entries[key]
        if entry.control == node:
            var spec: SaOptionSpec = entry.specs.get(tool_id, null)
            return spec != null and spec.bar_own_tool
    return false


## The spec *tool_id* declared for *key*, or null.
func spec_for(key: StringName, tool_id: StringName) -> SaOptionSpec:
    var entry: Entry = _entries.get(key, null)
    return entry.specs.get(tool_id, null) if entry != null else null


## The keys *tool_id* declared, in the order the bar built them.
func keys_for(tool_id: StringName) -> Array[StringName]:
    var out: Array[StringName] = []
    for key: StringName in _entries:
        if (_entries[key] as Entry).belongs_to(tool_id):
            out.append(key)
    return out


func sliders() -> Array[FactorSlider]:
    var out: Array[FactorSlider] = []
    for key: StringName in _entries:
        var slider := (_entries[key] as Entry).control as FactorSlider
        if slider != null:
            out.append(slider)
    return out


## The value behind *key* on *tool*, or null when the tool does not declare
## it or has nowhere to keep it.
##
## A `CURVE` row answers its points rather than the `Curve` object, because every
## caller here reads a value rather than holds one, and an `Object` in a dump
## stringifies to `null`: a row with a shape on it would have read like a row
## with nothing behind it. The write side is deliberately not its mirror, a
## control's move going through `_on_curve_changed` below.
func read(key: StringName, tool: ToolState, tool_id: StringName) -> Variant:
    var spec := spec_for(key, tool_id)
    var target := _target_of(spec, tool)
    if target == null:
        return null
    var value: Variant = target.get_indexed(spec.property_path())
    if spec.kind == SaOptionSpec.Kind.CURVE:
        return SaCurveRow.points_of(value as Curve)
    return value


## Writes *value* behind *key* on *tool* and mirrors it onto the control.
## True when there was somewhere to write.
func write(key: StringName, value: Variant, tool: ToolState, tool_id: StringName) -> bool:
    var spec := spec_for(key, tool_id)
    var target := _target_of(spec, tool)
    if target == null:
        return false
    target.set_indexed(spec.property_path(), value)
    show_value(key, value)
    option_written.emit(key, value)
    return true


## Puts *value* on the control for *key* without writing it anywhere. What
## the other surface calls when this one moved the option.
func show_value(key: StringName, value: Variant) -> void:
    var entry: Entry = _entries.get(key, null)
    if entry == null:
        return
    var was_muted := muted
    muted = true
    _show_value(entry, value)
    muted = was_muted
    value_shown.emit(key, value)


## Mirrors every value *tool* holds onto the controls. The bar's signal guard
## is up while this runs. *canvas_min* is the document's smaller dimension,
## for the specs that show a canvas fraction as pixels. A slider is named for
## the tool it shows, so a MIDI binding moves that tool's value.
func sync(tool: ToolState, tool_id: StringName, canvas_min: float) -> void:
    _shown_tool = tool
    _shown_tool_id = tool_id
    for key: StringName in _entries:
        var entry: Entry = _entries[key]
        var spec: SaOptionSpec = entry.specs.get(tool_id, null)
        if spec == null:
            continue
        if spec != entry.applied:
            _apply_range(entry.control, spec)
            entry.applied = spec
        var slider := entry.control as FactorSlider
        if slider != null and spec.scale_by_canvas:
            slider.display_value_multiplier = spec.display_scale * canvas_min
        var target := _target_of(spec, tool)
        # An ACTION row's property names a method, not a value, so there is
        # nothing to read back onto it.
        if target == null or spec.kind == SaOptionSpec.Kind.ACTION:
            continue
        # The grid hears the tool's loads and reads the row again after one.
        if spec.kind == SaOptionSpec.Kind.TIP_IMAGE:
            (entry.control as SaTipGrid).follow(tool, read_spec.bind(spec, tool))
        var value: Variant = target.get_indexed(spec.property_path())
        if value == null:
            continue
        _show_value(entry, value)
        entry.shown_for = tool_id
        if slider != null:
            slider.value_name = StringName("tool/%s/%s" % [tool_id, key])
            slider.words = spec.words_on(target)
        _hold_default(entry, tool_id, value, false)


## Gives a slider the value Backspace puts back while *tool_id* is shown, and
## remembers it per tool.
##
## A slider is built with a range and no value, and the first `sync` is what
## puts the tool's value on it, so a default taken when the slider is built
## would be the range's floor and Backspace over Flow would lay no paint. A
## later `sync` keeps what is held, because it also runs after a drag, a tool
## switch and a canvas resize, and a default that followed it would be whatever
## the painter had just moved the slider to. *from_preset* is the one caller
## that moves it, `_on_preset_loaded`.
func _hold_default(entry: Entry, tool_id: StringName, value: Variant, from_preset: bool) -> void:
    var slider := entry.control as FactorSlider
    if slider == null:
        return
    if from_preset or not entry.defaults.has(tool_id):
        entry.defaults[tool_id] = float(value)
    if entry.shown_for == tool_id:
        slider.default_value = entry.defaults[tool_id]


## The connection to `EventBus.preset_loaded` lives as long as the host is in
## the tree. A surface freed with its controls left the connection behind
## when it was made in `_init` and nothing broke it, so every preset loaded
## for the rest of the run tested a control that was gone. A host that
## is not in the tree has no row on screen to follow a preset, and it listens
## from the moment it enters.
func _hear_presets() -> void:
    if not EventBus.preset_loaded.is_connected(_on_preset_loaded):
        EventBus.preset_loaded.connect(_on_preset_loaded)


func _stop_hearing_presets() -> void:
    if EventBus.preset_loaded.is_connected(_on_preset_loaded):
        EventBus.preset_loaded.disconnect(_on_preset_loaded)


## A preset was loaded, or a new brush started: the settings of the tool that
## took it hold the preset's values now, so those are what Backspace puts back.
##
## Read off the settings and not off the sliders, because the surfaces take the
## announcement one after another and the slider of a surface that has not yet
## taken it still shows the value from before. The bar writes the preset before
## it announces, so the settings are final by now.
func _on_preset_loaded(_stored_name: String) -> void:
    var tool := _shown_tool
    var tool_id := _shown_tool_id
    var machine := binding._machine
    if (tool == null or tool.get("settings") == null) and machine != null:
        tool_id = machine.fallback_tool_name()
        tool = machine.get_tool(tool_id)
    if tool == null:
        return
    for key: StringName in _entries:
        var entry: Entry = _entries[key]
        var spec: SaOptionSpec = entry.specs.get(tool_id, null)
        if spec == null or not (entry.control is FactorSlider):
            continue
        var value: Variant = read_spec(spec, tool)
        if value != null:
            _hold_default(entry, tool_id, value, true)


## The value behind *spec* on *tool*, for a caller holding the spec rather
## than a control.
##
## The canvas right-click menu offers every option a tool declares, and the bar
## builds a control only for the ones flagged `bar`, so the menu cannot go
## through an entry any more.
static func read_spec(spec: SaOptionSpec, tool: ToolState) -> Variant:
    var target := _target_of(spec, tool)
    return target.get_indexed(spec.property_path()) if target != null else null


## Writes *value* behind *spec* on *tool*, with no control in hand. True when
## there was somewhere to write.
static func write_spec(spec: SaOptionSpec, value: Variant, tool: ToolState) -> bool:
    var target := _target_of(spec, tool)
    if target == null:
        return false
    target.set_indexed(spec.property_path(), value)
    return true


## The object the spec's property lives on: the tool, or its settings.
static func _target_of(spec: SaOptionSpec, tool: ToolState) -> Object:
    if spec == null or tool == null:
        return null
    if spec.on_tool:
        return tool
    var settings: Variant = tool.get("settings")
    return settings if settings is Object else null


func _show_value(entry: Entry, value: Variant) -> void:
    match entry.kind:
        SaOptionSpec.Kind.FLOAT, SaOptionSpec.Kind.INT:
            (entry.control as FactorSlider).value = float(value)
        SaOptionSpec.Kind.BOOL:
            (entry.control as Button).set_pressed_no_signal(bool(value))
        SaOptionSpec.Kind.ENUM:
            # By value rather than by hunting an index for it, which is what a
            # row keyed on the caller's own value buys.
            (entry.control as SaChoiceButton).select_value(value)
        SaOptionSpec.Kind.BLEND_MODE:
            (entry.control as BlendModeButton).select_mode(StringName(value))
        SaOptionSpec.Kind.CURVE:
            # Muted, because `sync` does not, and `set_points` reports a move:
            # a slider mirrored onto itself rewrites the number that was there
            # and nothing notices, where a curve would build a new `Curve`, write
            # it and report it, marking an untouched brush changed on every open.
            var graph := SaCurveRow.graph_of(entry.control)
            if graph != null:
                var was_muted := muted
                muted = true
                graph.set_points(SaCurveRow.points_of(value as Curve))
                muted = was_muted
        SaOptionSpec.Kind.TIP_IMAGE:
            (entry.control as SaTipGrid).show_tip(String(value))
        SaOptionSpec.Kind.CUSTOM:
            # The module says how its own widget takes a value. The ramp's
            # binder points the control at the ramp object itself rather than
            # handing it a copy: the painter edits the tool's own ramp and the
            # live preview reads the same one.
            var binder: Callable = entry.applied.bind_value if entry.applied != null else Callable()
            if binder.is_valid():
                binder.call(entry.control, value)
        _:
            pass


func _build(spec: SaOptionSpec) -> Control:
    match spec.kind:
        SaOptionSpec.Kind.FLOAT, SaOptionSpec.Kind.INT:
            return _build_slider(spec)
        SaOptionSpec.Kind.BOOL:
            return _build_toggle(spec)
        SaOptionSpec.Kind.ENUM:
            return _build_choice(spec)
        SaOptionSpec.Kind.BLEND_MODE:
            return _build_blend(spec)
        SaOptionSpec.Kind.ACTION:
            return _build_action(spec)
        SaOptionSpec.Kind.CURVE_OPTION:
            return _build_curve_option(spec)
        SaOptionSpec.Kind.CURVE:
            return _build_curve(spec)
        SaOptionSpec.Kind.CUSTOM:
            return _build_custom(spec)
        SaOptionSpec.Kind.TIP_IMAGE:
            return _build_tip_image(spec)
        _:
            # COLOR has no consumer yet: the picker docker holds the colour.
            return null


func _build_slider(spec: SaOptionSpec) -> FactorSlider:
    var slider := FactorSlider.new()
    slider.name = _node_name(spec.key, "Slider")
    _apply_range(slider, spec)
    slider.custom_minimum_size = Vector2(
        DockerUtils.px(spec.width if spec.width > 0 else ToolOptionsBar.SLIDER_MIN_WIDTH), DockerUtils.px(18)
    )
    slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    slider.value_changed.connect(_on_slider_changed.bind(spec.key))
    return slider


## The range, the text, the tooltip and the display of a slider, from *spec*. Applied
## again when the shown tool's spec for the key differs from the one the
## control was built from.
func _apply_range(node: Control, spec: SaOptionSpec) -> void:
    var slider := node as FactorSlider
    if slider == null:
        return
    slider.min_value = spec.min_value
    slider.max_value = spec.max_value
    slider.soft_max_value = spec.soft_max
    slider.logarithmic = spec.logarithmic
    slider.step = 1.0 if spec.kind == SaOptionSpec.Kind.INT else spec.step
    slider.prefix = _host.tr(spec.label) + ": "
    slider.suffix = spec.suffix
    slider.normalized_display = spec.percent
    slider.decimal_places = 0 if spec.kind == SaOptionSpec.Kind.INT else spec.decimals
    slider.trim_trailing_zeros = spec.trim_trailing_zeros
    slider.steps_by_whole_units = spec.steps_by_whole_units
    slider.display_value_multiplier = spec.display_scale
    # With the rest, because one slider serves every tool declaring the key, and
    # the noise brush's Opacity is not the stamp brush's.
    slider.tooltip_text = _host.tr(spec.tooltip)


## A widget the declaring module builds.
##
## The one kind this file cannot build, and the point of it: the enum is not a
## fixed list, so a widget such as the gradient tool's colour ramp lives with
## the module that needs it rather than here. The factory comes off the spec, the
## width, the name and the tooltip are still applied here, because a module that
## brings a widget should not also have to know how the layout names a row or how
## the host translates a string.
##
## The `write` handed to the factory is this file's own write path, so a widget
## that reports a move is muted, mirrored onto the other surface and written to
## the shown tool exactly as a slider is. The ramp never calls it: its value is an
## object the binder pointed it at, and every edit lands on that object directly.
## Nothing is connected to `ramp_changed` either, because an option change
## repaints nothing in Sara, a gradient being set up before the drag rather than
## during it.
func _build_custom(spec: SaOptionSpec) -> Control:
    if not spec.build_control.is_valid():
        push_warning("ToolOptionControls: option '%s' is CUSTOM and brought no factory." % spec.key)
        return null
    var key := spec.key
    var built := spec.build_control.call(spec, func(value: Variant) -> void: _write_from_control(key, value)) as Control
    if built == null:
        push_warning("ToolOptionControls: the factory for option '%s' built no control." % spec.key)
        return null
    built.name = _node_name(spec.key, "Custom")
    if spec.width > 0:
        built.custom_minimum_size = Vector2(DockerUtils.px(spec.width), built.custom_minimum_size.y)
    if not spec.tooltip.is_empty():
        built.tooltip_text = _host.tr(spec.tooltip)
    return built


## The `TIP_IMAGE` row, a grid of the tip folders' pictures whose press is
## written the way a choice's is. It asks the docker's row for the width under
## its label rather than the column beside it.
func _build_tip_image(spec: SaOptionSpec) -> SaTipGrid:
    var grid := SaTipGrid.new(_on_choice_picked.bind(spec.key))
    grid.name = _node_name(spec.key, "Grid")
    grid.set_meta(UNDER_LABEL_META, true)
    if not spec.tooltip.is_empty():
        grid.tooltip_text = _host.tr(spec.tooltip)
    return grid


## Drives a custom option: a `CUSTOM` control's own capture door, for a scenario
## step.
##
## By method rather than by class, because the skeleton does not know what a
## colour ramp is, so the step
## finds the visible control answering `capture_option_edit` and hands it the
## step's dictionary. A widget that wants a step of its own writes that one
## method and needs no line here.
##
## The name is `capture_option_edit` and not `capture_edit`, because
## `FactorSlider` carries a static `capture_edit` taking a tree and a value,
## every slider on screen would answer `has_method` for it, and the ramp step
## would go to the first slider it met and report a bad call.
## A door found by name has to be named for the door and not for the verb.
static func capture_custom(tree: SceneTree, spec: Dictionary) -> String:
    if tree == null:
        return "SaCapture: no tree"
    for node in tree.root.find_children("*", "Control", true, false):
        var widget := node as Control
        if widget != null and widget.has_method("capture_option_edit") and widget.is_visible_in_tree():
            return String(widget.call("capture_option_edit", spec))
    return "SaCapture: no custom option control on screen to edit"


## A modulated parameter. A button that opens the editor at the option's own
## page, not an inline graph.
##
## Not inline because the control is a slider, eight preset buttons, a sensor
## list, a graph and two rows underneath, which is a page and not a row on a bar
## that is already tight at 1920.
func _build_curve_option(spec: SaOptionSpec) -> Button:
    var btn := _bar_button(spec, "Curve", 54)
    btn.text = _host.tr(spec.label)
    btn.pressed.connect(_on_curve_option_pressed.bind(spec.key))
    return btn


## A `Button` the bar builds, with what every kind shares: its name from the
## key, its width from the spec or *default_width*, the row's height, centred in
## the row, the tooltip or the label in its place, and no keyboard focus.
##
## **No focus**, because of the Space key. A button focused by its click answers
## the next Space itself, as `ui_accept`, before the shortcut router sees it, so
## a toggle pressed on the bar would turn the pan key into a second press of
## that toggle, so the rows built here from a spec say so as the bar's own
## buttons do.
func _bar_button(spec: SaOptionSpec, suffix: String, default_width: int) -> Button:
    var btn := SaMake.button(null, _node_name(spec.key, suffix))
    btn.custom_minimum_size = Vector2(
        DockerUtils.px(spec.width if spec.width > 0 else default_width), DockerUtils.px(DockerUtils.BASE_ICON_SIZE + 2)
    )
    var label := _host.tr(spec.label)
    btn.tooltip_text = _host.tr(spec.tooltip) if not spec.tooltip.is_empty() else label
    btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    btn.focus_mode = Control.FOCUS_NONE
    return btn


## The `CURVE` row, built by `SaCurveRow`, which owns what a `Curve` and a
## graph's points are to each other and says the rest.
func _build_curve(spec: SaOptionSpec) -> Control:
    var tooltip := _host.tr(spec.tooltip) if not spec.tooltip.is_empty() else ""
    return SaCurveRow.build(_node_name(spec.key, "Curve"), tooltip, _on_curve_changed.bind(spec.key))


## A `CURVE` row was drawn on: write the shape the graph now holds, as a whole
## new `Curve` rather than as an edit of the one the tool holds. The resource is
## `@export`ed and travels inside the preset, so replacing it is one write
## through the door every other kind writes through, where editing it in place
## would move a value nothing was told about.
func _on_curve_changed(key: StringName) -> void:
    if muted:
        return
    var entry := _entries.get(key, null) as Entry
    var graph := SaCurveRow.graph_of(entry.control) if entry != null else null
    if graph == null:
        return
    var was: Variant = read_spec(spec_for(key, _shown_tool_id), _shown_tool)
    _write_from_control(key, SaCurveRow.curve_of(graph.points, was as Curve))


## Opens whatever can host the option behind *key* on the shown tool.
##
## The editor when one has bound itself, the bare host otherwise, and a warning
## when the property holds no resource, because a button that does nothing
## quietly is a defect the capture harness once filed. A resource and not a
## class: the option's class is the declaring module's, and the skeleton knows
## only that the page's widget, which the spec brings, edits it in place.
func _on_curve_option_pressed(key: StringName) -> void:
    var spec := spec_for(key, _shown_tool_id)
    var value: Variant = read(key, _shown_tool, _shown_tool_id)
    var option := value as Resource
    if spec == null or option == null:
        push_warning("SaCapture: '%s' holds no curve option to edit" % key)
        return
    var page := spec.page if not spec.page.is_empty() else spec.label
    if open_curve_editor.is_valid():
        open_curve_editor.call(option, page)
        return
    CurveOptionHost.open(_host.get_tree(), spec, option, page)


func _build_toggle(spec: SaOptionSpec) -> Button:
    var with_icon := not spec.icon.is_empty()
    var btn := _bar_button(spec, "Btn", SaBarIconButton.WIDTH if with_icon else 54)
    btn.toggle_mode = true
    # Godot's own pressed box is a shade off its normal one, which against a
    # dark panel is no difference at all.
    SaTheme.make_toggle(btn)
    if with_icon:
        SaBarIconButton.shape(btn, spec.icon, _host.tr(spec.label))
    else:
        btn.text = _host.tr(spec.label)
    btn.toggled.connect(_on_toggled.bind(spec.key))
    return btn


## A row that does something rather than holding a value: the crop tool's Crop
## button. `property` names the method it calls on the tool, so the docker can
## carry a command without a second declaration language beside SaOptionSpec.
func _build_action(spec: SaOptionSpec) -> Button:
    var btn := _bar_button(spec, "Action", 54)
    btn.text = _host.tr(spec.label)
    btn.pressed.connect(_on_action_pressed.bind(spec.key))
    return btn


## The `ENUM` row: a button opening `SaChoicePopup`, where it was an
## `OptionButton` whose list is a `PopupMenu`. The node keeps its name, so a
## dump and a scenario step still find `StabilizerModeOpt`, and the labels are
## translated here rather than in the control because the host is what knows the
## locale.
func _build_choice(spec: SaOptionSpec) -> SaChoiceButton:
    var option := SaMake.choice(null, _node_name(spec.key, "Opt"))
    option.custom_minimum_size = Vector2(
        DockerUtils.px(spec.width if spec.width > 0 else 84), DockerUtils.px(DockerUtils.BASE_ICON_SIZE + 2)
    )
    option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    # Drawn at the theme's size, as the blend chip, the Keep toggle and the
    # sliders' numbers are, so no drop-down on the bar reads smaller than the
    # controls it stands among.
    if not spec.tooltip.is_empty():
        option.tooltip_text = _host.tr(spec.tooltip)
    var rows: Array = []
    for choice: Dictionary in spec.choices:
        rows.append({"id": choice.get("id"), "label": _host.tr(String(choice.get("label", "")))})
    option.set_choices(rows)
    # A choice that carries its own sentence shows it on its row, written on the
    # row's button the way `SaMenu.set_item_tooltip` writes a menu row's, so
    # the stabilizer's three modes read the same here as in the Tools menu.
    for choice: Dictionary in spec.choices:
        var sentence := String(choice.get("tooltip", ""))
        var row := option.popup.label_button(SaChoiceButton.row_id_of(choice.get("id")))
        if row != null and not sentence.is_empty():
            row.tooltip_text = _host.tr(sentence)
    option.choice_picked.connect(_on_choice_picked.bind(spec.key))
    return option


## Pointed at the registry by `_refresh_blend_modes`, because modules
## have not registered anything yet at construction time and the labels follow
## the document's colour space.
func _build_blend(spec: SaOptionSpec) -> BlendModeButton:
    var button := BlendModeButton.new(true)
    button.name = _node_name(spec.key, "Opt")
    button.custom_minimum_size = Vector2(
        DockerUtils.px(spec.width if spec.width > 0 else BlendModeButton.MIN_WIDTH),
        DockerUtils.px(DockerUtils.BASE_ICON_SIZE + 2)
    )
    button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    # No font scale of its own: the theme's size is what Keep Blend Mode beside
    # it and the sliders after it draw, and a chip a size smaller read as an
    # afterthought among them. The bar's second row has the room at 1920.
    if not spec.tooltip.is_empty():
        button.tooltip_text = _host.tr(spec.tooltip)
    button.mode_selected.connect(_on_blend_selected.bind(spec.key))
    return button


## `radius` -> `RadiusSlider`, so a node name stays readable in a dump.
static func _node_name(key: StringName, suffix: String) -> String:
    return String(key).capitalize().replace(" ", "") + suffix


func _on_slider_changed(value: float, key: StringName) -> void:
    _write_from_control(key, value)
    # A drag ticks an option that was off, so the words go with the first move.
    var entry: Entry = _entries.get(key, null)
    if entry != null and entry.applied != null and _shown_tool != null:
        (entry.control as FactorSlider).words = entry.applied.words_on(_target_of(entry.applied, _shown_tool))


func _on_toggled(pressed: bool, key: StringName) -> void:
    _write_from_control(key, pressed)


## An ACTION row was clicked: call the method on whichever tool is shown.
func _on_action_pressed(key: StringName) -> void:
    if muted:
        return
    var spec := spec_for(key, _shown_tool_id)
    var target := _target_of(spec, _shown_tool)
    var method := String(spec.property_path()) if spec != null else ""
    if target != null and not method.is_empty() and target.has_method(method):
        target.call(method)


func _on_choice_picked(value: Variant, key: StringName) -> void:
    _write_from_control(key, value)


func _on_blend_selected(mode_id: StringName, key: StringName) -> void:
    _write_from_control(key, mode_id)


## A control moved: write it to the shown tool, unless the host is the one
## moving the control, and count it on the usage tally as a value the hand set
## on this surface.
##
## The tool comes from the last `sync` rather than from the host, because the
## host is a plain `Control` and both surfaces sync on every tool change anyway.
func _write_from_control(key: StringName, value: Variant) -> void:
    if muted:
        return
    var spec := spec_for(key, _shown_tool_id)
    var target := _target_of(spec, _shown_tool)
    if target != null:
        target.set_indexed(spec.property_path(), value)
        SaUsageTally.option_set(key, _surface())
    option_written.emit(key, value)


## Which surface these controls are to the usage tally: the bar, the docker, or
## the brush editor's page, which sets neither flag.
func _surface() -> StringName:
    if only_flagged_for_bar:
        return SaUsageTally.BAR
    return SaUsageTally.DOCKER if for_docker else SaUsageTally.BRUSH_EDITOR
