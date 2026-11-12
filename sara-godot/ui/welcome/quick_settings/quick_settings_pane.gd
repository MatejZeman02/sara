## The Quick settings pane of the welcome window: the seven controls a painter
## reaches for before opening a document.
##
## **Every one of them is the control a Preferences page already holds**, built
## here a second time rather than reimplemented: the language is the Languages
## page's, the scale slider the Workspace page's, the theme button the Colour
## themes page's, the pressure pad the Tablet page's, the embedded
## subwindows switch the Workspace page's, the display profile the Display
## page's and the colour picker's shape the Colour Picker's Type row on Layouts
## and dockers.
## The pane owns no preference of its own, so there is nothing here that can
## disagree with the pages about what a setting means.
##
## **Above the seven stands "I'm coming from"**, the row `SaComingFromRow`
## builds, whose buttons set Sara up like Krita, Photoshop or Procreate in one press,
## and a second press puts Sara's own back. It is also the first row of Preferences > Interface.
## A press writes through the writers the pages already call, and the seven
## rows read the settings again at once, the new theme and picker shape among
## them.
##
## **No control gets a second writer.** All seven write a `SaSettings` property
## and nothing else, and the pane never touches `Window.content_scale_factor`:
## `SaUI.apply_to_window()` is the only writer of the window scale, and the scale
## reaches it through `SaSettings.ui_scale` the way the pages already do.
##
## The rows are the row layer's, `SaSettingsRows`, so the control column lines
## up with the Preferences pages rather than with the pane.
##
## **The pane follows the language it picks.** Its rows are
## built again in the new locale when the engine says the translation changed,
## a frame later, so the button that was pressed is not freed under its own
## signal. The window's own words follow on the same notification.
@tool
class_name WelcomeQuickSettingsPane
extends VBoxContainer

## The seven controls, so a test or a capture reads what the pane built rather
## than walking it by name. The names are the Preferences pages' own, which is
## what lets one capture step drive either surface.
var language_opt: SaChoiceButton
var scale_slider: HSlider
var font_slider: HSlider
var theme_opt: SaChoiceButton
var calibration: SaTabletCalibration
var embed_check: CheckButton
var profile_opt: SaChoiceButton
var picker_shape_opt: SaChoiceButton

## The "I'm coming from" row above the controls.
var coming_from: SaComingFromRow

## The number beside the scale slider, which reads the way the Workspace
## page's does, "100%", under a title that says only "UI scale".
var scale_readout: Label

## The number beside the font size slider, which reads the way the Workspace
## page's does, "100%", under a title that says only "Font size".
var font_readout: Label

## Whether the hand holds the scale slider's grabber.
var _scale_held: bool = false

## Whether the hand holds the font size slider's grabber.
var _font_held: bool = false

## The catalogues the language row lists, or null until `MainDialogs` hands
## them over, which it does once the modules can register any. Until then the
## row lists British English and the stored language.
var _catalogues: SaTranslationRegistry = null

## The locale the rows were last built in, so a notification that changes no
## language builds nothing.
var _built_in: String = ""


func _init() -> void:
    name = "QuickSettings"
    add_theme_constant_override("separation", SaUI.px(SaTheme.GAP))
    SaSettings.changed.connect(_on_setting_changed)
    _build()


## Builds the rows, in the locale set now, over whatever rows were there.
func _build() -> void:
    var old := get_node_or_null(^"QuickSettingsScroll")
    if old != null:
        remove_child(old)
        old.queue_free()
    _built_in = TranslationServer.get_locale()

    # The calibration is a whole Preferences page's body rather than a single
    # control, and the welcome window is 720 by 480: clipped it would hide the
    # strip the row exists for, so the pane scrolls.
    var scroll := SaMake.scroll(self, "QuickSettingsScroll")
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var page := SaMake.column(scroll, "QuickSettingsRows")
    page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    SaSettingsRows.setup_page(page)

    var rows := SaSettingsRows.section(page, tr("Quick settings"))
    _build_coming_from_row(rows)
    _build_language_row(rows)
    _build_scale_row(rows)
    _build_font_row(rows)
    _build_theme_row(rows)
    _build_pressure_row(rows)
    _build_embed_row(rows)
    _build_profile_row(rows)
    _build_picker_shape_row(rows)


