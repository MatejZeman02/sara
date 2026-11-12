## The bar's own controls as views another docker can hold: the preset group,
## Keep, the three symmetry switches, the stabiliser's toggle, Edit Brush and
## the rotation pair.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The rest of the bar's placeable elements, the option keys having theirs in
## `SaToolOptionViews.OptionView`. Each is a second view of the same state as at
## home, so a view holds no value of its own. It copies the face of the
## control it stands for, presses through that control, which runs the bar's own
## handler, and reads back what that handler wrote: the canvas's symmetry, the
## stabiliser mode of the tool in the hand, the Keep preference, the Brush
## Presets docker being open and the view's turn.
##
## Pressing through the home control rather than calling what it calls is what
## keeps the two surfaces one: a guard or a side effect the bar's handler grows
## later is the view's too, and nothing here names a private part of the bar.
##
## Built only through `SaToolOptionViews.register_controls`, the facade, which
## hands the door one builder per element.
class_name SaBarControlViews
extends RefCounted


## A button standing for one of the bar's own buttons, *home*, held weakly so a
## freed bar leaves the view inert rather than reading a freed object.
##
## It looks like its home: the same text or icon, tooltip, size and toggle
## face, and the same rule that no click on it keeps the keyboard from the
## canvas. A toggle puts its own state on its home and emits the home's
## `toggled`, which runs the bar's handler, and a plain button emits the home's
## `pressed`. Either way it then reads the state again through [method follow].
class ButtonView:
    extends Button

    var _home: WeakRef

    func _init(element: String, home: Button) -> void:
        _home = weakref(home)
        # Never a bar control's own name, so a scenario or `in_tree` that finds
        # the bar's control by name still finds the bar's.
        name = element.replace(" ", "") + "View"
        focus_mode = Control.FOCUS_NONE
        size_flags_vertical = Control.SIZE_SHRINK_CENTER
        if home != null:
            _copy_face(home)
        set_meta(SaMake.KIND_META, SaMake.Kind.TOGGLE if toggle_mode else SaMake.Kind.BUTTON)
        if toggle_mode and not _presses_home():
            toggled.connect(_on_toggled)
        else:
            pressed.connect(_on_pressed)

    func _notification(what: int) -> void:
        if what == NOTIFICATION_ENTER_TREE:
            follow()

    ## The bar's control this view stands for, or null once it is gone.
    func home_button() -> Button:
        return _home.get_ref() as Button

    ## Reads the state the home control shows onto this one. Every subclass that
    ## is a toggle says where that state lives, since the home's own pressed flag
    ## may not have heard the change yet when this runs.
    func follow() -> void:
        pass

    ## Whether a press reaches the home control as `pressed` even though this is
    ## a toggle: true for the preset button, whose lit state is the docker's and
    ## not the click's.
    func _presses_home() -> bool:
        return false

    func _copy_face(home: Button) -> void:
        text = home.text
        icon = home.icon
        icon_alignment = home.icon_alignment
        expand_icon = home.expand_icon
        tooltip_text = home.tooltip_text
        clip_text = home.clip_text
        text_overrun_behavior = home.text_overrun_behavior
        custom_minimum_size = home.custom_minimum_size
        for constant: StringName in [&"icon_max_width"]:
            if home.has_theme_constant_override(constant):
                add_theme_constant_override(constant, home.get_theme_constant(constant))
        if home.has_theme_font_size_override(&"font_size"):
            add_theme_font_size_override(&"font_size", home.get_theme_font_size(&"font_size"))
        toggle_mode = home.toggle_mode
        if toggle_mode:
            SaTheme.make_toggle(self)

    ## The home's own handler runs with the state this view was pressed to,
    ## even where the home shows another. The bar's stabiliser toggle does not
    ## hear a write from the bar's own Stabilizer dropdown, so it can stand lit
    ## over a mode of none, and setting it lit then would emit nothing.
    func _on_toggled(on: bool) -> void:
        var home := home_button()
        if home != null:
            home.set_pressed_no_signal(on)
            home.toggled.emit(on)
        follow()

    func _on_pressed() -> void:
        var home := home_button()
        if home != null:
            home.pressed.emit()
        follow()


