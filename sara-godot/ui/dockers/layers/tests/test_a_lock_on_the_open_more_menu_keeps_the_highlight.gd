## A lock pressed on the open More menu leaves the keyboard on its row.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The claim is that a lock written from the Layers docker's More menu reaches
## `LayersDocker._on_layer_lock_signal`, which rebuilds the menu while it is
## open, and the rebuild dropped the highlight, so a second Enter pressed
## nothing. `SaLayerActions.sync_from_active_layer` now keeps the highlighted row
## of a list that is open, and a list about to open still starts from nowhere.
##
## The docker stays out of the tree, as `test_layer_actions.gd` keeps it, and the
## menu's `visible` is written by hand: that flag is the whole of what the sync
## asks, and a detached window keeps it. What a painter sees is
## `scenarios/a-lock-pressed-on-the-open-more-menu-drops-the-keyboard-highlight.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")


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


func test_enter_on_a_lock_keeps_the_highlight_so_a_second_enter_unlocks() -> void:
    var docker := _docker_on_a_document()
    var actions := docker.actions
    var menu := actions.menu
    var layer := docker.active_layer()
    var paint_row := actions.row_id_of(SaLayerActions.Item.LOCK_PAINT)
    # Built the way an open builds it, on the docker's document.
    actions.sync_from_active_layer()
    menu.visible = true

    assert_true(menu.set_highlight(paint_row), "The keyboard is on Lock Layer")
    assert_true(menu.choose_highlighted(), "and enter presses it")
    assert_true(layer.is_locked, "which locks the layer")
    assert_true(menu.is_checked(paint_row), "and the rebuilt row shows the lock")
    assert_eq(menu.highlighted(), paint_row, "with the keyboard still on it")

    assert_true(menu.choose_highlighted(), "A second enter presses it again")
    assert_false(layer.is_locked, "and takes the lock off")
    assert_eq(menu.highlighted(), paint_row, "leaving the keyboard where it was")
    menu.visible = false
    docker.target_canvas.free()


func test_the_keyboard_moves_on_from_a_kept_highlight() -> void:
    var docker := _docker_on_a_document()
    var actions := docker.actions
    var menu := actions.menu
    var layer := docker.active_layer()
    # Built the way an open builds it, on the docker's document.
    actions.sync_from_active_layer()
    menu.visible = true

    menu.set_highlight(actions.row_id_of(SaLayerActions.Item.LOCK_PAINT))
    menu.choose_highlighted()
    assert_true(menu.move_highlight(1), "Down moves on from the kept row")
    assert_eq(menu.highlighted(), actions.row_id_of(SaLayerActions.Item.LOCK_ALPHA), "to Lock Alpha")
    menu.choose_highlighted()
    assert_true(layer.alpha_locked, "and enter locks the alpha")
    assert_true(layer.is_locked, "beside the paint lock")
    assert_eq(menu.highlighted(), actions.row_id_of(SaLayerActions.Item.LOCK_ALPHA), "the keyboard on Lock Alpha")
    menu.visible = false
    docker.target_canvas.free()


## What `about_to_popup` runs, on a list that is not visible yet: no highlight is
## carried from the visit before.
func test_a_list_about_to_open_starts_from_nowhere() -> void:
    var docker := _docker_on_a_document()
    var actions := docker.actions
    var menu := actions.menu

    menu.set_highlight(actions.row_id_of(SaLayerActions.Item.LOCK_ALPHA))
    actions.sync_from_active_layer()
    assert_eq(menu.highlighted(), &"", "A closed list is rebuilt with no row highlighted")
    docker.target_canvas.free()
