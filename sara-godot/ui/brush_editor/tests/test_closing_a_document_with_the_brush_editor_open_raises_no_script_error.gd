## Closing a document with the brush editor open raises no script error.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A Ctrl+W with the editor open once logged
## "Invalid type in function 'follow_blend_modes' ... (previously freed)",
## because the editor's pages kept the closed document and handed it to the
## next rows they built.
##
## Built the way the other document-tab suites build main: a first view from
## `render/main_canvas.gd`, the `SaDocumentTabs` over it, and a host that
## carries the registries and the tool options bar by the names the tabs read,
## so a second document has a machine of its own and the bar follows the front
## one. The editor is opened through its door, which wires it to the bus.
extends "res://tests/test_framework.gd"

## The views build canvases and the editor builds curve controls.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const ViewScript := preload("res://render/main_canvas.gd")

static var scratch_dir: String = SaDataRoot.path("test_close_with_editor")


## What main is to the tabs: the registries a new view is bound from and the
## bar pointed at the front document's machine.
class Host:
    extends Node

    var registries: SaRegistries = null
    var tool_options_bar: ToolOptionsBar = null


var _documents: SaDocuments = null
var _host: Host = null
var _first: Control = null
var _tabs: SaDocumentTabs = null
var _module: SaModule = null
var _was_embedding := false
var _kept_curve_editor: Callable = Callable()
var _kept_page := ""


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    # A window added unembedded maps a real OS window and blocks the run.
    tree.root.gui_embed_subwindows = true
    _kept_curve_editor = ToolOptionControls.open_curve_editor
    # Walking the pages writes the page the editor reopens on to the profile.
    _kept_page = SaSettings.brush_editor_page
    _documents = SaDocuments.new()
    tree.current_scene.set(&"documents", _documents)
    _host = Host.new()
    _host.name = "U528Host"
    EventBus.add_child(_host)
    _first = ViewScript.new()
    _host.add_child(_first)
    var surface := _first.get("surface") as SaSurface
    _documents.add(surface)
    _host.registries = Fixtures.make_registries(surface)
    _module = StampModuleScript.new()
    _module.register(_host.registries.context.for_module(_module.get_id()))
    var tools := _host.registries
    _first.call("bind_tools", tools.tools, tools.roles, tools.pens)
    var machine := _first.get("tool_machine") as ToolMachine
    machine.set_active_tool(&"brush")
    var bar := ToolOptionsBar.new()
    bar.name = "ToolOptionsBar"
    _host.add_child(bar)
    bar.target_tool_machine = machine
    bar.preset_store.dir = scratch_dir
    bar._ready()
    _host.tool_options_bar = bar
    _tabs = SaDocumentTabs.new(_host, _documents, _first)
    _host.add_child(_tabs)


func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var window := SaBrushEditorDoor.live_window(tree)
    if window != null:
        window.free()
    ToolOptionControls.open_curve_editor = _kept_curve_editor
    SaSettings.brush_editor_page = _kept_page
    tree.current_scene.set(&"documents", null)
    tree.root.gui_embed_subwindows = _was_embedding
    var registries := _host.registries
    _host.free()
    _host = null
    _first = null
    _tabs = null
    _documents = null
    _module.unregister(registries.context)
    registries.context.for_module(_module.get_id()).remove_all_registrations()
    _module = null
    SaColors.follow(null)
    if DirAccess.dir_exists_absolute(scratch_dir):
        for file_name: String in DirAccess.get_files_at(scratch_dir):
            DirAccess.remove_absolute(scratch_dir.path_join(file_name))
        DirAccess.remove_absolute(scratch_dir)


func _machine() -> ToolMachine:
    return _host.tool_options_bar.target_tool_machine


## The blend row on the editor's pages, walking the pages until one holds it,
## since which page a tool puts the row on is the module's choice. Read off the
## page's own controls, because the rows a switch leaves are only queued.
func _editor_blend_row(window: SaBrushEditorWindow) -> BlendModeButton:
    for index in window.pages.count():
        window.show_page(index)
        var controls := window.pages.page_controls
        var row := controls.control(ToolOptionControls.BLEND_KEY) as BlendModeButton if controls != null else null
        if row != null:
            return row
    return null