## One of the three symmetry switches. Lit while the canvas's symmetry has its
## field on, read from the document the bar's controls write to, which is the
## state the bar's switch writes and shows.
class SymmetryView:
    extends ButtonView

    ## The symmetry field this switch stands for: `mirror_horizontal`,
    ## `mirror_vertical` or `radial`.
    var field: StringName = &""

    var _bar: WeakRef
    var _heard: SaSymmetry = null

    func _init(element: String, home: Button, bar: ToolOptionsBar, for_field: StringName) -> void:
        super(element, home)
        field = for_field
        _bar = weakref(bar)
        # An icon alone was the bar's answer to a crowded row. A docker's column
        # has the room, so the switch says its name beside it.
        if icon != null:
            text = SaSettings.element_title("TopMenuBar", element)
            icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
        EventBus.document_loaded.connect(_on_document)
        EventBus.document_resized.connect(_on_document_resized)

    ## The canvas's symmetry, or null with no document behind the bar.
    func symmetry() -> SaSymmetry:
        var bar := _bar.get_ref() as ToolOptionsBar
        var document := bar.options.binding.document() if bar != null else null
        return document.symmetry if document != null else null

    func follow() -> void:
        var mirrors := symmetry()
        if mirrors != _heard:
            if _heard != null and _heard.changed.is_connected(follow):
                _heard.changed.disconnect(follow)
            _heard = mirrors
            if _heard != null:
                _heard.changed.connect(follow)
        if mirrors == null:
            return
        var on: bool = mirrors.radial >= 2 if field == &"radial" else bool(mirrors.get(field))
        set_pressed_no_signal(on)

    func _on_document(_document: SaDocument) -> void:
        follow()

    func _on_document_resized(_document: SaDocument, _size: Vector2i) -> void:
        follow()


## The stabiliser's quick toggle. Lit while the tool in the hand has a
## stabiliser mode other than none, which is what the bar's toggle shows and
## what a press on it writes through `ToolOptionsBar.write_option`.
class StabilizerView:
    extends ButtonView

    var _bar: WeakRef

    func _init(element: String, home: Button, bar: ToolOptionsBar) -> void:
        super(element, home)
        _bar = weakref(bar)
        # The bar shortens the word on its first row only. A docker has the room
        # for the whole of it.
        text = tr("Stabilizer")
        if bar != null:
            bar.options.option_written.connect(_on_written)
            bar.options.value_shown.connect(_on_written)
        EventBus.tool_changed.connect(_on_tool_changed)
        EventBus.preset_loaded.connect(_on_tool_changed)
        EventBus.brush_eraser_toggled.connect(_on_eraser_toggled)
        EventBus.tool_options_moved.connect(follow)

    ## A tool with no stabiliser leaves the toggle as it was, as the bar's does.
    func follow() -> void:
        var bar := _bar.get_ref() as ToolOptionsBar
        var mode: Variant = bar.read_option(&"stabilizer_mode") if bar != null else null
        if mode != null:
            set_pressed_no_signal(int(mode) > 0)

    func _on_written(key: StringName, _value: Variant) -> void:
        if key == &"stabilizer_mode":
            follow()

    func _on_tool_changed(_name: String) -> void:
        follow()

    func _on_eraser_toggled(_active: bool) -> void:
        follow()


## The Keep Blend Mode toggle. Lit while the preference is on, which is all the
## bar's toggle writes and all it shows.
class KeepBlendView:
    extends ButtonView

    func _init(element: String, home: Button) -> void:
        super(element, home)
        SaSettings.changed.connect(_on_setting_changed)
        SaSettings.profile_changed.connect(follow)

    func follow() -> void:
        set_pressed_no_signal(SaSettings.keep_blend_mode)

    func _on_setting_changed(property: StringName) -> void:
        if property == &"keep_blend_mode":
            follow()


