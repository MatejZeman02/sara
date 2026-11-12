## Every docker takes an opacity for its background and its window's edges.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every docker has an option to choose the alpha of its background and its
## window edges. `SaDockerOpacity` fades the docker's background panel,
## whose border is the window's edge, and the drag bar's own box, through
## `self_modulate`, which leaves everything the two hold at full. This suite
## sets the value through the menu, reads the alpha of what is faded and of
## every control the docker holds, and follows the value through the layout
## file, a save of the layout and a named layout loaded over it.
## `scenarios/every-docker-takes-an-opacity-for-its-background-and-its-window-s-edges.json`
## is the same on the running app, over a painted canvas.
@tool
extends "res://tests/test_framework.gd"

const SECTION := "U779Docker"


## A docker that builds what a real one builds: its content, a drag bar with a
## title, a button and a slider below it.
class StubDocker:
    extends DockerWindow

    func _init() -> void:
        _init_docker(SECTION, "Stub", Vector2i(300, 400))
        var column := VBoxContainer.new()
        column.name = "Column"
        _control_node.add_child(column)
        drag_handle = DockerUtils.make_drag_bar("Stub")
        column.add_child(drag_handle)
        var button := Button.new()
        button.text = "Press"
        column.add_child(button)
        column.add_child(HSlider.new())

    func _ready() -> void:
        _setup_docker_ready()


var _folder: String = SaDataRoot.path("test_docker_opacity")
var _host: Node = null
var _store: DockerLayoutStore = null
var _docker: StubDocker = null
var _kept_embedding: bool = true
var _layout_changes: int = 0


func before_each() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    _kept_embedding = root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    _clear_folder()
    _host = Node.new()
    _host.name = "U779OpacityHost"
    EventBus.add_child(_host)
    _store = _new_store()
    _docker = _new_docker()
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
    store.dockers_provider = func() -> Array: return [{"id": SECTION, "name": "Stub", "node": _docker}]
    store.save_allowed = func() -> bool: return true
    _host.add_child(store)
    return store


func _new_docker() -> StubDocker:
    var docker := StubDocker.new()
    _host.add_child(docker)
    assert_true(SaDockerOpacity.attach(docker, _store), "A docker in the tree takes an opacity")
    return docker


func _opacity(docker: Window = _docker) -> SaDockerOpacity:
    return SaDockerOpacity.of(docker)


func _background(docker: Window = _docker) -> CanvasItem:
    return docker.get_node("Control/DockerBackground") as CanvasItem


func _stored() -> Variant:
    var cfg := ConfigFile.new()
    if cfg.load(_store.path) != OK or not cfg.has_section_key(SECTION, SaDockerOpacity.KEY):
        return null
    return cfg.get_value(SECTION, SaDockerOpacity.KEY)


## Every control the docker holds besides the two faded boxes, each at full.
## The menu is a window of its own that hangs under the opacity, and is passed
## over.
func _assert_controls_at_full(docker: StubDocker, what: String) -> void:
    var checked := 0
    for node: Node in docker.get_node("Control").find_children("*", "CanvasItem", true, false):
        var item := node as CanvasItem
        if item == _background(docker) or item == docker.drag_handle or _opacity(docker).is_ancestor_of(item):
            continue
        assert_eq(item.modulate.a, 1.0, "%s: %s is drawn at full" % [what, item.name])
        assert_eq(item.self_modulate.a, 1.0, "%s: %s draws itself at full" % [what, item.name])
        checked += 1
    var title := docker.drag_handle.find_child("TitleLabel", true, false)
    assert_not_null(title, "%s: the drag bar's title is there to read" % what)
    assert_true(checked >= 4, "%s: the title, the button, the slider and the column were checked, %d were" % [what, checked])


