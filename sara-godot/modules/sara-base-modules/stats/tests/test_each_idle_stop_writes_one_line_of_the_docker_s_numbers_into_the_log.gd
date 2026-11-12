## Each idle stop writes one line of the Stats docker's numbers into the session
## log while the recorder runs.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Each idle refresh writes one line
## of numbers into the session log, only when the recorder is on, so a painter
## can read how a picture's value range grew over an hour. The suite opens a
## recorder in a scratch folder and hands the docker a service and an idle clock
## of its own over a real easel, with a stand-in part whose rows move at each
## run, beside the numbers the list names. The clock fires three times and the
## log holds three lines of the kind, each the numbers the page showed then,
## while it is still open. With the switch off, the docker closed or the
## recorder closed it holds none, a run at the graph docker's pace writes none
## while a stop under that pace writes one, and a stop whose tally the device
## hands back on a later frame writes its line once that answer is in.
extends "res://tests/test_framework.gd"

## A real easel under the service, whose run reads its composite.
const REQUIRES_GPU := true

const SIZE := Vector2i(256, 256)

static var scratch_folder: String = SaDataRoot.path("test_a4_stats_lines")


## A stand-in for a number the list names: a row counting the times the docker
## had it show what it found, one saying a share, and one the page never shows,
## so the line leaves it out. The docker has it show after its own run and again
## each time a number of the list folds an answer in, so the count is not the
## stops'.
class StandIn:
    extends SaStatsPart

    var shown: int = 0
    var _page: SaPage = null
    var _runs: SaPageRow = null
    var _share: SaPageRow = null

    func _init() -> void:
        reduction = SaReductionService.Reduction.new(false)

    func declare(page: SaPage) -> void:
        _page = page
        var block := page.section("Stand-in")
        _runs = block.custom("Runs", Label.new()).named(&"stand_in_runs")
        _runs.value = 0
        _share = block.custom("Share", Label.new()).named(&"stand_in_share")
        _share.value = ""
        var spare := block.custom("Spare", Label.new()).named(&"stand_in_spare")
        spare.value = "hidden"
        _runs.hides(spare, [-1])

    func refresh(_surface: SaSurface) -> void:
        shown += 1
        _runs.value = shown
        _share.value = "%d %%" % (shown * 10)
        _page.apply_rules()


var _easel: SaEasel = null
var _clock: SaIdleClock = null
var _service: SaReductionService = null
var _docker: StatsDocker = null
var _part: StandIn = null
var _recorder: SaStrokeRecorder = null
var _embedded: bool = false
var _host: Node = null


func before_each() -> void:
    _easel = SaEasel.create_default(SIZE)
    _easel.process_pending_composite()
    _clock = SaIdleClock.new()
    _clock.follow_settings = false
    _clock.follow_main = false
    _clock.idle_seconds = 1.0
    _clock.attach(_easel.document)
    _service = SaReductionService.new()
    _service.watch(_easel)
    _service.listen(_clock)
    var tree := Engine.get_main_loop() as SceneTree
    _embedded = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "A4StatsHost"
    EventBus.add_child(_host)
    _docker = StatsDocker.new(_service, _clock)
    # The tallies of the numbers the list names come back at once, so a stop's
    # line is in before the suite's next line. The last case reads one late.
    for listed: SaStatsPart in _docker.parts:
        var over := listed.reduction as SaReductionService.OverDocument
        if over != null:
            over.read_at_once = true
    _part = StandIn.new()
    _docker.parts.append(_part)
    _docker.page.rebuild()


func after_each() -> void:
    if _recorder != null:
        _recorder.close()
        DirAccess.remove_absolute(_recorder.path)
    _recorder = null
    if is_instance_valid(_docker):
        _docker.free()
    _docker = null
    _part = null
    if is_instance_valid(_host):
        _host.free()
    _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _embedded
    _service.free()
    _clock.free()
    _easel.free()


## Opens a recorder in a folder of the case's own, since a file is named by the
## second and two cases can open one in the same second.
func _record(folder: String) -> void:
    _recorder = SaStrokeRecorder.new(scratch_folder.path_join(folder), {"display_driver": "test"})
    assert_true(SaStrokeRecorder.running == _recorder, "The recorder runs")


func _open() -> void:
    _host.add_child(_docker)
    _docker.show()
    _docker.computing = true


## Paints, then fires the clock as the painter stopping after a dab does.
func _stop(step: int) -> bool:
    _paint(step)
    _clock.note_edit()
    return _clock.tick(_clock.idle_seconds)


func _paint(step: int) -> void:
    _easel.document.fill_layer(Color(float(step % 10) / 10.0, 0.3, 0.5, 1.0))
    _easel.process_pending_composite()


## The lines of the numbers' kind the open log holds now.
func _numbers_lines() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var file := FileAccess.open(_recorder.path, FileAccess.READ)
    while file != null and not file.eof_reached():
        var line := file.get_line()
        if line.is_empty():
            continue
        var row: Dictionary = JSON.parse_string(line)
        if row.get("k", "") == SaStrokeRecorder.NUMBERS:
            out.append(row)
    return out


## What the page shows now of every part row, as the dump reads it, its values
## under `n` and its titles under `l`, through a JSON line and back as the
## log's reader would.
func _page_shows() -> Dictionary:
    var values: Dictionary = {}
    var titles: Dictionary = {}
    var pages := SaPage.capture_state((Engine.get_main_loop() as SceneTree).root)
    for block: Dictionary in pages[StatsDocker.PAGE_NAME]["sections"]:
        for row: Dictionary in block["rows"]:
            if row["shown"] and not ["computing", "computed"].has(row["key"]):
                values[row["key"]] = row["value"]
                if not String(row["label"]).is_empty():
                    titles[row["key"]] = row["label"]
    return JSON.parse_string(JSON.stringify({"n": values, "l": titles}))


