## The documents open side by side: a view of its own for each, the views not in
## front hidden, and the tab bar above the canvas that names them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Each further document gets what the main canvas has, its own surface, easel,
## view and tool machine, built from the first view's own script, so zoom,
## pan, rotation and a tool's session stay with the painting they were made in.
## `SaDocuments` stays the one writer of which documents are open and which is
## in front. This class builds and frees the views, shows the front one, and
## points the tool's controls at the front document's machine whenever the bus
## says the front moved. The dockers that show the document already follow the
## front through `MainFrontDocument` and `SaCanvasView.front_canvas`.
##
## The host is main in the app. It is read by name, `registries`,
## `hold_document`, `close_document` and the tool's controls, the way
## `SaDocuments.state_in` reads it, so a suite hands any node and gets views
## with no tools bound. The bar shows only while two or more documents are
## open, so the one painting Sara starts with keeps the whole canvas.
class_name SaDocumentTabs
extends Node

const NODE_NAME := "DocumentTabs"

## The commands that cycle the tabs, Ctrl+Tab and Ctrl+Shift+Tab as in every
## tabbed program.
const NEXT_COMMAND := &"window_next_document"
const PREVIOUS_COMMAND := &"window_previous_document"
## File > Close, Ctrl+W as in every tabbed program.
const CLOSE_COMMAND := &"file_close"

## The open documents, the owner of the list.
var documents: SaDocuments = null

## The tab bar above the canvas.
var bar: SaDocumentTabBar = null

## A view for each open document, the first being the one Sara starts with.
var views: Array[Control] = []

## The node the views are children of and whose tools they share, main in the app.
var _host: Node = null

## How many views were ever built, so each surface's id is new.
var _built: int = 1

## The machine the tool's controls were last pointed at.
var _machine: ToolMachine = null


## *host* holds the views, *open_documents* is the owner of the list, and
## *first_view* is the main canvas, already the host's child.
func _init(host: Node, open_documents: SaDocuments, first_view: Control) -> void:
    name = NODE_NAME
    _host = host
    documents = open_documents
    if first_view != null:
        views.append(first_view)
    bar = SaDocumentTabBar.new()
    bar.visible = false
    add_child(bar)
    bar.picked.connect(bring_forward)
    bar.close_asked.connect(close)


func _enter_tree() -> void:
    if not EventBus.active_document_changed.is_connected(_on_front_changed):
        EventBus.active_document_changed.connect(_on_front_changed)
    if not EventBus.docker_layout_changed.is_connected(place):
        EventBus.docker_layout_changed.connect(place)
    var viewport := get_viewport()
    if viewport != null and not viewport.size_changed.is_connected(place):
        viewport.size_changed.connect(place)
    var top := _top_bar()
    if top != null and not top.resized.is_connected(place):
        top.resized.connect(place)


func _exit_tree() -> void:
    if EventBus.active_document_changed.is_connected(_on_front_changed):
        EventBus.active_document_changed.disconnect(_on_front_changed)
    if EventBus.docker_layout_changed.is_connected(place):
        EventBus.docker_layout_changed.disconnect(place)


## The tabs of the main scene in *tree*, or null where there is none.
static func in_tree(tree: SceneTree) -> SaDocumentTabs:
    if tree == null or tree.current_scene == null:
        return null
    return tree.current_scene.get_node_or_null(NodePath(NODE_NAME)) as SaDocumentTabs


## Opens a further, untitled document in a view of its own, after the others,
## and brings it to the front. Answers its surface, or null when the view could
## build none. File > New, Open and New from Clipboard come here through
## `SaDocumentFiles`, which decides whether a file takes a tab of its own.
func add_document() -> SaSurface:
    if views.is_empty() or not is_instance_valid(views[0]):
        return null
    _built += 1
    # The first view's script rather than a preload of it: a view is a sibling
    # of the main canvas, and `render` keeps the file to itself.
    var view := (views[0].get_script() as Script).new(StringName("document_%d" % _built)) as Control
    _host.add_child(view)
    # Under the bars and the dockers, which are drawn after the views.
    if not views.is_empty() and is_instance_valid(views[-1]) and views[-1].get_parent() == _host:
        _host.move_child(view, views[-1].get_index() + 1)
    views.append(view)
    view.show_as_front(false)
    var surface: SaSurface = view.get("surface")
    if surface == null:
        views.erase(view)
        view.queue_free()
        return null
    _bind(view)
    if _host.has_method("hold_document"):
        _host.call("hold_document", surface)
    else:
        documents.add(surface)
    bring_forward(surface)
    _fit_when_placed(view)
    return surface


