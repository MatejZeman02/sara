## The tool options bar: what the skeleton offers every tool, and the controls
## each tool declares for itself.
##
## The skeleton's own are the preset group, the Keep toggle beside the blend
## dropdown, and the three symmetry toggles, which read the document rather than
## a tool. Everything else is built from the permanent tool's SaOptionSpec list
## by ToolOptionControls, so a module tool gets its row on the bar through the
## same door the brush does, and the bar has no idea what a radius is.
##
## The bar follows the machine's permanent tool, not the held one. A quick
## tool held on a key must not rearrange the bar under the hand, so holding
## Space or I leaves the brush's controls where they are, and selecting the
## eyedropper for good brings its own.
extends HBoxContainer

class_name ToolOptionsBar

## Announced after a tool's controls are built or dropped, so the top bar
## applies the stored layout to the new children.
signal controls_changed

## The preset group's own constants, kept reachable under the bar's name because
## that is where every caller looks for them. They live on
## `ToolOptionsPresets`, the group's own file.
const PRESET_LABEL := ToolOptionsPresets.PRESET_LABEL
const PRESET_ID_SAVE := ToolOptionsPresets.PRESET_ID_SAVE
const PRESET_ID_DELETE := ToolOptionsPresets.PRESET_ID_DELETE
const ToolOptionsAfter := preload("res://ui/dockers/tool_options/tool_options_after.gd")

## The narrowest a slider goes on the bar. It was 76, what fitting eight
## controls beside eleven menus allowed on one row, and at 80 a slider moved 11
## per cent a pixel under a painter's pen: the smallest control on the bar was
## the one reached for most. A short row sends its rarely used controls to the
## overflow first, by `SaTopBarRows.LEAVE_FIRST`, so the room comes from those.
## On a row with room the bar widens a slider from here, up to
## `SLIDER_EXTRA_WIDTH` more.
const SLIDER_MIN_WIDTH: int = 150
const SLIDER_EXTRA_WIDTH: int = 64

## The stored layout names of the skeleton's own controls, kept on the element
## table `SaToolOptionsElements` with the group each sits in.
const ELEMENT_PRESETS := SaToolOptionsElements.PRESETS
const ELEMENT_KEEP_BLEND := SaToolOptionsElements.KEEP_BLEND
const ELEMENT_MIRROR_H := SaToolOptionsElements.MIRROR_H
const ELEMENT_MIRROR_V := SaToolOptionsElements.MIRROR_V
const ELEMENT_RADIAL := SaToolOptionsElements.RADIAL
const ELEMENT_STABILIZER := SaToolOptionsElements.STABILIZER
const ELEMENT_EDIT_BRUSH := SaToolOptionsElements.EDIT_BRUSH

## The brush's Erase toggle, a row the stamp brush declares, which a short row
## keeps while it is on. Gone to the overflow at the bar's width, nothing on
## screen would show why a stroke lands as an Erase Stroke. Lit, it is the one
## sign, and pressing it is the way out.
const ERASE_KEY: StringName = &"eraser_toggled"

## Forwarded under the name every caller already uses. See
## `SaToolOptionsSwitches` for why it is Average rather than Rope.
const DEFAULT_STABILIZER_MODE := SaToolOptionsSwitches.DEFAULT_STABILIZER_MODE

## The key the blend dropdown is shared under, so the Keep toggle can find
## it whichever tool declared it.
const BLEND_KEY := ToolOptionControls.BLEND_KEY

var target_tool_machine: ToolMachine:
    set(machine):
        if target_tool_machine == machine:
            return
        target_tool_machine = machine
        if _built:
            options.binding.follow(machine)
            _refresh_presets()
            _sync_ui_from_settings()
    get:
        return target_tool_machine

## One container rather than two loose controls, so the layout order in
## Preferences moves the preset group as a unit and only one entry has to be
## added to the stored element list. It is a class of its own and owns the
## store, the filter and the selection as well as the two controls.
var preset_box: ToolOptionsPresets

## The sync a preset load leaves for the third frame after it.
var after := ToolOptionsAfter.new(3)

## Presets are saved and applied through the skeleton rather than through the
## module, because the bar already treats a tool's `settings` as an opaque
## resource. That is what lets any tool with a settings resource get presets
## without the base module knowing this exists.
##
## Held here rather than on the group, although the group is what uses it: the
## bar writes `keep_blend_mode` onto it from the Keep toggle, and a test points its
## `dir` at a scratch directory before anything has built a control. Both happen
## before `_build_ui_by_code` runs, so a store that only existed once the group
## did would be null under them.
var preset_store: SaPresetStore = SaPresetStore.new()

## The two controls, forwarded rather than duplicated so a caller that reaches
## for them on the bar finds them.
var preset_menu: Button:
    get:
        return preset_box.preset_menu if preset_box != null else null

var preset_name_edit: LineEdit:
    get:
        return preset_box.preset_name_edit if preset_box != null else null

