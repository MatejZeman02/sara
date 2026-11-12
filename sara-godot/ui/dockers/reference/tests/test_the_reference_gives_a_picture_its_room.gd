## The Reference docker gives a picture its room.
##
## Three sweeps read the board under its chrome: 41 of 223 pixels in one, 30 of
## 255 measured here before the change, under a drag bar, a row of tabs, five
## buttons that wrapped to two rows at the column's 310 and a label for the
## path. The buttons now stand as icons on the tabs' row, the label is the
## showing tab's hover, and the board stands straight under the row, so the
## docker's content below its drag bar is the row and the board and nothing
## else. Fit, Normalize and Solo are dimmed until the board holds a picture.
##
## Built in a tree, embedded and shown, at the size both shipped defaults give
## the Reference, because a container outside a tree sorts nothing. The suite
## has no frames to wait, since an `await` drops every assertion after it, so
## the containers are sorted by hand from the top down, as
## `test_the_presets_docker_reads_at_factory_settings.gd` sorts its own.
##
## The shots are
## `scenarios/the-reference-docker-opens-closed-and-gives-a-picture-its-room.json`.
extends "res://tests/test_framework.gd"

const REFERENCE_IMAGE := "res://ui/icon.png"

## The five buttons on the tabs' row, in the order they stand, with the icon
## each carries.
const BUTTONS := {
    "OpenButton": "folder_open",
    "FitButton": "fit_view",
    "NormaliseButton": "normalize",
    "SoloButton": "solo",
    "CanvasButton": "easel",
}

## The three that have nothing to act on until the board holds a picture.
const NEEDS_PICTURE: Array[String] = ["FitButton", "NormaliseButton", "SoloButton"]

## The width every docker of the default's columns has.
const COLUMN_WIDTH := 310

var _host: Node = null
var _embedded: bool = false


func after_each() -> void:
    if _host != null and is_instance_valid(_host):
        _host.free()
        (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _embedded
    _host = null


## The size both shipped defaults give the Reference.
func _shipped_size() -> Vector2i:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(DockerLayoutStore.SHIPPED_DEFAULTS), OK, "the shipped layout reads")
    return cfg.get_value("ReferenceDocker", "size", Vector2i())


## The docker in a tree at *at*, shown and laid out.
func _docker(at: Vector2i) -> ReferenceDocker:
    var tree := Engine.get_main_loop() as SceneTree
    _embedded = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "N90ReferenceHost"
    EventBus.add_child(_host)
    var docker := ReferenceDocker.new()
    _host.add_child(docker)
    # Shown, because a container in a hidden window sorts nothing.
    docker.show()
    docker.size = at
    var top := docker._control_node
    if SaUI.shared_theme != null:
        top.theme = SaUI.shared_theme
    top.size = Vector2(at)
    _sort(top)
    return docker