## What *document*'s tab reads, for a list that names it as the tab does.
static func tab_text(document: SaDocument) -> String:
    return SaDocumentTabBar.tab_text(document)


## Brings *surface*'s document to the front.
func bring_forward(surface: SaSurface) -> void:
    documents.bring_to_front(surface)


## Brings the document *step* tabs on forward, wrapping at either end: 1 is
## Ctrl+Tab, -1 is Ctrl+Shift+Tab. Answers whether the front moved.
func cycle(step: int) -> bool:
    var open := _open()
    if open.size() < 2:
        return false
    return documents.bring_to_front(open[posmod(open.find(_front()) + step, open.size())])


## Closes *surface*'s document, after asking about its unsaved changes and
## about nothing else's. Closing the last one leaves a fresh untitled document
## in its place, so there is always a front document. The view Sara started
## with is hidden rather than freed, since main holds it.
func close(surface: SaSurface) -> void:
    if surface == null or not _open().has(surface):
        return
    var files := SaDocumentFiles.in_tree(get_tree()) if is_inside_tree() else null
    if files == null:
        _close_now(surface)
        return
    files.confirm_discard(tr("closing it"), _close_now.bind(surface), surface.get_document())


## Places the bar under the top bar, across the room the dockers leave beside
## the front document, and shows it while two or more documents are open.
func place(_ignored: Variant = null) -> void:
    if bar == null or not is_inside_tree():
        return
    var top := _top_bar()
    var y := top.get_global_rect().end.y if top != null and top.is_visible_in_tree() else 0.0
    var room := Rect2(0.0, y, get_viewport().get_visible_rect().size.x, 0.0)
    var front := _front()
    var view := front.view as SaCanvasView if front != null else null
    if view != null and view.canvas != null and view.canvas.is_inside_tree():
        var free := view.get_free_rect()
        if free.size.x > 0.0:
            room = Rect2(free.position.x, y, free.size.x, 0.0)
    bar.place_in(room, _open().size() > 1)


## The document in front closed, File > Close and Ctrl+W.
func close_front() -> bool:
    if _front() == null:
        return false
    close(_front())
    return true


## A layer row released at *global_point*, a point in *from*'s viewport, which
## is the layers docker's own and can be a floating window's. Over the bar it
## is the bar's drop and answers true, so the list makes no reorder of it: on
## another document's tab *layer* is copied there on top, and anywhere else on
## the bar, its own tab included, nothing happens. Off the bar it answers false.
static func drop_layer(from: Control, layer: SaLayer, global_point: Vector2) -> bool:
    var tabs := in_tree(from.get_tree()) if from != null and from.is_inside_tree() else null
    if tabs == null or layer == null or not tabs.bar.is_visible_in_tree():
        return false
    var point := global_point
    var here := from.get_window()
    var there := tabs.bar.get_window()
    if here != there and here.is_embedded():
        # A docker embedded in the main window, the arithmetic the input driver aims with.
        point = Vector2(here.position) + here.get_final_transform() * global_point
    elif here != there:
        var screen := here.get_screen_transform() * global_point
        point = there.get_screen_transform().affine_inverse() * screen
    if not tabs.bar.get_global_rect().has_point(point):
        return false
    var surface := tabs.bar.surface_at(point)
    var source := layer.get_parent() as SaDocument
    if surface != null and surface.get_document() != source:
        SaClipboard.copy_layer_across(source, layer, surface.get_document())
    return true


