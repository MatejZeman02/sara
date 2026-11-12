## The Stats docker: numbers about the picture, computed only while the docker
## is open and its switch is on, with the time they were computed.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A docker of its own, friendly with the graph docker rather than a page of
## it.** The two share `SaReductions`, the one service that runs the graph's
## pass and these numbers on one schedule, and neither docker names the other.
##
## **A closed docker costs nothing, and an open one has a switch that turns the
## computing on.** Compute is off until the painter
## turns it on, for the session. While the docker is open with it on, every
## part's reduction and the docker's own run are registered with the service,
## and they are taken off when the docker closes or the switch goes off. The
## service runs them each time the idle clock says the painter has stopped, and
## at the graph docker's pace while that one is open.
##
## **The line under the switch says when the numbers were computed**, the clock
## time of the last run, so a painter who kept painting sees that the numbers
## are a minute old. It moves on a run and on nothing else, so with the switch off
## a stroke leaves it as it was. A clock time rather than an age, because an age
## would move by itself and say the numbers were new again when nothing ran.
##
## **The numbers join it from a list.** `stats_parts.gd` names the parts, each
## a file of its own in this folder that extends [SaStatsPart] and declares its
## rows and its reduction. This docker shows no number itself: it is the frame
## they join.
##
## **A declared page**, so the `pages` block of the state dump reads every row
## under `StatsPage`: the switch, the line, then each part's rows in the order
## of the list. It finds the canvas of the document in front itself, as the
## Recorder docker does, and hands it to each part with every refresh.
##
## **Registered by `module.gd` beside it**, through `SaContext.register_docker`,
## the call every module's docker makes (hard rule 6). No script of the
## skeleton names it, and the shipped layouts and a painter's saved one find it
## by the id below, which a saved layout holds, so the id is not free to
## change.
##
## **Each idle stop leaves one line of numbers in the session log** while the
## stroke recorder runs, so a painter
## can read how a picture's value range grew over an hour. The line is the
## recorder's kind `s`, written through `SaStrokeRecorder.running` once the
## numbers of that stop are in: every part row of the page by its key, as the
## dump reads its value and its title, so a number joins the line by joining the
## page. A run
## at the graph docker's pace writes none, or an open graph would fill the log
## at fifteen lines a second. While that pace runs, a stop asks for one more
## run and the line follows it.
@tool
class_name StatsDocker
extends DockerWindow

const Parts := preload("stats_parts.gd")

## The docker's id, the section `docker_layout.cfg` files its window under. A
## saved layout holds it, so it does not change.
const DOCKER_ID := &"StatsDocker"

## What its row in the Window menu says on hover.
const SENTENCE := "Numbers about the picture, computed when you stop painting once its switch is on."

## What the docker opens at. A column of rows, so taller than wide.
const DEFAULT_SIZE := Vector2i(280, 320)

## The name of the container the page is drawn into, which is the name the
## `pages` block of the state dump files it under.
const PAGE_NAME := "StatsPage"

## What the switch says under its title: when it computes, and that off means
## nothing at all. Short, because the switch takes the right of the row and the
## sentence wraps in what is left, and a longer one pushed the line under it
## out of a docker of the default size.
const SWITCH_SENTENCE := "On, the numbers are computed each time you stop painting. Off, nothing is."

## What the switch says on hover, the whole schedule.
const SWITCH_HOVER := (
    "Computes the numbers each time you stop painting for the Idle after time on the Performance page,"
    + " and as often as the Graph docker draws while it is open. Off, nothing is computed."
)

## Whether the numbers are computed, the switch's binding. Off until the
## painter turns it on, and kept while the session lasts.
var computing: bool = false:
    set(value):
        computing = value
        _follow_open()

## The clock time of the last run, empty before the first, and when it was by
## `Time.get_ticks_msec`, -1 before the first.
var computed_at: String = ""
var computed_msec: int = -1

## The parts the list names, one of each, in its order.
var parts: Array[SaStatsPart] = []

## The docker's own run, registered after every part's so it comes last in a
## pass: it stamps the time and has each part show what its run found.
var stamp: SaReductionService.Reduction = null

## The page the docker is drawn from.
var page: SaPage = null

## The surface of the document the painter is working on, or null before there
## is one.
var surface: SaSurface = null

