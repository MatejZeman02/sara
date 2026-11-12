## A drag of a Theme colours swatch recolours the interface at most once a
## frame and writes the palette file once, when the picker closes.
##
## The picker sends a colour per pointer motion, and writing the
## file and recolouring every window on each would hold a frame for a second in
## Preferences. A recolour leaves the shared theme's `changed`
## alone, which would have every control in every window take its theme again, and
## tells only the controls whose theme colour moved.
extends "res://tests/test_framework.gd"

const PALETTE_NAME := "Drag"
const KEY := "accent_primary"

var _saved_theme: String = "default"
var _saved_setting: String = "default"
var _saved_shared: Theme = null
## The process frame of every recolour the bus announced.
var _frames_heard: Array[int] = []
## How many times the shared theme emitted `changed`.
var _shared_heard: int = 0


func before_each() -> void:
    _saved_theme = SaTheme.palette_id
    _saved_setting = SaSettings.theme_name
    _saved_shared = SaUI.shared_theme
    _frames_heard.clear()
    _shared_heard = 0


func after_each() -> void:
    if SaTheme.is_custom(SaTheme.palette_id):
        SaTheme.delete_custom(SaTheme.palette_id)
    SaSettings.theme_name = _saved_setting
    SaTheme.use_named(_saved_theme)
    SaUI.shared_theme = _saved_shared


func _on_recoloured(_id: String) -> void:
    _frames_heard.append(Engine.get_process_frames())


func _on_shared_changed() -> void:
    _shared_heard += 1


func _colour(i: int) -> Color:
    return Color.from_hsv(float(i) / 130.0, 0.6, 0.7, 1.0)


func _file_colour(path: String) -> Variant:
    if not FileAccess.file_exists(path):
        return null
    var read := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SaPalette
    return null if read == null else read.get(KEY)


func test_a_drag_recolours_once_a_frame_and_writes_the_file_once_the_picker_closes() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This suite needs the real scene tree, for the frames a drag is folded into")
    if tree == null:
        return
    SaTheme.use_named("default")
    SaUI.init_global_theme(null)
    SaSettings.theme_name = SaTheme.fork(PALETTE_NAME)
    var path := SaTheme.custom_path(SaTheme.palette_id)
    # The fork wrote it, so it goes, and whatever writes it from here is the drag.
    DirAccess.remove_absolute(path)

    var host := Node.new()
    host.name = "U562Host"
    EventBus.add_child(host)
    var page := SaColorThemesPage.new()
    host.add_child(page)
    var picker := page._swatches[KEY] as ColorPickerButton
    var shared := SaUI.shared_theme
    shared.changed.connect(_on_shared_changed)
    EventBus.theme_changed.connect(_on_recoloured)

    for i: int in 60:
        picker.color_changed.emit(_colour(i))
    assert_eq(_frames_heard.size(), 0, "Sixty colours in one frame recolour nothing yet")
    await tree.process_frame
    await tree.process_frame
    assert_eq(_frames_heard.size(), 1, "and are applied once at the next frame")
    assert_eq(SaTheme.palette.get(KEY), _colour(59), "as the last of them")

    for i: int in range(60, 120):
        picker.color_changed.emit(_colour(i))
        await tree.process_frame
    await tree.process_frame
    var frames := {}
    for frame: int in _frames_heard:
        assert_false(frames.has(frame), "The interface was recoloured twice in frame %d" % frame)
        frames[frame] = true
    assert_true(_frames_heard.size() >= 50, "and sixty colours over sixty frames recolour about once a frame")
    assert_true(_shared_heard <= frames.size(), "The shared theme's `changed` is emitted at most once a frame")
    assert_eq(SaTheme.palette.get(KEY), _colour(119), "ending on the last colour sent")
    assert_null(_file_colour(path), "The palette file is written 0 times while the picker is open")

    picker.popup_closed.emit()
    assert_eq(_file_colour(path), _colour(119), "and once when it closes, holding the last colour sent")
    DirAccess.remove_absolute(path)
    page.save_swatches()
    host.remove_child(page)
    assert_null(_file_colour(path), "and nothing writes it again on closing the page with nothing changed")

    shared.changed.disconnect(_on_shared_changed)
    EventBus.theme_changed.disconnect(_on_recoloured)
    page.free()
    host.free()


func test_closing_the_page_mid_drag_saves_the_colour_the_painter_ended_on() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    SaTheme.use_named("default")
    var host := Node.new()
    EventBus.add_child(host)
    var page := SaColorThemesPage.new()
    host.add_child(page)
    # From a shipped palette, so the first motion forks it.
    page.drag_swatch(KEY, _colour(3))
    page.drag_swatch(KEY, _colour(7))
    var path := SaTheme.custom_path(SaTheme.palette_id)
    assert_true(SaTheme.is_custom(SaTheme.palette_id), "The first motion forks the shipped palette")
    host.remove_child(page)
    assert_eq(_file_colour(path), _colour(7), "Taking the page away before the frame applies and saves the last colour")
    assert_eq(SaTheme.palette.get(KEY), _colour(7), "and the interface wears it")
    page.free()
    host.free()


func test_an_edited_text_colour_reaches_a_label_and_a_box_its_button_without_the_theme_s_changed() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    SaTheme.use_named("default")
    SaUI.init_global_theme(null)
    SaSettings.theme_name = SaTheme.fork(PALETTE_NAME)
    var shared := SaUI.shared_theme
    var host := Control.new()
    host.theme = shared
    var label := Label.new()
    var button := Button.new()
    SaTheme.make_toggle(button)
    host.add_child(label)
    host.add_child(button)
    EventBus.add_child(host)
    shared.changed.connect(_on_shared_changed)
    var red := Color(0.8, 0.1, 0.1)
    SaTheme.set_color("text_primary", red, false)
    assert_eq(_shared_heard, 0, "One edited colour leaves the shared theme's `changed` alone")
    assert_eq(label.get_theme_color("font_color"), red, "and a label in the tree takes the edited text colour")
    var green := Color(0.1, 0.6, 0.2)
    SaTheme.set_color("accent_primary", green, false)
    var pressed := button.get_theme_stylebox("pressed") as StyleBoxFlat
    assert_eq(pressed.bg_color, SaTheme.palette.toggle_on, "and a toggle's pressed box holds the edited accent's state")
    assert_eq(_shared_heard, 0, "with the theme still quiet")
    shared.changed.disconnect(_on_shared_changed)
    host.free()
