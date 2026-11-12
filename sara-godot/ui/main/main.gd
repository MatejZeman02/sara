## The application window, and the order the pieces of it come up in.
##
## Owns the registries, the dockers, the dialogs, the menu bar and the tool
## options bar, and builds them in a fixed sequence: the registries first,
## because the toolbox and both blend dropdowns are populated from what modules
## registered rather than from hardcoded lists, and the docker layout last,
## because a compositor reports placeholder geometry until every window is
## mapped. `_boot_in_stages` is that sequence, one private function per step,
## in the order the steps are listed there.
##
## **Each stage is on a frame of its own**, behind the
## welcome window `SaBoot` showed before this class loaded, and whatever waits
## for a whole Sara waits on `EventBus.boot_finished`.
##
## It was split twice to fit a line count, into a `MainBootstrap` that wrote
## five of its members and named `main.` a hundred times, and a `MainArguments`
## of fifty lines, and both were taken back: a boot is the one thing this class
## is for. What is a policy rather than a wiring step belongs in one of the
## classes beside it, `MainDockers` and `MainDialogs`, each of which owns what
## it works on.
class_name Main
extends Node

const WorkspaceControllerScript = preload("res://ui/layout/workspace_controller.gd")

## The most frames the boot waits for the worker loading the modules' scripts,
## about five seconds at sixty frames a second.
const MODULE_SCRIPT_FRAMES := 300

## How long one frame's share of the built-in dockers may run, in microseconds,
## a handful of dockers.
const DOCKER_SLICE_USEC := 100000

## How long one frame's share of the Tool Options docker's controls may run, in
## microseconds. A tool whose controls take longer than this stands in a frame
## alone whatever this says.
const TOOL_OPTIONS_SLICE_USEC := 60000

## Where the main scene's load ends: the first member's initialiser runs before
## any other member is built and before `_init`, so the span from the last
## autoload's `_init` to here is the scene and every script it pulls in.
@warning_ignore("unused_private_class_variable")
var _scene_loaded_marked := SaBootMarks.marked(&"main_scene_loaded")

## The public API's registries. Built before any UI so the toolbox and the blend
## dropdowns can be populated from what modules registered rather than from
## hardcoded lists.
var registries := SaRegistries.new()

## The open documents and the one in front, whose easel `SaContext.get_easel()`
## answers. The main canvas's surface is the first.
var documents := SaDocuments.new()

## A view for each open document and the tab bar above them, see `SaDocumentTabs`.
var document_tabs: SaDocumentTabs

var main_canvas: Control
var info_docker: Window
var toolbox_docker: Window
var layers_docker: Window
var color_docker: Window
var tool_options_bar: ToolOptionsBar
var custom_title_bar: TopMenuBar
## The zoom, the size and the colour space along the bottom edge.
var status_line: SaStatusLine
## The canvas right-click menu over the same specs as the bar.
var context_menu: ToolContextMenu = null

## The timed recovery copy of the main document, asked about leftover copies
## once the window is up. One of `autosaves`.
var autosave: SaAutosave = null
## One autosave per open document, attached as `hold_document` opens it and
## detached as `close_document` closes it.
var autosaves: SaAutosave.PerDocument = null

var _workspace_controller := WorkspaceControllerScript.new()
## Preferences, New and Colour Space. Built in _ready and parented in the same
## breath, so the tree owns it: a Main a test constructs and never runs never
## makes one, and an unparented Node is a leak nothing would free.
var dialogs: MainDialogs = null

## Docker registration, the Window menu's docker rows, docker geometry and the
## layout store. Public, because the shortcut router is handed its methods and
## the presets docker asks it for a toggle. A child from `_init`, so a Main a
## suite builds and frees unrun takes it along, and moved last in
## `_ensure_children_initialized`, so the focus mode message it holds draws
## over the canvas and the bar.
var dockers := MainDockers.new(registries.ui)
var _shortcut_router := ShortcutRouter.new()
## How a document comes in and goes out, and the one question every destructive
## path asks. It was the File menu's, and main reached it by asking the bar for
## that menu. Built in `_init` beside the router, so the quit, the chords and
## the command line's document have it before the bar exists.
var _files: SaDocumentFiles = null

var is_test_environment: bool = false

## The welcome window `SaBoot` showed, for `MainDialogs`, or null.
var _welcome_window: SaWelcomeWindow = null

## Whether the last stage has run, before which no half-built layout is saved.
var _booted: bool = false

## The picture over the window while it builds, gone after its fade.
var _cover: SaBootCover = null

## Where a quit keeps the window's picture for the next boot's cover. A suite
## points it at a file of its own, the way it does the layout store's path.
var last_session_path := SaBootCover.picture_path()

## The factories this Main put on `SaCanvas`'s static overlay lists, and only
## those it found missing, so freeing it leaves both lists as it found them.
## One Main lives for the whole session, and a suite builds and frees many.
var _added_overlays: Array[Callable] = []
var _added_surface_overlays: Array[Callable] = []