## The service the docker registers with: the one a suite handed in, or the
## autoload `SaReductions` when none was.
var _service: SaReductionService = null

## The idle clock whose stop leaves a line in the session log: the one a suite
## handed in, or the autoload `SaIdle` when none was.
var _clock: SaIdleClock = null

## Whether a stop came and its line is not in the log yet, because the run it
## asked for or an answer of that run is still to come.
var _line_owed: bool = false

## The line saying when the numbers were computed.
var _computed_line: SaPageRow = null


## *service* is the one to register with and *clock* the one whose stops are
## logged, for a suite driving a service and a clock of its own. The app's
## registry builds the docker with neither, and it registers with
## `SaReductions` and hears `SaIdle`.
func _init(service: SaReductionService = null, clock: SaIdleClock = null) -> void:
    _service = service
    _clock = clock
    stamp = SaReductionService.Reduction.new(false, _ran)
    for script: GDScript in Parts.ALL:
        var part: SaStatsPart = script.new()
        parts.append(part)
        if part.reduction != null and part.reduction.has_signal(&"folded"):
            part.reduction.connect(&"folded", _show_parts)
    _init_docker(DOCKER_ID, tr("Stats"), DEFAULT_SIZE, Vector2i(200, 160))
    # Where it stands until a layout places it, on the left as the graph docker
    # does. Each of the four shipped layouts and the default file give it a
    # section of its own, so a fresh profile opens it under the closed Info.
    position = Vector2i(2, 400)

    var vbox := SaMake.column(_control_node, "VBoxContainer")
    vbox.set_anchors_preset(Control.PRESET_FULL_RECT)

    drag_handle = DockerUtils.make_drag_bar(tr("Stats"))
    vbox.add_child(drag_handle)

    var margin := SaMake.margin(vbox, "MarginContainer", SaUI.BASE_MARGIN)
    margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var scroll := SaMake.scroll(margin, "Scroll")
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    var rows := SaMake.column(scroll, PAGE_NAME, SaTheme.GAP)
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    page = SaPage.new(_declare)
    page.declare_rows()
    page.realize(rows)
    var switch := page.row(&"computing")
    switch.control.tooltip_text = SaPage.translated(SWITCH_HOVER)


func _ready() -> void:
    _setup_docker_ready()
    if not SaInHand.Settings.profile_changed().is_connected(apply_layout_settings):
        SaInHand.Settings.profile_changed().connect(apply_layout_settings)
    apply_layout_settings()
    visibility_changed.connect(_follow_open)
    # Deferred, because the dockers are built before the main canvas has a
    # document.
    _find_surface.call_deferred()


func _enter_tree() -> void:
    _follow_open()


## Still inside the tree while this runs, so every run is taken off outright.
func _exit_tree() -> void:
    _hear_stops(false)
    var service := _registry()
    if service == null:
        return
    for reduction: SaReductionService.Reduction in registered():
        service.leave(reduction)


func apply_layout_settings() -> void:
    apply_docker_base_layout(DOCKER_ID)


## Every run the docker registers while it is open with its switch on: each
## part's reduction in the order of the list, then its own.
func registered() -> Array[SaReductionService.Reduction]:
    var out: Array[SaReductionService.Reduction] = []
    for part: SaStatsPart in parts:
        if part.reduction != null:
            out.append(part.reduction)
    out.append(stamp)
    return out


## The words of the line under the switch for a run at *clock_time*, the empty
## string for none yet.
static func computed_text(clock_time: String) -> String:
    if clock_time.is_empty():
        return TranslationServer.translate("Not computed yet. The numbers come the next time you stop painting.")
    return TranslationServer.translate("Computed at %s.") % clock_time


## The switch and the line, then each part's rows.
func _declare(declared: SaPage) -> void:
    var top := declared.section("")
    var switch := top.toggle("Compute", self, ^"computing").named(&"computing").node("ComputeSwitch")
    switch.explain(SWITCH_SENTENCE)
    _computed_line = top.note(computed_text(computed_at)).named(&"computed").node("ComputedLine")
    for part: SaStatsPart in parts:
        part.declare(declared)


