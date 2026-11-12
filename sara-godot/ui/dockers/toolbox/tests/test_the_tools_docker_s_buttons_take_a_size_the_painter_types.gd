## The Tools docker's buttons take a size the painter types or chooses.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Tools docker has an option for a custom size. The toolbox's buttons are sized in logical pixels, 40 by default, and
## scaled by the UI scale. This suite sets the toolbox's size to custom values
## through the menu and controller, checks that every button and flyout row is
## sized to that value times the UI scale, and follows the value across a save, a
## layout preset, and a reload.
@tool
extends "res://tests/test_framework.gd"

const SECTION := "ToolBoxDocker"
const Fixtures = preload("res://tests/fixtures.gd")
const ToolBoxDockerScript := preload("res://ui/dockers/toolbox/toolbox_docker.gd")

var _folder: String = SaDataRoot.path("test_u778_toolbox_size")
var _host: Node = null
var _store: DockerLayoutStore = null
var _docker: ToolBoxDocker = null
var _kept_embedding: bool = true
var _layout_changes: int = 0


func before_each() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    _kept_embedding = root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    _clear_folder()
    _host = Node.new()
    _host.name = "U778ToolBoxSizeHost"
    EventBus.add_child(_host)
    _store = _new_store()
    _docker = await _new_toolbox()
    _layout_changes = 0
    EventBus.docker_layout_changed.connect(_count_layout_change)


func after_each() -> void:
    EventBus.docker_layout_changed.disconnect(_count_layout_change)
    if _host != null:
        _host.free()
        _host = null
    _store = null
    _docker = null
    _clear_folder()
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding
    SaUI.user_scale = 1.0
    SaToolBoxSize.shown_size = SaToolBoxSize.DEFAULT_SIZE


func _count_layout_change() -> void:
    _layout_changes += 1


func _clear_folder() -> void:
    for sub: String in ["layouts", ""]:
        var path := _folder.path_join(sub)
        var dir := DirAccess.open(path)
        if dir == null:
            continue
        for file_name in dir.get_files():
            DirAccess.remove_absolute(path.path_join(file_name))
        DirAccess.remove_absolute(path)


func _new_store() -> DockerLayoutStore:
    var store := DockerLayoutStore.new()
    store.path = _folder.path_join("docker_layout.cfg")
    store.dockers_provider = func() -> Array: return [{"id": SECTION, "name": "Toolbox", "node": _docker}]
    store.save_allowed = func() -> bool: return true
    _host.add_child(store)
    return store


func _new_toolbox() -> ToolBoxDocker:
    var docker := ToolBoxDockerScript.new() as ToolBoxDocker
    docker.name = SECTION
    _host.add_child(docker)
    # The store reaches the size the way it does in the app, through the
    # opacity `MainDockers` attaches to every docker.
    assert_true(SaDockerOpacity.attach(docker, _store), "The opacity attaches to the toolbox")
    docker.rebuild_from_registry(Fixtures.make_tool_registry())
    await (Engine.get_main_loop() as SceneTree).process_frame
    return docker


func _stored() -> Variant:
    var cfg := ConfigFile.new()
    if cfg.load(_store.path) != OK or not cfg.has_section_key(SECTION, SaToolBoxSize.KEY):
        return null
    return cfg.get_value(SECTION, SaToolBoxSize.KEY)


func _assert_buttons_at_size(docker: ToolBoxDocker, size_px: int, context: String) -> void:
    var expected := Vector2(float(SaUI.px(size_px)), float(SaUI.px(size_px)))
    for category: Variant in docker._buttons:
        var btn: Button = docker._buttons[category]
        assert_eq(
            btn.custom_minimum_size, expected, "%s: button for '%s' is at %d logical px" % [context, String(category), size_px]
        )


func _open_flyout(docker: ToolBoxDocker, category: StringName) -> SaToolFlyout:
    assert_true(docker.open_flyout(category), "Category '%s' opened its flyout" % String(category))
    var flyout: SaToolFlyout = docker._flyouts.get(category)
    assert_not_null(flyout, "Flyout built for '%s'" % String(category))
    return flyout


func test_a_fresh_toolbox_is_at_default_size_and_menu_offers_steps() -> void:
    assert_eq(_docker.size_controller.current_size, SaToolBoxSize.DEFAULT_SIZE, "Fresh toolbox is at 40 px")
    _assert_buttons_at_size(_docker, 40, "Default toolbox")

    var menu: SaChoicePopup = _docker.size_controller.fill_menu()
    assert_not_null(menu, "fill_menu returns menu")
    var ids: Array[StringName] = menu.row_ids()
    for step: int in SaToolBoxSize.STEPS:
        assert_true(ids.has(StringName(str(step))), "Menu offers step %d" % step)

    var slider := menu.find_child(String(SaToolBoxSize.SLIDER_NAME), true, false) as FactorSlider
    assert_not_null(slider, "The menu carries the custom size's slider")
    assert_eq(slider.min_value, float(SaToolBoxSize.MIN_SIZE), "The slider starts at the smallest size")
    assert_eq(slider.max_value, float(SaToolBoxSize.MAX_SIZE), "The slider ends at the largest size")
    assert_eq(slider.value, 40.0, "The slider shows the size in hand")


