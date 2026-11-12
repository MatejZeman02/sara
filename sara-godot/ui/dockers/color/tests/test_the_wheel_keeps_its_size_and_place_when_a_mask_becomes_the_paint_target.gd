## The colour picker keeps its size when a layer mask becomes
## the paint target.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Clicking on a layer mask must not change the colour picker wheel's size. The grey cover [SaGreyVeil] is a child of the
## picker's column, top level so the column lays it out with nothing else, but
## the column's own sum of the height its rows take counted every visible child
## but the wheel, the cover included. A mask as the target showed the cover,
## the sum grew by one gap, and a wheel capped by the docker's height shrank by
## that gap and moved every row under it.
##
## The docker's column is built as the Default layout ships it, short enough
## that the height left caps the wheel, with a cover following a store of this
## suite's own, so the app's pair is left as the painter had it. The target is
## switched from the layer to its mask and back, and the shape's size and place
## and the pair's place under it are read each time.
extends "res://tests/test_framework.gd"

const SaColorPickerScript = preload("res://ui/dockers/color/sa_color_picker.gd")

static var scratch_path: String = SaDataRoot.path("test_colors.cfg")

var _hosts: Array[Node] = []


func after_each() -> void:
    for host: Node in _hosts:
        host.free()
    _hosts.clear()
    if FileAccess.file_exists(scratch_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))


## A host in the tree that every node of one test hangs under, freed after it.
func _host() -> Node:
    var host := Node.new()
    host.name = "U670TestHost"
    EventBus.add_child(host)
    _hosts.append(host)
    return host


## The docker's column at *width* by *height*, a scroll holding a margin holding
## the picker, with the shape and the pair shown as the Default layout ships,
## and a cover following *store* laid over it as every picker on screen wears.
func _column(host: Node, store: SaColorStore, width: int, height: int) -> SaColorPicker:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(width, height)
    host.add_child(viewport)
    var scroll := SaMake.scroll(viewport, "Scroll")
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size = Vector2(width, height)
    var margin := SaMake.margin(scroll, "MarginContainer", SaUI.BASE_MARGIN)
    margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var picker := SaColorPickerScript.new()
    margin.add_child(picker)
    for child in picker.get_children():
        var row := child as Control
        if row != null:
            row.visible = row == picker.shape or row == picker.preview_box
    picker.add_child(SaGreyVeil.new(store))
    _lay_out(viewport)
    return picker


## Sorts every container under *node*, outside in, twice, so the wheel's fit
## before a sort and the rows' places after it have both landed. A test cannot
## await a frame.
func _lay_out(node: Node) -> void:
    for _pass in 2:
        _sort_under(node)


func _sort_under(node: Node) -> void:
    for child: Node in node.get_children():
        var box := child as Container
        if box != null:
            box.notification(Container.NOTIFICATION_PRE_SORT_CHILDREN)
            box.notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_under(child)


## What a painter sees of the wheel: the shape's size and place in the column,
## the frame's, and where the pair under it starts.
static func _wheel(picker: SaColorPicker) -> Dictionary:
    return {
        "shape": Rect2(picker.shape.position, picker.shape.size),
        "frame": Rect2(picker.shape.frame.position, picker.shape.frame.size),
        "pair": picker.preview_box.position.y,
    }


## The layer as the target, then its mask, then the layer again, in a column
## whose height caps the wheel. The cover shows for the mask, and the wheel and
## the pair under it hold their size and place all three times.
func test_the_wheel_keeps_its_size_and_place_whichever_the_target() -> void:
    var host := _host()
    var easel := SaEasel.create_default(Vector2i(32, 32))
    host.add_child(easel)
    var document := easel.document
    var layer := document.active_layer
    assert_true(SaMaskOps.new(document).run(SaMaskOps.ADD, layer), "the layer takes a mask")
    var store := SaColorStore.new()
    store.path = scratch_path
    host.add_child(store)
    store.follow(document)

    var picker := _column(host, store, ColorDocker.DEFAULT_SIZE.x, 220)
    var wheel := picker.wheel_report()
    var inner := float(ColorDocker.DEFAULT_SIZE.x - 2 * SaUI.px(SaUI.BASE_MARGIN))
    assert_true(float(wheel["left"]) < inner, "the docker is short enough that its height caps the wheel: %s" % wheel)
    var on_the_layer := _wheel(picker)

    document.mask_target = layer.mask
    assert_true(store.masking, "the mask as the target greys the store")
    var veil := picker.get_node("GreyVeil") as SaGreyVeil
    assert_true(veil.visible, "and the cover shows over the picker")
    _lay_out(picker.get_viewport())
    assert_eq(_wheel(picker), on_the_layer, "the wheel keeps its size and place with the mask as the target")
    assert_eq(float(picker.wheel_report()["side"]), float(wheel["side"]), "and the side the column gave it")

    document.mask_target = null
    assert_false(store.masking, "the layer as the target again gives the colours back")
    _lay_out(picker.get_viewport())
    assert_eq(_wheel(picker), on_the_layer, "and the wheel is where it was before the mask")


## The rule the column sizes the wheel by counts the rows a painter sees, so a
## cover shown over the picker adds nothing to the height the rows take.
func test_the_cover_takes_no_room_from_the_wheel() -> void:
    var host := _host()
    var easel := SaEasel.create_default(Vector2i(32, 32))
    host.add_child(easel)
    var document := easel.document
    var layer := document.active_layer
    assert_true(SaMaskOps.new(document).run(SaMaskOps.ADD, layer), "the layer takes a mask")
    var store := SaColorStore.new()
    store.path = scratch_path
    host.add_child(store)
    store.follow(document)
    var picker := _column(host, store, ColorDocker.DEFAULT_SIZE.x, 220)
    var left := float(picker.wheel_report()["left"])
    document.mask_target = layer.mask
    assert_eq(float(picker.wheel_report()["left"]), left, "the height left for the wheel is the same under the cover")