## Beside the dropdown: loading a preset leaves the mode alone. A toggle
## `Button` like the Stabilizer switch, the name kept from when it was a check
## box because scenarios and notes point at it.
var keep_blend_chk: Button

## The four switches, split out into `ui/tool_options/tool_options_switches.gd`: the three
## symmetry toggles and the stabiliser one, which are the controls on this bar that are not
## built from a tool's `SaOptionSpec` list.
##
## The four buttons are still reachable under the names every caller already
## uses, because a split is not a rename and `ui/tool_options/tests/test_stabilizer_toggle.gd`
## and the Tool Options docker both ask for them by name. The Edit Brush button,
## which opens the brush editor rather than writing anything.
var edit_brush_btn: Button

var switches := SaToolOptionsSwitches.new()
## What each control a rule puts on the bar or takes off it last answered.
var _rules_held: Dictionary[StringName, bool] = {}

var mirror_h_btn: Button:
    get:
        return switches.mirror_h_btn

var mirror_v_btn: Button:
    get:
        return switches.mirror_v_btn

var radial_btn: Button:
    get:
        return switches.radial_btn

var stabilizer_btn: Button:
    get:
        return switches.stabilizer_btn

## The generated controls, one per declared option key.
var options: ToolOptionControls

var _ignore_slider_signals: bool = false
var _built: bool = false

## The tool the controls were last synced as showing, so a switch knows which
## tool's keys it is taking them from. Empty until the first sync.
var _synced_for: StringName = &""


func _init() -> void:
    name = "ToolOptionsBar"
    options = ToolOptionControls.new(self)
    # The bar takes the options a tool flagged for it, the Tool Options docker
    # takes every one.
    options.only_flagged_for_bar = true
    # A control writes to whoever the last `sync` said owns it, and a brush row
    # on the bar with the eyedropper chosen is owned by nobody there, so it
    # would move and write nothing. This catches the announcement and lands the
    # value on the painting tool instead.
    options.option_written.connect(_land_on_the_owner)
    options.option_written.connect(_hear_blend)
    options.binding.tools_changed.connect(_on_tools_changed)
    size_flags_horizontal = SIZE_SHRINK_BEGIN
    size_flags_vertical = SIZE_SHRINK_CENTER
    # Asked for through the meta rather than as a plain override, because the
    # theme pass on the next line, and the two in `ui/main/main.gd`, each replace a
    # plain one. The bar is the fullest row in the app and 40 per cent of the
    # global gap is what lets every control fit inside the slot at 1920.
    set_meta(SaUI.SEPARATION_SCALE_META, 0.4)
    DockerUtils.apply_compact_ui(self)


func _ready() -> void:
    if not _built:
        _build_ui_by_code()
    if not EventBus.tool_changed.is_connected(_on_tool_changed):
        EventBus.tool_changed.connect(_on_tool_changed)
    # A tool that moved its own values, or the size drag and the brackets: the
    # rows read again, nothing is rebound.
    if not EventBus.tool_options_moved.is_connected(_on_tool_options_moved):
        EventBus.tool_options_moved.connect(_on_tool_options_moved)
    # The erase toggle is written by the key and by the other surface's bar
    # as well as by this one, and announces itself from its setter.
    if not EventBus.brush_eraser_toggled.is_connected(_on_event_eraser_toggled):
        EventBus.brush_eraser_toggled.connect(_on_event_eraser_toggled)
    # Size and Feather are fractions of the canvas shown as pixels, so a
    # document that changed size leaves both rows reading the old one.
    if not EventBus.document_resized.is_connected(_on_document_resized):
        EventBus.document_resized.connect(_on_document_resized)
    options.binding.follow(target_tool_machine)
    _refresh_presets()
    _sync_ui_from_settings()


func _build_ui_by_code() -> void:
    _built = true
    _build_preset_group()

    # A toggle button built the way the Stabilizer's is, with its name on the
    # button rather than on a label beside a box, because a check box with text
    # reads as a name rather than a switch. The same builder, so it lights the
    # same way when on and keeps no keyboard focus past its click.
    keep_blend_chk = _add_toggle_btn(self, tr("Keep Blend Mode"), _on_keep_blend_toggled)
    keep_blend_chk.name = "KeepBlendChk"
    # Marked a toggle the way `SaMake.check_box` marked the box, so a scenario's
    # `control` step still reads and moves it by name.
    keep_blend_chk.set_meta(SaMake.KIND_META, SaMake.Kind.TOGGLE)
    keep_blend_chk.set_pressed_no_signal(SaSettings.keep_blend_mode)
    keep_blend_chk.tooltip_text = tr(
        (
            "Keep your blend mode when you load a preset, rather than the preset's own."
            + " An eraser preset still erases, and your mode comes back after it."
        )
    )
    preset_store.keep_blend_mode = SaSettings.keep_blend_mode

    # The Edit Brush control, and the last of the bar's own: it is not a tool
    # option and it writes nowhere, it opens a window. Beside the preset group
    # rather than at the far end, because the two are the same errand, "change
    # what this brush is" rather than "change one number about it".
    edit_brush_btn = SaMake.button(
        self, "EditBrushButton", tr("Edit Brush"), tr("Open the brush editor at the page you were last on")
    )
    edit_brush_btn.custom_minimum_size = Vector2(DockerUtils.px(72), DockerUtils.px(DockerUtils.BASE_ICON_SIZE + 2))
    edit_brush_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    edit_brush_btn.set_meta(SaUI.FONT_SCALE_META, SaUI.SMALL_FONT_SCALE)
    # A focused button eats the next Space itself, as `ui_accept`, before the
    # router ever sees it, so a press here would leave Space reopening this
    # editor instead of panning. No button on the bar keeps the keyboard past its click.
    edit_brush_btn.focus_mode = Control.FOCUS_NONE
    edit_brush_btn.pressed.connect(open_brush_editor)

    switches.document_source = _target_document
    switches.settings_source = _get_active_brush_settings
    switches.write_option = write_option
    switches.build(self, _add_toggle_btn)