## One layout pass from *node* down, the one the engine would run next frame.
func _sort(node: Node) -> void:
    if node is Container:
        (node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child: Node in node.get_children():
        _sort(child)


## Where *control*'s rectangle sits inside the docker's own content.
func _in_docker(control: Control, docker: ReferenceDocker) -> Rect2:
    return Rect2(control.global_position - docker._control_node.global_position, control.size)


func _button(docker: ReferenceDocker, node_name: String) -> Button:
    return docker.find_child(node_name, true, false) as Button


func test_the_buttons_stand_on_the_tabs_row_as_icons() -> void:
    var docker := _docker(_shipped_size())
    var tabs := docker.find_child("TabRow", true, false) as Control
    var bar := docker.find_child("Tabs", true, false) as Control
    assert_not_null(tabs, "the tabs' row is there")
    for node_name: String in BUTTONS:
        var button := _button(docker, node_name)
        assert_not_null(button, "%s is on the docker" % node_name)
        if button == null:
            continue
        assert_true(tabs.is_ancestor_of(button), "%s stands on the tabs' row" % node_name)
        assert_eq(_in_docker(button, docker).position.y, _in_docker(bar, docker).position.y, "%s at the tabs' top" % node_name)
        assert_eq(button.icon, SaUI.get_icon(BUTTONS[node_name]), "%s carries its icon" % node_name)
        assert_not_null(button.icon, "which ships in assets/icons")
        assert_eq(button.text, "", "and says nothing beside it")
        assert_false(button.tooltip_text.is_empty(), "%s says on hover what it does" % node_name)
    var normalize := _button(docker, "NormaliseButton")
    assert_true(normalize.tooltip_text.begins_with("Normalize"), "the word a button said leads its hover")
    assert_null(docker.find_child("PathLabel", true, false), "and no label for the path under the row")
    var button_row := docker.find_child("ButtonRow", true, false) as Control
    assert_true(_in_docker(button_row, docker).end.x <= COLUMN_WIDTH, "the row ends inside the column's 310")


## The board starts where the row ends and runs to the column's foot, so the
## docker's content below its drag bar is the row and the board.
##
## **Three quarters of the content, not of the window.** The note's measure of
## the docker's whole height is out of reach at the 223 both defaults give it:
## the drag bar every docker carries is 31 and one row of tabs 33, so the two
## alone are 64 and a quarter of 223 is 56. What the board is given is
## everything the Reference itself shows, the row aside, which is 137 of the
## 180 under the drag bar and over the grip. At the 255 it had before it was
## shipped closed, the old rows left the board 30 and these leave it 169.
func test_the_board_takes_the_docker_but_for_its_bar_and_one_row() -> void:
    var at := _shipped_size()
    var docker := _docker(at)
    var column := docker.content_column()
    var tabs := docker.find_child("TabRow", true, false) as Control
    var board := _in_docker(docker.board_view, docker)
    var row := _in_docker(tabs, docker)
    var content := _in_docker(column, docker)
    assert_eq(board.position.y, row.end.y, "the board starts where the tabs' row ends")
    assert_eq(board.end.y, content.end.y, "and runs to the column's foot")
    assert_eq(board.size.x, content.size.x, "across the column's whole width")
    var bar_end := _in_docker(docker.drag_handle, docker).end.y
    var below_bar := content.end.y - bar_end
    var share := board.size.y / below_bar
    var said := "%d of the %d below the drag bar" % [board.size.y, below_bar]
    assert_true(share >= 0.75, "the board takes three quarters of the docker's content, %s" % said)
    var whole := board.size.y / float(at.y)
    assert_true(whole >= 0.6, "and %d of the docker's %d" % [board.size.y, at.y])


func test_an_empty_board_dims_what_needs_a_picture() -> void:
    var docker := ReferenceDocker.new()
    docker.board_view.size = Vector2(300, 170)
    for node_name: String in BUTTONS:
        var dimmed := NEEDS_PICTURE.has(node_name)
        var button := _button(docker, node_name)
        assert_eq(button.disabled, dimmed, "%s is %s on an empty board" % [node_name, "dimmed" if dimmed else "live"])
        if dimmed:
            assert_true(button.tooltip_text.ends_with("first."), "and %s says why: %s" % [node_name, button.tooltip_text])
    assert_true(docker.load_image(REFERENCE_IMAGE), "a picture opens on the board")
    for node_name: String in NEEDS_PICTURE:
        var button := _button(docker, node_name)
        assert_false(button.disabled, "%s is live once the board holds a picture" % node_name)
        assert_false(button.tooltip_text.ends_with("first."), "and says only what it does")
    docker.clear()
    for node_name: String in NEEDS_PICTURE:
        assert_true(_button(docker, node_name).disabled, "%s is dimmed again once the board is cleared" % node_name)
    docker.free()


## What the path label said is each tab's hover: the chosen picture's path on
## the showing tab, and how many pictures a board holds on every tab.
func test_each_tab_says_on_hover_what_the_label_said() -> void:
    var docker := ReferenceDocker.new()
    docker.board_view.size = Vector2(300, 170)
    var bar := (docker.find_child("TabRow", true, false) as ReferenceTabs).bar
    # The board the view's first draw asks for.
    docker.board()
    assert_eq(bar.get_tab_tooltip(0), "No reference", "an empty board says so")
    docker.load_image(REFERENCE_IMAGE)
    assert_eq(bar.get_tab_tooltip(0), REFERENCE_IMAGE, "the picture just opened is chosen, and its path is the hover")
    docker.board_view.deselect()
    docker.add_board("Second")
    assert_eq(bar.get_tab_tooltip(0), "1 picture", "a tab not showing says how many it holds")
    assert_eq(bar.get_tab_tooltip(1), "No reference", "and the new one that it holds none")
    docker.free()


## The tabs' row is the column's widest, and it fits the default's 310 with
## room for one tab's title.
func test_the_row_fits_the_column_and_keeps_a_tab_readable() -> void:
    var docker := _docker(_shipped_size())
    var wanted := DockerWindow.column_min_width(docker)
    assert_true(wanted <= COLUMN_WIDTH, "the column wants %d, inside the %d of the column" % [wanted, COLUMN_WIDTH])
    var bar := docker.find_child("Tabs", true, false) as Control
    assert_true(bar.size.x >= ReferenceTabs.BAR_MIN_W, "the tabs are given %d at 310" % bar.size.x)
