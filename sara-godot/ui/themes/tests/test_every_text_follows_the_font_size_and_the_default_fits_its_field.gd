## Every text the main window draws follows the Font size
## slider, and the default text fits inside its field with room above and below.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The default text must not be so big it barely
## fits its fields, and the Font size slider must change it. The main
## window's own pieces are built here the way `Main` builds them, the top bar
## with the Tool Options bar in it, the Layers and Brush Presets panels and the
## Workspace page of Preferences, and every label, button and text field under
## them is read at the slider's least and at its most. The running app's proof
## is `scenarios/sara-s-default-text-fits-inside-its-fields-and-the-font-size-slider-moves-every-text-sara-draws.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar's controls come from the tools' descriptors, which need a device.
const REQUIRES_GPU := true

const WINDOW := Vector2i(1920, 1080)

## The size of the Preferences window's page, as it opens at 1920 by 1080.
const PREFERENCES := Vector2(760, 900)

## The least room a field leaves above and below its line of text, in logical
## pixels.
const ROOM := 1.0

## The scratch profile, absent before each test, so every piece is a fresh one.
static var scratch_profile: String = SaDataRoot.path("test_font_profile.cfg")

var _saved_path: String
var _kept_font_scale: float
var _kept_theme: Theme
var _surface: SaSurface
var _machine: ToolMachine
var _window: SubViewport
var _easel: SaEasel
var _canvas: SaCanvas
var _bar: TopMenuBar
var _layers: LayersDocker
var _presets: BrushPresetsDocker
var _page: SaWorkspacePage


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    _kept_font_scale = SaUI.user_font_scale
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    # The theme `Main` builds at boot and every window shares, which a suite
    # run never builds, and put back afterwards.
    _kept_theme = SaUI.shared_theme
    SaUI.init_global_theme(null)
    _set_font_scale(SaSettings.ui_font_scale)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _window = SubViewport.new()
    _window.name = "U704Window"
    _window.size = WINDOW
    _window.gui_embed_subwindows = true
    _window.render_target_update_mode = SubViewport.UPDATE_DISABLED
    EventBus.add_child(_window)
    var main := Node.new()
    main.name = "U704Main"
    _window.add_child(main)
    var options := ToolOptionsBar.new()
    options.target_tool_machine = _machine
    options._ready()
    _bar = TopMenuBar.new()
    _bar.add_tool_options(options)
    main.add_child(_bar)
    var note_mode := SaNoteMode.new()
    _bar.add_child(note_mode)
    _bar.bind_commands(Fixtures.make_menu_registries(note_mode).commands)
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _layers = LayersDocker.new()
    _layers.target_canvas = _canvas
    main.add_child(_layers)
    _layers.sync_layer_list()
    _presets = BrushPresetsDocker.new()
    main.add_child(_presets)
    # The Preferences window takes the shared theme and reads its text from it
    # alone, so the page hangs from a host that holds the same theme.
    var preferences := Control.new()
    preferences.name = "U704Preferences"
    preferences.theme = SaUI.shared_theme
    preferences.size = PREFERENCES
    main.add_child(preferences)
    _page = SaWorkspacePage.new()
    preferences.add_child(_page)
    _page.size = PREFERENCES
    _apply()


func after_each() -> void:
    _window.free()
    _canvas.free()
    _easel.free()
    Fixtures.teardown(_surface, _machine)
    SaUI.shared_theme = _kept_theme
    _set_font_scale(_kept_font_scale)
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## The Font size slider moved to *font_scale*, the way `SaSettingsApply` passes
## it on: the shared theme rewritten and the change announced.
func _set_font_scale(font_scale: float) -> void:
    SaUI.user_font_scale = font_scale
    SaUI.refresh_font_sizes()
    EventBus.ui_font_scale_changed.emit(font_scale)


## The theme pass `Main` runs over the bar at a change of the font size, the
## page's own refit that the Preferences window runs, and every container sorted.
func _apply() -> void:
    DockerUtils.apply_ui_theme(_bar)
    _bar.rows.refit()
    _bar.offset_bottom = _bar.get_combined_minimum_size().y
    SaUI.apply_ui_theme(_layers)
    SaUI.apply_ui_theme(_presets)
    SaSettingsRows.refit(_page)
    # The engine tells a control its theme changed on a later frame, and a
    # suite that awaits drops every assertion after the await, so
    # the page is told here, which is what that frame would do.
    _page.propagate_notification(Control.NOTIFICATION_THEME_CHANGED)
    _sort(_window)


func _sort(node: Node) -> void:
    if node is Container:
        node.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        if not child is Window or child is DockerWindow:
            _sort(child)


## Every control under *node* that draws words, keyed by its path.
func _texts(node: Node, out: Dictionary = {}) -> Dictionary:
    for child in node.get_children():
        if child is Window and not child is DockerWindow:
            continue
        if child is CanvasItem and not (child as CanvasItem).visible:
            continue
        var control := child as Control
        if control != null and not _words(control).is_empty():
            out[String(_window.get_path_to(control))] = control
        _texts(child, out)
    return out


func _words(control: Control) -> String:
    if control is Label:
        return (control as Label).text
    if control is Button:
        return (control as Button).text
    if control is LineEdit:
        var edit := control as LineEdit
        return edit.text if not edit.text.is_empty() else edit.placeholder_text
    return ""


## The size *control*'s words are drawn at, its label settings first where it
## has them, since a label reads those over its theme.
func _drawn_size(control: Control) -> int:
    var label := control as Label
    if label != null and label.label_settings != null:
        return label.label_settings.font_size
    return control.get_theme_font_size(&"font_size")