## Read the settings back on every open.
##
## The window is built once and shown again, and the Preferences pages write the
## same properties, so a control left on the value it was built with is a
## control that disagrees with the app. `SaWelcomeWindow` reads its own checkbox
## back on this same signal for the same reason.
func _ready() -> void:
    var host := get_window()
    if host != null:
        host.visibility_changed.connect(_on_host_shown)


## The rows are built again when the language changed under them, a frame
## later and once however many notifications came.
func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED and TranslationServer.get_locale() != _built_in:
        _built_in = TranslationServer.get_locale()
        follow_language.call_deferred()


## Builds the rows again in the language set now and reads the settings into
## them. Public because a suite cannot wait the frame the notification defers it
## by, so it calls this itself.
func follow_language() -> void:
    _build()
    refresh()


## Lists the catalogues of *registry* in the language row from now on, and
## again whenever a module brings or takes one. `MainDialogs` calls it, since
## the window is built by the boot before any registry exists.
func follow_catalogues(registry: SaTranslationRegistry) -> void:
    if _catalogues != null and _catalogues.changed.is_connected(_list_languages):
        _catalogues.changed.disconnect(_list_languages)
    _catalogues = registry
    if _catalogues != null:
        _catalogues.changed.connect(_list_languages)
    _list_languages()


## The language row's choices, the Languages page's own list.
func _list_languages() -> void:
    if is_instance_valid(language_opt):
        language_opt.set_choices(SaLanguagesPage.choices(_catalogues, SaSettings.ui_language))
        language_opt.select_value(SaSettings.ui_language)


func _on_host_shown() -> void:
    var host := get_window()
    if host != null and host.visible:
        refresh()


## Puts the stored values back into the seven controls, silently.
##
## Silently on purpose: this is what the settings say, and a setter that
## announced the new value would turn the read into a write of it. The
## calibration's own `refresh()` reads the same way.
func refresh() -> void:
    coming_from.refresh()
    _list_languages()
    scale_slider.set_value_no_signal(SaSettings.ui_scale)
    scale_readout.text = SaWorkspacePage.percent(SaSettings.ui_scale)
    font_slider.set_value_no_signal(SaSettings.ui_text_size)
    font_readout.text = SaWorkspacePage.percent(SaSettings.ui_text_size)
    theme_opt.select_value(SaTheme.palette_id)
    calibration.refresh()
    embed_check.set_pressed_no_signal(SaSettings.embed_subwindows)
    profile_opt.select_value(SaSettings.display_profile)
    picker_shape_opt.select_value(SaSettings.color_picker_shape)


func _on_setting_changed(prop: StringName) -> void:
    if prop == &"ui_scale":
        if is_instance_valid(scale_slider) and not _scale_held:
            scale_slider.set_value_no_signal(SaSettings.ui_scale)
            if is_instance_valid(scale_readout):
                scale_readout.text = SaWorkspacePage.percent(SaSettings.ui_scale)
    elif prop == &"ui_font_scale":
        if is_instance_valid(font_slider) and not _font_held:
            font_slider.set_value_no_signal(SaSettings.ui_text_size)
            if is_instance_valid(font_readout):
                font_readout.text = SaWorkspacePage.percent(SaSettings.ui_text_size)


## "I'm coming from", the row that sets every preference a program a painter
## knows has a meaning for, and the seven below read them again after a press.
func _build_coming_from_row(rows: Container) -> void:
    coming_from = SaComingFromRow.new()
    coming_from.program_applied.connect(func(_program: String) -> void: refresh())
    SaSettingsRows.row(rows, tr("I'm coming from"), tr(SaComingFromRow.HINT), coming_from)
    coming_from.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## The language Sara speaks, the Languages page's row: the same list, from
## `SaLanguagesPage.choices`, so a language a module registers is in both, and
## the same one setting behind it, which `SaSettingsApply` sets on
## `TranslationServer` at once.
func _build_language_row(rows: Container) -> void:
    language_opt = SaMake.choice(null, "LanguageOpt", SaLanguagesPage.choices(_catalogues, SaSettings.ui_language))
    language_opt.select_value(SaSettings.ui_language)
    language_opt.choice_picked.connect(func(id: Variant) -> void: SaSettings.ui_language = String(id))
    SaSettingsRows.row(
        rows, tr("Language"), tr("The language Sara's windows speak. It switches at once, with no restart."), language_opt
    )


