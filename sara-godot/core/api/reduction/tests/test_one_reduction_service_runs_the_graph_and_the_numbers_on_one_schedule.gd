## One reduction service runs the graph and the numbers on one schedule.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The maintainers' ruling was one shared service under both dockers, at the graph
## docker's per-frame pace while it is open and on the idle clock otherwise,
## and a closed docker costs nothing. So the suite builds a service of its own,
## hands it a real easel and a real idle clock, and drives both by hand: a
## frame is a call to `tick` with the time it is at, and seconds pass in the
## clock's `tick`. A reduction that counts its runs stands in for a docker's.
##
## The reduction over the document is a real one, `measure.gmacs`'s first pass
## over the composite, read back at once so an assertion can follow it, and
## once on a later frame the way the app reads it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Real composites and a real kernel over them.
const REQUIRES_GPU := true

## Two chunks by two, so a chunk painted alone is one of four.
const SIZE := Vector2i(512, 512)

## A frame at sixty a second, in milliseconds.
const FRAME_MSEC := 16

## `measure.gmacs`'s cells a slot, as `SaMeasure.CELLS` holds them, which a
## suite of `ui` may not name.
const CELLS := 8
const CELL_TEXELS := 0
const CELL_SUM_L := 2

var _easel: SaEasel = null
var _clock: SaIdleClock = null
var _service: SaReductionService = null
var _embedded: bool = false
var _host: Node = null


func before_each() -> void:
    _easel = SaEasel.create_default(SIZE)
    _easel.process_pending_composite()
    _clock = SaIdleClock.new()
    _clock.follow_settings = false
    _clock.follow_main = false
    _clock.idle_seconds = 5.0
    _clock.attach(_easel.document)
    _service = SaReductionService.new()
    _service.watch(_easel)
    _service.listen(_clock)