## The preset group as one: the preset button, its label the preset in hand,
## lit while the Brush Presets docker is open, a press opening or closing it
## the way the bar's does. The name field the group swaps in for a save is the
## bar's alone, since it is opened from the docker's Save and answers there.
class PresetView:
    extends ButtonView

    ## The Brush Presets docker, a window of its own and not a control.
    var _docker: Window = null

    func _init(element: String, home: Button) -> void:
        super(element, home)
        EventBus.preset_loaded.connect(_on_preset_loaded)
        EventBus.preset_store_changed.connect(_on_store_changed)
        EventBus.docker_layout_changed.connect(follow)
        # Deferred, because the bar names the new tool's preset on the same
        # announcement and may hear it after this view.
        EventBus.tool_changed.connect(_on_tool_changed)

    func _presses_home() -> bool:
        return true

    func follow() -> void:
        var home := home_button()
        if home != null:
            text = home.text
            tooltip_text = home.tooltip_text
        var docker := _presets_docker()
        set_pressed_no_signal(docker != null and docker.visible)

    ## The Brush Presets docker, found once it is in the tree and heard from
    ## then on, the way the preset group finds it.
    func _presets_docker() -> Window:
        if is_instance_valid(_docker) and _docker.is_inside_tree():
            return _docker
        _docker = null
        if not is_inside_tree():
            return null
        _docker = get_tree().root.find_child(SaDockerIds.BRUSH_PRESETS, true, false) as Window
        if _docker != null:
            _docker.visibility_changed.connect(follow)
            _docker.tree_exited.connect(follow)
        return _docker

    func _on_preset_loaded(_name: String) -> void:
        follow()

    func _on_store_changed(_name: String, _saved: bool) -> void:
        follow()

    func _on_tool_changed(_name: String) -> void:
        follow.call_deferred()


## The rotation slider: the view's turn in degrees, a move on it turning the
## canvas through the bar's own slider, and the bar's slider and this one both
## following the view whichever of the two, the View menu or a chord turned it.
##
## A row holding a slider rather than a slider itself, because `FactorSlider`
## is a tool script and a class extending it would have to make this whole
## file one.
class RotationView:
    extends HBoxContainer

    ## Within half a degree the slider is taken to show the view's angle already,
    ## the bar's own tolerance, so the view answering a drag never moves the
    ## slider under the pointer.
    const SAME_ANGLE: float = 0.5

    ## The view's own slider, the bar's range and words.
    var slider: FactorSlider

    var _home: WeakRef
    var _view_source: Callable
    var _heard: SaView = null

    func _init(element: String, home: FactorSlider, view_source: Callable) -> void:
        _home = weakref(home)
        _view_source = view_source
        name = element.replace(" ", "") + "View"
        set_meta(SaMake.KIND_META, SaMake.Kind.ROW)
        slider = FactorSlider.new()
        # The bar's is "RotationSlider", and a scenario finds this one by name.
        slider.name = name + "Slider"
        slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        # A slider for a scenario's `control` step, which moves it as a drag does.
        slider.set_meta(SaMake.KIND_META, SaMake.Kind.SLIDER)
        if home != null:
            slider.preferred_width = home.preferred_width
            slider.min_value = home.min_value
            slider.max_value = home.max_value
            slider.wraps = home.wraps
            slider.step = home.step
            slider.decimal_places = home.decimal_places
            slider.prefix = home.prefix
            slider.suffix = home.suffix
            slider.tooltip_text = home.tooltip_text
            slider.value = home.value
        slider.value_changed.connect(_on_moved)
        add_child(slider)
        EventBus.boot_finished.connect(follow)
        EventBus.document_loaded.connect(_on_document)

    func _notification(what: int) -> void:
        if what == NOTIFICATION_ENTER_TREE:
            follow()

    ## The view this slider turns, connected to the first time it is seen.
    func canvas_view() -> SaView:
        var found := _view_source.call() as SaView if _view_source.is_valid() else null
        if found == _heard:
            return found
        if _heard != null and _heard.transform_changed.is_connected(follow):
            _heard.transform_changed.disconnect(follow)
        _heard = found
        if _heard != null:
            _heard.transform_changed.connect(follow)
        return found

    ## Puts the view's angle on the slider, with the bar's two guards: within
    ## half a degree is the same angle, and so are -180 and 180.
    func follow() -> void:
        var turned := canvas_view()
        if turned == null:
            return
        var degrees := rad_to_deg(turned.get_rotation())
        if absf(degrees - slider.value) < SAME_ANGLE:
            return
        if absf(absf(degrees) - 180.0) < SAME_ANGLE and absf(absf(slider.value) - 180.0) < SAME_ANGLE:
            return
        slider.set_value_no_signal(degrees)

    ## A move here is a move of the bar's slider, whose own handler turns the
    ## view about the middle of the viewport and redraws the canvas.
    func _on_moved(degrees: float) -> void:
        var home := _home.get_ref() as FactorSlider
        if home != null:
            home.set_value_no_signal(degrees)
            home.value_changed.emit(degrees)
        follow()

    func _on_document(_document: SaDocument) -> void:
        follow()
