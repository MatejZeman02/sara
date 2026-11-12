## ALT and a double click on the top bar open its line in Preferences, the
## gesture every docker's drag handle answers.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every docker answers the gesture and the welcome tips teach it, so a painter
## who learnt it on a docker tries it on the bar, whose line is the top bar's
## section of Layouts and dockers.
##
## **The same request a docker's handle sends.** The page and the line are
## `SaDockersPage.page_of` and `line_of` for the bar's category, which is where
## `DockerDragHandle.settings_page_of` asks too, so the two gestures cannot land
## in different places.
##
## **Heard in `_input`, before the titles.** A title acts on its press, so the
## second press of the double click would otherwise reach the title as well.
## The press is taken here, every open menu goes away, and the release that
## follows is taken too. A press on an embedded docker over the bar is that
## docker's and never reaches this viewport's `_input`, and a press without ALT
## or without the double click goes on to the bar as before.
class_name SaTopBarPageGesture
extends Node

## Puts every menu of the bar away, the bar's own `_hide_menus`.
var _hide_menus: Callable

## Whether the last press was the gesture, so its release is taken as well.
var _is_opening: bool = false


## *hide_menus* puts the bar's menus away. The bar is this node's parent, and
## its rectangle is where the gesture counts, the empty part and the titles
## alike.
func _init(hide_menus: Callable) -> void:
    name = "TopBarPageGesture"
    _hide_menus = hide_menus


func _bar() -> Control:
    return get_parent() as Control


## The Preferences page the gesture opens, Layouts and dockers.
static func page() -> String:
    return SaDockersPage.page_of(SaDockersPage.TOP_BAR)


## The line on that page the gesture lands on, the top bar's.
static func line() -> StringName:
    return SaDockersPage.line_of(SaDockersPage.TOP_BAR)


func _input(event: InputEvent) -> void:
    var button := event as InputEventMouseButton
    if button != null and handle_input(button, button.position):
        get_viewport().set_input_as_handled()


## Whether *button*, a press or release at *at* in the bar's viewport, is the
## gesture's. Apart from `_input` so a suite and the capture step drive it
## without a pointer.
func handle_input(button: InputEventMouseButton, at: Vector2) -> bool:
    if button.button_index != MOUSE_BUTTON_LEFT:
        return false
    if not button.pressed:
        var was_opening := _is_opening
        _is_opening = false
        return was_opening
    _is_opening = false
    if not (button.alt_pressed and button.double_click):
        return false
    var bar := _bar()
    if bar == null or not bar.is_visible_in_tree() or not bar.get_global_rect().has_point(at):
        return false
    _hide_menus.call()
    _is_opening = true
    # Deferred for the reason `DockerDragHandle._open_settings_page` gives: a
    # window taking focus inside input handling desynchronises the engine's
    # popup bookkeeping.
    if EventBus:
        EventBus.settings_row_requested.emit.call_deferred(page(), line())
    return true


## A point on the bar under no control that takes a press, its empty part, or
## the bar's centre when every point is taken. Searched from the right of the
## first row's middle, where the room the tool options leave is.
func empty_point() -> Vector2:
    var bar := _bar()
    var rect := bar.get_global_rect()
    var y := rect.position.y + rect.size.y * 0.25
    var x := rect.end.x - 2.0
    while x > rect.position.x:
        var at := Vector2(x, y)
        if not _taken(bar, at):
            return at
        x -= 4.0
    return rect.get_center()


## Whether a visible control under *node* that acts on a press covers *at*, a
## button, a slider or a field. The rows' boxes stop a press too and are the
## empty part a painter means.
static func _taken(node: Node, at: Vector2) -> bool:
    for child in node.get_children():
        var control := child as Control
        if control == null or not control.is_visible_in_tree():
            continue
        var acts := control is BaseButton or control is Range or control is LineEdit
        if acts and control.get_global_rect().has_point(at):
            return true
        if _taken(control, at):
            return true
    return false


## Drives the gesture on the running bar for the door's `docker_page` step,
## `{"docker_page": {"id": "TopMenuBar", "on": "File"}}`, and answers what the
## two clicks did. *on* names a menu title, and without it the press lands on
## the bar's empty part. `"alt": false` makes it a plain double click.
##
## The real bar, the real titles and the real gesture, with the pointer's place
## supplied, the seam `DockerDragHandle.capture_page` is for a docker and for
## the same reason: a modifier held through two clicks is nothing an injected
## click carries. A first press on a title is the title's own, so it opens the
## menu the second press has to close. The request is deferred, so the scenario
## waits before it shoots, and the dump's `preferences_search.open_page` says
## where Preferences landed.
static func capture(tree: SceneTree, spec: Dictionary) -> String:
    var bar: TopMenuBar = null
    for node in tree.root.find_children("*", "PanelContainer", true, false):
        if node is TopMenuBar:
            bar = node as TopMenuBar
            break
    if bar == null or bar.page_gesture == null:
        return "SaCapture: no top bar to double click"
    var on := String(spec.get("on", ""))
    var is_alt := bool(spec.get("alt", true))
    var title: Button = null
    var at := bar.page_gesture.empty_point()
    if not on.is_empty():
        title = bar.menu_buttons.get(on) as Button
        if title == null:
            return "SaCapture: the top bar has no menu called '%s'" % on
        at = title.get_global_rect().get_center()
    var opened := ""
    var asked := false
    for double_click: bool in [false, true]:
        var press := _click(true, is_alt, double_click)
        var taken := bar.page_gesture.handle_input(press, at)
        asked = asked or taken
        if not taken and title != null:
            # What the engine does with a press the gesture let through.
            title.pressed.emit()
        if not double_click:
            opened = _open_menus(bar)
        bar.page_gesture.handle_input(_click(false, is_alt, false), at)
    var where := on if not on.is_empty() else "its empty part"
    var menus := "open after the first click [%s], after the second [%s]" % [opened, _open_menus(bar)]
    if not asked:
        return "SaCapture: docker_page TopMenuBar on %s double-click: no page, nothing asked for, %s" % [where, menus]
    return "SaCapture: docker_page TopMenuBar on %s alt-double-click: asked for '%s' at '%s', %s" % [where, page(), line(), menus]


static func _click(pressed: bool, alt: bool, double_click: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.alt_pressed = alt
    event.double_click = double_click
    return event


static func _open_menus(bar: TopMenuBar) -> String:
    var names: Array[String] = []
    for menu_name: String in bar.menus:
        if (bar.menus[menu_name] as Window).visible:
            names.append(menu_name)
    return ", ".join(names)