func after_each() -> void:
    if _host != null and is_instance_valid(_host):
        _host.free()
        (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _embedded
    _host = null
    _service.free()
    _clock.free()
    _easel.free()


## A dab of a stroke: an edit through the history and the composite that shows
## it, which is what a frame of painting does to the easel.
func _paint(step: int) -> void:
    _easel.document.fill_layer(Color(float(step % 10) / 10.0, 0.2, 0.4, 1.0))
    _easel.process_pending_composite()


## The first pass of `measure.gmacs` over the composite, a chunk a slot.
func _numbers() -> SaReductionService.OverDocument:
    return SaReductionService.OverDocument.new("measure", "measure_sum", CELLS, _measure_push)


## The 96 bytes `measure.gmacs` reads, in its own order, for *rect* of the
## composite. The composite is one texture, so the dispatch starts where the
## rectangle does and the rectangle is its own share.
func _measure_push(rect: Rect2i, slot: int, document: SaDocument) -> PackedFloat32Array:
    var space := document.color_space
    var params := PackedFloat32Array(
        [
            float(rect.position.x),
            float(rect.position.y),
            float(rect.position.x),
            float(rect.position.y),
            float(rect.end.x),
            float(rect.end.y),
            float(slot),
            float(space.coordinates),
        ]
    )
    params.append_array(space.transfer.to_params())
    params.append_array(PackedFloat32Array([0.0, 0.0, 0.0]))
    for column: Vector3 in SaColorSpaceGlsl.basis_columns(space.to_linear_srgb_matrix()):
        params.append_array(PackedFloat32Array([column.x, column.y, column.z]))
    return params


## Paints the chunk at *grid_pos* of the paint layer one colour and tells the
## document, the way a dab inside one chunk does.
func _paint_chunk(grid_pos: Vector2i, colour: Color) -> void:
    var document := _easel.document
    document.active_layer.get_or_create_chunk(grid_pos).clear(colour)
    document.invalidate_chunk_regions({grid_pos: Rect2i(Vector2i.ZERO, Vector2i.ONE * SaLayer.CHUNK_SIZE)})


## Fires the clock as the painter stopping after an edit does.
func _stop() -> bool:
    _clock.note_edit()
    return _clock.tick(_clock.idle_seconds)


func test_with_the_graph_open_a_stroke_runs_it_at_most_every_interval_and_once_after_the_last_composite() -> void:
    var seen: Array[int] = []
    var counted := SaReductionService.Reduction.new(true, func(easel: SaEasel) -> void: seen.append(easel.composite_count))
    _service.add(counted)
    var now := 1000
    _service.tick(now)
    assert_eq(counted.runs, 1, "Registered, it runs on the next frame")

    var ran_at: Array[int] = []
    # Thirty-two frames of paint, so the last composite falls inside an interval
    # rather than on a run.
    for frame in 32:
        now += FRAME_MSEC
        _paint(frame)
        if _service.tick(now):
            ran_at.append(now)
    var stroke_ended := now
    var last_composite := _easel.composite_count
    for frame in 12:
        now += FRAME_MSEC
        if _service.tick(now):
            ran_at.append(now)

    assert_true(ran_at.size() >= 5, "A half-second stroke is reduced several times, %d" % ran_at.size())
    assert_true(ran_at.size() < 32, "and fewer than once a composite, %d of 32" % ran_at.size())
    var gaps_ok := true
    for i in range(1, ran_at.size()):
        gaps_ok = gaps_ok and ran_at[i] - ran_at[i - 1] >= SaReductionService.PAINT_INTERVAL_MSEC
    assert_true(gaps_ok, "No two runs in %d ms, at %s" % [SaReductionService.PAINT_INTERVAL_MSEC, ran_at])
    var after := ran_at.filter(func(at: int) -> bool: return at > stroke_ended)
    assert_eq(after.size(), 1, "One run after the last composite, at %s with the stroke over at %d" % [ran_at, stroke_ended])
    assert_eq(seen.back(), last_composite, "and it read the last composite")
    var first_after: int = after[0] if not after.is_empty() else stroke_ended - 1
    var waited := first_after - stroke_ended
    assert_true(waited >= 0 and waited <= SaReductionService.PAINT_INTERVAL_MSEC, "within an interval of the end, %d ms" % waited)


func test_with_the_graph_open_a_moved_shape_runs_at_once() -> void:
    var panel := [Vector2i(300, 200)]
    var counted := SaReductionService.Reduction.new(true, Callable(), func() -> Variant: return panel[0])
    _service.add(counted)
    _service.tick(1000)
    _paint(1)
    assert_false(_service.tick(1010), "Paint inside the interval waits")
    panel[0] = Vector2i(400, 200)
    assert_true(_service.tick(1020), "and a docker dragged wider does not")
    assert_false(_service.tick(1030), "Nothing moved, nothing runs")
    counted.stale()
    assert_true(_service.tick(1040), "A reduction that asks is run")


func test_with_the_graph_closed_it_runs_once_when_the_clock_fires_and_never_while_edits_keep_coming() -> void:
    var counted := SaReductionService.Reduction.new(false)
    _service.add(counted)
    var now := 1000
    for edit in 20:
        _paint(edit)
        now += FRAME_MSEC
        _service.tick(now)
        assert_false(_clock.tick(4.0), "an edit every four seconds, edit %d" % edit)
    assert_eq(counted.runs, 0, "Never while the edits keep coming, frames or no frames")
    assert_true(_clock.tick(1.0), "Five seconds after the last edit the clock fires")
    assert_eq(counted.runs, 1, "and it runs once")
    _clock.tick(60.0)
    _service.tick(now + 60000)
    assert_eq(counted.runs, 1, "and not again until the next edit")


func test_with_the_graph_open_the_clock_adds_no_run() -> void:
    var paced := SaReductionService.Reduction.new(true)
    var numbers := SaReductionService.Reduction.new(false)
    _service.add(paced)
    _service.add(numbers)
    _service.tick(1000)
    assert_eq(numbers.runs, 1, "With the graph open every reduction runs at its pace")
    assert_true(_stop(), "The clock fires")
    assert_eq(numbers.runs, 1, "and adds nothing to a reduction already kept up to date")


func test_with_nothing_registered_nothing_is_dispatched() -> void:
    _paint(3)
    var before := SaCompute.dispatches
    assert_false(_service.tick(2000), "A frame runs nothing")
    assert_true(_stop(), "The clock fires")
    assert_eq(SaCompute.dispatches, before, "Nothing was dispatched")
    assert_eq(_service.passes, 0, "and nothing ran")

    var numbers := _numbers()
    numbers.read_at_once = true
    _service.add(numbers)
    _service.leave(numbers)
    _paint(4)
    before = SaCompute.dispatches
    _service.tick(3000)
    assert_true(_stop(), "The clock fires again")
    assert_eq(SaCompute.dispatches, before, "A reduction taken off costs nothing either")
    assert_false(_service.is_processing(), "and the service stops looking at frames")


func test_a_chunk_painted_alone_is_the_one_chunk_the_next_run_dispatches_over() -> void:
    var numbers := _numbers()
    numbers.read_at_once = true
    _service.add(numbers)
    assert_true(_stop(), "The clock fires")
    var every: Array[Vector2i] = SaLayer.grid_positions(SIZE)
    var first := numbers.dispatched.duplicate()
    first.sort()
    every.sort()
    assert_eq(first, every, "The first run reads every painted chunk")
    var unpainted := numbers.total.duplicate()
    assert_eq(unpainted[CELL_TEXELS], SIZE.x * SIZE.y, "every texel of the canvas once")

    _paint_chunk(Vector2i(1, 0), Color.BLACK)
    assert_true(_stop(), "The clock fires again")
    assert_eq(numbers.dispatched, [Vector2i(1, 0)] as Array[Vector2i], "The next run dispatched over that chunk alone")
    assert_eq(numbers.total[CELL_TEXELS], SIZE.x * SIZE.y, "The count stays the canvas's")
    assert_true(
        numbers.total[CELL_SUM_L] < unpainted[CELL_SUM_L],
        "and the black chunk lowered the sum of L, %d from %d" % [numbers.total[CELL_SUM_L], unpainted[CELL_SUM_L]]
    )

    var fresh := _numbers()
    fresh.read_at_once = true
    fresh.run(_easel, 0)
    assert_eq(fresh.dispatched.size(), 4, "A reduction from nothing reads all four")
    assert_eq(numbers.total, fresh.total, "and the folded total is the one it sums afresh")
    fresh.let_go()
    numbers.let_go()


func test_the_tally_comes_back_on_a_later_frame() -> void:
    var numbers := _numbers()
    _service.add(numbers)
    var heard: Array[int] = []
    numbers.folded.connect(func() -> void: heard.append(1))
    assert_true(GlobalShaderCompiler.get_rd() == RenderingServer.get_rendering_device(), "The suites run on the main device")
    assert_true(_stop(), "The clock fires")
    assert_eq(numbers.waiting, 1, "The run asked the device for its tally")
    assert_true(heard.is_empty(), "and returned without waiting for the answer")
    var at_once := _numbers()
    at_once.read_at_once = true
    at_once.run(_easel, 0)
    for frame in 8:
        if numbers.waiting == 0:
            break
        RenderingServer.force_draw(false, 0.0)
    assert_eq(numbers.waiting, 0, "The device answered within a few frames")
    assert_eq(heard.size(), 1, "and the total moved once")
    assert_eq(numbers.total, at_once.total, "to what a read at once says")
    at_once.let_go()
    numbers.let_go()


func test_the_graph_docker_registers_its_pass_while_it_is_open() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var service := SaReductionService.shared()
    assert_true(service != null, "The service is the autoload SaReductions")
    if service == null:
        return
    _embedded = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "A2GraphHost"
    EventBus.add_child(_host)
    var docker := GraphDocker.new()
    assert_false(service.holds(docker.reduction), "Built and not open, it holds nothing")
    _host.add_child(docker)
    assert_false(service.holds(docker.reduction), "In the tree and hidden, as the main scene leaves it, it holds nothing")
    docker.show()
    assert_true(service.holds(docker.reduction), "Open, its pass is registered")
    assert_true(docker.reduction.sets_pace, "and sets the per-frame pace")
    docker.hide()
    assert_false(service.holds(docker.reduction), "Closed, it is taken off")
    docker.show()
    assert_true(service.holds(docker.reduction), "Opened again, it is back")
    _host.remove_child(docker)
    assert_false(service.holds(docker.reduction), "Out of the tree, it is taken off")
    docker.free()

    var own := GraphDocker.new()
    _service.add(own.reduction)
    _service.tick(1000)
    assert_eq(own.reduction.runs, 1, "The graph's pass runs on the service's decision")
    _service.leave(own.reduction)
    own.free()


## The Stats docker, the base modules', registers its
## numbers on the same autoload the Graph docker's pass is on. It is reached
## the way the app reaches it, through the module's registration and the
## factory it hands the docker registry, since no script of the skeleton names
## the docker.
func test_the_stats_docker_registers_its_numbers_on_the_same_service() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var service := SaReductionService.shared()
    assert_true(service != null, "The service is the autoload SaReductions")
    if service == null:
        return
    var registries := Fixtures.make_registries()
    var module: SaModule = load(Fixtures.STATS_MODULE).new()
    module.register(registries.context.for_module(module.get_id()))
    var entries := registries.ui.list_dockers().filter(func(entry: Dictionary) -> bool: return entry["module"] == module.get_id())
    assert_eq(entries.size(), 1, "The module registers one docker")
    if entries.size() != 1:
        return
    _embedded = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "StatsHost"
    EventBus.add_child(_host)
    var graph := GraphDocker.new()
    var stats: Window = (entries[0]["factory"] as Callable).call()
    _host.add_child(graph)
    _host.add_child(stats)
    graph.show()
    stats.show()
    stats.set(&"computing", true)
    var numbers: Array = stats.call(&"registered")
    assert_true(numbers.size() > 1, "Open with its switch on, the Stats docker has its parts' runs and its own")
    for reduction: SaReductionService.Reduction in numbers:
        assert_true(service.holds(reduction), "and each is on SaReductions")
    assert_true(service.holds(graph.reduction), "beside the Graph docker's pass")
    stats.hide()
    for reduction: SaReductionService.Reduction in numbers:
        assert_false(service.holds(reduction), "Closed, the Stats docker's runs are taken off")
    assert_true(service.holds(graph.reduction), "and the Graph's stays")
    graph.hide()
    assert_false(service.holds(graph.reduction), "until the Graph closes too")
