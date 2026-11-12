## The welcome window stands above the blur while Sara boots, as the first window
## `SaBoot` puts up would otherwise be drawn below it.
##
## The boot cover is a `CanvasLayer` above layer 1024, where the engine draws
## every embedded window, so the welcome window `SaBoot` puts up first was drawn
## under the blur for the whole boot. The cover now draws the welcome window's
## own picture over itself, with the windows under it in the tree, and brings it
## in front of a docker the boot shows after it, since the engine hands a press
## to the topmost embedded window under it. Here the pieces of a boot are put up
## in the order `SaBoot` and `Main` put them up: the cover, the welcome window
## built as the boot builds it, and a docker over its corner.
##
## The windows are embedded, as the docker suites embed theirs, because a window
## that maps one of the OS's own hangs the run. With subwindows not embedded the
## welcome window is a window of its own over the main window and the cover, and
## `scenarios/the-welcome-window-stands-above-the-blur-while-sara-boots.json`
## shoots the boot held with the cover up, once embedded and once not.
extends "res://tests/test_framework.gd"

## The layer the engine draws embedded windows on, `SUBWINDOW_CANVAS_LAYER` in
## `viewport.h`, which the cover has to stand above.
const SUBWINDOW_LAYER := 1024


## A window standing for a docker the boot shows, with the presses that reach
## the panel filling it.
class Docker:
    extends Window

    var pressed: int = 0

    func _init() -> void:
        name = "LayersDocker"
        borderless = true
        size = Vector2i(300, 200)
        var panel := Control.new()
        panel.set_anchors_preset(Control.PRESET_FULL_RECT)
        panel.gui_input.connect(_count_press)
        add_child(panel)

    func _count_press(event: InputEvent) -> void:
        if SaPutAway.is_press(event):
            pressed += 1


var _host: Node = null
var _previous_embedding: bool = true
var _cover: SaBootCover = null
var _welcome: SaWelcomeWindow = null
## The presses that reached the welcome window's close button.
var _presses_on_close: int = 0


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = Node.new()
    _host.name = "D32CoverHost"
    EventBus.add_child(_host)
    var no_picture := SaDataRoot.path("test_d32_no_last_session.webp")
    _cover = SaBootCover.new(Vector2i(1280, 800), no_picture, true, SaBootCover.FADE_SEC)
    _host.add_child(_cover)
    # As `SaBoot` puts it up, built for a boot that is still going.
    _welcome = SaWelcomeWindow.new(true)
    _host.add_child(_welcome)
    _welcome.popup_centered()
    _lay_out(_welcome)
    _presses_on_close = 0
    _welcome.close_button.gui_input.connect(_count_close)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding


func test_the_cover_stands_above_the_layer_every_embedded_window_is_drawn_on() -> void:
    assert_true(_cover.layer > SUBWINDOW_LAYER, "The cover is above the embedded windows, so a docker stays hidden")
    assert_eq(_cover.get_child(-1), _cover._lifted, "and what it lifts is drawn last, over the picture and the line")


func test_a_press_on_the_welcome_window_reaches_it_once_the_cover_has_lifted_it() -> void:
    var docker := _docker_over_the_close_button()
    var at := _close_button_centre()
    _press(at)
    assert_eq(docker.pressed, 1, "Before the lift a docker the boot showed after the welcome window takes the press")
    assert_eq(_presses_on_close, 0, "and the welcome window's button under it hears nothing")

    _cover.lift()
    _press(at)
    assert_eq(_presses_on_close, 1, "After it the press on the welcome window's button reaches the button")
    assert_eq(docker.pressed, 1, "and the docker under the cover hears nothing more")
    assert_true(_welcome.has_focus(), "The welcome window holds the keyboard")
    assert_eq(_stack()[-1], _welcome, "and is the front of the embedded windows")


func test_the_welcome_window_is_drawn_over_the_cover_and_the_docker_is_not() -> void:
    var docker := _docker_over_the_close_button()
    _cover.lift()
    var above := SaBootCover.above(_stack())
    assert_eq(above, [_welcome] as Array[Window], "The cover draws the welcome window over its blur")
    assert_false(above.has(docker), "and leaves the docker under it")
    _welcome.hide()
    assert_eq(SaBootCover.above(_stack()), [] as Array[Window], "A welcome window put away is drawn no more")


