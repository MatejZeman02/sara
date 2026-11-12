## The toolbox opens tall enough for every one of its buttons.
##
## The shipped layouts give the toolbox 800, a guess made when it held fewer
## tools, and the fit used to cut a docker's content to that and never raise it,
## so a toolbox with a tool more than the guess allowed, or with larger buttons
## the painter chose, opened with its last button cut off. The docker says how
## tall its buttons are and the fit opens it at that height, at any button size
## and UI scale, and the column's floors take it back only where the host is
## too short.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")

## The first row below a one-row bar.
const TOP := 65

static var scratch_live: String = SaDataRoot.path("test_toolbox_every_button_layout.cfg")

var _root: Node = null
var _toolbox: ToolBoxDocker = null


func after_each() -> void:
    if _root != null:
        _root.free()
        _root = null
    _toolbox = null
    if FileAccess.file_exists(scratch_live):
        DirAccess.remove_absolute(scratch_live)


func _opened_at(host: Vector2i, button_size: int) -> void:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(DockerLayoutStore.SHIPPED_DEFAULTS), OK, "the shipped default reads")
    cfg.save(scratch_live)
    _root = Node.new()
    EventBus.add_child(_root)
    var viewport := SubViewport.new()
    viewport.size = host
    viewport.gui_embed_subwindows = true
    _root.add_child(viewport)
    var parent := Control.new()
    parent.set_anchors_preset(Control.PRESET_FULL_RECT)
    viewport.add_child(parent)
    _toolbox = ToolBoxDockerScript.new() as ToolBoxDocker
    _toolbox.name = "ToolBoxDocker"
    parent.add_child(_toolbox)
    _toolbox.rebuild_from_registry(Fixtures.make_tool_registry())
    _toolbox.size_controller.show_size(button_size)
    var store := DockerLayoutStore.new()
    store.name = "DockerLayoutStore"
    store.path = scratch_live
    store.dockers_provider = func() -> Array: return [{"id": "ToolBoxDocker", "name": "ToolBoxDocker", "node": _toolbox}]
    store.save_allowed = func() -> bool: return true
    store.top_inset = func() -> int: return TOP
    _root.add_child(store)
    store.restore_all()


func test_buttons_taller_than_the_shipped_800_are_not_cut_off() -> void:
    _opened_at(Vector2i(1920, 1080), 56)
    var asked := _toolbox.opening_height(Vector2i(60, 800))
    assert_true(asked > 800, "at a button size of 56 the column wants more than the file's 800, %d" % asked)
    assert_eq(_toolbox.size.y, asked, "and the toolbox opens at all of it")
    assert_true(_toolbox.size.y >= int(_toolbox.grid_container.get_combined_minimum_size().y), "holding every button")


func test_the_default_size_still_opens_at_its_buttons() -> void:
    _opened_at(Vector2i(1920, 1080), SaToolBoxSize.DEFAULT_SIZE)
    assert_eq(_toolbox.size.y, _toolbox.opening_height(Vector2i(60, 800)), "at the buttons' height")
    assert_true(_toolbox.size.y < 800, "which is under the file's 800 for the tools of the fixture")


## A module that registers a tool after the layout placed the toolbox gives it
## a button the layout's fit never counted, so the toolbox grows to hold it
## while the painter has not arranged a docker, and keeps its size after.
func test_a_tool_a_module_adds_late_is_not_cut_off() -> void:
    DockerWindow.forget_painter_sizing()
    _opened_at(Vector2i(1920, 1080), SaToolBoxSize.DEFAULT_SIZE)
    var registry := _toolbox._tool_registry
    var before := _toolbox.size.y
    for i in 3:
        var late := SaToolDescriptor.create(StringName("late_%d" % i), Fixtures.FakeTool)
        late.category = StringName("late_%d" % i)
        assert_true(registry.register(late), "a late tool registers")
    await (Engine.get_main_loop() as SceneTree).process_frame
    await (Engine.get_main_loop() as SceneTree).process_frame
    assert_true(_toolbox.size.y > before, "the toolbox grew from %d to %d" % [before, _toolbox.size.y])
    assert_true(_toolbox.size.y >= _toolbox.opening_height(_toolbox.size), "to hold every button, %d" % _toolbox.size.y)


func test_a_size_the_painter_set_by_hand_is_kept_when_a_tool_arrives() -> void:
    _opened_at(Vector2i(1920, 1080), SaToolBoxSize.DEFAULT_SIZE)
    EventBus.docker_layout_changed.emit()
    var set_by_hand := _toolbox.size.y
    var late := SaToolDescriptor.create(&"late_by_hand", Fixtures.FakeTool)
    late.category = &"late_by_hand"
    _toolbox._tool_registry.register(late)
    await (Engine.get_main_loop() as SceneTree).process_frame
    await (Engine.get_main_loop() as SceneTree).process_frame
    assert_eq(_toolbox.size.y, set_by_hand, "the painter's height stays")
    DockerWindow.forget_painter_sizing()