func test_a_fresh_docker_is_plain_and_its_menu_offers_the_steps() -> void:
    var opacity := _opacity()
    assert_not_null(opacity, "The opacity hangs under the docker")
    assert_eq(opacity.alpha, 1.0, "A docker the layout says nothing of is plain")
    assert_eq(_background().self_modulate.a, 1.0, "and its background is drawn whole")
    assert_true(SaDockerOpacity.attach(_docker, _store), "A second attach answers that it is there")
    var found := _docker.get_node("Control").find_children(String(SaDockerOpacity.NODE_NAME), "", false, false)
    assert_eq(found.size(), 1, "and adds no second one")
    var menu := opacity.fill_menu()
    var ids: Array[StringName] = []
    for step: int in SaDockerOpacity.STEPS:
        ids.append(StringName(str(step)))
    assert_eq(menu.row_ids(), ids, "The menu offers every step")
    assert_eq(menu.row_labels()[0], "100%", "and reads in percent")


func test_a_step_chosen_fades_the_background_and_the_frame_and_nothing_else() -> void:
    var opacity := _opacity()
    assert_true(opacity.fill_menu().press_row(&"50"), "The 50% row is pressed")
    assert_almost_eq(opacity.alpha, 0.5, 0.0001, "The docker is at 50%")
    assert_almost_eq(_background().self_modulate.a, 0.5, 0.0001, "Its background and its edge are at 50%")
    assert_almost_eq(_docker.drag_handle.self_modulate.a, 0.5, 0.0001, "and so is the drag bar's box")
    var style := (_background() as Control).get_theme_stylebox("panel") as StyleBoxFlat
    assert_eq(style.bg_color.a, SaTheme.palette.bg_primary.a, "The style keeps the palette's colour, which a theme switch writes")
    _assert_controls_at_full(_docker, "At 50%")
    assert_eq(_layout_changes, 1, "The choice is a change of the layout the painter made")
    assert_almost_eq(float(_stored()), 0.5, 0.0001, "and the layout file holds it under the docker's section")
    opacity.choose(1.0)
    assert_null(_stored(), "A plain docker leaves no key behind")


func test_a_right_press_on_the_bar_opens_the_menu_and_moves_nothing() -> void:
    var at := _docker.position
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_RIGHT
    press.pressed = true
    press.position = Vector2(20, 5)
    _docker.drag_handle.gui_input.emit(press)
    var release := press.duplicate() as InputEventMouseButton
    release.pressed = false
    _docker.drag_handle.gui_input.emit(release)
    var motion := InputEventMouseMotion.new()
    motion.position = Vector2(220, 205)
    motion.relative = Vector2(200, 200)
    _docker.drag_handle.gui_input.emit(motion)
    assert_not_null(_opacity().menu, "A right press on the drag bar builds the menu")
    assert_eq(_docker.position, at, "and starts no drag of the docker")


func test_the_value_is_kept_across_a_layout_saved_and_loaded() -> void:
    _opacity().choose(0.7)
    _store.save(true)
    assert_almost_eq(float(_stored()), 0.7, 0.0001, "A save of the layout keeps the docker's opacity")
    assert_true(_store.save_preset("see through"), "The layout is saved under a name")
    _opacity().choose(1.0)
    assert_eq(_background().self_modulate.a, 1.0, "Back to plain")
    assert_true(_store.load_preset("see through"), "The named layout loads")
    assert_almost_eq(_opacity().alpha, 0.7, 0.0001, "and puts the docker back at 70%")
    assert_almost_eq(_background().self_modulate.a, 0.7, 0.0001, "background and edge with it")
    _assert_controls_at_full(_docker, "After the load")
    # A run started over the same file reads the value as the docker is built.
    _docker.free()
    _docker = _new_docker()
    assert_almost_eq(_opacity().alpha, 0.7, 0.0001, "A docker built over the layout file opens at 70%")


func test_a_hand_edited_value_is_read_within_reach() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value(SECTION, SaDockerOpacity.KEY, 0.0)
    DirAccess.make_dir_recursive_absolute(_folder)
    cfg.save(_store.path)
    _opacity().read_back()
    assert_eq(_opacity().alpha, SaDockerOpacity.LOWEST, "A zero in the file reads as the least the menu offers")
    cfg.set_value(SECTION, SaDockerOpacity.KEY, "half")
    cfg.save(_store.path)
    _opacity().read_back()
    assert_eq(_opacity().alpha, 1.0, "A value that is no number reads as plain")