func _init(welcome_window: SaWelcomeWindow = null) -> void:
    SaBootMarks.mark(&"main_init")
    _welcome_window = welcome_window
    # Before any canvas is built, the scene's own included: `render` names
    # nothing under `ui`, so what is drawn over a canvas is handed to it.
    if SaCanvas.add_overlay_factory(SaCanvasOverlay.attach_to):
        _added_overlays.append(SaCanvasOverlay.attach_to)
    if SaCanvas.add_overlay_factory(SaEffectGuidePainter.attach_to):
        _added_overlays.append(SaEffectGuidePainter.attach_to)
    for factory: Callable in [SaQuickMaskBanner.attach_to, SaEnvironmentView.attach_to, SaIsolateActiveLayer.attach_to]:
        if SaCanvas.add_surface_overlay_factory(factory):
            _added_surface_overlays.append(factory)
    _shortcut_router.name = "ShortcutRouter"
    _shortcut_router.tool_machine_provider = get_tool_machine
    _shortcut_router.canvas_provider = get_canvas
    _shortcut_router.dockers_provider = dockers.get_docker_config
    _shortcut_router.toggle_docker = dockers.toggle_docker
    _shortcut_router.toggle_all_dockers = dockers.toggle_all_dockers
    _shortcut_router.summon = dockers.summon
    _shortcut_router.request_quit = _request_quit
    _shortcut_router.file_command = _on_file_shortcut
    _files = SaDocumentFiles.new(get_canvas, documents)
    # The File > Quit row, which asks rather than quits, so every way out still
    # ends at the one `_request_quit` below.
    if not EventBus.quit_requested.is_connected(_request_quit):
        EventBus.quit_requested.connect(_request_quit)
    add_child(_shortcut_router)
    add_child(_files)
    add_child(dockers)


## The children, built once and only when they are not there yet. `MainCanvas`
## is looked up first because two layout suites plant a `Control` of that name
## to stand in for a canvas that would need a GPU. Nothing plants the bar, the
## tool options bar or the focus mode, so those are built outright.
func _ensure_children_initialized() -> void:
    if custom_title_bar != null and is_instance_valid(custom_title_bar):
        return
    _build_the_canvas()
    _build_the_dockers()
    _build_the_bar()


## The canvas, the first of the three children and the boot's first stage of
## them. Each of the three is its own frame of the boot, because together they
## hold the window too long for one, and the canvas's is not the main scene's
## frame either, for the same reason.
func _build_the_canvas() -> void:
    if main_canvas != null and is_instance_valid(main_canvas):
        return
    main_canvas = find_child("MainCanvas", true, false) as Control
    if main_canvas == null:
        main_canvas = preload("res://render/main_canvas.gd").new()
        main_canvas.name = "MainCanvas"
        add_child(main_canvas)
    main_canvas.unique_name_in_owner = true
    main_canvas.owner = self
    SaBootMarks.mark(&"canvas_built")


## The built-in dockers' windows. Both calls pass over what is already there,
## so after the boot's own slices of them this builds nothing new.
func _build_the_dockers() -> void:
    dockers.register_builtin_dockers()
    dockers.instantiate_registered_dockers()

    info_docker = dockers.registered_docker_node(SaDockerIds.INFO)
    toolbox_docker = dockers.registered_docker_node(SaDockerIds.TOOLBOX)
    layers_docker = dockers.registered_docker_node(SaDockerIds.LAYERS)
    color_docker = dockers.registered_docker_node(SaDockerIds.COLOR)
    SaBootMarks.mark(&"dockers_built")


## The title bar and the tool options row inside it, and the status line.
func _build_the_bar() -> void:
    if custom_title_bar != null and is_instance_valid(custom_title_bar):
        return
    custom_title_bar = preload("res://ui/top_bar/top_menu_bar.gd").new()
    custom_title_bar.name = "CustomTitleBar"
    custom_title_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
    add_child(custom_title_bar)
    add_child(TopMenuBar.window_frame(custom_title_bar, is_inside_tree() and get_parent() == get_tree().root))
    custom_title_bar.unique_name_in_owner = true
    custom_title_bar.owner = self
    custom_title_bar.add_to_group(SaCanvasView.COVER_GROUP)

    tool_options_bar = ToolOptionsBar.new()
    tool_options_bar.name = "ToolOptionsBar"
    custom_title_bar.add_tool_options(tool_options_bar)
    tool_options_bar.unique_name_in_owner = true
    tool_options_bar.owner = self
    document_tabs = SaDocumentTabs.new(self, documents, main_canvas)
    add_child(document_tabs)
    status_line = SaStatusLine.new(
        func() -> SaSurface: return documents.front if documents.front != null else main_canvas.get("surface")
    )
    add_child(status_line)
    EventBus.active_document_changed.connect(status_line.follow.unbind(1))

    # Last, so the focus mode message under it draws over everything else in
    # the window, the canvas and the bar included.
    move_child(dockers, -1)
    SaBootMarks.mark(&"bar_built")


## Starts the boot and returns after its first stage. Headless, where the
## first GPU call would crash, it builds nothing and says it is finished.
func _ready() -> void:
    SaCrashProbe.at_boot()
    SaBootMarks.mark(&"bootstrap_begin")
    var ds_name := DisplayServer.get_name()
    if ds_name == "headless":
        _booted = true
        EventBus.boot_finished.emit()
        return
    # A hundred readers find this node as the current scene, `SaBoot`'s sibling.
    if is_inside_tree() and get_parent() == get_tree().root:
        get_tree().current_scene = self
    _boot_in_stages(ds_name)


