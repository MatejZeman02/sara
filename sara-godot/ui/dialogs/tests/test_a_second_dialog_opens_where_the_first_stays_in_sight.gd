## A dialog shown over another opens down and right of it, and on top.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Feather and Border once opened at one rectangle, and closing the top window
## showed another that looked the same. The rule is to cascade and raise, so a
## dialog that is shown
## while another on screen sits at its position moves down and right by the
## height of its title strip, inside the host, and is raised above it.
##
## Feather and Border are two `SaRadiusDialog`s of one declared size that
## `SaSelectMenu` centres on the same host, so they are the pair that matters.
## The screen is a `SubViewport` with subwindows embedded in it, for the reason
## `test_the_about_window_fits_a_screen` gives, and the stacking order is read
## from `Viewport.get_embedded_subwindows`, where the last window is on top.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

var _kept_embedding: bool = true
var _kept_inset: Callable = Callable()
var _host: Node = null
var _screen: SubViewport = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _kept_inset = SaDialogWindow.top_inset
    SaDialogWindow.top_inset = Callable()
    _host = Node.new()
    _host.name = "N71CascadeTestHost"
    EventBus.add_child(_host)
    _screen = _new_screen(Vector2i(1280, 800))


func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    SaDialogWindow.top_inset = _kept_inset
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    _screen = null


## The row's own words: Feather and then Border, read apart, Border on top.
func test_border_opens_down_and_right_of_feather_and_on_top() -> void:
    var feather := _radius_dialog("Feather")
    var border := _radius_dialog("Border")
    _open(feather)
    var feather_at := feather.position
    _open(border)
    var step := _step(border)
    assert_eq(feather.position, feather_at, "the dialog that was there first stays where it was")
    assert_eq(border.position - feather.position, step, "Border sits a title strip down and right of Feather")
    assert_true(step.x > 0 and step.y > 0, "the title strip has a height, or the step proves nothing: %s" % step)
    assert_eq(_screen.get_embedded_subwindows().back(), border, "Border is the window on top")
    assert_true(feather.visible and border.visible, "both are still on screen, so closing the top one shows the other")


## Two dialogs of different heights centred on one host. Feather
## and Border have hint lines of different lengths, so the taller opened
## 14 pixels above the shorter at one left edge, and corners that close were not
## read as one place: Border covered Feather whole. Border is made the taller here
## by hand, so the pair differs whatever the hint lines wrap to.
func test_a_taller_dialog_opens_a_title_strip_down_and_right_of_a_shorter_one() -> void:
    var feather := _radius_dialog("Feather")
    var border := _radius_dialog("Border")
    _open(feather)
    var feather_at := feather.position
    border.size = Vector2i(feather.size.x, feather.size.y + 28)
    _open(border)
    var step := _step(border)
    assert_eq(feather.position, feather_at, "the shorter dialog that was there first stays where it was")
    assert_eq(border.position - feather.position, step, "the taller sits a title strip down and right of the shorter")
    var strip := Rect2i(feather.position, Vector2i(feather.size.x, step.y))
    assert_false(
        Rect2i(border.position, border.size).intersects(strip),
        "Feather's title strip is in sight under Border: %s and %s" % [strip, Rect2i(border.position, border.size)]
    )
    assert_eq(_screen.get_embedded_subwindows().back(), border, "the taller is the window on top")


## The running app's order: Border opens at a height clear of Feather's strip,
## and the fit a frame later grows it about its centre over the strip. The walk
## at the show has nothing to move, so the fit asks again. The growth is written
## here the way `fit_opening_size` writes it, half of it off the position,
## because the fit itself needs a drawn frame for its numbers: in this suite a
## wrapping hint answers its height one character wide and the fit fills the host.
## The fit's own call is walked on the running app by a scenario.
func test_a_dialog_grown_over_the_strip_after_its_show_is_cascaded_again() -> void:
    var feather := _radius_dialog("Feather")
    var border := _radius_dialog("Border")
    _open(feather)
    var feather_at := feather.position
    border.size = Vector2i(feather.size.x, feather.size.y >> 2)
    _open(border)
    var step := _step(border)
    var clear := border.position.y >= feather.position.y + step.y
    assert_true(clear, "the short Border opens clear of the strip: %s" % border.position)
    var grown := Vector2i(0, feather.size.y + 28 - border.size.y)
    border.size += grown
    border.position -= Vector2i(0, grown.y >> 1)
    border.cascade_off_the_open_dialogs()
    assert_eq(feather.position, feather_at, "Feather stays where it was")
    assert_eq(border.position - feather.position, step, "the grown Border sits a title strip down and right of Feather")


## Feather grown over the strip of a Border opened after it moves nothing: the
## one opened later is on top, and the one below is not cascaded off it.
func test_the_dialog_below_grown_is_not_moved_off_the_one_above() -> void:
    var feather := _radius_dialog("Feather")
    var border := _radius_dialog("Border")
    _open(feather)
    _open(border)
    var feather_at := feather.position
    feather.size += Vector2i(0, 60)
    feather.cascade_off_the_open_dialogs()
    assert_eq(feather.position, feather_at, "Feather is not cascaded off Border, which opened over it")


## The other way about: a shorter dialog centred over a taller one opens lower
## than it and still has to clear its strip. Forty pixels taller puts it twenty
## lower, under the 26 pixel strip a 15 point title draws.
func test_a_shorter_dialog_opens_a_title_strip_down_and_right_of_a_taller_one() -> void:
    var feather := _radius_dialog("Feather")
    var border := _radius_dialog("Border")
    feather.size = Vector2i(feather.size.x, feather.size.y + 40)
    _open(feather)
    _open(border)
    assert_eq(border.position - feather.position, _step(border), "the shorter sits a title strip down and right of the taller")