## Registers the docker's runs while it is open with its switch on, and takes
## them off otherwise, so a closed docker and an open one switched off cost
## nothing.
func _follow_open() -> void:
    var wanted := computing and visible and is_inside_tree()
    _hear_stops(wanted)
    var service := _registry()
    if service == null:
        return
    for reduction: SaReductionService.Reduction in registered():
        if wanted:
            service.add(reduction)
        else:
            service.leave(reduction)


## The docker's own run, after every part's: the time is stamped and each part
## shows what it found. A run off the per-frame pace is the service's answer
## to a stop, so it owes the log its line.
func _ran(_easel: SaEasel) -> void:
    computed_msec = Time.get_ticks_msec()
    computed_at = Time.get_time_string_from_system()
    var words := computed_text(computed_at)
    _computed_line.explanation = words
    var shown := _computed_line.line as Label
    if shown != null and is_instance_valid(shown):
        shown.text = words
    var service := _registry()
    if service != null and not service.paced():
        _line_owed = true
    _show_parts()


## Has each part write what its reduction holds now into its rows, then writes
## the line a stop owes once every answer is in.
func _show_parts() -> void:
    if surface == null or surface.get_document() == null:
        _find_surface()
    for part: SaStatsPart in parts:
        part.refresh(surface)
    _write_owed()


## The clock said the painter has stopped. Off the per-frame pace the service
## runs everything for it and [method _ran] owes the line. On that pace a run
## comes every frame the paint moves and owes none, so this stop asks for one
## more and its run owes the line.
func _on_stopped() -> void:
    var service := _registry()
    if service == null or not service.paced() or not (computing and visible and is_inside_tree()):
        return
    _line_owed = true
    stamp.stale()


## Writes the line a stop owes into the session log, every number of the page
## by its key, once no part waits for an answer of the run. Nothing, and nothing
## owed after, while the recorder is off.
func _write_owed() -> void:
    if not _line_owed:
        return
    var recorder := SaStrokeRecorder.running
    if recorder == null or not recorder.is_recording():
        _line_owed = false
        return
    for part: SaStatsPart in parts:
        var over := part.reduction as SaReductionService.OverDocument
        if over != null and over.waiting > 0:
            return
    _line_owed = false
    recorder.note_numbers(numbers(), titles())


## Every number the docker holds, by the key of its row, as the dump reads the
## row's value: each part row the page shows, which leaves out the switch, the
## line under it, a hidden row and a button.
func numbers() -> Dictionary:
    var out: Dictionary = {}
    for told: Dictionary in _logged():
        out[told["key"]] = told["value"]
    return out


## The title each of those rows shows, by the same key, where it has one. A
## part may say a number in a row's title, as the value groups title each group
## by its middle value, and the line carries that too.
func titles() -> Dictionary:
    var out: Dictionary = {}
    for told: Dictionary in _logged():
        if not String(told["label"]).is_empty():
            out[told["key"]] = told["label"]
    return out


## Each part row the page shows, as the dump describes it.
func _logged() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    if page == null:
        return out
    for row: SaPageRow in page.rows():
        if row == _computed_line or row.key == &"computing" or row.kind == SaPageRow.Kind.ACTION:
            continue
        var told := row.describe()
        if told["shown"]:
            out.append(told)
    return out


## Hears the clock's stops while *wanted*, and lets go of them and of any line
## owed otherwise.
func _hear_stops(wanted: bool) -> void:
    if not wanted:
        _line_owed = false
    var clock := _clock if _clock != null and is_instance_valid(_clock) else _shared_clock()
    if clock == null:
        return
    var heard := clock.stopped.is_connected(_on_stopped)
    if wanted and not heard:
        clock.stopped.connect(_on_stopped)
    elif heard and not wanted:
        clock.stopped.disconnect(_on_stopped)


## The front surface, as the Recorder docker finds its own, and null until
## that surface has a document to count.
func _find_surface() -> void:
    surface = null
    if not is_inside_tree():
        return
    var front := SaInHand.Canvas.front()
    if front != null and front.get_document() != null:
        surface = front


func _registry() -> SaReductionService:
    if _service != null and is_instance_valid(_service):
        return _service
    return SaReductionService.shared()


## The app's idle clock, the autoload `SaIdle`, or null in a run without it.
static func _shared_clock() -> SaIdleClock:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null or tree.root == null:
        return null
    return tree.root.get_node_or_null(^"SaIdle") as SaIdleClock