## The preset group, which builds itself. What crosses the seam is the two
## questions it cannot answer alone: which settings resource a preset is read
## from and written onto, and what to do once one has been applied.
func _build_preset_group() -> void:
    preset_box = ToolOptionsPresets.new()
    preset_box.preset_store = preset_store
    preset_box.settings_source = _get_active_brush_settings
    preset_box.on_applied = func() -> void: after.ask(&"values", self, _sync_ui_from_settings)
    # The chooser draws a thumbnail by driving the tool that owns the settings,
    # and this is the surface that knows which tool that is.
    preset_box.tool_source = shown_tool
    preset_box.descriptor_source = func() -> SaToolDescriptor:
        return target_tool_machine.get_descriptor(shown_tool_id()) if target_tool_machine != null else null
    preset_box.engines_source = shown_engines
    preset_box.engine_switch = take_engine
    add_child(preset_box)


func _add_toggle_btn(parent: Container, label_text: String, callback: Callable, icon_name: String = "") -> Button:
    var btn := Button.new()
    btn.toggle_mode = true
    SaTheme.make_toggle(btn)
    # The symmetry and stabiliser toggles are bar buttons like the rest, so the
    # same rule applies, no click here keeps the keyboard from the canvas.
    btn.focus_mode = Control.FOCUS_NONE
    if icon_name != "":
        SaBarIconButton.shape(btn, icon_name, label_text)
    else:
        btn.text = label_text
        var min_w := DockerUtils.px(24) if label_text.begins_with("(") else DockerUtils.px(54)
        btn.custom_minimum_size = Vector2(min_w, DockerUtils.px(DockerUtils.BASE_ICON_SIZE + 2))
        btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    parent.add_child(btn)
    btn.toggled.connect(callback)
    return btn


# --- The tools' own controls -------------------------------------------------


## The controls moved under the bar: a tool's rows came or went, or the blend
## modes were rebuilt. A row that came is titled for Preferences and laid out by
## the top bar, and the values are read again.
func _on_tools_changed(rebuilt: bool) -> void:
    if not _built:
        return
    if rebuilt:
        _register_titles()
    _sync_ui_from_settings()
    if rebuilt:
        controls_changed.emit()


## Tells Preferences what to call each generated row, lets a key that is not in
## the default order appear in the list at all, and hands on what the first spec
## declared for the key said about the row on a fresh bar, hidden or not and
## which element it follows. And hands the door a view another docker can hold,
## the key's control for the tool in the hand (`SaToolOptionViews`).
func _register_titles() -> void:
    var registry := target_tool_machine.registry if target_tool_machine != null else null
    var first_specs: Dictionary = {}
    if registry != null:
        for descriptor: SaToolDescriptor in registry.list_descriptors():
            for spec: SaOptionSpec in descriptor.options:
                if spec != null and spec.bar and not first_specs.has(spec.key):
                    first_specs[spec.key] = spec
    for key in options.keys():
        var spec: SaOptionSpec = first_specs.get(key, null)
        var hides := spec != null and spec.bar_hidden
        var after_key := spec.bar_after if spec != null else ""
        var view := SaToolOptionViews.builder(self, key)
        SaSettings.register_layout_element("TopMenuBar", String(key), options.title_for(key, registry), hides, after_key, view)


## The tool whose controls the bar shows: the permanent one, never the held one.
func shown_tool_id() -> StringName:
    if target_tool_machine == null:
        return &""
    var id := target_tool_machine.default_tool_name
    return id if not String(id).is_empty() else target_tool_machine.active_tool_name


func shown_tool() -> ToolState:
    var id := shown_tool_id()
    return target_tool_machine.get_tool(id) if target_tool_machine != null and not String(id).is_empty() else null


