## The Info docker's sections placed in another docker keep
## updating with Info closed.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A placed section reads what the docker would
## read, and keeps reading it when Info itself is closed. So each view here is
## built through the door, `SaSettings.build_element_view`, the way a composed
## docker builds one, with the docker hidden and never ticking, and nothing in
## the suite hands a view a canvas or a tool machine. What it reads comes from
## the docker's own.
##
## A docker is a `Window` and adding one to the tree in a headless test hangs,
## so the docker never enters the tree, which is Info closed at its most closed:
## its own ticker was never even made. The views are controls and do enter it,
## under a host node, so each starts its own ticker the way a placed one does.
## A suite cannot await a frame, so emitting the ticker's `timeout` stands for
## the tenth of a second that brings the next refresh.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const DOCKER := preload("res://ui/dockers/panels/info_docker.gd")

const CATEGORY: String = SaDockerIds.INFO

var _registries: SaRegistries
var _easel: SaEasel
var _canvas: SaCanvas
var _doc: SaDocument
var _machine: ToolMachine
var _docker: InfoDocker
## The node the views are placed under, in the tree.
var _host: Node
## The background, at full opacity, and Ink above it at a quarter, made active.
var _bottom: SaLayer
var _top: SaLayer


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(256, 256))
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    var ops := SaLayerOps.new(_doc)
    _bottom = _doc.active_layer
    _top = ops.add()
    _top.name = "Ink"
    ops.set_opacity(_top, 0.25)
    _doc.set_active_layer(_top)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _machine = ToolMachine.new()
    _docker = DOCKER.new()
    _docker.name = "E4InfoUnderTest"
    _docker.target_canvas = _canvas
    _docker.target_tool_machine = _machine
    _docker.hide()
    _host = Node.new()
    _host.name = "E4Host"
    EventBus.add_child(_host)


func after_each() -> void:
    _host.free()
    if _docker != null:
        _docker.free()
    _machine.free()
    _canvas.free()
    _easel.free()
    _docker = null
    _doc = null


## A fresh view of *element* of the Info docker, built through the door and
## placed under the host, where it comes into sight.
func _place(element: String) -> SaInfoSection.View:
    var built := SaSettings.build_element_view(CATEGORY, element)
    if built != null:
        _host.add_child(built)
    return built as SaInfoSection.View


## What *view*'s row *key* reads, or "" when it has no such row.
func _reads(view: SaInfoSection.View, key: String) -> String:
    var row: Array = view.section.rows.get(key, [])
    return (row[1] as Label).text if not row.is_empty() else ""


func test_every_section_is_placeable_under_info() -> void:
    for entry: Array in InfoDocker.SECTIONS:
        var section: String = entry[0]
        assert_true(SaSettings.is_placeable(CATEGORY, section), "'%s' has a view the Info docker registered" % section)
    assert_false(SaSettings.is_placeable(CATEGORY, "Drag Handle"), "while the docker's drag bar is not placeable")


## The case that matters: the Active layer view built through the door with Info
## closed, another layer made active, and the view naming it after the next
## refresh.
func test_the_active_layer_view_names_the_layer_made_active_with_info_closed() -> void:
    var view := _place("Active layer")
    assert_not_null(view, "The door builds a view of the Active layer section")
    if view == null:
        return
    assert_false(_docker.visible, "with the Info docker closed")
    assert_eq(view.section.title, "Active layer", "The view holds the section it was asked for")
    assert_eq(view.section.rows.keys(), ["Name", "Blend", "Opacity", "Locked"], "with the rows the docker declares for it")
    assert_false(view.ticker.is_stopped(), "and it ticks while it is in sight, Info closed or not")
    assert_eq(_reads(view, "Name"), "Ink", "It reads the active layer as soon as it is placed")
    assert_eq(_reads(view, "Opacity"), "25%", "at its own opacity")

    _doc.set_active_layer(_bottom)
    assert_eq(_reads(view, "Name"), "Ink", "Another layer made active, the view still reads the last refresh")
    view.ticker.timeout.emit()
    assert_eq(_reads(view, "Name"), str(_bottom.name), "and after the next one it names the layer made active")
    assert_eq(_reads(view, "Opacity"), "100%", "at that layer's opacity")

    var home: Array = _docker._section_boxes["Active layer"].rows["Name"]
    assert_eq((home[1] as Label).text, "", "The closed docker's own section read nothing, so the view did not copy it")


