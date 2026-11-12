## The bare window a curve option's own widget is shown in when the brush editor
## is not the thing showing it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **This is not the brush editor.** That is a dashboard, a page list, a live
## preview and a Reset. This is one widget in a `SaDialogWindow` with nothing
## else in it. It is kept beside the editor because the Tool Options docker's
## `CURVE_OPTION` button falls back to it
## whenever nothing has bound `ToolOptionControls.open_curve_editor`, which is
## every run that has not opened the editor yet and every test that builds a
## docker on its own.
##
## **The widget comes off the spec**, and the host names no control, so the
## skeleton parses without the module whose option it shows. The host builds
## what `spec.build_control` gives it, points it at the value with
## `spec.bind_value`, and draws the page's name above it. A second open rebuilds the widget
## rather than rebinding it, because two specs can bring two classes and the host
## has no way to ask one to take the other's value.
##
## Its own file, apart from the door that applies a scenario's steps, because a
## window that builds a throwaway host is not the same thing as that door.
##
## `@tool` because the inner `Shell` extends `SaDialogWindow`, which is one.
@tool
class_name SaCurveOptionHost
extends RefCounted

## The bare host's geometry in logical units. Tall because the control is a
## slider, eight buttons, a list, a graph and two rows stacked in one column.
const HOST_SIZE := Vector2i(320, 620)
const HOST_MIN_SIZE := Vector2i(280, 420)
const HOST_MARGIN: int = SaTheme.GAP


## The bare window itself, a dialog shell that names and sizes itself as every
## `SaDialogWindow` does, from its own constructor.
class Shell:
    extends SaDialogWindow

    func _init() -> void:
        _init_dialog("CurveOptionHost", "Curve Option", HOST_SIZE, HOST_MIN_SIZE)


## Shows *value* in the bare host through *spec*'s widget, building the window
## on first use, and answers the widget.
##
## The value is edited in place, so the caller keeps whatever it handed over
## and there is no write-back to get wrong. A null value is the module's to
## answer: the capture harness opens the host on one when no control is on
## screen, and the binder makes a throwaway.
static func open(tree: SceneTree, spec: SaOptionSpec, value: Variant, page_title: String) -> Control:
    if spec == null or not spec.build_control.is_valid():
        push_warning("SaCurveOptionHost: '%s' brought no widget to host" % (spec.key if spec != null else &""))
        return null
    var host := _host(tree)
    if host == null:
        host = _build_host(tree)
        if host == null:
            return null
    var scroll := host.find_child("HostScroll", true, false) as ScrollContainer
    var title := host.find_child("HostTitle", true, false) as Label
    if scroll == null or title == null:
        return null
    for child in scroll.get_children():
        scroll.remove_child(child)
        child.free()
    var control := spec.build_control.call(spec, Callable()) as Control
    if control == null:
        push_warning("SaCurveOptionHost: the factory for '%s' built no control" % spec.key)
        return null
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(control)
    if spec.bind_value.is_valid():
        spec.bind_value.call(control, value)
    title.text = page_title
    title.visible = not page_title.is_empty()
    (host as Window).popup_centered()
    return control


static func _host(tree: SceneTree) -> Node:
    return tree.root.find_child("CurveOptionHost", true, false)


static func _build_host(tree: SceneTree) -> Node:
    var window := Shell.new()
    var margin := SaMake.margin(window.content, "HostMargin", HOST_MARGIN)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "HostColumn", 6)
    SaMake.label(column, "HostTitle")
    var scroll := SaMake.scroll(column, "HostScroll")
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    tree.root.add_child(window)
    return window