## The engines the shown tool paints with, each preset engine to the tool on
## this surface that paints it: every engine of the Brush while the Brush is
## shown under any of them, and the shown tool alone otherwise. A tool that
## names no preset engine is left out, which is a tool that takes no presets.
func shown_engines() -> Dictionary:
    var out: Dictionary = {}
    var registry := target_tool_machine.registry if target_tool_machine != null else null
    if registry == null:
        return out
    for id: StringName in registry.engines_of(shown_tool_id()):
        var descriptor := registry.get_descriptor(id)
        var painter := target_tool_machine.get_tool(id)
        if descriptor != null and painter != null and not String(descriptor.preset_engine).is_empty():
            out[descriptor.preset_engine] = painter
    return out


## Makes the engine of the shown tool that paints *engine*'s presets the tool in
## hand, which is what a load of a noise preset asks with the stamp brush shown.
## A shown tool that takes no presets, the lasso or the eyedropper, has no
## engines to look in, so the machine's fallback tool is asked instead and the
## tool that paints the preset comes into the hand. False when no tool has such
## an engine, and the load then goes into the settings and leaves the tool alone.
func take_engine(engine: StringName) -> bool:
    var registry := target_tool_machine.registry if target_tool_machine != null else null
    if registry == null:
        return false
    var home := shown_tool_id()
    if preset_box != null and preset_box.takes_no_presets():
        home = target_tool_machine.fallback_tool_name()
    var id := registry.engine_for(home, engine)
    if String(id).is_empty() or not target_tool_machine.registered_tools.has(id):
        return false
    if id != shown_tool_id():
        target_tool_machine.set_active_tool(id)
    return true


## The control built for *key*, whichever tool declared it. Null when no
## registered tool has.
func control_for(key: StringName) -> Control:
    return options.control(key)


## The specs of the shown tool, in the order the bar shows them. What the
## canvas right-click menu builds from.
func shown_specs() -> Array[SaOptionSpec]:
    var out: Array[SaOptionSpec] = []
    var descriptor := target_tool_machine.get_descriptor(shown_tool_id()) if target_tool_machine != null else null
    if descriptor != null:
        out.assign(descriptor.options)
    return out


## The value behind *key* on the shown tool, or null.
##
## Falls back to the tool's own spec list, because the bar builds a control only
## for the options flagged `bar` and the right-click menu still offers every one
## of them.
func read_option(key: StringName) -> Variant:
    var value: Variant = options.read(key, owner_tool(key), owner_of(key))
    if value != null:
        return value
    return ToolOptionControls.read_spec(declared_spec(key), shown_tool())


## A value written on the other surface, for the bar's own controls that are not
## `options`' and so are not reached by `options.show_value`. The Tool Options
## docker connects this beside that one.
func show_written_option(key: StringName, value: Variant) -> void:
    _hear_blend(key, value)
    if key == &"stabilizer_mode":
        switches.show_stabilizer_mode(int(value))


## A blend mode written on either surface is the preset group's to hear. A mode
## picked by hand ends what a preset that erased owes the brush, and a preset in
## hand that does not carry that mode is not in hand any more, the way an edited
## preset is not on the Brush Presets docker. With Keep blend on a preset that
## paints never set the mode, so nothing it carries is in question, and only an
## erasing preset, which sets Erase whatever the switch says, is let go.
func _hear_blend(key: StringName, value: Variant) -> void:
    if key != ToolOptionControls.BLEND_KEY or preset_box == null:
        return
    preset_box.blend_memory.forget()
    var in_hand := preset_box.selected_preset
    if in_hand.is_empty():
        return
    if preset_store.keep_blend_mode and not preset_store.erases(in_hand):
        return
    var stored := preset_store.load_preset(in_hand)
    if stored != null and stored.get("blend_mode") != StringName(value):
        preset_box.release_preset()


## What the bar's own switches are showing and which row each is on, for a
## capture. The three symmetry toggles are read from the document elsewhere, so
## this is about the stabilizer toggle. The width arithmetic is not here: it is
## the top bar's, and `top_bar_rotation` in the same dump already carries it.
##
## It also carries `options`, a row per generated control, so a dump
## says what the bar shows for a key that is not the stabilizer.
func bar_report() -> Dictionary:
    var out := switches.report(self)
    out["options"] = option_report()
    out["keep_blend_toggle"] = _keep_blend_report()
    out["icon_buttons"] = SaBarIconButton.report((get_tree().root as Node) if is_inside_tree() else (self as Node))
    return out


## The Keep toggle as a dump prints it, its class and toggle mode beside what it
## holds, so a capture shows it is a switch like the Stabilizer's rather than a
## check box, and whether a label sits beside it.
func _keep_blend_report() -> Dictionary:
    if keep_blend_chk == null:
        return {}
    var rect := keep_blend_chk.get_global_rect()
    var labels_beside := 0
    for sibling: Node in keep_blend_chk.get_parent().get_children():
        if sibling is Label and (sibling as Label).text.contains("Keep"):
            labels_beside += 1
    return {
        "name": String(keep_blend_chk.name),
        "class": keep_blend_chk.get_class(),
        "toggle_mode": keep_blend_chk.toggle_mode,
        "text": keep_blend_chk.text,
        "pressed": keep_blend_chk.button_pressed,
        "setting": SaSettings.keep_blend_mode,
        "tooltip": keep_blend_chk.tooltip_text,
        "labels_beside": labels_beside,
        "visible": keep_blend_chk.is_visible_in_tree(),
        "on_second_row": keep_blend_chk.get_parent() != self,
        "rect": {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y},
    }