func test_menu_step_chosen_resizes_buttons_and_flyout_rows() -> void:
    var menu: SaChoicePopup = _docker.size_controller.fill_menu()
    assert_true(menu.press_row(&"56"), "The 56 px row is pressed")
    assert_eq(_docker.size_controller.current_size, 56, "Toolbox is at 56 px")
    _assert_buttons_at_size(_docker, 56, "At 56 px")

    var flyout := _open_flyout(_docker, &"fill")
    for id_str: String in flyout.ids:
        var row := flyout.label_button(StringName(id_str))
        assert_not_null(row, "Flyout row '%s' exists" % id_str)
        assert_almost_eq(row.custom_minimum_size.y, float(SaUI.px(56)), 0.001, "Flyout row is 56 px tall")

    assert_eq(_layout_changes, 1, "Changing size announces docker layout change")
    assert_eq(int(_stored()), 56, "Layout file holds button_size 56")


func test_a_custom_size_typed_or_dragged_sizes_every_button_and_row() -> void:
    var slider := _docker.size_controller.fill_menu().find_child(String(SaToolBoxSize.SLIDER_NAME), true, false) as FactorSlider
    slider._line_edit.visible = true
    slider._line_edit.text = "27"
    slider._stop_editing()
    assert_eq(_docker.size_controller.current_size, 27, "A typed 27 is the size")
    assert_eq(int(_stored()), 27, "and what the layout file keeps")
    _assert_buttons_at_size(_docker, 27, "Typed 27")

    var flyout := _open_flyout(_docker, &"fill")
    for id_str: String in flyout.ids:
        var row := flyout.label_button(StringName(id_str))
        assert_almost_eq(row.custom_minimum_size.y, float(SaUI.px(27)), 0.001, "Flyout row at 27 px")

    slider._set_from_drag(1.0)
    assert_eq(_docker.size_controller.current_size, 72, "A drag to the slider's end is the largest size")
    _assert_buttons_at_size(_docker, 72, "Dragged to 72")
    for id_str: String in flyout.ids:
        var row := flyout.label_button(StringName(id_str))
        assert_almost_eq(row.custom_minimum_size.y, float(SaUI.px(72)), 0.001, "An open flyout's row follows to 72 px")

    slider._line_edit.visible = true
    slider._line_edit.text = "500"
    slider._stop_editing()
    assert_eq(_docker.size_controller.current_size, SaToolBoxSize.MAX_SIZE, "A typed 500 stops at the largest size")


func test_size_is_kept_across_layout_saved_and_loaded() -> void:
    _docker.size_controller.choose(56)
    _store.save(true)
    assert_eq(int(_stored()), 56, "Save preserves button_size")
    assert_true(_store.save_preset("Custom Layout"), "Preset saved")

    _docker.size_controller.choose(40)
    assert_eq(_docker.size_controller.current_size, 40, "Reset to default")
    _assert_buttons_at_size(_docker, 40, "Reset")

    assert_true(_store.load_preset("Custom Layout"), "Preset loads")
    assert_eq(_docker.size_controller.stored(), 56, "Stored value reads 56 after preset load")
    assert_eq(_docker.size_controller.current_size, 56, "Docker button size restored to 56")
    _assert_buttons_at_size(_docker, 56, "Restored layout")


## Built outside the tree, as `test_flyout_scale.gd` does: an embedded docker
## and its popup both answer 1.0 whatever the scale, and a detached one takes
## the OS window's branch of `SaUI.window_scale`, the factor a painter's screen
## gives a floating toolbox.
func test_the_size_is_on_top_of_the_ui_scale() -> void:
    var saved_override := SaUI.os_scale_override
    SaUI.os_scale_override = 1.5
    var docker := ToolBoxDockerScript.new() as ToolBoxDocker
    docker.name = SECTION
    docker.rebuild_from_registry(Fixtures.make_tool_registry())
    docker.apply_window_scale()
    docker.size_controller.choose(56)
    assert_true(docker.open_flyout(&"fill"), "The fills' flyout opens")
    var flyout: SaToolFlyout = docker._flyouts[&"fill"]
    var factor := flyout.content_scale_factor
    assert_almost_eq(factor, 1.5, 0.0001, "The flyout renders at the scale of one and a half")
    var row := flyout.label_button(StringName(flyout.ids[0]))
    assert_almost_eq(row.custom_minimum_size.y, 56.0, 0.001, "A row is 56 logical pixels tall")
    assert_almost_eq(row.custom_minimum_size.y * factor, 84.0, 0.001, "and drawn at 56 times the scale, 84")
    _assert_buttons_at_size(docker, 56, "At the scale of 1.5")
    assert_almost_eq(docker.content_scale_factor, 1.5, 0.0001, "The buttons are drawn at the same factor")
    docker.free()
    SaUI.os_scale_override = saved_override


func test_a_toolbox_built_on_a_layout_file_opens_at_its_size() -> void:
    _docker.size_controller.choose(32)
    _host.remove_child(_docker)
    _docker.free()
    _docker = await _new_toolbox()
    assert_eq(_docker.size_controller.current_size, 32, "A new toolbox reads 32 from the layout file")
    _assert_buttons_at_size(_docker, 32, "Built on the file")


func test_the_menu_keeps_the_opacity_and_the_bar_opens_only_it() -> void:
    var opacity := SaDockerOpacity.of(_docker)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_RIGHT
    press.pressed = true
    _docker.drag_handle.gui_input.emit(press)
    assert_null(opacity.menu, "The opacity's own menu is never built on the toolbox's bar")
    var menu := _docker.size_controller.menu
    assert_not_null(menu, "The bar's right press builds the size's menu")
    assert_true(menu.press_row(&"opacity_50"), "The menu carries the opacity's 50 per cent")
    assert_almost_eq(opacity.alpha, 0.5, 0.001, "and the row sets the docker's opacity")
    assert_eq(_docker.size_controller.current_size, 40, "and leaves the size as it was")
    menu.hide()