func test_a_window_the_welcome_window_opened_stays_above_it_and_is_drawn_with_it() -> void:
    _docker_over_the_close_button()
    _cover.lift()
    # A list it dropped or a tip over one of its rows, a window under it in the tree.
    var list := Window.new()
    list.name = "DroppedList"
    list.borderless = true
    list.position = _welcome.position + Vector2i(40, 60)
    list.size = Vector2i(160, 120)
    _welcome.add_child(list)
    assert_eq(_stack()[-1], list, "The list opened in front of the welcome window")

    assert_false(SaBootCover.bring_forward(_stack()), "The cover leaves a window of the welcome window's own in front")
    assert_eq(_stack()[-1], list, "so the list stays where it opened")
    assert_eq(SaBootCover.above(_stack()), [_welcome, list] as Array[Window], "and both are drawn, the list over the window")


func test_a_tip_the_pointer_passes_through_does_not_stand_in_front() -> void:
    _cover.lift()
    var tip := Window.new()
    tip.name = "DockerTip"
    tip.borderless = true
    tip.unfocusable = true
    tip.mouse_passthrough = true
    tip.size = Vector2i(120, 30)
    _host.add_child(tip)
    assert_eq(_stack()[-1], tip, "A docker's tip stands at the front")
    assert_false(SaBootCover.bring_forward(_stack()), "but a press passes through it, so nothing is brought forward")
    assert_false(SaBootCover.above(_stack()).has(tip), "and it is not the welcome window's, so it stays under the cover")


func test_once_the_fade_begins_a_window_shown_after_is_left_where_it_opened() -> void:
    _cover.reach(&"boot_finished")
    var docker := _docker_over_the_close_button()
    _cover.lift()
    assert_eq(_stack()[-1], docker, "The boot is over, so the cover no longer puts the welcome window in front")
    assert_eq(SaBootCover.above(_stack()), [_welcome] as Array[Window], "while it still draws it over the fading blur")


# --- Helpers --------------------------------------------------------------------


## A docker shown after the welcome window, over its close button, which is where
## the boot's dockers come up: in front, holding the keyboard.
func _docker_over_the_close_button() -> Docker:
    var docker := Docker.new()
    docker.position = Vector2i(_close_button_centre()) - Vector2i(150, 60)
    _host.add_child(docker)
    assert_eq(_stack()[-1], docker, "The docker shown after the welcome window stands in front of it")
    return docker


func _stack() -> Array[Window]:
    var stack: Array[Window] = []
    stack.assign((Engine.get_main_loop() as SceneTree).root.get_embedded_subwindows())
    return stack


## The close button's centre in the main window's logical space, where the
## embedded windows are placed and a press is tested against them.
func _close_button_centre() -> Vector2:
    var inside := _welcome.close_button.get_global_rect().get_center()
    return Vector2(_welcome.position) + _welcome.get_final_transform() * inside


## A left press at *at*, into the main window the way the engine hands one over,
## so it goes to the topmost embedded window under it. The pointer then leaves
## for a place far from every window and is released there, so no button acts:
## a button that saw no motion takes a release anywhere as a click.
func _press(at: Vector2) -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    root.push_input(_button(at, true), true)
    var away := InputEventMouseMotion.new()
    away.position = Vector2(-50, -50)
    away.global_position = away.position
    away.button_mask = MOUSE_BUTTON_MASK_LEFT
    root.push_input(away, true)
    root.push_input(_button(away.position, false), true)


func _button(at: Vector2, pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    event.position = at
    event.global_position = at
    return event


func _count_close(event: InputEvent) -> void:
    if SaPutAway.is_press(event):
        _presses_on_close += 1


## Lays the window out now: a suite runs in one call, and a container sorts its
## children on a later frame.
func _lay_out(node: Node) -> void:
    for _pass in 2:
        _sort_under(node)


func _sort_under(node: Node) -> void:
    if node is Container:
        (node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        _sort_under(child)