## The interface scale, the same slider the Workspace page builds and the same
## one setting behind it.
##
## **Nothing is clamped here.** `SaSettingsValues.ui_scale`'s own setter is the
## one place a scale enters the app, and it has the floor.
func _build_scale_row(rows: Container) -> void:
    scale_slider = HSlider.new()
    scale_slider.name = "UiScaleSlider"
    # The wheel belongs to the page that scrolls, which has no undo for a
    # value moved by a notch passing over the track.
    scale_slider.scrollable = false
    scale_slider.min_value = 0.5
    scale_slider.max_value = 2.0
    scale_slider.step = 0.05
    scale_slider.value = SaSettings.ui_scale
    # Written when the hand lets go, the rule the Workspace page's
    # `_wire_slider` gives: a rescale under a held grabber moves the track, and
    # the drag then chases its own handle. A key or a click on the track has no
    # gesture to disturb and applies at once.
    scale_slider.drag_started.connect(func() -> void: _scale_held = true)
    scale_slider.drag_ended.connect(
        func(changed: bool) -> void:
            _scale_held = false
            if changed:
                SaSettings.ui_scale = scale_slider.value
    )
    # The readout follows the grabber while it is held, so the hand sees the
    # value it will let go on before the rescale lands.
    scale_slider.value_changed.connect(
        func(val: float) -> void:
            scale_readout.text = SaWorkspacePage.percent(val)
            if not _scale_held:
                SaSettings.ui_scale = val
    )
    # The value beside the slider, as on the Workspace page, so the title
    # reads the same at every scale.
    scale_readout = SaWorkspacePage.readout_beside(scale_slider)
    var box := scale_slider.get_parent() as Control
    scale_slider.tooltip_text = tr("Resize every window, row and control at once.")
    SaSettingsRows.row(
        rows, tr("UI scale"), tr("Every window, row and control resizes at once, over the display's own scale."), box
    )
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## The interface text size, the same slider the Workspace page builds and the
## same setting behind it.
func _build_font_row(rows: Container) -> void:
    font_slider = HSlider.new()
    font_slider.name = "FontSizeSlider"
    font_slider.scrollable = false
    font_slider.min_value = ceilf(SaSettingsValues.MIN_TEXT_SIZE * 100.0) / 100.0
    font_slider.max_value = floorf(SaSettingsValues.MAX_TEXT_SIZE * 100.0) / 100.0
    font_slider.step = 0.01
    font_slider.value = SaSettings.ui_text_size
    font_slider.drag_started.connect(func() -> void: _font_held = true)
    font_slider.drag_ended.connect(
        func(changed: bool) -> void:
            _font_held = false
            if changed:
                SaSettings.ui_text_size = font_slider.value
    )
    font_slider.value_changed.connect(
        func(val: float) -> void:
            font_readout.text = SaWorkspacePage.percent(val)
            if not _font_held:
                SaSettings.ui_text_size = val
    )
    font_readout = SaWorkspacePage.readout_beside(font_slider)
    var box := font_slider.get_parent() as Control
    font_slider.tooltip_text = tr("Set the size of the interface's text.")
    SaSettingsRows.row(rows, tr("Font size"), _font_hint(SaSettings.ui_text_size), box)
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## The hint under the Font size row at *text_size*, the painter's reading, which
## names the points the stored multiplier draws.
func _font_hint(text_size: float) -> String:
    var font_scale := text_size * SaSettingsValues.DEFAULT_FONT_SCALE
    var points := maxi(1, int(round(float(SaUI.BASE_FONT_SIZE) * font_scale)))
    return (
        tr_n(
            "Text at %d point, and the dockers grow with it. Buttons, margins and icons keep the size the UI scale gives them.",
            "Text at %d points, and the dockers grow with it. Buttons, margins and icons keep the size the UI scale gives them.",
            points
        )
        % points
    )


## The palette the interface is drawn with, over the rows `SaTheme` offers now.
##
## The choice carries the palette's id rather than a position in the list, which
## is what lets the handler write what it was handed. The Preferences page
## refreshes this list when the theme changes. This one is built with the window
## and re-read on every open, which is as often as a palette can change.
func _build_theme_row(rows: Container) -> void:
    var choices: Array = []
    for entry: Dictionary in SaTheme.available():
        choices.append({"id": String(entry["id"]), "label": String(entry["name"])})
    theme_opt = SaMake.choice(null, "ColorThemeOpt", choices)
    theme_opt.select_value(SaTheme.palette_id)
    theme_opt.choice_picked.connect(func(id: Variant) -> void: SaSettings.theme_name = String(id))
    SaSettingsRows.row(rows, tr("Colour theme"), tr("The palette every panel is drawn with."), theme_opt)