## Every option the bar built a control for: what the control is showing, what
## the shown tool holds behind the same key, and whether the row is on the bar
## at all.
##
## The two readings are separate on purpose. A bar that has stopped following
## its tool shows one number while the tool holds another, and a report that
## asked the tool twice, or the control twice, could not tell that apart. It is
## also what makes a `bar_option` step checkable: the step drives the control,
## and the pair says the value reached the tool.
##
## Keyed by option key rather than by label, because the key is what a scenario
## names and a label is translated.
func option_report() -> Dictionary:
    var out := {}
    if options == null:
        return out
    var tool_id := shown_tool_id()
    for key: StringName in options.keys():
        var node := options.control(key)
        # `owning_tool` rather than `owner`, which shadows `Node.owner`.
        var owning_tool := owner_of(key)
        out[String(key)] = {
            "shown": control_value(key),
            "tool": options.read(key, owner_tool(key), owning_tool),
            "visible": node != null and node.visible,
            "declared": options.spec_for(key, tool_id) != null,
            # `declared` is whether the shown tool declared it and `owner` is who
            # the value actually comes from: a brush row with the eyedropper
            # chosen reads declared false and owner brush, and is on the bar.
            "owner": String(owning_tool),
        }
    return out


## What the control built for *key* is showing, whatever kind it is, with no
## reference to the tool behind it.
##
## Null when there is no control, and null for the two kinds that show no value:
## a CUSTOM control such as the gradient's ramp is pointed at the tool's own
## object rather than handed a copy, and an ACTION row is a button that holds
## nothing.
func control_value(key: StringName) -> Variant:
    var node := options.control(key) if options != null else null
    if node == null:
        return null
    var slider := node as FactorSlider
    if slider != null:
        return slider.value
    var blend_button := node as BlendModeButton
    if blend_button != null:
        return String(blend_button.current)
    # The row keeps the caller's own value, so there is no index to turn back
    # into one.
    var choice := node as SaChoiceButton
    if choice != null:
        return choice.selected_value()
    var toggle := node as Button
    if toggle != null and toggle.toggle_mode:
        return toggle.button_pressed
    return null


## Writes *value* behind *key* on the tool that owns it and shows it on the bar.
##
## `owner_of` rather than `shown_tool_id`: with the eyedropper chosen, Size
## still writes the brush's radius, because the group is on the bar and live,
## nothing dimmed.
func write_option(key: StringName, value: Variant) -> bool:
    if options.write(key, value, owner_tool(key), owner_of(key)):
        return true
    if not ToolOptionControls.write_spec(declared_spec(key), value, shown_tool()):
        return false
    # No control here to mirror it onto, but the docker has one.
    options.option_written.emit(key, value)
    return true


## Opens the brush editor on the tool this bar is showing, at the page the
## profile remembers, or closes it when it is open.
##
## Through `SaBrushEditorDoor.toggle`, which is the same door the Edit Brush
## command uses, so the button and the chord cannot open two different windows.
func open_brush_editor() -> void:
    if is_inside_tree():
        SaBrushEditorDoor.toggle(get_tree())


## The spec the shown tool declares for *key*, control or no control.
func declared_spec(key: StringName) -> SaOptionSpec:
    for spec: SaOptionSpec in shown_specs():
        if spec.key == key:
            return spec
    return null


## Stored element name -> the control it stands for. The preset group is the
## container, not the controls inside it: the preset button and the name field
## that replaces it are one affordance, and moving or hiding half of it would
## leave the bar in a state nothing recovers from.
func layout_elements() -> Dictionary:
    var out := {
        ELEMENT_PRESETS: preset_box,
        ELEMENT_KEEP_BLEND: keep_blend_chk,
        ELEMENT_MIRROR_H: mirror_h_btn,
        ELEMENT_MIRROR_V: mirror_v_btn,
        ELEMENT_RADIAL: radial_btn,
        ELEMENT_STABILIZER: stabilizer_btn,
        ELEMENT_EDIT_BRUSH: edit_brush_btn,
    }
    out.merge(options.layout_elements())
    return out


## Stored element name -> the group the top bar draws a break between.
func layout_groups() -> Dictionary:
    return SaToolOptionsElements.groups(target_tool_machine.registry if target_tool_machine != null else null)


## Whether *control* has a place on the bar while the shown tool is shown. The
## top bar ANDs this with the profile's own visibility for the control, on every
## layout pass and on every tool change. The skeleton's own controls always have
## a place, a generated one for a tool that declared it, and the painting tools'
## controls for every tool.
func shows_for_active_tool(control: Control) -> bool:
    if control == keep_blend_chk:
        # Keep is about the blend mode a preset carries, so it sits beside the
        # dropdown and goes with it.
        return _has_a_place(options.control(BLEND_KEY))
    if not options.is_generated(control):
        return true
    return _has_a_place(control) and SaToolOptionsRules.holds(self, control)