## The boot, a stage a frame, so the welcome window keeps drawing.
func _boot_in_stages(ds_name: String) -> void:
    _boot_the_window(ds_name)
    await _next_frame()
    _build_the_canvas()
    _keep_the_cover_on_top()
    await _next_frame()
    # The built-in dockers' windows, a slice a frame.
    while not dockers.register_builtin_dockers(DOCKER_SLICE_USEC):
        _keep_the_cover_on_top()
        await _next_frame()
    _build_the_dockers()
    _keep_the_cover_on_top()
    await _next_frame()
    _build_the_bar()
    _keep_the_cover_on_top()
    _boot_the_document()
    _boot_the_interface()
    SaBootMarks.mark(&"interface_built")
    await _next_frame()
    _wire_the_dockers()
    if _reach(&"ui_built", ds_name):
        return
    await _next_frame()
    await _bootstrap_modules()
    if _reach(&"modules_bootstrapped", ds_name):
        return
    _canonicalize_blend_favourites(registries.blend_modes)
    if _reach(&"blend_favourites_canonical", ds_name):
        return
    await _next_frame()
    _boot_the_layout()
    _finish_the_boot()
    _hold_the_boot_fit()
    _follow_the_screens()
    SaTrail.watch(self)
    _booted = true
    _reach(&"boot_finished", ds_name)
    EventBus.boot_finished.emit()
    # After the boot's own tool switch, so the tally counts only the hand's.
    SaUsageTally.start_if_asked(get_tree() if is_inside_tree() else null, OS.get_cmdline_user_args())
    # After the signal, so a scenario's first step and the door meet a whole Sara.
    _start_the_capture(ds_name)


## Marks *stage* and moves the cover's line on to it. True when the command
## line holds the boot there, `--hold-boot-at=<stage>` from a scenario that
## shoots the cover, in which case the capture starts here and the boot goes
## no further.
func _reach(stage: StringName, ds_name: String) -> bool:
    SaBootMarks.mark(stage)
    if _cover != null and is_instance_valid(_cover):
        _cover.reach(stage)
    if stage == &"boot_finished" or SaBootCover.held_at(OS.get_cmdline_user_args()) != stage:
        return false
    _start_the_capture(ds_name)
    return true


## Runs *then* once the cover has faded, so a dialog the boot opens is never
## under it, or on the next idle frame when there is no cover.
func _after_the_cover(then: Callable) -> void:
    if _cover != null and is_instance_valid(_cover) and _cover.is_inside_tree():
        _cover.gone.connect(then, CONNECT_ONE_SHOT | CONNECT_DEFERRED)
    else:
        then.call_deferred()


## Waits for the next frame. A suite's `Main`, outside any tree, runs every
## stage inside its one synchronous `_ready()` call, `boot_finished` included.
func _next_frame() -> void:
    if is_inside_tree():
        await get_tree().process_frame


## The window and the router, before the children, because the router has to
## be watching before anything builds a window. `SaBoot` set the embedding.
func _boot_the_window(ds_name: String) -> void:
    # First, so nothing the boot builds is seen before it.
    var window_size := get_window().size if is_inside_tree() else DisplayServer.window_get_size()
    var driven := SaBoot.capture_requested(OS.get_cmdline_user_args())
    var fade := 0.0 if driven else SaBootCover.FADE_SEC
    _cover = SaBootCover.new(window_size, last_session_path, SaSettings.show_last_session, fade)
    add_child(_cover)

    # Before anything builds a window, so the router hears the dockers, the
    # dialogs the menus open and the popups Godot makes for a dropdown. A test
    # calls this on a Main it never added to the tree, and there is no tree to
    # watch from there.
    if is_inside_tree():
        _shortcut_router.watch_windows(get_tree())

    # A test that builds a Main should not stamp a boot banner into the middle of
    # the test transcript.
    if not is_test_environment:
        SaBootHeader.print_header(ds_name)

    # The engine would quit on the window manager's close request by itself.
    # Main answers it instead, so a modified document gets its prompt first.
    if is_inside_tree():
        get_tree().auto_accept_quit = false


## The cover over whatever the boot has built so far, which is added after it.
func _keep_the_cover_on_top() -> void:
    if _cover != null and is_instance_valid(_cover):
        move_child(_cover, -1)


## The document's title and its autosave.
##
## The title is a node of its own, which follows whichever document is in
## front. It is built here, before the first surface is in `documents`, and
## names that document as soon as the owner says it is in front.
##
## Whether `SaBoot` opened the welcome window decides where the recovery copies
## are offered, its row or the chain of windows.
func _boot_the_document() -> void:
    add_child(SaWindowTitle.new(documents))
    _start_autosave(SaAutosave.surface_at_start(_welcome_window != null))