## The pen's pressure calibration, which is `SaTabletCalibration` itself and not
## a smaller copy of it: the strip, the readout and the slider are that
## control's own, and its `set_max_pressure()` is the single writer of the
## setting behind them.
func _build_pressure_row(rows: Container) -> void:
    calibration = SaTabletCalibration.new()
    calibration.name = "TabletCalibration"
    SaSettingsRows.row(rows, tr("Pen pressure"), tr("Where the pen's usable travel ends, measured on the strip."), calibration)
    # A page body takes the width it needs rather than sitting at the row
    # layer's left edge, which is where a switch or a spin box belongs.
    calibration.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Whether a docker is drawn inside the main window or as a window of its own,
## the same switch the Workspace page holds.
func _build_embed_row(rows: Container) -> void:
    embed_check = CheckButton.new()
    embed_check.name = "EmbedSubwindowsCheck"
    embed_check.button_pressed = SaSettings.embed_subwindows
    embed_check.toggled.connect(func(pressed: bool) -> void: SaSettings.embed_subwindows = pressed)
    SaSettingsRows.row(rows, tr("Dockers inside the main window"), tr(SaDockersPage.EMBED_HINT), embed_check)


## The monitor's colour space, the Display page's Display profile row: the same
## list, every id in `SaSettings.DISPLAY_PROFILES` under the colour space's own
## name and the system's profile, which a fresh profile starts on, and the same
## one setting behind it.
##
## The tooltip says what the welcome window's question 3 asked it to, that a
## wider profile than sRGB helps only on a monitor that shows that gamut.
func _build_profile_row(rows: Container) -> void:
    var choices: Array = []
    for profile_id: String in SaSettings.DISPLAY_PROFILES:
        choices.append({"id": profile_id, "label": tr(SaColorSpace.display_name(StringName(profile_id)))})
    if SaSettingsValues.display_profile_offered(SaSettingsValues.DISPLAY_PROFILE_SYSTEM):
        choices.append({"id": SaSettingsValues.DISPLAY_PROFILE_SYSTEM, "label": tr("The system's profile")})
    profile_opt = SaMake.choice(null, "DisplayProfileOpt", choices)
    profile_opt.select_value(SaSettings.display_profile)
    profile_opt.choice_picked.connect(func(id: Variant) -> void: SaSettings.display_profile = String(id))
    profile_opt.tooltip_text = tr(
        "Display P3 or Rec. 2020 helps only on a monitor that shows that gamut. On any other, keep sRGB."
    )
    SaSettingsRows.row(
        rows,
        tr("Display profile"),
        tr("The colour space your monitor shows. The view converts into it last, and encodes as sRGB."),
        profile_opt
    )


## The colour picker's shape, the Colour Picker's Type row: the shapes
## `SaPickerShape` lists under their own labels, and `color_picker_shape` behind
## them.
##
## The row writes the setting itself rather than through
## `SaSettings.set_docker_option`, which the Type row calls, because that call
## reaches the setting only once the picker registered the row's spec, and the
## welcome window opens before any docker is built. Both end in the one setter
## of `color_picker_shape`, which every picker in the tree follows.
func _build_picker_shape_row(rows: Container) -> void:
    var choices: Array = []
    for i in range(SaPickerShape.KIND_KEYS.size()):
        choices.append({"id": SaPickerShape.KIND_KEYS[i], "label": tr(SaPickerShape.KIND_LABELS[i])})
    picker_shape_opt = SaMake.choice(null, "PickerShapeOpt", choices)
    picker_shape_opt.select_value(SaSettings.color_picker_shape)
    picker_shape_opt.choice_picked.connect(func(id: Variant) -> void: SaSettings.color_picker_shape = String(id))
    SaSettingsRows.row(
        rows, tr("Colour picker"), tr("Which colour model the picker reads, and how it lays its area out."), picker_shape_opt
    )


