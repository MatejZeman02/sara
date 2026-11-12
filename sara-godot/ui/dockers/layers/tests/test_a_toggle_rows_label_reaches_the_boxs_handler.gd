## A toggle row's label reaches the handler its box reaches, and only that.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A press on the label of a row with a box presses the box, so the
## caller hears `marked` and never `chosen`. Three handlers kept a branch for a
## toggle row's `chosen` that nothing emits, under comments saying the label
## closed the menu: `SaLayerActions._on_menu_choice`,
## `MainDockers._on_docker_row_chosen` and `SaMenu._on_row_chosen`. The branches
## went, and these tests hold what a press still does without them: one press
## of a label is one write, through the box's handler, with the list left open,
## and a plain row's label still acts once and closes.
##
## The Dockers menu is built by Sara's own main scene, which no suite has, so its
## half is `scenarios/four-places-still-answer-a-toggle-rows-label-on-chosen.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")


## A top bar menu on a bare popup that records every id it is handed, with a
## tick row whose handler reads the tick, flips it and writes it, the way the
## View menu's rows do.
class RecordingMenu:
    extends SaMenu

    const ID_COMMAND := 1
    const ID_TICK := 2

    var pressed: Array[int] = []
    var ticked := false

    func _init(menu_popup: SaChoicePopup) -> void:
        super(menu_popup)

    func _add_items() -> void:
        add_item("Command", ID_COMMAND)
        add_check_item("Tick", ID_TICK, ticked)

    func on_id_pressed(id: int) -> void:
        pressed.append(id)
        if id == ID_TICK:
            ticked = not is_item_checked(id)
            set_item_checked(id, ticked)


var _host: Node = null
var _anchor: Control = null
var _was_embedding := false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "D89ToggleHost"
    EventBus.add_child(_host)
    _anchor = Control.new()
    _anchor.size = Vector2(120.0, 24.0)
    _host.add_child(_anchor)


func after_each() -> void:
    _host.free()
    _host = null
    _anchor = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding


## The recording menu, filled and open embedded under the host, so `visible` is
## the list a painter sees rather than a detached window's flag.
func _open_menu() -> RecordingMenu:
    var popup := SaChoicePopup.new()
    _host.add_child(popup)
    var menu := RecordingMenu.new(popup)
    menu.populate()
    popup.open_under(_anchor)
    return menu


func _docker_on_a_document() -> LayersDocker:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    var docker: LayersDocker = LayersDockerScript.new()
    docker.name = "LayersDocker"
    canvas.add_child(docker)
    docker.target_canvas = canvas
    docker._ready()
    return docker


func test_a_tick_rows_label_is_one_write_and_the_menu_stays_open() -> void:
    var menu := _open_menu()
    var tick := SaMenu.key(RecordingMenu.ID_TICK)

    assert_true(menu.popup.press_row(tick), "The tick row's label takes a press")
    assert_eq(menu.pressed, [RecordingMenu.ID_TICK] as Array[int], "which reaches the handler once")
    assert_true(menu.ticked, "and writes the flip")
    assert_true(menu.is_item_checked(RecordingMenu.ID_TICK), "which the box shows")
    assert_true(menu.popup.visible, "with the menu still open")

    menu.popup.press_row(tick)
    assert_eq(menu.pressed.size(), 2, "A second press in the same visit is a second write")
    assert_false(menu.ticked, "which flips it back")
    assert_false(menu.is_item_checked(RecordingMenu.ID_TICK), "and the box follows")
    assert_true(menu.popup.visible, "and the menu is open still")


func test_a_tick_rows_box_and_its_label_write_alike() -> void:
    var menu := _open_menu()
    var tick := SaMenu.key(RecordingMenu.ID_TICK)

    menu.popup.press_check(tick)
    assert_true(menu.ticked, "The box ticks")
    menu.popup.press_row(tick)
    assert_false(menu.ticked, "and the label unticks what the box ticked")
    assert_eq(menu.pressed.size(), 2, "one write each")
    assert_true(menu.popup.visible, "in one visit")


func test_a_command_rows_label_acts_once_and_closes_the_menu() -> void:
    var menu := _open_menu()

    assert_true(menu.popup.press_row(SaMenu.key(RecordingMenu.ID_COMMAND)), "The command row takes a press")
    assert_eq(menu.pressed, [RecordingMenu.ID_COMMAND] as Array[int], "which reaches the handler once")
    assert_false(menu.popup.visible, "and closes the menu behind it")


## The Layers docker's More menu: its three check rows are written from `marked`
## alone, and `chosen` carries only the plain rows.
func test_the_layer_menus_check_rows_never_emit_chosen() -> void:
    var docker := _docker_on_a_document()
    var actions := docker.actions
    var layer := docker.active_layer()
    var chosen: Array[StringName] = []
    actions.menu.chosen.connect(func(id: StringName) -> void: chosen.append(id))

    actions.press_item(SaLayerActions.Item.LOCK_PAINT)
    assert_true(layer.is_locked, "Lock Layer's label locks the layer")
    actions.press_item(SaLayerActions.Item.LOCK_ALPHA)
    assert_true(layer.alpha_locked, "Lock Alpha's label locks its alpha")
    actions.press_item(SaLayerActions.Item.LOCK_PAINT)
    assert_false(layer.is_locked, "and a second press on a label unlocks, one flip a press")

    actions.toggle_group()
    actions.sync_from_active_layer()
    var group := docker.active_layer()
    assert_true(group.is_group, "A group is active")
    actions.press_item(SaLayerActions.Item.ISOLATE)
    assert_true(group.isolated, "and the label of Blend Group on Its Own isolates it")
    assert_eq(chosen, [] as Array[StringName], "with not one of the four presses heard on chosen")

    actions.press_item(SaLayerActions.Item.MOVE_DOWN)
    assert_eq(chosen, [actions.row_id_of(SaLayerActions.Item.MOVE_DOWN)] as Array[StringName], "A plain row is")
    docker.target_canvas.free()
