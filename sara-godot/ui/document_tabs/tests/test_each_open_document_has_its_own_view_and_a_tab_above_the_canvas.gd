## Each open document has its own view and a tab above the
## canvas.
##
## A host stands in for main: a first view built from `render/main_canvas.gd`
## the way main builds the main canvas, held by an `SaDocuments` the runner
## hands `SaCanvasView.front_canvas()`, and the `SaDocumentTabs` over both. The
## second document is added through the tabs, since opening a file into a tab
## is a separate path.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const ViewScript := preload("res://render/main_canvas.gd")

var _documents: SaDocuments = null
var _host: Node = null
var _first: Control = null
var _tabs: SaDocumentTabs = null
var _was_embedding := false


## Embedding is forced as the other docker suites do, so the dockers under
## the host map no OS window.
func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _documents = SaDocuments.new()
    tree.current_scene.set(&"documents", _documents)
    _host = Node.new()
    _host.name = "U325Host"
    EventBus.add_child(_host)
    _first = ViewScript.new()
    _host.add_child(_first)
    _documents.add(_first.get("surface") as SaSurface)
    _tabs = SaDocumentTabs.new(_host, _documents, _first)
    _host.add_child(_tabs)


func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    tree.current_scene.set(&"documents", null)
    tree.root.gui_embed_subwindows = _was_embedding
    _host.free()
    _host = null
    _first = null
    _tabs = null
    _documents = null
    SaColors.follow(null)


func test_the_dockers_follow_the_second_document_and_the_first_keeps_its_zoom() -> void:
    var layers := LayersDocker.new()
    var references := ReferenceDocker.new()
    _host.add_child(references)
    var front := MainFrontDocument.new([layers])
    _host.add_child(front)
    front.show_canvas(SaCanvasView.canvas_of(_documents.front))
    var was_kept: Variant = SaSettings.get_docker_option(SaDockerIds.REFERENCE, ReferenceDocker.OPTION_STORE)
    SaSettings.set_docker_option(SaDockerIds.REFERENCE, ReferenceDocker.OPTION_STORE, "document")

    var first := _documents.front
    first.get_document().reference_boards = [SaReferenceBoard.new("First's board").to_header()]
    first.view.set_zoom(2.5)
    var first_pan := Vector2(37.0, -21.0)
    first.view.set_pan(first_pan)

    var second := _tabs.add_document()
    assert_not_null(second, "The tabs add a second document")
    assert_eq(_documents.surfaces.size(), 2, "and the owner holds two")
    assert_eq(_documents.front, second, "with the second in front")
    assert_true(second.view != first.view, "shown through a view of its own")
    var machines: Array = [_first.get("tool_machine"), _tabs.views[1].get("tool_machine")]
    assert_true(machines[1] != null and machines[1] != machines[0], "with a tool machine of its own")
    var second_document := second.get_document()
    for i in 3:
        SaLayerOps.new(second_document).add()
    second_document.reference_boards = [SaReferenceBoard.new("Second's board").to_header()]
    _documents.bring_to_front(first)
    _documents.bring_to_front(second)

    assert_true(_tabs.views[1].visible, "The second document's view is shown")
    assert_false(_first.visible, "and the first one's is hidden")
    layers.sync_layer_list()
    assert_eq(layers.target_canvas, SaCanvasView.canvas_of(second), "The Layers docker holds the second canvas")
    var second_count := SaLayerOps.new(second_document).layers().size()
    assert_eq(layers.item_list.row_count(), second_count, "and draws a row for each of the second document's layers")
    assert_true(second_count != SaLayerOps.new(first.get_document()).layers().size(), "a count the first does not have")
    assert_eq(references.board().name, "Second's board", "The Reference docker shows the second document's board")

    second.view.set_zoom(0.5)
    _documents.bring_to_front(first)
    assert_true(_first.visible, "The first document's view is shown again")
    assert_false(_tabs.views[1].visible, "and the second one's hidden")
    assert_almost_eq(first.view.get_zoom(), 2.5, 0.0001, "The first view's zoom is as it was left")
    assert_eq(first.view.get_pan(), first_pan, "and so is its pan")
    assert_almost_eq(second.view.get_zoom(), 0.5, 0.0001, "while the second keeps its own")
    assert_eq(references.board().name, "First's board", "The Reference docker shows the first document's board again")

    SaSettings.set_docker_option(SaDockerIds.REFERENCE, ReferenceDocker.OPTION_STORE, was_kept)
    layers.free()


func test_the_tabs_name_each_document_mark_the_modified_one_and_cycle() -> void:
    assert_false(_tabs.bar.visible, "One document open shows no tab bar")
    var first := _documents.front
    var second := _tabs.add_document()
    var third := _tabs.add_document()
    assert_true(_tabs.bar.visible, "Three open show it")
    first.get_document().modified = true
    assert_eq(
        _tabs.bar.tab_texts(), ["Untitled*", "Untitled", "Untitled"] as Array[String], "A tab for each, the modified one marked"
    )
    var front_tab := _tabs.bar.tabs.get_child(2).get_node("Name") as Button
    assert_true(front_tab.button_pressed, "The front document's tab is pressed")

    assert_eq(_documents.front, third, "The last added is in front")
    assert_true(_tabs.cycle(1), "Ctrl+Tab moves the front")
    assert_eq(_documents.front, first, "past the last tab to the first")
    assert_true(_tabs.cycle(-1), "Ctrl+Shift+Tab moves it back")
    assert_eq(_documents.front, third, "to the last")
    _tabs.cycle(-1)
    assert_eq(_documents.front, second, "and on to the one before")

    _tabs.bar.picked.emit(first)
    assert_eq(_documents.front, first, "A click on a tab brings its document forward")
    assert_eq(SaDocumentTabBar.tab_text(null), "", "A tab with no document reads nothing")


func test_closing_a_tab_lets_its_document_and_its_view_go() -> void:
    var first := _documents.front
    var second := _tabs.add_document()
    var view := _tabs.views[1]
    _tabs.close(second)
    assert_eq(_documents.surfaces.size(), 1, "The closed document is let go")
    assert_eq(_documents.front, first, "and the first comes forward")
    assert_true(view.is_queued_for_deletion(), "Its view goes with it")
    assert_true(_first.visible, "The first view is shown")
    assert_false(_tabs.bar.visible, "One document left shows no tab bar")
    _tabs.close(first)
    assert_eq(_documents.surfaces.size(), 1, "The last document has no close")


func test_a_hidden_view_runs_nothing() -> void:
    assert_not_null(_tabs.add_document(), "A second document is added")
    assert_eq(_first.process_mode, Node.PROCESS_MODE_DISABLED, "The view behind another's tab is stopped")
    assert_eq((_first.get("tool_machine") as Node).process_mode, Node.PROCESS_MODE_DISABLED, "and its tool machine too")
    _documents.bring_to_front(_documents.surfaces[0])
    assert_eq((_first.get("tool_machine") as Node).process_mode, Node.PROCESS_MODE_ALWAYS, "In front it runs again")
    assert_eq((_tabs.views[1].get("tool_machine") as Node).process_mode, Node.PROCESS_MODE_DISABLED, "and the second stops")


func test_the_bar_sizes_in_logical_units() -> void:
    assert_eq(_tabs.bar.custom_minimum_size.y, float(SaUI.px(SaDocumentTabBar.HEIGHT)), "Its height is logical pixels")
    assert_true(_tabs.bar.is_in_group(SaCanvasView.COVER_GROUP), "and a fit leaves room under it")