## Puts the pane in front, because the shot a scenario takes after driving it
## has to have the pane in it rather than whichever tab was last looked at.
func reveal() -> void:
    var tabs := get_parent() as TabContainer
    if tabs != null:
        tabs.current_tab = tabs.get_tab_idx_from_control(self)


## `"ui_scale"` or `"font_size"`, the two sliders this pane shares with the
## Workspace page.
func slider_named(key: String) -> HSlider:
    return font_slider if (key == "font_size" or key == "ui_font_scale") else scale_slider


## The pane's door for a scenario, reached through the `{"workspace":...}` step,
## which is the one place a scale slider is driven by name.
##
## `{"workspace": {"welcome": true, "slider": "ui_scale", "value": 1.4}}` shows
## the pane and moves its slider the way the Workspace page's own capture does,
## and answers with the value the control holds. Without a `value` it only
## reports, which is how a scenario reads the pane back after the Preferences
## page moved the same setting.
func drive_sliders(spec: Dictionary) -> String:
    reveal()
    if spec.has("rows"):
        return _report_rows(String(spec["rows"]))
    if spec.has("coming_from"):
        return _drive_coming_from(String(spec["coming_from"]))
    var key := String(spec.get("slider", "ui_scale"))
    if key != "ui_scale" and key != "font_size" and key != "ui_font_scale":
        return "SaCapture: the Quick settings pane has no '%s' slider" % key
    var slider := slider_named(key)
    if spec.has("value"):
        slider.value = float(spec["value"])
    return (
        "SaCapture: welcome quick settings '%s' = %.2f (min %.2f, step %.3f), ui scale %.2f"
        % [key, slider.value, slider.min_value, slider.step, SaUI.scale()]
    )


## `{"workspace": {"welcome": true, "coming_from": "krita"}}` presses the
## program's button of "I'm coming from", an empty name pressing none, and
## answers which button is pressed and every value a press sets, so a run's log
## says in words what its shot shows.
func _drive_coming_from(program: String) -> String:
    if not program.is_empty():
        coming_from.press(program)
    var pressed: Array[String] = []
    for id: String in coming_from.buttons:
        if coming_from.buttons[id].button_pressed:
            pressed.append(id)
    return (
        (
            "SaCapture: welcome quick settings coming from pressed [%s], shortcuts '%s', palette '%s', layout '%s', "
            + "picker '%s', ui scale %.2f"
        )
        % [
            ", ".join(pressed),
            SaSettings.shortcuts_profile,
            SaTheme.palette_id,
            coming_from.layout_in_force(),
            SaSettings.color_picker_shape,
            SaUI.scale(),
        ]
    )


## `{"workspace": {"welcome": true, "rows": "Colour picker"}}` scrolls the pane
## until the row titled *scroll_to* is on screen, an empty title scrolling
## nothing, and answers every row's title with whether the scroll shows all of
## it. A shot is a picture a session cannot read, so the line says in words
## which rows the shot holds.
func _report_rows(scroll_to: String) -> String:
    var scroll := get_node_or_null(^"QuickSettingsScroll") as ScrollContainer
    var lines: Array[HBoxContainer] = []
    for node in find_children("*", "HBoxContainer", true, false):
        if node.has_meta(SaSettingsRows.ROW_META):
            lines.append(node as HBoxContainer)
    for line in lines:
        if scroll != null and String(line.get_meta(SaSettingsRows.TITLE_META)) == scroll_to:
            scroll.ensure_control_visible(line)
    var shown: Array[String] = []
    var seen := scroll.get_global_rect() if scroll != null else Rect2()
    for line in lines:
        var whole := seen.encloses(line.get_global_rect().grow(-0.5))
        shown.append("%s %s" % [String(line.get_meta(SaSettingsRows.TITLE_META)), "shown" if whole else "scrolled off"])
    return "SaCapture: welcome quick settings %d rows: %s" % [lines.size(), ", ".join(shown)]


## Finds the pane in a running app and drives it. Called by the step table's
## `{"workspace":...}` step when the spec names the welcome window, which keeps
## the pane's own driving in this file.
static func capture_pane(root: Node, spec: Dictionary) -> String:
    var pane := root.find_child("QuickSettings", true, false)
    if pane == null or not pane.has_method("drive_sliders"):
        return "SaCapture: the welcome window is not open"
    return pane.drive_sliders(spec)