## The rule for which tool owns a control, in one place because three questions
## ask it.
##
## A control the shown tool declared stays, **and one a painting tool declared
## stays too**, whatever is chosen, so the brush's settings do not vanish when
## another tool is in hand. There is no third state, nothing dimmed: the group
## is on the bar and live, the way Krita's is.
##
## Asked through `SaToolDescriptor.is_painting` rather than by naming the brush,
## because hard rule 6 cuts both ways: a module that ships a painting tool of its
## own gets the same treatment without a line here, and the skeleton names no
## module's tool id. The flag already decides which tools may draw a ring and
## which are blocked mid-stroke, so this is a third reading of one idea rather
## than a fourth idea.
##
## **A painting tool's row that is its own alone is the exception**. The fill
## paints, so its Grow slider would stand on the brush's bar as the brush group
## stands on the fill's, which is clutter rather than a setting at hand: such a
## spec says `bar_own_tool`, and its row then comes and goes with its tool.
func _has_a_place(control: Control) -> bool:
    if control == null:
        return false
    if options.belongs_to(control, shown_tool_id()):
        return true
    for id: StringName in painting_tool_ids():
        if options.belongs_to(control, id) and not options.own_tool_only(control, id):
            return true
    return false


## Every registered tool whose descriptor says it paints, in registration order.
##
## Two today, the brush and the eraser, and they share most of their keys, so the
## first that declares one is the one a value is read from and written to.
func painting_tool_ids() -> Array[StringName]:
    var out: Array[StringName] = []
    if target_tool_machine == null:
        return out
    for id: StringName in target_tool_machine.registered_tools.keys():
        var descriptor := target_tool_machine.get_descriptor(id)
        if descriptor != null and descriptor.is_painting:
            out.append(id)
    return out


## The tool the control for *key* reads from and writes to.
##
## The shown tool when it declared the key, and otherwise the painting tool that
## did, so the brush group on the bar with the eyedropper chosen edits the
## brush rather than sitting there doing nothing.
## Empty when nobody declared it, which is what the callers already branch on.
func owner_of(key: StringName) -> StringName:
    var shown := shown_tool_id()
    if options.spec_for(key, shown) != null:
        return shown
    var declarer := _first_painting_declarer(key)
    return declarer if not String(declarer).is_empty() else shown


## The tool `owner_of` names, or null.
func owner_tool(key: StringName) -> ToolState:
    var id := owner_of(key)
    return target_tool_machine.get_tool(id) if target_tool_machine != null and not String(id).is_empty() else null


## Dims and disables every control whose `enabled_when` option is not on one of
## the values it named.
##
## The same rule the Tool Options docker applies to its own rows, through the same
## `SaOptionSpec.apply_enabled`, because two surfaces show one option and a
## painter who dims a row in the docker expects the bar's twin to dim with it.
## The bar has no labelled row to grey, so the control greys itself.
##
## Asked of `owner_of` rather than of the shown tool, because the brush's controls
## are on the bar for every tool and a rule read against the wrong tool would dim
## them all.
func sync_row_enabled() -> void:
    if options == null:
        return
    for key: StringName in options.keys():
        var spec := options.spec_for(key, owner_of(key))
        if spec == null:
            continue
        var value: Variant = options.read(spec.enabled_when, owner_tool(key), owner_of(key))
        SaOptionSpec.apply_enabled(options.control(key), null, spec, value)


## A control on the bar moved and the shown tool does not own it, so the value
## goes to the painting tool that does.
##
## `ToolOptionControls._write_from_control` writes through whoever the last
## `sync` recorded, which has to stay the shown tool or that tool's own rows
## would write to the brush. So it writes nothing for a brush row here and
## announces the value anyway, and this is what lands it. Announced rather than
## returned, so this is the only seam there is, and it is in the bar because the
## rule about painting tools is the bar's.
##
## Silent for a key the shown tool does own, which is every key on every tool
## that declares its own, so the ordinary path costs one dictionary lookup.
func _land_on_the_owner(key: StringName, value: Variant) -> void:
    # A row that decides whether another is dead has just moved, so the answer
    # is stale until this runs. Cheap enough to run on every write: it is one
    # dictionary lookup per control and only the gradient declares a rule.
    sync_row_enabled.call_deferred()
    if options.spec_for(key, shown_tool_id()) != null:
        return
    var id := owner_of(key)
    if id == shown_tool_id():
        return
    var spec := options.spec_for(key, id)
    var tool_node := target_tool_machine.get_tool(id) if target_tool_machine != null else null
    if spec == null or tool_node == null:
        return
    ToolOptionControls.write_spec(spec, value, tool_node)


## Every slider the bar owns, wherever a row has put it.
func sliders() -> Array[FactorSlider]:
    return options.sliders()


# --- Values in and out ---------------------------------------------------------