## The overlays, the theme, the bus connections, the dialogs and the three
## windows the boot installs.
func _boot_the_interface() -> void:
    # The root window draws the brush ring over the main canvas. Docker windows
    # attach their own in DockerWindow._setup_docker_ready.
    #
    # Deferred because the root window is still building its children while Main
    # is in _ready, and add_child() is rejected during that window. Attaching
    # eagerly leaves the overlay orphaned, which shows up as a leaked CanvasItem
    # RID at exit.
    CursorOverlay.attach_to.call_deferred(get_window())
    add_child(CursorOverlay.WindowWatch.new())

    # Mailbox at boot and the frame cap off while the hand is moving, which is
    # the presentation half of the ring's lag. On Main rather than on the
    # window, because it needs `_input` and a frame, and nothing else in the
    # window knows it is there.
    SaFramePacer.attach_to(self)

    # The bar exists, so the dockers can have the Window menu's popup.
    dockers.bind_bar(custom_title_bar)
    dockers.hold_the_presets()

    DockerUtils.apply_ui_theme(custom_title_bar)
    DockerUtils.apply_ui_theme(tool_options_bar)

    if not EventBus.ui_scale_changed.is_connected(_on_ui_scale_changed):
        EventBus.ui_scale_changed.connect(_on_ui_scale_changed)
    if not EventBus.ui_font_scale_changed.is_connected(_on_ui_font_scale_changed):
        EventBus.ui_font_scale_changed.connect(_on_ui_font_scale_changed)
    if not EventBus.secondary_workspace_requested.is_connected(_on_secondary_workspace_requested):
        EventBus.secondary_workspace_requested.connect(_on_secondary_workspace_requested)
    if not EventBus.docker_reparent_requested.is_connected(_on_docker_reparent_requested):
        EventBus.docker_reparent_requested.connect(_on_docker_reparent_requested)
    if not EventBus.local_server_requested.is_connected(_on_local_server_requested):
        EventBus.local_server_requested.connect(_on_local_server_requested)
    if dialogs == null:
        dialogs = MainDialogs.new(registries, get_canvas, _welcome_window, dockers.below_bar)
        add_child(dialogs)
    dialogs.connect_event_bus()
    # The autosave finds the recovery copies and the dialogs ask about them.
    # Here, where both exist: the autosave starts before the dialogs are built
    # and defers its offer past this line. Guarded by the signal's own list,
    # because a bound callable does not compare equal to the bare one.
    if autosave != null and autosave.recoveries_found.get_connections().is_empty():
        autosave.recoveries_found.connect(dialogs.offer_recoveries.bind(autosave))

    SaMessage.install(self)
    SaPickers.attach(self)
    SaFilterDialogWindow.install(self)
    SaFilterEditWindow.install(self)


## Every docker that shows the document is pointed at the front one, and the
## bar and the context menu at the main canvas's tool machine.
func _wire_the_dockers() -> void:
    if info_docker and main_canvas:
        info_docker.visible = false

    # The minimap shows the main canvas and moves its view. Hidden until asked
    # for, like the Info docker.
    var minimap := dockers.registered_docker_node(SaDockerIds.MINIMAP) as MinimapDocker
    if minimap != null and main_canvas:
        minimap.view_transforms = registries.view_transforms
        minimap.visible = false

    # The graph scopes what the main canvas shows, so it needs the same canvas
    # the minimap does. Hidden until asked for, like the other two.
    var graph := dockers.registered_docker_node(SaDockerIds.GRAPH) as GraphDocker
    if graph != null and main_canvas:
        graph.visible = false

    if toolbox_docker and main_canvas:
        toolbox_docker.target_tool_machine = main_canvas.tool_machine
    # The four that hold a canvas follow the front document from here on.
    var front := MainFrontDocument.new([info_docker, minimap, graph, layers_docker])
    add_child(front)
    front.show_canvas(main_canvas.canvas if main_canvas else null)

    dockers.place_dockers_until_settled()

    if tool_options_bar and main_canvas:
        context_menu = ToolContextMenu.new()
        add_child(context_menu)
        context_menu.bind(tool_options_bar, main_canvas.tool_machine)


## The bar's tool options and the Tool Options docker pointed at the main
## canvas's machine, a frame each, once the machine holds its tools.
##
## Each builds its rows for the machine's tool, a slow build. Wired after the
## tools are bound rather than before, so the first tool change finds neither
## following a machine and costs a few milliseconds, and each build is a frame
## of its own rather than both landing on the one `tool_changed` of the
## machine's first tool. The docker's build is two frames.
func _wire_the_tool_options() -> void:
    if main_canvas == null:
        return
    if tool_options_bar != null:
        tool_options_bar.target_tool_machine = main_canvas.tool_machine
        SaBootMarks.mark(&"tool_options_bar_bound")
        await _next_frame()
    # The Tool Options docker builds from the same specs as the bar. The bar is
    # handed over so the two follow each other's writes, and the machine after
    # it, because binding the peer first means the docker's first sync already
    # has somewhere to mirror to.
    var tool_options_docker := dockers.registered_docker_node(SaDockerIds.TOOL_OPTIONS) as ToolOptionsDocker
    if tool_options_docker != null:
        # Its controls for every tool first, a slice a frame, because the docker
        # builds them all where the bar builds only the flagged few.
        while not tool_options_docker.options.binding.build_a_slice(main_canvas.tool_machine, TOOL_OPTIONS_SLICE_USEC):
            await _next_frame()
        tool_options_docker.peer_bar = tool_options_bar
        # The docker leaves out a row the bar holds, so a new split of the bar is news to it.
        var rows := custom_title_bar.rows if custom_title_bar != null else null
        if rows != null and not rows.refitted.is_connected(tool_options_docker.sync_from_tool):
            rows.refitted.connect(tool_options_docker.sync_from_tool)
        tool_options_docker.target_tool_machine = main_canvas.tool_machine
        add_child(SaSimulationPanel.new(registries, tool_options_docker))
        SaBootMarks.mark(&"tool_options_docker_bound")
        await _next_frame()


