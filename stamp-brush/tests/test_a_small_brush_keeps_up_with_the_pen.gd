## A small brush keeps up with the pen.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## "Pencil, Wash and Oil Smudge lag badly behind the pen at small sizes." The
## walk paints a dab every half pixel or so whatever the tip, so a small tip
## paints many dabs an event and the cost is whatever each dab pays again. What
## this holds is that count and the three things a walk now settles once: one
## commit of the dirty rectangles for the whole event, the dynamics' options and
## the paper read once a walk, and the tip's softness table built once until it
## moves. The walk's plain dabs go as one dispatch a chunk, which
## `test_a_walks_dabs_go_as_one_dispatch_a_chunk.gd` holds. The commit and the
## send happen once a frame rather than each event, so these flush
## by hand where a frame would.
##
## The timing itself is the scenario's,
## `scenarios/a-small-brush-keeps-up-with-the-pen.json`, read by
## `sara_perf.py`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## Never the real `user://brush_presets`, which is the painter's own folder.
static var scratch_dir: String = SaDataRoot.path("test_w4_presets")
## A 2 px tip on the 256 px canvas, the scenario's smallest size.
const SMALL_RADIUS: float = 1.0 / 256.0
## The press and two reports, inside the first chunk so every dab touches one.
## A report walks the segment before it, so the second report paints the 100 px
## from [constant FROM] to [constant MID].
const FROM := Vector2(20, 40)
const MID := Vector2(120, 40)
const TO := Vector2(220, 40)

var _surface: SaSurface = null
var _machine: ToolMachine = null


## A context that counts its commits instead of dirtying a document.
class CountingContext:
    extends SaPaintContext

    var commits: Array[int] = [0]

    func _init(counter: Array[int], mask: SaMask = null) -> void:
        super(null, mask)
        commits = counter

    func commit_invalidation() -> void:
        commits[0] += 1


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
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


## Pencil at 2 px, pressed at [constant FROM] and reported at [constant MID],
## which paints nothing yet. Answers false when the shipped
## recipe could not be loaded.
func _small_pencil() -> bool:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(_brush().settings, ShippedPresetsScript)
    if not store.apply_preset("Pencil", _brush().settings):
        return false
    _brush().settings.radius = SMALL_RADIUS
    _surface.view.mouse_position = FROM
    _button(true)
    _motion(MID)
    return true


func test_every_dab_of_an_event_reaches_the_card_in_the_one_chunk() -> void:
    assert_true(_small_pencil(), "Pencil loads")
    var dabs_before := SaStrokeLedger.dabs
    var targets_before := SaStrokeLedger.targets
    var laid_before: int = _brush().stroke_info.dab_index
    _motion(TO)
    _brush()._walk_batch.flush()
    var dabs := SaStrokeLedger.dabs - dabs_before
    var laid: int = _brush().stroke_info.dab_index - laid_before
    assert_true(dabs >= 50, "A 2 px Pencil paints many dabs over 100 px of one event, %d here" % dabs)
    assert_eq(dabs, laid, "and every dab the walk laid reached the card by the frame's end")
    assert_eq(SaStrokeLedger.targets - targets_before, dabs, "each in the one chunk the run crosses")
    _button(false)


func test_a_frames_dirty_rectangles_are_committed_when_it_flushes() -> void:
    assert_true(_small_pencil(), "Pencil loads")
    var doc := _surface.easel.document
    _motion(TO)
    assert_not_null(_brush()._walk_batch._unsent, "The event's rectangles wait for the frame")
    _brush()._walk_batch.flush()
    assert_null(_brush()._walk_batch._unsent, "and the frame commits them")
    assert_true(doc._dirty_chunks.has(Vector2i.ZERO), "The frame's dabs reached the compositor before it composites")
    var dirty: Rect2i = doc._dirty_chunks.get(Vector2i.ZERO, Rect2i())
    assert_true(dirty.has_point(Vector2i(MID) - Vector2i(1, 0)), "down to the last dab, %s" % dirty)
    _button(false)


func test_a_walk_commits_its_dabs_once() -> void:
    var counter: Array[int] = [0]
    var batch := SaWalkBatch.new(SaDynamics.new(), SaDabPattern.new())
    batch.open(null)
    for i in 30:
        batch.invalidate(CountingContext.new(counter))
    assert_eq(counter[0], 0, "Thirty dabs of a walk commit nothing while it runs")
    batch.close()
    assert_eq(counter[0], 0, "nor when it ends")
    batch.flush()
    assert_eq(counter[0], 1, "and once when the frame flushes")


func test_a_dab_outside_a_walk_commits_at_once() -> void:
    var counter: Array[int] = [0]
    var batch := SaWalkBatch.new(SaDynamics.new(), SaDabPattern.new())
    batch.invalidate(CountingContext.new(counter))
    batch.invalidate(CountingContext.new(counter))
    assert_eq(counter[0], 2, "The press's dab and the airbrush's commit as they always did")


func test_a_dab_on_another_mask_commits_what_the_walk_held() -> void:
    var counter: Array[int] = [0]
    var batch := SaWalkBatch.new(SaDynamics.new(), SaDabPattern.new())
    batch.open(null)
    batch.invalidate(CountingContext.new(counter))
    batch.invalidate(CountingContext.new(counter, SaMask.new()))
    assert_eq(counter[0], 1, "A context the walk's cannot take commits the walk's first")
    batch.close()
    batch.flush()
    assert_eq(counter[0], 2, "and its own at the frame's end")


func test_the_softness_table_is_built_once_until_it_moves() -> void:
    var tip: Resource = SaBrushTipScript.new()
    tip.softness_curve = Curve.new()
    tip.softness_curve.add_point(Vector2(0, 1))
    tip.softness_curve.add_point(Vector2(1, 0))
    tip.softness = 0.5
    var first: PackedFloat32Array = tip.softness_table()
    assert_true(tip._table_fresh, "The first ask keeps its table")
    assert_eq(tip.softness_table(), first, "and the second answers it")

    tip.softness = 0.9
    assert_false(tip.softness_table() == first, "A new softness is a new table")

    var before: PackedFloat32Array = tip.softness_table()
    tip.softness_curve.set_point_value(0, 0.25)
    assert_false(tip._table_fresh, "An edit in the curve drops the kept table")
    assert_false(tip.softness_table() == before, "and the next ask reads the edit")


func test_the_dynamics_read_an_option_once_a_walk() -> void:
    var dynamics := SaDynamics.new()
    dynamics.settings = _brush().settings
    var option: SaCurveOption = dynamics._option("size_option")
    assert_not_null(option, "The brush carries a size option")
    dynamics.hold()
    assert_eq(dynamics._option("size_option"), option, "Held, the option is the one read")
    dynamics.settings = null
    assert_eq(dynamics._option("size_option"), option, "and stays it for the rest of the walk")
    dynamics.release()
    assert_null(dynamics._option("size_option"), "Released, the settings are read afresh")