## The settings the presets read and write: the shown tool's, or the tool
## machine's fallback tool's when the shown tool keeps none, so Save with pan
## selected still saves the brush the painter was using. The fallback rather
## than the id `brush`, so the skeleton names no module's tool.
func _get_active_brush_settings() -> Resource:
    if target_tool_machine == null:
        return null
    var tool_node := shown_tool()
    if tool_node and "settings" in tool_node and tool_node.settings != null:
        return tool_node.settings
    var fallback := target_tool_machine.get_tool(target_tool_machine.fallback_tool_name())
    if fallback and "settings" in fallback:
        return fallback.settings
    return null


## The machine holds a surface, not a Control: the document is the authority and
## reaching it through the view would be the same UI-into-core coupling the
## surface exists to remove. The controls hold the machine.
func _target_document() -> SaDocument:
    return options.binding.document()


## The document's smaller dimension, which is what a spec flagged
## `scale_by_canvas` turns its fraction into pixels with.
##
## Public because the Brush Editor is opened from this bar and shows the same
## rows: it has no document behind it and must not reach for one, so the number
## is handed to `bind_tool` the way the specs and the store are. Read as 1.0
## there, every size in the editor would show as "Size: 0 px" while the row
## above it read the pixels correctly.
func canvas_min_dimension() -> float:
    return options.binding.canvas_min_dimension()


func _on_keep_blend_toggled(pressed: bool) -> void:
    SaSettings.keep_blend_mode = pressed
    preset_store.keep_blend_mode = pressed


func _on_tool_changed(_tool_name: String) -> void:
    options.binding.follow(target_tool_machine)
    _refresh_presets(selected_preset_name())
    _sync_switched_tool()


## The rows are fitted again as well, because Erase on is held on the bar
## whatever else leaves it, and off it may leave again.
func _on_event_eraser_toggled(_active: bool) -> void:
    _sync_ui_from_settings()
    controls_changed.emit()


func _on_tool_options_moved() -> void:
    _sync_ui_from_settings()


func _on_document_resized(_document: SaDocument, _size: Vector2i) -> void:
    _sync_ui_from_settings()


func _sync_ui_from_settings() -> void:
    if not _built:
        return
    _ignore_slider_signals = true
    options.muted = true
    # The switches carry their own guard, and it has to be up across the same
    # window: `sync_symmetry` presses three toggles and every one of them would
    # write straight back to the document without it.
    switches.muted = true
    var tool_id := shown_tool_id()
    var canvas_min := canvas_min_dimension()
    # The painting tools first and the shown tool last. `sync` skips every entry
    # the tool it is given did not declare, so the first pass fills the brush
    # group and the second leaves it alone and fills the shown tool's own. Last
    # matters: `sync` also records who the controls belong to, and a control the
    # shown tool declared has to keep writing to the shown tool.
    #
    # **In reverse, so the last writer of a shared key is the first declarer**
    # (f19). The brush and the eraser share `blend_mode` and the eraser's is
    # `erase`. Forwards, with a tool that is not a painting tool chosen, nothing
    # was skipped and the eraser wrote last, so the row read Erase while
    # `owner_of` named the brush and the control edited the brush's Normal. A
    # painter who read Erase, picked the brush and expected paint to come away
    # got paint put down. Reversing makes the two agree for every shared key
    # rather than for `blend_mode` alone: `owner_of` answers the first id of
    # `painting_tool_ids()` that declared the key, so walking that list
    # backwards leaves exactly that tool's value in the control. The shown tool
    # is still synced after the loop, which is `owner_of`'s own first branch.
    var painting_ids := painting_tool_ids()
    painting_ids.reverse()
    for painting_id: StringName in painting_ids:
        if painting_id != tool_id:
            options.sync(target_tool_machine.get_tool(painting_id), painting_id, canvas_min)
    if not String(tool_id).is_empty():
        options.sync(shown_tool(), tool_id, canvas_min)
    _synced_for = tool_id
    sync_row_enabled()
    var ruled := SaToolOptionsRules.answers(self)
    if SaToolOptionsRules.moved(_rules_held, ruled):
        controls_changed.emit()
    _rules_held = ruled
    switches.sync_symmetry()
    switches.sync_stabilizer()
    switches.muted = false
    options.muted = false
    _ignore_slider_signals = false


