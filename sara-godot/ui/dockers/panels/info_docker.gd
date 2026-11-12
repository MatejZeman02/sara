## The Info docker: live counters, in sections that fit the docker's width.
##
## The GPU numbers are dispatches and workgroups per tick rather than
## cumulative, because a running total says nothing about whether the stroke
## you just made was expensive.
##
## The sections are cells of an `HFlowContainer` rather than one column of
## lines, so two sit side by side at the default width and one when the docker
## is narrow, the numbers stay on screen at an ordinary docker width, and the
## handle is a bar across the top like everywhere else.
##
## Each section is an [SaInfoSection], which holds its rows and the code that
## fills them, and a view of each is registered through the door, so a section
## placed in another docker reads what this one would and keeps reading it
## while this docker is closed.
##
## The panel's Preferences have a row per section, Selected colours among them,
## the foreground and background pair a painter is working with.
##
## The document comes first, then its colour space, the active layer and the
## selected colours, which are what a painter checks a file against. The
## engine's numbers, Build, Input, History and GPU, sit under one Diagnostics
## fold that opens closed, one press away for whoever measures a stroke, because
## a panel that opens on the build and the input reads as a developer's page and
## at its default size fits only four of its eight sections. The fold is
## Diagnostics rather than Performance, because it holds the build and the
## pointer as well as the engine's counters.
##
## Build leads the fold: the version, the commit and the export date the banner
## prints at start. Its rows are written once, when the section is built,
## because nothing about a running build changes, and so the section stands
## with no document open, where every other section has nothing to say.
@tool
extends DockerWindow

class_name InfoDocker

## Section title -> the row keys under it, in the order they are drawn. The one
## declaration: `_build_sections()` makes the sections from this, and a view of
## one placed in another docker is built from it too, each section filling its
## rows by the same keys. Each title is also the docker's layout element in
## Preferences, so a title here and the string in
## `SaSettingsLayout.DEFAULT_ORDERS` are the same word or the page offers a row
## for a section that is not there. `test_info_docker` fails when they drift.
const SECTIONS: Array = [
    ["Document", ["Name", "Size", "Depth", "VRAM", "VRAM all", "Layers", "Tiles", "Focus mode"]],
    ["Colour space", ["Space", "Gamut", "Declared", "Transfer", "Depth", "White", "Red", "Green", "Blue"]],
    ["Active layer", ["Name", "Blend", "Opacity", "Locked"]],
    ["Selected colours", ["Foreground", "FG value", "FG stops", "FG alpha", "Background", "BG value", "BG stops", "BG alpha"]],
    ["Build", ["Version", "Commit", "Built"]],
    ["Input", ["Pressure", "Device", "Tool"]],
    ["History", ["Steps", "Paint", "Layer pool", "Widest step", "Dropped"]],
    ["GPU", ["Dispatches", "Lists", "Uniform sets", "Workgroups", "Session", "Composite", SaInfoSection.RECENT_MEAN, "FPS"]],
]

## The words a row is shown under, kept with the section that shows them.
const ROW_TITLES := SaInfoSection.ROW_TITLES

## The sections drawn inside the Diagnostics fold rather than above it: the
## build, the pointer and what the engine spent, which a painter reads to file a
## note or measure a stroke and not while painting. Moving one of them in
## Preferences moves it among these four, and the rest among the others.
const PERFORMANCE_SECTIONS: Array[String] = ["Build", "Input", "History", "GPU"]

## What the docker opens at, matching its row in `docker_layout_default.cfg` and
## in every shipped layout but Default, whose two files close it shorter so that
## the Stats docker closed under it has its room. Its height holds the four
## sections above the fold with the fold closed. An open fold scrolls
## rather than growing the panel, because a panel taller than this is one
## nobody keeps open.
const DEFAULT_SIZE := Vector2i(500, 520)

## The sections above the fold.
var stats_flow: HFlowContainer

## The fold the engine's sections sit in, closed when the docker is built, and
## the flow inside it that lays them out the way `stats_flow` lays out the rest.
var performance_fold: FoldableContainer
var performance_flow: HFlowContainer

## The last three pop-up messages, at the foot under the fold.
var messages: SaInfoMessages

var target_canvas: SaCanvas
var target_tool_machine: ToolMachine

## Section title -> its [SaInfoSection], which holds the section's rows and
## fills them.
var _section_boxes: Dictionary[String, SaInfoSection] = {}

var _update_timer: Timer


