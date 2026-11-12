## A closed Stats docker, and an open one switched off, register nothing.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The spec's refresh rule is that a closed docker costs nothing and an open
## one has a switch that turns the computing on. So the suite hands the docker
## a service of its own, with a real easel and a real idle clock, and reads
## what the service holds as the docker is built, put in the tree, shown,
## switched, hidden and taken out. Then the clock fires as it does when the
## painter stops, and the line under the switch moves with the switch on and
## stays as it was with it off.
extends "res://tests/test_framework.gd"

## A real easel under the service, whose run reads its composite.
const REQUIRES_GPU := true

const SIZE := Vector2i(256, 256)


## A stand-in for a number the list names: a reduction of its own, and a count
## of the times the docker asked it to show what that found.
class StandIn:
    extends SaStatsPart

    var shown: int = 0
    var shown_with: SaSurface = null

    func _init() -> void:
        reduction = SaReductionService.Reduction.new(false)

    func refresh(surface: SaSurface) -> void:
        shown += 1
        shown_with = surface


var _easel: SaEasel = null
var _clock: SaIdleClock = null
var _service: SaReductionService = null
var _docker: StatsDocker = null
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
    _host.name = "A3StatsHost"
    EventBus.add_child(_host)
    _docker = StatsDocker.new(_service)


func after_each() -> void:
    if is_instance_valid(_docker):
        _docker.free()
    _docker = null
    if is_instance_valid(_host):
        _host.free()
    _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _embedded
    _service.free()
    _clock.free()
    _easel.free()


## Fires the clock as the painter stopping after a dab does.
func _stop(step: int) -> bool:
    _easel.document.fill_layer(Color(float(step % 10) / 10.0, 0.3, 0.5, 1.0))
    _easel.process_pending_composite()
    _clock.note_edit()
    return _clock.tick(_clock.idle_seconds)


func test_a_closed_docker_registers_nothing_with_its_switch_on_or_off() -> void:
    assert_false(_docker.computing, "The switch is off until the painter turns it on")
    assert_eq(_service.reductions.size(), 0, "Built and not open, it registers nothing")
    _docker.computing = true
    assert_eq(_service.reductions.size(), 0, "Switched on while it is not in the tree, still nothing")
    _host.add_child(_docker)
    assert_false(_docker.visible, "In the tree it starts hidden, as the main scene leaves it")
    assert_eq(_service.reductions.size(), 0, "In the tree and hidden with the switch on, nothing")
    _docker.computing = false
    _docker.computing = true
    assert_eq(_service.reductions.size(), 0, "and switching it off and on while closed registers nothing")


func test_an_open_docker_registers_its_run_only_while_its_switch_is_on() -> void:
    _host.add_child(_docker)
    _docker.show()
    assert_eq(_service.reductions.size(), 0, "Open with the switch off, nothing is registered")
    _docker.computing = true
    assert_true(_service.holds(_docker.stamp), "Switched on while open, its run is registered")
    assert_false(_docker.stamp.sets_pace, "and it does not set the per-frame pace")
    _docker.computing = false
    assert_eq(_service.reductions.size(), 0, "Switched off, it is taken off")
    _docker.computing = true
    _docker.hide()
    assert_eq(_service.reductions.size(), 0, "Closed with the switch on, it is taken off")
    _docker.show()
    assert_true(_service.holds(_docker.stamp), "Opened again with the switch on, it is back")
    _host.remove_child(_docker)
    assert_eq(_service.reductions.size(), 0, "Out of the tree, it is taken off")


func test_a_part_registers_ahead_of_the_line_and_shows_after_its_run() -> void:
    var part := StandIn.new()
    _docker.parts.append(part)
    _host.add_child(_docker)
    _docker.show()
    _docker.computing = true
    var held := _service.reductions.size()
    assert_eq(held, _docker.registered().size(), "Every part's run and the docker's own are registered")
    assert_true(_service.reductions[held - 2] == part.reduction, "the part's ahead of")
    assert_true(_service.reductions[held - 1] == _docker.stamp, "the docker's own, which comes last")
    assert_true(_stop(1), "The clock fires")
    assert_eq(part.reduction.runs, 1, "The part's reduction ran")
    assert_eq(part.shown, 1, "and the docker had it show what it found once its own run came")
    _docker.computing = false
    assert_eq(_service.reductions.size(), 0, "Switched off, the part leaves with the docker's run")


func test_the_clock_moves_the_line_with_the_switch_on_and_leaves_it_with_the_switch_off() -> void:
    _host.add_child(_docker)
    _docker.show()
    var line := _docker.page.row(&"computed")
    assert_eq(_docker.computed_at, "", "Nothing has run yet")
    assert_eq(line.explanation, StatsDocker.computed_text(""), "and the line says so")
    assert_true(_stop(1), "With the switch off the clock fires")
    assert_eq(_docker.stamp.runs, 0, "and nothing runs")
    assert_eq(_docker.computed_at, "", "so the line stays as it was")

    _docker.computing = true
    assert_true(_stop(2), "Switched on, the painter stops again")
    assert_eq(_docker.stamp.runs, 1, "and the docker's run comes")
    assert_false(_docker.computed_at.is_empty(), "with the time it ran")
    assert_true(_docker.computed_msec >= 0, "and its tick")
    assert_eq(line.explanation, StatsDocker.computed_text(_docker.computed_at), "The line says the time")
    assert_eq((line.line as Label).text, line.explanation, "and the label shows it")

    _docker.computing = false
    var said := line.explanation
    var at := _docker.computed_msec
    assert_true(_stop(3), "Switched off, a stroke and a stop")
    assert_eq(_docker.stamp.runs, 1, "run nothing")
    assert_eq(_docker.computed_msec, at, "and leave the time")
    assert_eq(line.explanation, said, "and the line as they were")


func test_the_dump_reads_the_switch_and_the_line_under_the_page_name() -> void:
    _host.add_child(_docker)
    _docker.show()
    assert_eq(_docker.parts.size(), StatsDocker.Parts.ALL.size(), "One part a line of the list")
    for part: SaStatsPart in _docker.parts:
        assert_true(part is SaStatsPart, "and each extends the contract")
    var pages := SaPage.capture_state((Engine.get_main_loop() as SceneTree).root)
    assert_true(pages.has(StatsDocker.PAGE_NAME), "The state dump files the page under its name")
    if not pages.has(StatsDocker.PAGE_NAME):
        return
    var rows: Array = pages[StatsDocker.PAGE_NAME]["sections"][0]["rows"]
    assert_eq(rows[0]["key"], "computing", "The switch comes first")
    assert_eq(rows[0]["value"], false, "and reads off")
    assert_false(String(rows[0]["explain"]).is_empty(), "with the sentence that says what it does")
    assert_eq(rows[1]["key"], "computed", "then the line")
    assert_eq(rows[1]["explain"], StatsDocker.computed_text(""), "which says nothing has run yet")
