## The main scene's root, and the first stages of the boot: the window and the
## welcome window on screen, then the kernels and the main script behind them.
##
## The script of `Main` names nearly every class Sara has, and Godot loads a
## script with every class it names, so a scene rooted on `Main` would show
## nothing until that whole graph and the kernels had loaded. This node names
## none of that. It puts the welcome window up when the boot should
## show one, lets a frame draw it, and then loads `main.gd` on a worker thread
## while it compiles the kernels here a slice a frame, so the window keeps
## answering. `Main` is built once both are done, joins the root beside this
## node, takes the current scene and runs the rest of the boot in stages of
## its own, ending on `EventBus.boot_finished`.
##
## A welcome window this node built stays its child. `Main` is handed it and
## its `MainDialogs` shows that one again from Help rather than a second.
##
## Under a headless display server nothing is built, the way `Main` built
## nothing there, because the first GPU call would crash.
class_name SaBoot
extends Node

## The script this node loads by path. Naming `Main` here would load its whole
## graph with this one, which is the wait this node exists to take off screen.
const MAIN_PATH := "res://ui/main/main.gd"

## By path, so a first run after the file lands needs no class rescan, which
## the main scene's root cannot wait for.
const AgentInvite := preload("res://ui/boot/sa_agent_invite.gd")
const BackgroundStart := preload("res://ui/boot/sa_background_start.gd")

## How long one frame's share of the kernels stage may run, in microseconds.
## A slice is a handful of kernels, and a click on the welcome window waits at
## most that long.
const KERNEL_SLICE_USEC := 70000

## The user argument that prints the version and quits.
const VERSION_FLAG := "--version"

## The welcome window, or null when the boot shows none.
var _welcome: SaWelcomeWindow = null


## The worker task the boot started is collected before the tree goes, so the
## pool holds no lambda of Sara's for the engine's teardown to free late.
func _exit_tree() -> void:
    SaCardMemory.finish_aside()


func _ready() -> void:
    SaBootMarks.mark(&"boot_scene_ready")
    # First of all, so nothing is built or printed for a painter who only asked
    # which Sara this is. The launch wrapper adds `--headless` for the same
    # flag, since the window is already open by the time this runs.
    if version_requested(OS.get_cmdline_user_args()):
        print(SaBuildInfo.version_line(SaBuildInfo.read()))
        get_tree().quit()
        return
    # Before the headless return, since an agent asking for the paragraph is as
    # likely to pass `--headless` as not, and before anything is built.
    if AgentInvite.answer_help_flag(OS.get_cmdline_user_args(), get_tree()):
        return
    # The launch wrapper's windowless run, so before the headless return.
    if OS.get_cmdline_user_args().has(SaSingleInstance.HAND_OVER_FLAG):
        var went := SaSingleInstance.handed(OS.get_cmdline_user_args(), document_paths(OS.get_cmdline_user_args(), false))
        get_tree().quit(0 if went else SaSingleInstance.NOT_HANDED)
        return
    if DisplayServer.get_name() == "headless":
        return
    # Before anything is built, so a second start with files hands them over
    # and quits on its first frame.
    if SaSingleInstance.start(OS.get_cmdline_user_args(), document_paths(OS.get_cmdline_user_args(), false), get_tree()):
        get_tree().quit()
        return
    # The autoload has already sent the window of a Sara a notebook started to
    # the taskbar, and this boot must not bring anything forward over it.
    var kept_back: bool = BackgroundStart.asks(OS.get_cmdline_user_args())["minimised"]
    # On a worker while the boot runs, so the first stroke's release does not
    # wait for `nvidia-smi`.
    SaCardMemory.read_aside()
    # Here and not in the cursor package, because only the app's own boot is
    # sure the pen it hears is the painter's.
    SaCursorPolicy.pen_carries_system_pointer = true
    # Before the first window is built, the welcome window included.
    get_viewport().gui_embed_subwindows = SaSettings.embed_subwindows
    var theme_began := Time.get_ticks_usec()
    SaUI.init_global_theme(get_tree())
    SaBootMarks.add_work(&"themes and fonts", theme_began)
    SaScrollPace.install(get_tree())
    SaScrollJump.install(get_tree())
    SaDragScroll.install(get_tree(), func(scroll: ScrollContainer) -> bool: return scroll.get_window() is DockerWindow)
    var args := OS.get_cmdline_user_args()
    # Timed when nothing is built too, so the table says a start that showed no
    # welcome window spent nothing on its picture rather than leaving it out.
    var welcome_began := Time.get_ticks_usec()
    # A welcome window takes the keyboard, which a Sara kept back must not.
    var quiet := capture_requested(args) or kept_back
    if SaWelcomeWindow.wanted_at_start(SaSettings.welcome_at_start, document_path(args), quiet, false):
        _welcome = SaWelcomeWindow.new(true, not SaSettings.first_launch_done)
        put_up(_welcome, self)
    SaBootMarks.add_work(&"welcome picture", welcome_began)
    EventBus.boot_finished.connect(SaLightModeOffer.at_start.bind(self, _welcome, capture_requested(args)), CONNECT_ONE_SHOT)
    # Read off a frame that draws anyway, so it costs nothing and dispatches no full-canvas pass.
    RenderingServer.frame_post_draw.connect(SaBootMarks.mark.bind(&"first_frame"), CONNECT_ONE_SHOT)
    get_tree().process_frame.connect(SaBootMarks.boot_frame)
    EventBus.boot_finished.connect(get_tree().process_frame.disconnect.bind(SaBootMarks.boot_frame), CONNECT_ONE_SHOT)
    # A worker thread, not sub-threads: one thread compiling scripts in the order
    # the graph asks for them is the case Godot's script cache is built for.
    ResourceLoader.load_threaded_request(MAIN_PATH, "", false)
    # The modules' scripts beside it, which the modules stage would otherwise
    # load on this thread while the welcome window stood still.
    for module_script in ModuleLoader.wanted_script_paths(SaSettings.modules_off):
        ResourceLoader.load_threaded_request(module_script, "", false)
    _boot_behind_the_window()