## The editor opened through its door, a frame on from the suite's start, since
## the root is still adding the runner's children then and refuses another. The
## page it opened on is scrolled to at the end of the frame, after the one an
## await of `process_frame` resumes in, so two frames are let pass for that, as
## they pass before any painter can reach a tab.
func _open_editor() -> SaBrushEditorWindow:
    var tree := Engine.get_main_loop() as SceneTree
    await tree.process_frame
    var window := SaBrushEditorDoor.open(tree) as SaBrushEditorWindow
    for frame in 2:
        await tree.process_frame
    return window


## A tool other than the brush that the bar shows, for the change that rebuilds
## the editor's rows.
func _other_tool() -> StringName:
    for id: StringName in _machine().registered_tools:
        if id != &"brush" and id != _machine().active_tool_name:
            return id
    return &""


func test_a_tab_closed_under_the_editor_then_a_tool_change_raises_no_error_and_names_the_front_document() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var first_document := _documents.front.get_document()
    first_document.color_space = SaColorSpace.srgb()
    var second := _tabs.add_document()
    assert_not_null(second, "The tabs add a second document")
    assert_eq(_machine(), second.tool_machine, "and the bar follows its machine")
    var second_document := second.get_document()
    second_document.color_space = SaColorSpace.linear_srgb()
    var closed_space: SaColorSpace = second_document.color_space
    var held: WeakRef = weakref(second_document)

    var window := await _open_editor()
    assert_not_null(window, "The door opens the brush editor over the second document")
    if window == null:
        return
    var row := _editor_blend_row(window)
    assert_not_null(row, "The editor's pages show a blend row")
    if row == null:
        return
    assert_eq(row.space, second_document.color_space, "naming the second document's space")
    # Each page walked to scrolls its row into view at the end of a frame, and
    # the close would rebuild the list under those scrolls.
    for frame in 2:
        await tree.process_frame

    var errors := SaErrorCatcher.new()
    OS.add_logger(errors)
    _tabs.close(second)
    second_document = null
    second = null
    for frame in 3:
        await tree.process_frame
    var away := _other_tool()
    # A frame after each change, as a painter's two presses have between them:
    # the page list scrolls to its open row a frame after a rebuild, and two
    # rebuilds in one frame leave the first scroll a row that is gone.
    _machine().set_active_tool(away)
    await tree.process_frame
    _machine().set_active_tool(&"brush")
    await tree.process_frame
    row = _editor_blend_row(window)
    OS.remove_logger(errors)

    assert_null(held.get_ref(), "The closed document is freed")
    assert_true(away != &"", "The bar has a second tool to change to")
    assert_eq(errors.described(SaErrorCatcher.ERRORS), PackedStringArray(), "and the close and the tool change log no error")
    assert_eq(_machine(), _documents.front.tool_machine, "The bar is on the front document's machine")
    assert_not_null(row, "The editor still shows its blend row")
    if row == null:
        return
    assert_eq(row.space, first_document.color_space, "listing the front document's modes")
    assert_true(row.space != closed_space, "and not the closed one's")


func test_a_tab_closed_under_the_editor_names_the_front_document_with_no_tool_change() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var first_document := _documents.front.get_document()
    var second := _tabs.add_document()
    second.get_document().color_space = SaColorSpace.linear_srgb()
    var window := await _open_editor()
    if window == null:
        assert_not_null(window, "The door opens the brush editor")
        return
    var errors := SaErrorCatcher.new()
    OS.add_logger(errors)
    _tabs.close(second)
    second = null
    for frame in 3:
        await tree.process_frame
    var row := _editor_blend_row(window)
    OS.remove_logger(errors)
    assert_eq(errors.described(SaErrorCatcher.ERRORS), PackedStringArray(), "Walking the pages after a close logs no error")
    assert_not_null(row, "and the editor shows its blend row")
    if row != null:
        assert_eq(row.space, first_document.color_space, "on the front document's space")