## The Window menu's docker rows and the stored layout, last, because a
## compositor reports placeholder geometry until every window is mapped.
func _boot_the_layout() -> void:
    dockers.setup_dockers_menu()
    SaBootMarks.mark(&"dockers_menu_built")
    dockers.load_docker_layout()
    SaBootMarks.mark(&"layout_restored")
    dockers.boot_finished()


## The ready mark and line, and the command line's document.
func _finish_the_boot() -> void:
    SaBootMarks.mark(&"ready")
    # first_frame_after_ready is never dispatched for, only read off a frame
    # that draws anyway, so it costs nothing under hard rule 2, dirty-rect dispatch only. Low-processor
    # mode can leave a quiet process with no redraw queued for as long as
    # nothing moves, in which case this one-shot simply never fires, and
    # SaBootMarks.table() omits the mark rather than reporting a zero. Guarded
    # like every other connection here, because a bound Callable is equal to an
    # earlier one that bound the same name, and a second boot in one process (a
    # test builds several) tried to connect a duplicate and errored.
    var first_frame_mark := SaBootMarks.mark.bind(&"first_frame_after_ready")
    if not RenderingServer.frame_post_draw.is_connected(first_frame_mark):
        RenderingServer.frame_post_draw.connect(first_frame_mark, CONNECT_ONE_SHOT)
    if not is_test_environment:
        SaConsole.ready(SaBootMarks.ready_line_ms(), SaBootMarks.summary())

    # A path on the command line, once every window is up and the File menu can
    # answer. Deferred out of _ready for the same reason the menus defer: this
    # opens a document and rebinds the canvas.
    #
    # Guarded. Unguarded, every offscreen gate run printed two of these from the
    # message queue, with no backtrace and so nothing naming the suite behind
    # them:
    #
    #     ERROR: Error calling deferred method: 'GDScript::open_requested':
    #     Cannot convert argument 1 from Object to Object.
    #
    # Two suites build a `Main`, call `_ready()` on it by hand and free it in the
    # same frame, and the call then fired on a node that had gone. The guard is
    # the answer rather than a check inside the opener, which is too late: the
    # queue converts the argument before the body runs.
    #
    # **A closure over the Main was tried instead and is worse.** GDScript prints
    # `Lambda capture at index 0 was freed. Passed "null" instead.` and passes
    # null, so it trades one always-there error for another. The opener was a
    # static handed the Main then, and a method of the Main is the one deferred
    # form the message queue drops in silence once the object has gone. The
    # guard stays, because a suite's Main has nothing to open and the decision
    # is what `ui/main/tests/test_deferred_open.gd` pins.
    if should_open_the_command_line(self):
        _after_the_cover(_open_command_line_document)


## The screenshot and state harness and the door, once the boot has finished,
## or nothing unless `--capture` or `--agent-socket` was passed after `--`.
func _start_the_capture(ds_name: String) -> void:
    var capture := SaCapture.from_command_line()
    if capture != null:
        add_child(capture)
        # Pointless when the launch wrapper has already filtered them out.
        if ds_name.to_lower() == "wayland" and not OS.has_environment("SARA_WARNINGS_FILTERED"):
            SaConsole.notice("2 expected GNOME/Wayland warnings")
        SaConsole.blank()


## Modules > Local Server, whose door is the capture harness's, as at boot.
func _on_local_server_requested() -> void:
    SaCapture.flip_the_local_server(self)


## Whether a `Main` is one the command line's document should be opened into.
##
## A `Main` that is not in a tree is a `Main` a test built and called `_ready` on
## by hand, which `ui/dockers/tests/test_ui_components.gd` does twice and
## `ui/notes/tests/test_note_mode.gd` does once. There is no window to open a document
## into and no user argument to read in a suite, so the deferred call had nothing
## to do and only something to go wrong: both suites free their `Main` in the
## same frame, and the call then fired on an object that had gone.
##
## Named and public rather than inline, because "the run is quiet" cannot be
## asserted from inside GDScript, and this is the decision behind it that can.
##
## It asks one question and not two. `is_instance_valid` was in here as well and
## came out: a freed instance cannot reach a `Node` parameter at all, so the call
## fails on the same argument conversion the defect is about, one frame earlier.
static func should_open_the_command_line(main: Node) -> bool:
    return main.is_inside_tree()


## Opens what the command line asked for, once the window is up, each path in
## a tab of its own.
##
## Through the document flow's own `open_path`, so a `.sad` goes through the
## loader and an image through the import, and those a later start hands over
## open the same way, behaving as when a painter picks the file from the dialog.
func _open_command_line_document() -> void:
    SaSingleInstance.serve(get_tree(), _files.open_path, SaBoot.document_paths(OS.get_cmdline_user_args()))


## Moves a pinned blend mode saved under a former id onto the id it is
## registered under now, once every module has registered.
##
## The favourites are the second store of mode ids after a `.sad`, and
## `BlendModeButton` skips one the registry does not hold, so a mode pinned
## under a former id would leave the block without a word. Written back only when the
## list actually moves, so an ordinary boot writes no setting.
static func _canonicalize_blend_favourites(registry: SaBlendModeRegistry) -> void:
    if registry == null:
        return
    var current: Array = registry.canonical_list(SaSettings.blend_favorites)
    if current != SaSettings.blend_favorites:
        SaSettings.blend_favorites = current