## Adds *window* to *parent* hidden and shows it once, centred on the main
## window, which it follows while the main window takes its size. A `Window`
## joins the tree visible, so with subwindows off the OS window would be made
## and shown at the screen's top left, blank, until `popup_centered` moved it.
static func put_up(window: SaWelcomeWindow, parent: Node) -> void:
    window.visible = false
    parent.add_child(window)
    window.open()


## The kernels and the main script, and then `Main`. The first frame draws
## between the two waits at the top: a frame is processed before it is drawn,
## so one wait would put the first slice of kernels in front of it.
func _boot_behind_the_window() -> void:
    var tree := get_tree()
    await tree.process_frame
    await tree.process_frame
    while not GlobalShaderCompiler.compile_kernels(KERNEL_SLICE_USEC):
        await tree.process_frame
    SaBootMarks.mark(&"kernels_stage_done")
    var main_script: Script = null
    while main_script == null:
        main_script = _main_script()
        if main_script == null:
            await tree.process_frame
    SaBootMarks.mark(&"main_script_loaded")
    var main: Node = main_script.new(_welcome)
    # The name every node path under `Main` is written against.
    main.name = "MainRoot"
    tree.root.add_child(main)


## The main script once the worker has it, or null while it is still loading.
## A threaded load that failed is loaded again here, on this thread, so a boot
## never waits on a request that will not finish.
static func _main_script() -> Script:
    var status := ResourceLoader.load_threaded_get_status(MAIN_PATH)
    if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
        return null
    if status == ResourceLoader.THREAD_LOAD_LOADED:
        return ResourceLoader.load_threaded_get(MAIN_PATH) as Script
    push_warning("SaBoot: the threaded load of %s answered %d, loading it here." % [MAIN_PATH, status])
    return load(MAIN_PATH) as Script


## Whether *args* hold `--version`. Anywhere among them, since a path beside it
## changes nothing about the question, and nothing else answers to the flag: a
## path alone, or an option that merely begins the same way, does not ask.
static func version_requested(args: PackedStringArray) -> bool:
    return args.has(VERSION_FLAG)


## Whether the command line asked for a capture run or a door session. The
## capture harness reads the same arguments for what they say, and this is the
## boot's question alone: naming `SaCapture` to ask it would load the harness,
## most of the classes this node exists not to load.
static func capture_requested(args: PackedStringArray) -> bool:
    for arg: String in args:
        if arg == "--capture" or arg.begins_with("--capture="):
            return true
        # The door a painter's own Sara opens for a client to attach to, with
        # the known file as its port file.
        if arg == "--agent-door":
            return true
        # Either way in to the door, the Unix socket or the port file of the
        # TCP one, and neither when its value is empty.
        for door_arg: String in ["--agent-socket=", "--agent-port-file="]:
            if arg.begins_with(door_arg) and arg.length() > door_arg.length():
                return true
    return false


## The first user argument that names a file, or an empty string. What the
## welcome window asks to know whether a file was asked for at all.
##
## A file manager's "Open with" and `sara file.sad` from a terminal both
## arrive here, because the launch wrapper puts everything the user typed after
## `--` and Godot then hands it over as user arguments rather than reading it
## as an engine flag. The parsing is separate from the opening so a test can
## feed it a list: a test cannot start a process, and the bug this fixed was in
## the parsing rather than in the loading, which already worked from the File
## menu. Here rather than on `Main` because the boot asks
## it before `Main` is loaded, to know whether the welcome window opens.
##
## Anything beginning with a dash is an option, not a path: `--capture` and its
## friends go past untouched. A path that is not there is reported rather than
## ignored, because a typo at a terminal otherwise opens an empty canvas and
## says nothing.
static func document_path(args: PackedStringArray) -> String:
    var paths := document_paths(args)
    return paths[0] if not paths.is_empty() else ""


## Every user argument that names a file, in the order typed, each of which
## opens in a tab of its own. A path that is not there is reported and left
## out, and the others still open. *report* false leaves the report to the
## later call that opens them.
static func document_paths(args: PackedStringArray, report: bool = true) -> PackedStringArray:
    var paths := PackedStringArray()
    for arg: String in args:
        if arg.begins_with("-") or arg.is_empty():
            continue
        if FileAccess.file_exists(arg):
            paths.append(arg)
        elif report:
            SaProblems.report("Sara", "There is no file at '%s', so it was not opened." % arg)
    return paths