## Ctrl+Tab, Ctrl+Shift+Tab and Ctrl+W, through the door a module's command uses.
func register_commands(registries: SaRegistries) -> void:
    if registries == null or registries.context == null:
        return
    var ctx := registries.context.for_module(&"sara-skeleton")
    var next := SaCommandDescriptor.create(NEXT_COMMAND, "Next Document", cycle.bind(1))
    next.default_events = [SaAppCommands.chord(KEY_TAB, true)]
    next.category = &"window"
    next.sentence = "Bring the document in the next tab to the front."
    ctx.register_command(next)
    var previous := SaCommandDescriptor.create(PREVIOUS_COMMAND, "Previous Document", cycle.bind(-1))
    previous.default_events = [SaAppCommands.chord(KEY_TAB, true, true)]
    previous.category = &"window"
    previous.sentence = "Bring the document in the tab before to the front."
    ctx.register_command(previous)
    var shut := SaCommandDescriptor.create(CLOSE_COMMAND, "Close document", close_front)
    shut.label = "Close"
    shut.default_events = [SaAppCommands.chord(KEY_W, true)]
    shut.category = &"file"
    shut.sentence = "Close the document in front, asking first when it has unsaved changes. The last leaves a fresh one."
    ctx.register_command(shut)


## Opens, cycles or picks a document tab.
## The scenario's `{"tab": ...}`: `"add"` opens a further untitled document
## through the owner, `"next"` and `"previous"` cycle as the chords do, and a
## number brings that tab forward. Says what the tabs read after it.
static func capture_tab(tree: SceneTree, spec: Variant) -> String:
    var tabs := in_tree(tree)
    if tabs == null:
        return "SaCapture: tab finds no document tabs"
    var asked := str(int(spec)) if spec is float or spec is int else str(spec)
    if asked == "add":
        if tabs.add_document() == null:
            return "SaCapture: tab could not add a document"
    elif asked == "next" or asked == "previous":
        tabs.cycle(1 if asked == "next" else -1)
    elif asked.is_valid_int() and int(asked) >= 0 and int(asked) < tabs._open().size():
        tabs.bring_forward(tabs._open()[int(asked)])
    else:
        return "SaCapture: tab wants add, next, previous or a tab's number, not '%s'" % asked
    return "SaCapture: tabs %s, front %s" % [str(tabs.bar.tab_texts()), tabs.documents.state().get("front", "")]


## Lists the open documents: every one the painter has open, in tab order, with
## its name and which of them is in front, `{"documents": true}`.
##
## One dictionary a document, in the shape the `layers` step answers a stack in:
## `at` its place in the tab order counted from 0, `name` what the tab reads,
## the file's name or `Untitled` for one never saved, `id` its surface's id as
## the dump's `documents` block spells it, `modified` whether it has unsaved
## changes, and `front` for the one the painter is working on. Every other step
## acts on that one, so this is what a scenario or a notebook reads before it
## asks for another by name.
static func capture_documents(tree: SceneTree) -> String:
    var tabs := in_tree(tree)
    if tabs == null:
        return "SaCapture: documents %s" % JSON.stringify({"error": "there are no document tabs to list."})
    var open: Array = []
    for at in tabs._open().size():
        var surface := tabs._open()[at]
        var document := surface.get_document()
        var entry := {
            "at": at,
            "name": SaDocumentFiles.display_name(document),
            "id": String(surface.id),
            "modified": document != null and document.modified,
            "front": surface == tabs._front(),
        }
        open.append(entry)
    return "SaCapture: documents %s" % JSON.stringify(open)


## Brings a document forward: the open one of that name, the way a click on its
## tab does, `{"front": "study.sad"}`.
##
## The name is what [method capture_documents] answers, the file's name or
## `Untitled`, and a surface id such as `document_2` is taken too, so a scenario
## can name one of two untitled documents. Answers the document it brought
## forward, `{"front": {"name": ..., "id": ...}}`, and an error naming what is
## open for a name no document carries or one that two share.
static func capture_front(tree: SceneTree, asked: String) -> String:
    var tabs := in_tree(tree)
    if tabs == null:
        return "SaCapture: front %s" % JSON.stringify({"error": "there are no document tabs to bring a document forward in."})
    var found: Array[SaSurface] = []
    for surface in tabs._open():
        if SaDocumentFiles.display_name(surface.get_document()) == asked or String(surface.id) == asked:
            found.append(surface)
    if found.size() != 1:
        var names := tabs._open().map(
            func(surface: SaSurface) -> String: return SaDocumentFiles.display_name(surface.get_document())
        )
        var why := "no open document" if found.is_empty() else "%d open documents" % found.size()
        return "SaCapture: front %s" % JSON.stringify({"error": "%s is %s, the open ones being %s." % [asked, why, str(names)]})
    tabs.bring_forward(found[0])
    var moved := {"name": SaDocumentFiles.display_name(found[0].get_document()), "id": String(found[0].id)}
    return "SaCapture: front %s" % JSON.stringify(moved)