## Builds the registries, registers the skeleton's own built-ins through the
## public API, loads modules, then instantiates each surface's tools.
##
## Order matters: every module registers before any docker exists, so a docker
## such as the toolbox reads the registry rather than hardcoding its buttons.
##
## Three stages, a frame apart: the registrations, the surfaces bound to what
## was registered, and the router's own commands.
func _bootstrap_modules() -> void:
    await _wait_for_the_module_scripts()
    hold_document(main_canvas.get("surface") as SaSurface if main_canvas != null else null)
    var ctx: SaContext = registries.build_context(documents.front_easel, list_surfaces, SaAppDrive.new(get_tool_machine))
    var skeleton_began := Time.get_ticks_usec()
    registries.register_builtins()
    SaBootMarks.add_work(&"skeleton", skeleton_began)
    SaBootMarks.mark(&"builtins_registered")
    # Preferences, the two adjustments and the two dockers that shipped without
    # a chord. Registered before the Dockers menu is built, because that menu
    # reads each docker's action out of the InputMap and the registry is what
    # creates it.
    SaAppCommands.register_all(registries, dockers.toggle_docker_by_id, get_tool_machine, dockers.summon_docker_by_id)
    if document_tabs != null:
        document_tabs.register_commands(registries)
    SaBootMarks.mark(&"app_commands_registered")

    var compositor: SaCompositor = get_compositor()
    if compositor != null:
        compositor.set_registry(registries.blend_modes)
        compositor.filter_chain.registry = registries.filters

    ModuleLoader.load_and_register_modules(ctx)
    SaBootMarks.mark(&"modules_registered")
    await _next_frame()
    # The modules connected to the bus just now, and the pair was set before
    # they existed, so they would paint with their own default until a pick.
    SaColors.announce()

    # A module may have registered dockers. Build their windows now, and keep
    # building for anything registered after startup, which the dockers do on
    # the registry's own signal.
    dockers.instantiate_registered_dockers()

    report_registry_problems(registries)

    # A frame between the two, because each builds its surface and binds a
    # tool machine, a few hundred milliseconds together.
    for surface_host: Node in _surface_hosts():
        surface_host.bind_tools(registries.tools, registries.roles, registries.pens)
        await _next_frame()
    SaBootMarks.mark(&"tools_bound")
    await _wire_the_tool_options()

    # UI is built from the registries, not from hardcoded lists.
    if toolbox_docker != null and toolbox_docker.has_method("rebuild_from_registry"):
        toolbox_docker.rebuild_from_registry(registries.tools)
    # The stored shortcut profile is laid over the shipped map here, before the
    # File menu's commands register, so it may make an action whose command then
    # records the shipped chords. Nothing has read a chord yet, and the menus and
    # the toolbox follow a later rebind through the bus.
    SaShortcutStore.apply_active()
    if not EventBus.shortcuts_changed.is_connected(_on_shortcuts_changed):
        EventBus.shortcuts_changed.connect(_on_shortcuts_changed)
    if tool_options_bar != null:
        tool_options_bar.bind_registries(registries.blend_modes)
    var options_docker: Window = dockers.registered_docker_node(SaDockerIds.TOOL_OPTIONS)
    if options_docker != null and options_docker.has_method("bind_registries"):
        options_docker.bind_registries(registries.blend_modes)
    # The layers docker takes the layer types too, because its add button offers
    # them. Passed rather than stored on the document: every easel owns its own
    # document, so state bound once at startup would reach the first and miss
    # the scratchpad's and the secondary workspace's.
    if layers_docker != null and layers_docker.has_method("bind_registries"):
        layers_docker.bind_registries(registries.blend_modes, registries.layer_types)
    # A.sad records which type a layer is, not the Callable that resolves it.
    if not EventBus.document_loaded.is_connected(_on_document_loaded):
        EventBus.document_loaded.connect(_on_document_loaded)
    # The Modules menu lists what a module registered, so it needs the registry
    # rather than a list of built-ins. It subscribes to the registry's own
    # `changed`, which is what makes a module loaded later still appear.
    if custom_title_bar != null:
        custom_title_bar.bind_commands(registries.commands, dockers.toggle_all_dockers)
    if context_menu != null:
        context_menu.commands = registries.commands
    # Not an assignment: binding also puts the router's own view, interface and
    # clipboard chords into the registry, where the shortcuts dialog can list
    # them and an editor can change them, and hands them the view modes the
    # proof chords flip.
    #
    # Marked, because this stretch to `modules_bootstrapped` is where a slow
    # boot hides: every command it registers emits the registry's `changed`,
    # and every menu bound above would repopulate on each one. In one batch, so
    # they repopulate once.
    await _next_frame()
    SaBootMarks.mark(&"router_commands_begin")
    registries.commands.batch(_shortcut_router.bind_commands.bind(registries.commands, registries.view_transforms))
    # The view transforms: the menu lists them and the canvas applies them.
    var view_menu: SaViewMenu = custom_title_bar.menu("View") if custom_title_bar != null else null
    if view_menu != null:
        view_menu.view_transforms = registries.view_transforms
    var canvas: SaCanvas = get_canvas()
    if canvas != null:
        canvas.bind_view_transforms(registries.view_transforms)


