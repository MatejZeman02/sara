## Colour Picker, dragged by its title
## and summoned with the pointer still on that title, jumped under the pointer
## and from then on Windows listed its window as not visible, while its picture
## stayed on screen and took no input.
##
## The docker was in front and held the keyboard, because the painter had just
## dragged it. The summon hands the keyboard back to whatever held it before,
## and with the subwindows off it had no embedded window to ask, so it took the
## docker for one the summon had focused and released it. The release makes the
## docker unfocusable for one `grab_focus`, and Godot 4.7 on Windows writes that
## flag to a window of its own by rebuilding its style, which for a borderless
## window leaves `WS_VISIBLE` out: the OS hides the window and the compositor
## keeps its last picture.
##
## Linux keeps a window visible through the same writes, so what this suite
## holds is Sara's half: the summon writes no flag to a docker that held the
## keyboard before its chord, and the docker is shown, where the summon put it,
## still has the keyboard and takes a click. The docker is embedded, because a
## docker that maps an OS window hangs a headless run, and `MainDockers` stays
## out of the tree, which is what the summon sees with the subwindows off: no
## embedded window to say who held the keyboard before.
extends "res://tests/test_framework.gd"

## Where the docker was left by the drag, and the pointer on its own title.
const DRAGGED := Vector2i(600, 300)
const SIZE := Vector2i(280, 480)
const TITLE := Vector2(630, 315)

## Every property of a `Window` whose setter is `set_flag` in Godot 4.7, read
## off `ClassDB`. Windows writes most of them by rebuilding the window's style.
const FLAGS: Array[StringName] = [
    &"unresizable",
    &"borderless",
    &"always_on_top",
    &"transparent",
    &"unfocusable",
    &"popup_window",
    &"extend_to_title",
    &"mouse_passthrough",
    &"sharp_corners",
    &"exclude_from_capture",
    &"popup_wm_hint",
    &"minimize_disabled",
    &"maximize_disabled",
]


## A docker that notes every flag written to it once it is up, and the
## presses that reach the panel filling it.
##
## The panel counts what its `gui_input` is handed rather than a button's
## `button_down`, because a button presses only once a motion has put the
## pointer over it, and the question here is where the press goes.
class FlagWatch:
    extends Window

    var written: Array[StringName] = []
    var pressed: int = 0

    func _init() -> void:
        name = "ColorDocker"
        position = DRAGGED
        size = SIZE
        var panel := Control.new()
        panel.set_anchors_preset(Control.PRESET_FULL_RECT)
        panel.gui_input.connect(_count_press)
        add_child(panel)

    func _count_press(event: InputEvent) -> void:
        var press := event as InputEventMouseButton
        if press != null and press.pressed and press.button_index == MOUSE_BUTTON_LEFT:
            pressed += 1

    func _set(property: StringName, _value: Variant) -> bool:
        if property in FLAGS:
            written.append(property)
        # Unhandled, so the engine's own setter still writes the flag.
        return false


## The layout store `MainDockers` is built with, with the answers that write a
## file or wait on a compositor stubbed, as the other summon suites stub them.
class StubStore:
    extends DockerLayoutStore

    func save(_by_painter: bool = false) -> void:
        pass

    func fork_for_painter_edit() -> String:
        return ""

    func reapply_deferred(_win: Window, _section: String) -> void:
        pass

    func list_presets() -> Array[String]:
        return []

    func current_preset() -> String:
        return ""


var _host: Node = null
var _previous_embedding: bool = true
var _dwell_before: Variant = null


func before_each() -> void:
    _dwell_before = SaSettings.module_preference(
        SaDockerBorrow.MODULE_ID, SaDockerBorrow.DWELL_KEY, SaDockerBorrow.DEFAULT_DWELL_MS
    )
    SaDockerBorrow.new().dwell_ms = 1000
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = Node.new()
    _host.name = "D9SummonHost"
    EventBus.add_child(_host)


func after_each() -> void:
    DockerDragHandle.capture_pointer = null
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding
    SaSettings.set_module_preference(SaDockerBorrow.MODULE_ID, SaDockerBorrow.DWELL_KEY, _dwell_before)


## The docker up and holding the keyboard, as the drag by its title left it, and
## the dockers node over it. The node is a child of a plain node outside the tree,
## which the test frees at its end, and the docker goes with the host.
func _dockers(docker: FlagWatch) -> MainDockers:
    _host.add_child(docker)
    docker.show()
    docker.grab_focus()
    var registries := SaRegistries.new()
    registries.ui.register_docker(&"ColorDocker", "Colour Picker", func() -> Window: return Window.new(), &"docker_stub")
    registries.ui.set_docker_node(&"ColorDocker", docker)
    var outside := Node.new()
    outside.add_child(MainDockers.new(registries.ui, StubStore.new()))
    return outside.get_child(0) as MainDockers


func test_a_docker_holding_the_keyboard_is_summoned_under_its_own_title_and_stays_a_window() -> void:
    var docker := FlagWatch.new()
    var dockers := _dockers(docker)
    assert_true(docker.has_focus(), "the docker holds the keyboard, as a drag by its title leaves it")
    assert_false(dockers.is_inside_tree(), "and the summon has no embedded window to ask, as with the subwindows off")
    docker.written.clear()

    DockerDragHandle.capture_pointer = TITLE
    dockers.summon_docker_by_id(&"ColorDocker")

    var section := DockerLayoutStore.section_for(dockers.get_docker_config()[0])
    assert_true(dockers.layout_store.is_borrowed(section), "the chord summoned it")
    assert_eq(docker.written, [] as Array[StringName], "and wrote no window flag to it, which on Windows hid it")
    assert_true(docker.visible, "the docker is shown")
    assert_false(docker.unfocusable, "and can be focused")
    assert_eq(docker.position, Vector2i(TITLE - Vector2(SIZE) * 0.5), "centred on the pointer, where the summon put it")
    assert_eq(docker.position, dockers.layout_store.borrowed.held(section, "position"), "which is where the borrow holds it")
    assert_true(docker.has_focus(), "and the keyboard stays where it was, on the docker")

    var tree := Engine.get_main_loop() as SceneTree
    var stack: Array[Window] = []
    stack.assign(tree.root.get_embedded_subwindows())
    var centre := Vector2(docker.position) + Vector2(SIZE) * 0.5
    assert_eq(DockerFocus.window_under(stack, centre), docker, "the docker is the window under a click on it")
    # Unlike the dialog of the running app that `windows.md` measured, an
    # embedded window in a suite hands a pushed press to the control under it,
    # and the count is asserted rather than assumed.
    docker.push_input(_press(Vector2(SIZE) * 0.5), true)
    assert_eq(docker.pressed, 1, "and the click reaches the docker rather than the window under it")

    dockers.get_parent().free()


## A left press at *at* in the window's own coordinates.
func _press(at: Vector2) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.position = at
    event.global_position = at
    return event