## A dialog dragged off another's title strip, though it still covers part of
## the other's body, is not on it and is left where it was put.
func test_a_dialog_clear_of_the_title_strip_is_left_where_it_was_put() -> void:
    var feather := _radius_dialog("Feather")
    var border := _radius_dialog("Border")
    _open(feather)
    var at := feather.position + Vector2i(-40, _step(border).y + 20)
    border.popup(Rect2i(at, border.size))
    _settle(border)
    border.cascade_off_the_open_dialogs()
    assert_eq(border.position, at, "a dialog below the other's title strip keeps the position it was given")


## Closing the top one shows the other where the painter last saw it, not over
## the same rectangle.
func test_closing_the_top_one_leaves_the_first_where_it_was() -> void:
    var feather := _radius_dialog("Feather")
    var border := _radius_dialog("Border")
    _open(feather)
    _open(border)
    var feather_at := feather.position
    border.hide()
    assert_eq(feather.position, feather_at, "Feather has not moved")
    assert_true(feather.visible, "and is on screen")


## A third dialog on the first two is cascaded once for each it would sit on.
func test_a_third_dialog_is_walked_past_both() -> void:
    var first := _radius_dialog("Feather")
    var second := _radius_dialog("Border")
    var third := _radius_dialog("Radius")
    _open(first)
    _open(second)
    _open(third)
    var step := _step(third)
    assert_eq(third.position - first.position, step * 2, "the third is two steps from the first")
    assert_eq(third.position - second.position, step, "and one from the second")


## A dialog a painter dragged away from the one under it is not on it, so it is
## neither moved nor raised again.
func test_a_dialog_opened_elsewhere_is_left_where_it_was_put() -> void:
    var feather := _radius_dialog("Feather")
    var border := _radius_dialog("Border")
    _open(feather)
    border.popup(Rect2i(Vector2i(40, 40), border.size))
    _settle(border)
    border.cascade_off_the_open_dialogs()
    var at := Vector2i(40, 40)
    assert_eq(border.position, at, "a dialog shown away from every other keeps the position it was given")
    border.hide()
    border.popup(Rect2i(feather.position + Vector2i(3, 2), border.size))
    border.cascade_off_the_open_dialogs()
    assert_true(
        border.position.x > feather.position.x + 3 or border.position.y > feather.position.y + 2,
        "a dialog shown a few pixels from another is on it and moves: %s from %s" % [border.position, feather.position]
    )


## A hidden dialog is not one to keep clear of, and one shown again after it was
## closed opens where the host centres it.
func test_a_closed_dialog_is_not_one_to_keep_clear_of() -> void:
    var feather := _radius_dialog("Feather")
    var border := _radius_dialog("Border")
    _open(feather)
    var centred := feather.position
    feather.hide()
    _open(border)
    assert_eq(border.position, centred, "with Feather closed, Border opens where Feather did")


## The cascade keeps the window inside the host, and a host with no room to move
## into ends the walk instead of looping.
func test_the_cascade_stays_inside_the_host_and_ends() -> void:
    var small := _new_screen(Vector2i(330, 240))
    var first := _radius_dialog("Feather", small)
    var second := _radius_dialog("Border", small)
    _open(first)
    _open(second)
    var host := Rect2i(Vector2i.ZERO, small.size)
    assert_true(
        host.encloses(Rect2i(second.position, second.size)), "Border is inside a host of %s at %s" % [host.size, second.position]
    )


## Two dialogs in two hosts are not one place, whatever their coordinates say.
func test_dialogs_in_different_hosts_do_not_cascade() -> void:
    var elsewhere := _new_screen(Vector2i(1280, 800))
    var feather := _radius_dialog("Feather")
    var border := _radius_dialog("Border", elsewhere)
    _open(feather)
    _open(border)
    assert_eq(border.position, feather.position, "a dialog on another screen opens where that screen centres it")


func _new_screen(size: Vector2i) -> SubViewport:
    var screen := SubViewport.new()
    screen.size = size
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    return screen


## A radius dialog titled *label*, added to *screen* and not yet shown.
func _radius_dialog(label: String, screen: SubViewport = null) -> SaRadiusDialog:
    var dialog := SaRadiusDialog.new()
    (screen if screen != null else _screen).add_child(dialog)
    dialog.configure(label, 4)
    return dialog


## Shown the way `SaSelectMenu.open_radius_dialog` shows one, and given the frame's
## work it would have had: the window is visible from the moment it joins the tree,
## so this is a `popup_centered` on a window that is already up, which changes no
## visibility and leaves the cascade to the deferred call the frame would run.
func _open(dialog: SaDialogWindow) -> void:
    dialog.popup_centered()
    _settle(dialog)
    dialog.cascade_off_the_open_dialogs()


## The step a dialog cascades by, in its own window's units.
func _step(dialog: SaDialogWindow) -> Vector2i:
    var strip := ceili(dialog.title_strip_height())
    return SaUI.window_size_for(dialog, Vector2i(strip, strip))


## Lays *window* out the way a drawn frame would, which `fit_opening_size` needs
## for its numbers to be real: every container sorted, outside in.
func _settle(window: Window) -> void:
    _sort_children(window)
    var kept := window.size
    window.size = kept + Vector2i.ONE
    window.size = kept
    _sort_children(window)


func _sort_children(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)
