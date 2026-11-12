## A wheel notch that scrolls a page leaves its sliders where they were.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Godot's `HSlider` moves a step on a wheel press and lets the event go on to
## the `ScrollContainer` around it, so a painter rolling the wheel down a
## Preferences page changed every slider whose track passed under the pointer
## while the page scrolled on, with nothing to say a value moved and no undo to
## put it back. This suite puts a page in a scroll inside an embedded window,
## pushes wheel notches over its sliders the way the pointer would cross them,
## and reads the setting and the scroll. It also holds every slider the pages
## and the welcome screen build to `scrollable` false, so one added later
## through the same path is held too, and drags the UI scale slider to show a
## drag still applies on its release.
extends "res://tests/test_framework.gd"

const SCALE_SLIDER := "UiScaleSlider"
const AUTOSAVE_VALUE := "settings/autosave_interval_minutes"

var _kept_embedding := true
var _kept_scale := 1.0
var _kept_text := 1.0
var _kept_autosave := 2.0
var _host: Node = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _kept_scale = SaSettings.ui_scale
    _kept_text = SaSettings.ui_text_size
    _kept_autosave = SaSettings.autosave_interval_minutes
    _host = Node.new()
    _host.name = "WheelOverSlidersHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    SaSettings.ui_scale = _kept_scale
    SaSettings.ui_text_size = _kept_text
    SaSettings.autosave_interval_minutes = _kept_autosave
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding


func _frames(count: int) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    for i in count:
        await tree.process_frame


## The page in a column taller than the window, so the scroll has somewhere to
## go, inside a window of its own that takes pushed input.
func _scrolled(page: Control, window_size: Vector2i) -> Array:
    var window := Window.new()
    window.size = window_size
    _host.add_child(window)
    window.popup()
    var scroll := ScrollContainer.new()
    scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
    window.add_child(scroll)
    var column := VBoxContainer.new()
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(column)
    page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_child(page)
    var spacer := Control.new()
    spacer.custom_minimum_size = Vector2(10, 1500)
    column.add_child(spacer)
    return [window, scroll]


func _mouse(kind: MouseButton, at: Vector2, pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = kind
    event.pressed = pressed
    event.position = at
    event.global_position = at
    event.factor = 1.0
    if pressed and kind == MOUSE_BUTTON_LEFT:
        event.button_mask = MOUSE_BUTTON_MASK_LEFT
    return event


func _notch(window: Window, at: Vector2) -> void:
    window.push_input(_mouse(MOUSE_BUTTON_WHEEL_DOWN, at, true))
    window.push_input(_mouse(MOUSE_BUTTON_WHEEL_DOWN, at, false))


func _sliders(root: Node) -> Array[HSlider]:
    var found: Array[HSlider] = []
    for node: Node in root.find_children("*", "HSlider", true, false):
        found.append(node as HSlider)
    return found


func test_a_notch_over_the_ui_scale_slider_scrolls_the_page_and_keeps_the_scale() -> void:
    var page := SaWorkspacePage.new()
    var made := _scrolled(page, Vector2i(500, 300))
    var window := made[0] as Window
    var scroll := made[1] as ScrollContainer
    await _frames(4)
    var slider := page.find_child(SCALE_SLIDER, true, false) as HSlider
    assert_not_null(slider, "the Workspace page has its UI scale slider")
    if slider == null:
        return
    var scale_before := SaSettings.ui_scale
    var scroll_before := scroll.scroll_vertical
    _notch(window, slider.get_global_rect().get_center())
    await _frames(3)
    assert_almost_eq(SaSettings.ui_scale, scale_before, 0.001, "one notch over the UI scale slider leaves the scale where it was")
    assert_almost_eq(slider.value, scale_before, 0.001, "and the slider where it was")
    assert_true(scroll.scroll_vertical > scroll_before, "while the page scrolls")


func test_six_notches_over_autosave_every_leave_it_where_it_was() -> void:
    SaSettings.autosave_interval_minutes = 2.0
    var page := SaFilesPage.new()
    var made := _scrolled(page, Vector2i(600, 300))
    var window := made[0] as Window
    var scroll := made[1] as ScrollContainer
    await _frames(4)
    var slider: HSlider = null
    for found: HSlider in _sliders(page):
        if String(found.get_meta(SaPage.VALUE_NAME_META, "")) == AUTOSAVE_VALUE:
            slider = found
    assert_not_null(slider, "the Files page has its Autosave every slider")
    if slider == null:
        return
    scroll.scroll_vertical = maxi(0, int(slider.get_global_rect().position.y) - 100)
    await _frames(2)
    var scroll_before := scroll.scroll_vertical
    var read := PackedStringArray()
    for notch in 6:
        # The pointer stays on the track as the page moves under it, the worst
        # case for a painter whose hand is still.
        _notch(window, slider.get_global_rect().get_center())
        await _frames(2)
        read.append("%s" % SaSettings.autosave_interval_minutes)
    assert_almost_eq(
        SaSettings.autosave_interval_minutes, 2.0, 0.001, "six notches leave Autosave every at 2, it read %s" % ", ".join(read)
    )
    assert_true(scroll.scroll_vertical > scroll_before, "while the page scrolls")


func test_every_slider_the_pages_and_the_welcome_screen_build_leaves_the_wheel_to_the_page() -> void:
    var built: Dictionary[String, Control] = {
        "Workspace": SaWorkspacePage.new(),
        "Files": SaFilesPage.new(),
        "Display": SaDisplayPage.new(),
        "Tablet": SaTabletPage.new(),
        "the welcome screen's quick settings": WelcomeQuickSettingsPane.new(),
    }
    for where: String in built:
        var sliders := _sliders(built[where])
        assert_true(sliders.size() > 0, "%s builds at least one slider" % where)
        var wheeled := PackedStringArray()
        for slider: HSlider in sliders:
            if slider.scrollable:
                wheeled.append(str(slider.get_path()) if slider.is_inside_tree() else String(slider.name))
        assert_eq(wheeled.size(), 0, "no slider %s builds takes the wheel, found %s" % [where, ", ".join(wheeled)])
        built[where].free()


func test_a_drag_on_the_ui_scale_slider_still_applies_on_its_release() -> void:
    SaSettings.ui_scale = 1.0
    var page := SaWorkspacePage.new()
    var made := _scrolled(page, Vector2i(500, 300))
    var window := made[0] as Window
    await _frames(4)
    var slider := page.find_child(SCALE_SLIDER, true, false) as HSlider
    assert_not_null(slider, "the Workspace page has its UI scale slider")
    if slider == null:
        return
    var track := slider.get_global_rect()
    var from := track.get_center()
    # A press near the far left of the track and a drag along it, a quarter of
    # the way: the value the release writes is well under 1.
    var start := Vector2(track.position.x + track.size.x * 0.2, from.y)
    var stop := Vector2(track.position.x + track.size.x * 0.25, from.y)
    window.push_input(_mouse(MOUSE_BUTTON_LEFT, start, true))
    await _frames(1)
    var motion := InputEventMouseMotion.new()
    motion.position = stop
    motion.global_position = stop
    motion.relative = stop - start
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    window.push_input(motion)
    await _frames(1)
    window.push_input(_mouse(MOUSE_BUTTON_LEFT, stop, false))
    await _frames(3)
    assert_true(
        SaSettings.ui_scale < 0.95, "a drag on the UI scale slider applies on its release, it read %.2f" % SaSettings.ui_scale
    )
    assert_almost_eq(SaSettings.ui_scale, slider.value, 0.001, "at the value the slider shows")