## Brings the controls up to date with a tool switch, reading the tool switched
## to and not every painting tool.
##
## Every other control already shows its owner's value, since the last sync
## left it so and a switch moves no setting. What a switch changes is which tool
## the shown tool's own keys belong to, so those are read from the new tool, and
## a key the old tool showed that the new one does not declare goes back to its
## owner. On the brush and the eraser, which declare the same eleven keys, that
## is one tool read where the whole loop reads four, and the loop is a
## noticeable share of a switch.
##
## The owners are read in the loop's own order, the painting tools backwards
## and the shown tool last, so the last writer of a shared key is the one
## `owner_of` names. The set is closed over, because an
## owner read for one key writes every key it declares, and a key it shares with
## an earlier painting tool needs that tool read after it.
##
## With no tool shown, or nothing synced yet, this is the whole sync.
func _sync_switched_tool() -> void:
    var tool_id := shown_tool_id()
    if not _built or String(tool_id).is_empty() or String(_synced_for).is_empty():
        _sync_ui_from_settings()
        return
    var owners := _owners_left_showing(_synced_for, tool_id)
    _ignore_slider_signals = true
    options.muted = true
    switches.muted = true
    var canvas_min := canvas_min_dimension()
    var painting_ids := painting_tool_ids()
    painting_ids.reverse()
    for painting_id: StringName in painting_ids:
        if owners.has(painting_id):
            options.sync(target_tool_machine.get_tool(painting_id), painting_id, canvas_min)
    options.sync(shown_tool(), tool_id, canvas_min)
    _synced_for = tool_id
    sync_row_enabled()
    switches.sync_symmetry()
    switches.sync_stabilizer()
    switches.muted = false
    options.muted = false
    _ignore_slider_signals = false


## The painting tools whose values the controls must show again after a switch
## from *before* to *now*: the owner of every key *before* showed that *now*
## does not declare, and the owners of every key those declare, until no new
## one turns up. A key only *before* declared and no painting tool does keeps
## its control as it was, as the whole sync does.
func _owners_left_showing(before: StringName, now: StringName) -> Dictionary:
    var owners: Dictionary = {}
    var pending: Array[StringName] = []
    if before != now:
        pending.append(before)
    while not pending.is_empty():
        var from: StringName = pending.pop_back()
        for key: StringName in options.keys_for(from):
            if options.spec_for(key, now) != null:
                continue
            var declarer := _first_painting_declarer(key)
            if String(declarer).is_empty() or owners.has(declarer):
                continue
            owners[declarer] = true
            pending.append(declarer)
    return owners


## The first painting tool that declared *key*, which is whom `owner_of` names
## for a key the shown tool does not declare, or empty when none did.
func _first_painting_declarer(key: StringName) -> StringName:
    for id: StringName in painting_tool_ids():
        if options.spec_for(key, id) != null:
            return id
    return &""


# --- Presets -------------------------------------------------------------------

# The group itself is `ui/presets/tool_options_presets.gd`. What is left here is
# the door every caller already knocks on: the capture harness drives presets
# through the bar because the bar is what it can find, and
# `core/presets/tests/test_brush_presets.gd` was written against these names.
# Forwarding rather than renaming keeps the split invisible from outside.


## The preset the button is showing, empty when none is loaded.
func selected_preset_name() -> String:
    return preset_box.selected_preset if preset_box != null else ""


## Every preset the popup is offering, in the order it offers them.
func preset_names() -> Array[String]:
    return preset_box.preset_names() if preset_box != null else [] as Array[String]


## The tags the popup is offering, in the order it offers them.
func preset_tags() -> Array[String]:
    return preset_box.preset_tags() if preset_box != null else [] as Array[String]


## The tag the list is filtered by, empty for All.
func selected_tag() -> String:
    return preset_box.selected_tag if preset_box != null else ""


## Filters the list to *tag*, or to everything when it is empty.
func filter_by_tag(tag: String) -> void:
    if preset_box != null:
        preset_box.filter_by_tag(tag)


## Loads *stored_name* onto the settings in front of the painter.
##
## Public because `harness/sa_capture.gd` drives it: the list lives in a MenuButton's
## popup, which is a Window, and an injected click does not route into one.
func load_preset(stored_name: String) -> bool:
    return preset_box.load_preset(stored_name) if preset_box != null else false


## Writes the settings in front of the user under *preset_name* and shows it as
## loaded. Returns the name it was stored under, empty when nothing was written.
func save_current_as_preset(preset_name: String) -> String:
    return preset_box.save_current_as_preset(preset_name) if preset_box != null else ""


## Deletes the stored preset and leaves the brush exactly as it is.
func delete_loaded_preset() -> void:
    if preset_box != null:
        preset_box.delete_loaded_preset()


func _refresh_presets(select_name: String = "") -> void:
    if preset_box != null:
        preset_box.refresh(select_name)


func _on_preset_menu_id(id: int) -> void:
    if preset_box != null:
        preset_box._on_preset_menu_id(id)


# --- Blend modes ---------------------------------------------------------------


## Points the blend dropdown at the registry. The controls follow it and the
## document's colour space from here on, and say so through `tools_changed`.
func bind_registries(blend_registry: SaBlendModeRegistry) -> void:
    options.binding.follow_blend_modes(blend_registry)


## The bar's own switches and its width arithmetic, for the state dump. Empty on
## a run that has no bar, which no run has.
##
## Found by method rather than by cast: a cast to this file's own `class_name`
## inside a static function leaks the script.
static func capture_state(root: Window) -> Dictionary:
    for node in root.find_children("*", "HBoxContainer", true, false):
        if node.has_method("bar_report") and node.has_method("option_report"):
            return node.call("bar_report")
    return {}