## Frames go by until the worker `SaBoot` handed the modules' scripts to has
## loaded them, at most `MODULE_SCRIPT_FRAMES` of them.
##
## The modules stage collects each script from its threaded request, and a
## collect waits for the worker, and a module's script can still be loading
## when the stage begins. Waited out here a frame at a time, the welcome window
## keeps drawing, and a script that never finishes is collected after the cap.
func _wait_for_the_module_scripts() -> void:
    if not is_inside_tree():
        return
    var frames := 0
    for script_path in ModuleLoader.packaged_script_paths():
        while (
            frames < MODULE_SCRIPT_FRAMES
            and ResourceLoader.load_threaded_get_status(script_path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS
        ):
            await _next_frame()
            frames += 1
    SaBootMarks.mark(&"module_scripts_loaded")


## Every blend mode and layer type that names a kernel its shader lacks, reported
## where a painter sees it, and answered for a test.
##
## Through `SaProblems.report` rather than `push_error`, a line in a terminal
## the painter is not looking at, because a module whose mode names `hardmix`
## where its kernel is `hard_mix` boots to a layer that composites as Normal.
## `SaProblems.report` writes the same line to the log and keeps it for the
## problems window the main window attaches a moment later. A
## fault rather than a refusal, because nothing the painter did caused it and the
## line is the one a bug report needs.
static func report_registry_problems(registries_to_check: SaRegistries) -> Array[String]:
    var problems: Array[String] = registries_to_check.validate() if registries_to_check != null else ([] as Array[String])
    for problem: String in problems:
        # A static has no `self` to reach `tr` through. The sentence around the
        # registry's own is what a translator gets, and the ids, kernel and
        # shader inside it are names that stay as they are.
        SaProblems.report(
            "SaRegistries", TranslationServer.translate("A module names something that does not exist: %s") % problem
        )
    return problems


## Godot reports no notification when a window is dragged to a monitor of
## another scale, so a follower polls once a second and hands every window to
## `SaUI.apply_to_window`, the one writer. A child of the app rather than a step
## of the boot, because it outlives the boot and is not part of building the
## interface.
func _follow_the_screens() -> void:
    add_child(SaUI.ScreenFollower.new())


## The canvas fitted the document before the top bar and the window had their
## sizes, so the fit is taken again until they have. Not in a
## suite's `Main`, which is never in a tree, nor under a headless display server,
## where the boot builds no canvas.
func _hold_the_boot_fit() -> void:
    if not is_inside_tree() or main_canvas == null or custom_title_bar == null:
        return
    var canvas: SaCanvas = main_canvas.canvas
    var surface: SaSurface = main_canvas.surface
    if canvas == null or surface == null:
        return
    var covers: Array[Control] = [custom_title_bar, status_line]
    add_child(SaBootFit.new(canvas, surface.view, covers, get_window()))


func _on_ui_scale_changed(_effective_scale: float) -> void:
    # SaUI.apply_to_window is the single writer of content_scale_factor. Handlers
    # never assign it themselves, or the scale ends up applied more than once.
    if get_tree():
        SaUI.apply_to_window(get_tree().root)
    DockerUtils.apply_ui_theme(custom_title_bar)
    DockerUtils.apply_ui_theme(tool_options_bar)


## Text changed size and nothing else did, so only the theme pass runs. The root
## window is untouched, because content_scale_factor did not move.
func _on_ui_font_scale_changed(_font_scale: float) -> void:
    DockerUtils.apply_ui_theme(custom_title_bar)
    DockerUtils.apply_ui_theme(tool_options_bar)


## A secondary workspace is a host for dockers, so it is parented where the
## dockers are.
func _on_secondary_workspace_requested() -> void:
    _workspace_controller.create_secondary_workspace(dockers)


func _on_docker_reparent_requested(docker_name: String, target_host: Node) -> void:
    _workspace_controller.reparent_dockers(dockers.get_docker_config(), docker_name, target_host, dockers)


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        for factory in _added_overlays:
            SaCanvas.remove_overlay_factory(factory)
        for factory in _added_surface_overlays:
            SaCanvas.remove_surface_overlay_factory(factory)
        return
    # The layout is deliberately not saved on EXIT_TREE or PREDELETE. A
    # docker's geometry is measured in logical units while it is embedded and
    # in physical pixels when it is not, and is_embedded() flips to false
    # during teardown while the window still reports its logical size. Saving
    # then normalised every value by the display scale a second time, so the
    # whole layout was halved on every exit and shrank run after run until it
    # hit the minimum-size floor. Every user change already saves through
    # docker_layout_changed, so these two added nothing but that corruption.
    if not _booted:
        # Half built, so a close quits without asking and no layout is saved.
        if what == NOTIFICATION_WM_CLOSE_REQUEST:
            SaTrail.hand_over(get_tree(), "closed before the boot finished, quit called")
        return
    if (
        what == NOTIFICATION_WM_CLOSE_REQUEST
        or what == NOTIFICATION_APPLICATION_PAUSED
        or what == NOTIFICATION_APPLICATION_FOCUS_OUT
        or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT
    ):
        dockers.layout_store.save()

    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        _request_quit("the window asked to close, and the docker layout is saved")

    if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
        var tm := get_tool_machine()
        if tm and tm.active_tool and tm.active_tool.has_method("release_all_keys"):
            tm.active_tool.release_all_keys()


## A File menu chord pressed anywhere in the app does what the row it names
## does.
func _on_file_shortcut(action: StringName) -> void:
    _files.run_action(action)


## Quits once the document flow has asked about unsaved work, `why` opening the quit's trail.
## Every way out ends here: Ctrl+Q, and the bar's and the window manager's close requests.
## The question is about every open document with unsaved work, not the front
## one alone, which is why the flow is asked rather than told a document.
func _request_quit(why := "quit asked") -> void:
    if not is_inside_tree():
        return
    # Before the question and anything torn down, so the picture is the window
    # the painter left. Off in Preferences, it writes nothing and removes one.
    SaBootCover.keep_the_session(get_viewport(), last_session_path, SaSettings.show_last_session)
    SaTrail.stage(why)
    _files.confirm_quit(_quit_now)


## A quit the painter chose, so the recovery copy has done its job.
func _quit_now() -> void:
    SaTheme.save_unsaved()
    if autosaves != null or autosave != null:
        if autosaves != null:
            autosaves.discard_all()
        if autosave != null:
            autosave.discard_recovery()
        SaTrail.stage("the recovery copy removed")
    SaTrail.hand_over(get_tree(), "quit called", not is_test_environment)


## Starts the autosave on the main document, and after the window is up asks
## about any recovery copy a previous session left behind, when *surface* is the
## chain rather than the welcome window's row. Not in a test, which builds a Main
## without a window and must not be asked anything.
func _start_autosave(surface: String) -> void:
    var canvas := get_canvas()
    if canvas == null or canvas.document == null:
        return
    autosave = _autosaves().attach(canvas.document)
    if surface == "chain" and not is_test_environment and is_inside_tree():
        _after_the_cover(autosave.offer_recoveries.bind(SaSettings.recent_files()))


## Opens *surface* as a document: held among the documents, and its autosave
## started.
func hold_document(surface: SaSurface) -> void:
    if documents.add(surface) and surface.get_document() != null:
        _autosaves().attach(surface.get_document())


## Closes *surface*'s document: let go of, its autosave stopped and its recovery
## copy removed, the other documents' kept.
func close_document(surface: SaSurface) -> void:
    if documents.remove(surface) and autosaves != null and surface.get_document() != null:
        autosaves.detach(surface.get_document())


func _autosaves() -> SaAutosave.PerDocument:
    if autosaves == null:
        autosaves = SaAutosave.PerDocument.new()
        add_child(autosaves)
    return autosaves


## Re-attaches every loaded layer's resolve hook from its recorded type id, and
## moves a layer saved under a blend mode's former id onto its current one.
##
## A layer whose type is not registered, because the module owning it is not
## installed, keeps its fields and its id and simply does not resolve. Losing a
## collaborator's layer because you had not installed their module would be worse
## than opening it inert.
func _on_document_loaded(document: SaDocument) -> void:
    if document == null:
        return
    SaBootMarks.mark(&"document_loaded")
    var layers: Array = document.get_children().filter(func(child: Node) -> bool: return child is SaLayer)
    registries.layer_types.rebind(layers)
    # And a mode saved under the id it carried before a rename, for the same
    # reason: the file records an id and the registry is what answers for it.
    registries.blend_modes.rebind(layers)


## Every paintable surface host (the main canvas, and the scratchpad when built).
func _surface_hosts() -> Array:
    var hosts: Array = []
    if main_canvas != null and main_canvas.has_method("bind_tools"):
        hosts.append(main_canvas)
    if info_docker != null and info_docker.has_method("bind_tools"):
        hosts.append(info_docker)
    return hosts


## A chord moved, so every surface that prints one says it again.
##
## One emit covers the menus, because each is built from the command registry
## and rebuilds when it announces a change. The toolbox needs nothing: it
## re-reads the InputMap on every hover, so its tooltips are already right.
func _on_shortcuts_changed() -> void:
    if registries != null and registries.commands != null:
        registries.commands.changed.emit()


## SaContext.list_surfaces(): the open documents', then the scratchpad's.
func list_surfaces() -> Array:
    var surfaces: Array = documents.surfaces.duplicate()
    for surface_host: Node in _surface_hosts():
        if surface_host.surface != null and not surfaces.has(surface_host.surface):
            surfaces.append(surface_host.surface)
    return surfaces


func get_tool_machine() -> ToolMachine:
    _ensure_children_initialized()
    var front := documents.front.tool_machine as ToolMachine if documents.front != null else null
    return front if front != null else (main_canvas.tool_machine if main_canvas else null)


## The front surface's canvas, and the main canvas's before any is held.
func get_canvas() -> SaCanvas:
    _ensure_children_initialized()
    var front := SaCanvasView.canvas_of(documents.front)
    return front if front != null else (main_canvas.canvas if main_canvas else null)


func get_compositor() -> SaCompositor:
    var c := get_canvas()
    return c.compositor if c else null


## Handles shortcuts when main window is focused
func _unhandled_input(event: InputEvent) -> void:
    _shortcut_router.handle_viewport_input(event, get_viewport())