func _close_now(surface: SaSurface) -> void:
    if _open().size() < 2 and add_document() == null:
        return
    # The document closes here, so its card gets its picture first.
    SaWelcomeWindow.keep_closing_picture(surface.easel)
    var view := _view_of(surface)
    if _host.has_method("close_document"):
        _host.call("close_document", surface)
    else:
        documents.remove(surface)
    _show()
    if view == null or view == views[0]:
        return
    views.erase(view)
    view.queue_free()


## Binds the tools of *view* from the host's registries and hands its
## compositor the blend modes and filters, as main does for the first view.
func _bind(view: Control) -> void:
    var registries := _host.get("registries") as SaRegistries
    if registries == null:
        return
    view.call("bind_tools", registries.tools, registries.roles, registries.pens)
    var canvas: SaCanvas = view.get("canvas")
    if canvas != null and canvas.compositor != null:
        canvas.compositor.set_registry(registries.blend_modes)
        canvas.compositor.filter_chain.registry = registries.filters


## A new view fits its document once the bar and the window have their sizes,
## the way Ctrl+0 shows it.
func _fit_when_placed(view: Control) -> void:
    if not is_inside_tree():
        return
    await get_tree().process_frame
    if not is_instance_valid(view):
        return
    var surface: SaSurface = view.get("surface")
    if surface != null and surface.view != null:
        surface.view.reset(surface.get_canvas_size())


func _on_front_changed(surface: SaSurface) -> void:
    for view: Control in views:
        if is_instance_valid(view) and view.has_method("show_as_front"):
            view.call("show_as_front", view.get("surface") == surface)
    _follow_tools(surface.tool_machine as ToolMachine if surface != null else null)
    _show()


## Points the bar's tool options, the Tool Options docker, the toolbox and the
## right-click menu at *machine*, which first takes the tool in hand on the
## machine they leave, so a switch of tab never changes the brush. The settings
## of a tool are shared between machines already, see `ToolMachine`.
func _follow_tools(machine: ToolMachine) -> void:
    if machine == null or machine == _machine:
        return
    var leaving := _machine
    _machine = machine
    if leaving != null and leaving != machine and machine.registered_tools.has(leaving.active_tool_name):
        if machine.active_tool_name != leaving.active_tool_name:
            machine.set_active_tool(leaving.active_tool_name)
    var options_bar := _host.get("tool_options_bar") as ToolOptionsBar
    if options_bar != null and options_bar.target_tool_machine != null:
        options_bar.target_tool_machine = machine
    var docks: Object = _host.get("dockers")
    var options_docker := (
        docks.call("registered_docker_node", SaDockerIds.TOOL_OPTIONS) as ToolOptionsDocker if docks != null else null
    )
    if options_docker != null and options_docker.target_tool_machine != null:
        options_docker.target_tool_machine = machine
    var toolbox: Object = _host.get("toolbox_docker")
    if toolbox != null and &"target_tool_machine" in toolbox:
        toolbox.set(&"target_tool_machine", machine)
    # Named by its method, since the menu is an inner file of `ui/tool_options`.
    var menu: Object = _host.get("context_menu")
    if menu != null and menu.has_method("bind"):
        menu.call("bind", options_bar, machine)


## The tabs drawn again from the owner's list, and the bar placed.
func _show() -> void:
    bar.show_documents(_open(), _front())
    place()


## The open documents' surfaces in tab order.
func _open() -> Array[SaSurface]:
    return documents.surfaces if documents != null else ([] as Array[SaSurface])


## The surface in front, or null.
func _front() -> SaSurface:
    return documents.front if documents != null else null


func _view_of(surface: SaSurface) -> Control:
    for view: Control in views:
        if is_instance_valid(view) and view.get("surface") == surface:
            return view
    return null


func _top_bar() -> Control:
    return _host.get("custom_title_bar") as Control if _host != null else null