func _init() -> void:
    _init_docker(SaDockerIds.INFO, "Info", DEFAULT_SIZE, Vector2i(200, 160))

    var vbox := SaMake.column(_control_node, "VBoxContainer")
    vbox.set_anchors_preset(Control.PRESET_FULL_RECT)

    drag_handle = DockerUtils.make_drag_bar("Info")
    vbox.add_child(drag_handle)

    var margin := SaMake.margin(vbox, "MarginContainer", SaUI.BASE_MARGIN)
    margin.size_flags_vertical = Control.SIZE_EXPAND_FILL

    # Scrolled, because eight sections at one column is taller than any docker
    # anybody would keep open, and the alternative is a cut line.
    var scroll := SaMake.scroll(margin, "ScrollContainer")
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

    var body := SaMake.column(scroll, "Body")
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    stats_flow = HFlowContainer.new()
    stats_flow.name = "StatsFlow"
    stats_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_child(stats_flow)
    stats_flow.unique_name_in_owner = true
    stats_flow.owner = self

    # The engine's own fold, the one About keeps its licences in, so the press
    # that opens it and the arrow that says so are the ones a painter has met.
    performance_fold = FoldableContainer.new()
    performance_fold.name = "PerformanceFold"
    performance_fold.title = tr("Diagnostics")
    performance_fold.folded = true
    performance_fold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_child(performance_fold)

    performance_flow = HFlowContainer.new()
    performance_flow.name = "PerformanceFlow"
    performance_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    performance_fold.add_child(performance_flow)

    messages = SaInfoMessages.new()
    body.add_child(messages)

    _build_sections()
    _register_views(weakref(self))


## One [SaInfoSection] per declared section, in the fold when it is one of the
## engine's. Each obeys the docker's own switch for it in Preferences.
func _build_sections() -> void:
    for entry: Array in SECTIONS:
        var section: String = entry[0]
        var flow := performance_flow if PERFORMANCE_SECTIONS.has(section) else stats_flow
        var box := SaInfoSection.new(section, entry[1], SaDockerIds.INFO)
        flow.add_child(box)
        _section_boxes[section] = box


## Each section made an element another docker can hold: a view of it, built by [method SaInfoSection.view], is registered
## through `SaSettings.register_layout_element`, the call a module makes (hard
## rule 6). A view reads the canvas and the tool machine main handed *home*, the
## docker held weakly, so a view built before main wires the docker takes them
## when it does, the door keeps no docker a suite has freed alive, and a view of
## a docker that is gone shows nothing. A docker built again registers again,
## its views replacing the last one's.
##
## Static, so the builders hold no docker of their own, and untyped, because a
## cast to this file's own `class_name` inside a static function leaks the
## script at exit.
static func _register_views(home: WeakRef) -> void:
    var sources := func() -> Array:
        var docker: Object = home.get_ref()
        return [] if docker == null else [docker.get(&"target_canvas"), docker.get(&"target_tool_machine")]
    for entry: Array in SECTIONS:
        var section: String = entry[0]
        var keys: Array = entry[1]
        var builder := func() -> Control: return SaInfoSection.view(section, keys, sources)
        SaSettings.register_layout_element(SaDockerIds.INFO, section, section, false, "", builder)


func _ready() -> void:
    assert(drag_handle != null, "DragHandle node not found")
    assert(stats_flow != null, "StatsFlow node not found")

    _setup_docker_ready()

    # Ten times a second through a Timer rather than every frame in _process:
    # nothing here is worth a frame's work and the panel is often not visible.
    #
    # **And it stops while the panel is hidden**, rather than `autostart`
    # running it for good. A closed docker, which the default layout keeps
    # closed and which is still in the tree, would otherwise format twenty
    # strings a tick for nobody, and the moment a GPU counter moved the tick
    # would write a new number into a hidden label and the engine would draw a
    # frame of a window nobody sees, then another when the delta went back to
    # zero. `visibility_changed` is the same shape `brush_editor_window.gd` runs its
    # own ticker by.
    _update_timer = Timer.new()
    _update_timer.name = "UpdateTimer"
    _update_timer.wait_time = SaInfoSection.TICK
    _update_timer.timeout.connect(_update_stats)
    add_child(_update_timer)
    if not visibility_changed.is_connected(_follow_visibility):
        visibility_changed.connect(_follow_visibility)
    _follow_visibility()

    if not SaSettings.profile_changed.is_connected(apply_layout_settings):
        SaSettings.profile_changed.connect(apply_layout_settings)
    apply_layout_settings()