func _drawn_font(control: Control) -> Font:
    var label := control as Label
    if label != null and label.label_settings != null and label.label_settings.font != null:
        return label.label_settings.font
    return control.get_theme_font(&"font")


func test_every_text_is_larger_at_the_sliders_most_than_at_its_least() -> void:
    _set_font_scale(SaUI.MIN_FONT_SCALE)
    _apply()
    var least := {}
    var texts := _texts(_window)
    for path: String in texts:
        least[path] = _drawn_size(texts[path])
    _set_font_scale(SaUI.MAX_FONT_SCALE)
    _apply()
    texts = _texts(_window)
    var still: Array[String] = []
    for path: String in least:
        if texts.has(path) and _drawn_size(texts[path]) <= int(least[path]):
            still.append('%s "%s" at %d' % [path.get_file(), _words(texts[path]), least[path]])
    assert_true(least.size() > 40, "The walk read the bar, both panels and the page, %d texts" % least.size())
    assert_true(still.is_empty(), "%d texts stayed the size they were: %s" % [still.size(), "; ".join(still)])


## The height *control*'s field is built at, its own minimum or the theme's
## button height, rather than the height it has: a field whose text is too tall
## grows round it, so its own size would always hold its text.
func _field_height(control: Control) -> float:
    return maxf(control.custom_minimum_size.y, float(SaUI.BASE_BTN_H))


func test_at_the_default_every_field_holds_its_text_with_room_above_and_below() -> void:
    var tight: Array[String] = []
    var read := 0
    var texts := _texts(_window)
    for path: String in texts:
        var control: Control = texts[path]
        if not (control is Button or control is LineEdit):
            continue
        read += 1
        var height := _drawn_font(control).get_height(_drawn_size(control))
        var field := _field_height(control)
        if (field - height) / 2.0 < ROOM:
            tight.append('%s "%s" %.1f of %.0f' % [path.get_file(), _words(control), height, field])
    assert_true(read > 20, "The walk read the fields of the bar, both panels and the page, %d" % read)
    assert_true(tight.is_empty(), "%d fields hold their text with no room: %s" % [tight.size(), "; ".join(tight)])


## The bar's small controls built with a fixed 11 pixels, which the theme pass
## wrote over, draw the fraction they ask for at every position of the slider.
func test_the_bars_small_controls_draw_their_own_fraction_at_every_size() -> void:
    for font_scale: float in [SaUI.MIN_FONT_SCALE, SaSettingsValues.DEFAULT_FONT_SCALE, SaUI.MAX_FONT_SCALE]:
        _set_font_scale(font_scale)
        _apply()
        var wanted := roundi(SaUI.get_font_size() * SaUI.SMALL_FONT_SCALE)
        for node_name: String in ["PresetMenu", "PresetNameEdit", "EditBrushButton"]:
            var control := _bar.find_child(node_name, true, false) as Control
            assert_not_null(control, "The bar has %s" % node_name)
            assert_eq(_drawn_size(control), wanted, "%s at a Font size of %.2f" % [node_name, font_scale])
    _set_font_scale(SaSettingsValues.DEFAULT_FONT_SCALE)
    _apply()
    var preset := _bar.find_child("PresetMenu", true, false) as Control
    assert_eq(_drawn_size(preset), 11, "At the default the preset group draws the 11 pixels it was built with")


## What a dialog holds outside the theme, a heading or a hint built at a size of
## its own, follows the slider through `SaUI.refit_text`, which is what
## `SaDialogWindow` runs at a change of the Font size. A `Window` added to the
## tree hangs a headless run, so the pages two dialogs carry are built bare.
func test_a_dialogs_own_sizes_follow_the_slider_through_refit_text() -> void:
    var pages: Array[Control] = [SaTabletCalibration.new(), SaColorSpaceBrowser.new()]
    var least: Dictionary = {}
    var asked := 0
    for font_scale: float in [SaUI.MIN_FONT_SCALE, SaUI.MAX_FONT_SCALE]:
        _set_font_scale(font_scale)
        for page: Control in pages:
            SaUI.refit_text(page)
            for control: Control in _asking(page):
                var drawn := control.get_theme_font_size("font_size")
                var wanted := SaUI.font_size_for(float(control.get_meta(SaUI.FONT_SCALE_META)))
                assert_eq(drawn, wanted, "%s draws its fraction at %.2f" % [control.name, font_scale])
                if font_scale == SaUI.MIN_FONT_SCALE:
                    least[control] = drawn
                else:
                    asked += 1
                    assert_true(drawn > int(least[control]), "%s grows from the least to the most" % control.name)
    assert_true(asked >= 6, "The calibration page and the colour space browser ask for six sizes of their own")
    _set_font_scale(SaSettingsValues.DEFAULT_FONT_SCALE)
    for page: Control in pages:
        SaUI.refit_text(page)
        var hint := _asking(page)[0]
        var wanted := roundi(float(SaUI.get_font_size()) * float(hint.get_meta(SaUI.FONT_SCALE_META)))
        assert_eq(hint.get_theme_font_size("font_size"), wanted, "%s at the default" % hint.name)
        page.free()
    assert_eq(SaUI.font_size_for(SaUI.fraction_of(11)), 11, "A size stated as points draws those points at the default")


func _asking(node: Node, out: Array[Control] = []) -> Array[Control]:
    if node is Control and node.has_meta(SaUI.FONT_SCALE_META):
        out.append(node as Control)
    for child in node.get_children():
        _asking(child, out)
    return out