func test_three_stops_open_and_switched_on_write_three_lines_of_what_the_page_showed() -> void:
    _record("three")
    _open()
    var showed: Array[Dictionary] = []
    for step in 3:
        assert_true(_stop(step + 1), "The clock fires, stop %d" % (step + 1))
        showed.append(_page_shows())
    assert_true(_part.shown >= 3, "The part showed at each run")
    var lines := _numbers_lines()
    assert_eq(lines.size(), 3, "Three stops, three lines of the kind, read while the log is still open")
    var last := -1
    for at in mini(lines.size(), 3):
        assert_eq(lines[at]["n"], showed[at]["n"], "Line %d holds the numbers the page showed then" % (at + 1))
        assert_eq(lines[at]["l"], showed[at]["l"], "and the titles they were shown under")
        assert_true(int(lines[at]["t"]) >= last, "on the log's clock, in order")
        last = int(lines[at]["t"])
    if lines.size() == 3:
        var numbers: Dictionary = lines[2]["n"]
        assert_eq(numbers.get("stand_in_runs"), float(_part.shown), "by the rows' keys")
        assert_eq(numbers.get("stand_in_share"), "%d %%" % (_part.shown * 10), "whatever a row holds")
        assert_eq((lines[2]["l"] as Dictionary).get("stand_in_share"), "Share", "and each title by the same key")
        assert_false(numbers.has("stand_in_spare"), "A row the page hides is left out")
        assert_false(numbers.has("computing") or numbers.has("computed"), "and so are the switch and the line")
        for listed: SaStatsPart in _docker.parts:
            if listed is not StandIn:
                assert_true(numbers.has("value_groups"), "The numbers the list names are in the line with no line of their own")


func test_with_the_switch_off_or_the_docker_closed_a_stop_writes_none() -> void:
    _record("off")
    _host.add_child(_docker)
    _docker.show()
    assert_true(_stop(1), "Open with the switch off, the clock fires")
    _docker.computing = true
    _docker.hide()
    assert_true(_stop(2), "Closed with the switch on, it fires again")
    _host.remove_child(_docker)
    assert_true(_stop(3), "and out of the tree")
    assert_eq(_numbers_lines().size(), 0, "and no stop wrote a line")
    assert_eq(_part.shown, 0, "nor ran the part")


func test_with_the_recorder_closed_a_stop_writes_none() -> void:
    _record("closed")
    _open()
    assert_true(_stop(1), "The clock fires while it records")
    assert_eq(_numbers_lines().size(), 1, "and the stop writes its line")
    _recorder.close()
    assert_null(SaStrokeRecorder.running, "Closed, nothing records")
    var shown := _part.shown
    assert_true(_stop(2), "The clock fires again")
    assert_true(_part.shown > shown, "The numbers still refresh")
    assert_eq(_numbers_lines().size(), 1, "and the log holds the one line it had")


func test_a_run_at_the_graph_pace_writes_none_and_a_stop_under_it_writes_one() -> void:
    _record("paced")
    _open()
    var graph := SaReductionService.Reduction.new(true)
    _service.add(graph)
    assert_true(_service.paced(), "A reduction that sets the pace stands in for the open graph docker")
    var now := 1000
    for step in 3:
        _paint(step + 1)
        now += 100
        assert_true(_service.tick(now), "The paint moved, so the pace runs, frame %d" % (step + 1))
    assert_eq(_docker.stamp.runs, 3, "The docker's run came at the pace")
    assert_eq(_numbers_lines().size(), 0, "and wrote no line")
    assert_true(_stop(4), "The painter stops")
    now += 100
    assert_true(_service.tick(now), "The stop asked the pace for one more run")
    assert_eq(_numbers_lines().size(), 1, "and that run wrote the stop's line")
    now += 100
    assert_false(_service.tick(now), "With nothing new, the next frame runs nothing")
    _paint(5)
    now += 100
    assert_true(_service.tick(now), "Paint again at the pace")
    assert_eq(_numbers_lines().size(), 1, "still one line")
    _service.leave(graph)


func test_a_stop_whose_tally_comes_back_later_writes_its_line_once_the_answer_is_in() -> void:
    var late: SaReductionService.OverDocument = null
    for listed: SaStatsPart in _docker.parts:
        if listed.reduction is SaReductionService.OverDocument:
            late = listed.reduction
    assert_not_null(late, "A number the list names reduces over the document")
    if late == null:
        return
    late.read_at_once = false
    _record("late")
    _open()
    assert_true(_stop(1), "The clock fires")
    if late.waiting == 0:
        # A run on a device that is not the main one reads at once, and then
        # the line is in already.
        assert_eq(_numbers_lines().size(), 1, "Read at once, the line is in")
        return
    assert_eq(_numbers_lines().size(), 0, "While the device has not answered, no line is written")
    for frame in 8:
        if late.waiting == 0:
            break
        RenderingServer.force_draw(false, 0.0)
    assert_eq(late.waiting, 0, "The device answered within a few frames")
    var lines := _numbers_lines()
    assert_eq(lines.size(), 1, "and the answer folded in wrote the stop's line")
    if lines.size() == 1:
        assert_eq(lines[0]["n"], _page_shows()["n"], "holding the numbers the page shows with the answer in")
    assert_true(_stop(2), "The clock fires again")
    for frame in 8:
        if late.waiting == 0:
            break
        RenderingServer.force_draw(false, 0.0)
    assert_eq(_numbers_lines().size(), 2, "and that stop writes one more, once")
