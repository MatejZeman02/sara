## A Pencil dab costs half the GDScript it does.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The bench the row asks for. A 2 px Pencil is laid along a straight line, a
## report every 25 px as a fast pen reports, and a frame's flush after every
## fourth report, until the stroke has laid [constant DABS] dabs. The time from
## the first report to the last flush over the dabs laid is the mean cost a dab
## on the CPU, from `SaStrokeInfo.feed` through the dynamics, the colour, the
## paint context and the held record to the frame's send. The card's own time
## is not in it, because the lists are recorded here and run after.
##
## It prints the figure as a `bench:` line. The best of [constant RUNS] strokes is
## the figure, because a gate shared with other runs slows a stroke that runs
## beside them and never speeds one up. What it asserts is the walk itself,
## which is what the figure is a mean over, and a ceiling far above the figure,
## for a dab that has grown many times dearer.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

static var scratch_dir: String = SaDataRoot.path("test_d5_pencil_bench_presets")

## The dabs a measured stroke lays, which the row names.
const DABS: int = 2000
## Measured strokes, after one that warms the kernels and the caches.
const RUNS: int = 3
## A report's travel in document pixels, a pen at 5000 screen px/s and 200 Hz
## at a zoom of two thirds.
const REPORT_PX: float = 25.0
## Reports a frame, a pen at 200 Hz on a 60 Hz screen rounded up.
const REPORTS_A_FRAME: int = 4
## A ceiling no machine the gate runs on comes near: a dab measured 170 µs
## of GDScript on one development machine, and this is six times that.
const CEILING_USEC: float = 1000.0
## The canvas, wide enough for a row of [constant DABS] dabs.
const CANVAS := Vector2i(2048, 256)
const ROW_Y: float = 128.0

var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    if DirAccess.dir_exists_absolute(scratch_dir):
        for file_name: String in DirAccess.get_files_at(scratch_dir):
            DirAccess.remove_absolute(scratch_dir.path_join(file_name))
        DirAccess.remove_absolute(scratch_dir)


func _brush() -> Object:
    return _machine.active_tool


func _button(pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    _brush().handle_input(event)


func _motion(at: Vector2) -> void:
    var motion := InputEventMouseMotion.new()
    motion.pressure = 0.8
    _surface.view.mouse_position = at
    _brush().handle_input(motion)


## Pencil at a 2 px diameter. False when the shipped recipe could not be loaded.
func _pencil() -> bool:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(_brush().settings, ShippedPresetsScript)
    if not store.apply_preset("Pencil", _brush().settings):
        return false
    _brush().settings.radius = 1.0 / float(mini(CANVAS.x, CANVAS.y))
    return true


## One stroke along the row until it has laid *dabs*, and what it cost:
## `dabs`, the dabs laid between the first report and the last flush, and
## `usec`, the time that took.
func _stroke(dabs: int) -> Dictionary:
    var from := Vector2(8.0, ROW_Y)
    _surface.view.mouse_position = from
    _button(true)
    # The press's own dab and the stroke's opening, outside the time.
    _motion(from + Vector2(REPORT_PX, 0.0))
    _brush()._walk_batch.flush()
    var first: int = _brush().stroke_info.dab_index
    var at := from + Vector2(REPORT_PX, 0.0)
    var reports := 0
    var started := Time.get_ticks_usec()
    while _brush().stroke_info.dab_index - first < dabs and at.x < float(CANVAS.x) - REPORT_PX:
        at += Vector2(REPORT_PX, 0.0)
        _motion(at)
        reports += 1
        if reports % REPORTS_A_FRAME == 0:
            _brush()._walk_batch.flush()
    _brush()._walk_batch.flush()
    var spent := Time.get_ticks_usec() - started
    var laid: int = _brush().stroke_info.dab_index - first
    _button(false)
    return {"dabs": laid, "usec": spent}


func test_a_pencil_dab_s_mean_cost() -> void:
    assert_true(_pencil(), "Pencil loads")
    _stroke(DABS)
    var means: Array[float] = []
    var laid: Array[int] = []
    for run in RUNS:
        var stroke := _stroke(DABS)
        laid.append(stroke["dabs"])
        means.append(float(stroke["usec"]) / maxf(1.0, float(stroke["dabs"])))
    var best: float = means.min()
    print("bench: a Pencil 2 px dab costs %.1f us, the best of %s over %s dabs" % [best, str(means), str(laid)])
    for count in laid:
        assert_true(count >= DABS, "A stroke along the row lays %d dabs, %d here" % [DABS, count])
    assert_true(best < CEILING_USEC, "A Pencil 2 px dab costs %.1f us, under %.0f" % [best, CEILING_USEC])


## The block a held dab hands its walk, packed once while its numbers hold and
## placed on each target, is the block `SaDabPacking.pack_dab_params` packs for
## that dab at that target with its mirror written, float for float, for the
## first dab, for one that changes only its sequence, and for one that changes
## its colour.
func test_a_record_placed_on_a_target_is_the_dab_s_packing() -> void:
    assert_true(_pencil(), "Pencil loads")
    var settings: Resource = _brush().settings
    var reads := SaWalkBatch.Reads.new(settings, _brush().dab_pattern)
    var info := SaStrokeInfo.new()
    var tip := SaBrushTipScript.new()
    tip.diameter = 2.0
    var target := SaPaintContext.Target.new()
    target.grid_pos = Vector2i(3, 1)
    target.local_center = Vector2(17.25, 40.5)
    target.render_offset = Vector2(8.0, 32.0)
    var dab := SaDabParams.new()
    dab.flow = 0.75
    dab.sharpness = 0.2
    dab.pattern_strength = 0.4
    var asks: Array[Array] = [
        [Color(0.2, 0.3, 0.4, 0.9), 7.0],
        [Color(0.2, 0.3, 0.4, 0.9), 8.0],
        [Color(0.6, 0.1, 0.4, 0.5), 9.0],
    ]
    for ask: Array in asks:
        var color: Color = ask[0]
        var sequence: float = ask[1]
        var record := reads.record(tip, dab, color, Vector2(1.0, 1.0), 0.3, Vector2(0.5, 0.5), 0, false, 5, sequence)
        var placed := reads.placed(record, target, 256, info)
        var packed := SaDabPacking.pack_dab_params(
            target.local_center,
            target.render_offset,
            color,
            Vector2(1.0, 1.0),
            0.3,
            Vector2(0.5, 0.5),
            reads.flow * 0.75,
            0,
            false,
            tip,
            0.2,
            reads.sharpness_softness,
            sequence,
            _brush().dab_pattern.strength_for(0.4, settings),
            SaDabPattern.offset_for(target, 256, settings, info),
            SaSmallDab.mode_diameter(settings, tip.diameter)
        )
        packed[SaDabGeometry.MIRROR_INDEX] = 5.0
        assert_eq(placed, packed, "The record placed is the packing, at sequence %s" % sequence)
        assert_eq(reads.packing(256, info).call(target), packed, "The walk's packing places the same block")