## Each section is its own layout element, so the painter hides GPU and keeps
## Input rather than switching the whole panel off, and the order of the rows in
## Preferences is the order the sections are drawn in.
##
## The one "Telemetry Stats" element it replaces is renamed by the version 9
## migration, which carries a stored `false` onto every section so a panel
## somebody had switched off stays off.
func apply_layout_settings() -> void:
    apply_docker_base_layout(SaDockerIds.INFO)
    if drag_handle != null:
        drag_handle.visible = SaSettings.get_element_visible(SaDockerIds.INFO, "Drag Handle")
    if stats_flow == null:
        return
    # Moving to a strictly increasing index from the front is the one safe way
    # to reorder a run of children: everything before `at` is already placed, so
    # the box being moved is always at or after it, whatever the previous move
    # did to the indices. One index for each flow, because
    # a section is moved among its own flow's children and never across the fold.
    var at: Dictionary = {}
    var any_folded_shown := false
    for element: String in SaSettings.get_layout_order(SaDockerIds.INFO):
        var box: VBoxContainer = _section_boxes.get(element)
        if box == null:
            continue
        box.visible = SaSettings.get_element_visible(SaDockerIds.INFO, element)
        var flow := box.get_parent()
        var index: int = at.get(flow, 0)
        flow.move_child(box, index)
        at[flow] = index + 1
        if flow == performance_flow and box.visible:
            any_folded_shown = true
    # A fold whose four sections are all switched off would be a title over
    # nothing, which opens on an empty band.
    performance_fold.visible = any_folded_shown
    messages.visible = SaSettings.get_element_visible(SaDockerIds.INFO, SaInfoMessages.ELEMENT)


## The sections in the order they are drawn, each with the rows it is showing
## and the text in them. It is a claim about which sections exist and what the
## colour rows say, and a screenshot of a panel of small numbers cannot answer
## either.
##
## The fold's sections are reported closed or open, after the others and each
## marked `folded` with the fold's state, because a dump asks for the counters
## on purpose and a replay compares the GPU section's whether a painter could
## see it or not.
func section_report() -> Array:
    # A hidden docker's ticker is stopped, so its labels hold whatever
    # the last visible tick left. A dump asks for the counters on purpose, and
    # a scenario that closes this panel and then reads it would otherwise be
    # handed numbers from before it closed, so the rows are brought up to date
    # once here rather than left stale.
    if _update_timer != null and _update_timer.is_stopped():
        _update_stats()
    var out: Array = []
    for child in stats_flow.get_children() + performance_flow.get_children():
        var box := child as SaInfoSection
        if box == null or not box.visible:
            continue
        var rows: Dictionary = {}
        for key: String in box.rows:
            var row: Array = box.rows[key]
            if (row[1] as Label).visible:
                rows[key] = (row[1] as Label).text
        var entry := {"section": box.title, "rows": rows}
        if box.get_parent() == performance_flow:
            entry["folded"] = performance_fold.folded
        if box.fps_graph != null:
            entry["graph"] = box.fps_graph.report()
        out.append(entry)
    return out


## Feeds the FPS graph every frame while the docker is shown, and writes the
## FPS row when what it reads changed.
func _process(_delta: float) -> void:
    follow_frame(Time.get_ticks_usec(), Engine.get_frames_drawn(), OS.low_processor_usage_mode)


## One frame of the GPU section's FPS row and graph, with the clock, the
## drawn-frame count and the rest passed in so a suite can drive it.
func follow_frame(now_usec: int, frames_drawn: int, resting: bool) -> void:
    var gpu: SaInfoSection = _section_boxes.get("GPU")
    if gpu != null:
        gpu.follow_frame(now_usec, frames_drawn, resting)


## Fills every section from the canvas and the tool machine main handed the
## docker, each by the code a placed copy of it is filled by.
func _update_stats() -> void:
    for section: SaInfoSection in _section_boxes.values():
        section.fill(target_canvas, target_tool_machine)
    messages.refresh()


## Starts the ticker while the panel is shown and stops it while it is not.
##
## Called once from `_ready` as well as on every change, because a docker the
## saved layout opens hidden never emits `visibility_changed` and would
## otherwise keep the timer in whatever state it was built in.
func _follow_visibility() -> void:
    set_process(visible)
    if _update_timer == null:
        return
    if visible:
        if _update_timer.is_stopped():
            _update_timer.start()
        return
    _update_timer.stop()


## The Info docker's visible sections in the order they are drawn, each with the
## rows it is showing, for the state dump. Empty when the docker is not built.
## The docker answers with what it shows, and the harness adds its own marks.
##
## Untyped on purpose: a cast to this file's own `class_name` inside a static
## function leaks the script at exit.
static func capture_state(root: Window) -> Array:
    var docker := root.find_child(SaDockerIds.INFO, true, false)
    if docker == null or not docker.has_method("section_report"):
        return []
    return docker.call("section_report")


## The foreground and background as they are stored, with the headroom each has
## above the display's white. Hard rule 5 lets a colour sit above 1.0, and a hex
## or a screenshot cannot say by how much, so the numbers are here in full.
##
## `SaColors` is an autoload, so this answers whether the eyedropper read a
## value back unclamped even when the Info docker was never opened.
static func capture_selected_colours() -> Dictionary:
    var fore := SaColors.foreground
    var back := SaColors.background
    return {
        "foreground": [fore.r, fore.g, fore.b, fore.a],
        "foreground_stops": SaInfoSection.stops_above_white(fore),
        "background": [back.r, back.g, back.b, back.a],
        "background_stops": SaInfoSection.stops_above_white(back),
    }
