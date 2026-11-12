## File > New with its details open shows the colour space picker whole at 1920
## by 1080: the preset, the gamut and its primaries, the white point and its
## coordinates, the curve, the gamma, the colour model and the row that saves
## the space, every one inside the rows' visible part with no scrolling.
##
## The screen is a `SubViewport` of that size with subwindows embedded in it, as
## `test_colour_space_draws_its_diagram_whole.gd` has it and for its reasons, and
## the layout is sorted by hand outside in, because a suite has no frames.
extends "res://tests/test_framework.gd"

## The dialog draws the colour space browser, which draws a gamut.
const REQUIRES_GPU := true

const FULL_HD := Vector2i(1920, 1080)

## The picker's rows, by the nodes a painter sees.
const PICKER_NODES: Array[String] = [
    "SpaceOption",
    "DepthOption",
    "GamutRowOption",
    "PrimariesFields",
    "WhitePointOption",
    "WhitePointXy",
    "TransferOption",
    "GammaSlider",
    "CoordinatesOption",
    "SpaceSaver",
]

var _kept_scale: float = 1.0
var _kept_embedding: bool = true
var _kept_details: bool = false
var _host: Node = null


func before_each() -> void:
    _kept_scale = SaUI.user_scale
    SaUI.user_scale = 1.0
    _kept_details = SaSettings.new_document_details
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "FileNewPickerTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaUI.user_scale = _kept_scale
    SaSettings.new_document_details = _kept_details
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


func test_every_row_of_the_picker_lies_inside_the_visible_rows() -> void:
    var screen := SubViewport.new()
    screen.size = FULL_HD
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    var dialog := NewDocumentDialog.new()
    screen.add_child(dialog)
    dialog.popup_centered()
    dialog.page.row(&"details").drive(true)
    for _pass in 3:
        _settle(dialog.content)
        dialog.fit_opening_size()
    _settle(dialog.content)

    var view := dialog.find_child("RowsScroll", true, false) as Control
    var seen := view.get_global_rect().grow(0.5)
    for node_name: String in PICKER_NODES:
        var control := dialog.find_child(node_name, true, false) as Control
        assert_true(control != null and control.is_visible_in_tree(), "%s is shown with the details open" % node_name)
        if control != null:
            assert_true(
                seen.encloses(control.get_global_rect()),
                "%s at %s lies inside the rows' visible part %s" % [node_name, control.get_global_rect(), seen]
            )
    var window := Rect2(Vector2.ZERO, Vector2(FULL_HD))
    assert_true(window.encloses(Rect2(Vector2(dialog.position), Vector2(dialog.size))), "and the window lies inside the screen")
    assert_true(dialog.browser.is_visible_in_tree(), "with the drawing beside the rows")


func _settle(node: Node) -> void:
    for _round in 2:
        _remeasure_labels(node)
        _sort_children(node)


func _remeasure_labels(node: Node) -> void:
    for child: Node in node.get_children():
        var label := child as Label
        if label != null and label.autowrap_mode != TextServer.AUTOWRAP_OFF:
            label.update_minimum_size()
        _remeasure_labels(child)


func _sort_children(node: Node) -> void:
    if node == null:
        return
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)