## A view in sight ticks and one out of sight does not, the docker's own rule
## for itself (f10), and coming back into sight fills it at once.
func test_a_view_out_of_sight_stops_ticking_and_fills_again_when_shown() -> void:
    var view := _place("Active layer")
    if view == null:
        assert_true(false, "No view of the Active layer section was built")
        return
    view.hide()
    assert_true(view.ticker.is_stopped(), "A view out of sight stops its ticker, nobody reads its rows")
    _doc.set_active_layer(_bottom)
    view.show()
    assert_false(view.ticker.is_stopped(), "and starts it again when it is shown")
    assert_eq(_reads(view, "Name"), str(_bottom.name), "filling its rows at once rather than a tenth of a second later")


## The docker's other sections are views of the same kind, each filled by the
## code that fills it at home: the Document view of a closed docker counts what
## the docker's row counts, the document's children, and follows a layer added.
func test_the_document_view_counts_the_layers_with_info_closed() -> void:
    var view := _place("Document")
    if view == null:
        assert_true(false, "No view of the Document section was built")
        return
    var before := _doc.get_child_count()
    assert_eq(_reads(view, "Size"), "256 x 256", "The Document view reads the canvas size")
    assert_eq(_reads(view, "Layers"), str(before), "and the layers")
    SaLayerOps.new(_doc).add()
    assert_eq(_reads(view, "Layers"), str(before), "A layer added, the view still reads the last refresh")
    view.ticker.timeout.emit()
    assert_eq(_reads(view, "Layers"), str(before + 1), "and the one more after the next refresh")


## A placed section is shown and hidden by the docker holding it, so Info's own
## switch for the section, which hides the docker's copy, leaves the view alone.
func test_infos_own_switch_hides_its_copy_and_not_a_placed_one() -> void:
    var view := _place("Active layer")
    if view == null:
        assert_true(false, "No view of the Active layer section was built")
        return
    var was := SaSettings.get_element_visible(CATEGORY, "Active layer")
    SaSettings.set_element_visible(CATEGORY, "Active layer", false)
    view.ticker.timeout.emit()
    # Through a local: the privates rule reads `fill` called on a private as
    # Array.fill, a write, whatever the member's type.
    var home: SaInfoSection = _docker._section_boxes["Active layer"]
    home.fill(_canvas, _machine)
    assert_true(view.section.visible, "The placed section still shows with Info's switch for it off")
    assert_false(home.visible, "while the docker's own copy obeys it")
    SaSettings.set_element_visible(CATEGORY, "Active layer", was)


## A view built before main hands the docker its canvas, as a composed docker's
## view at boot is, reads nothing until then and the canvas once it is handed.
func test_a_view_built_before_the_docker_has_a_canvas_takes_it_when_handed() -> void:
    _docker.free()
    _docker = DOCKER.new()
    var view := _place("Active layer")
    if view == null:
        assert_true(false, "No view of the Active layer section was built")
        return
    assert_eq(_reads(view, "Name"), "", "With no canvas the view reads nothing")
    _docker.target_canvas = _canvas
    _docker.target_tool_machine = _machine
    view.ticker.timeout.emit()
    assert_eq(_reads(view, "Name"), "Ink", "and the canvas main hands the docker afterwards")


## The door holds the docker weakly, so a view of a docker that is gone builds,
## reads nothing and raises nothing.
func test_a_view_of_a_docker_that_is_gone_reads_nothing() -> void:
    _docker.free()
    _docker = null
    var view := _place("Active layer")
    if view == null:
        assert_true(false, "No view of the Active layer section was built")
        return
    view.ticker.timeout.emit()
    assert_eq(_reads(view, "Name"), "", "A view of a freed docker reads nothing")
