## A walk's plain dabs go to the card as one dispatch a chunk at the walk's end,
## and paint what one dispatch a dab painted, to the bit.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Each dab of a small tip as a compute list and a dispatch of its own would be
## thirty an event for a 6 px Wash. `SaWalkBatch` holds a walk's plain dabs as records and
## `dabs.gmacs` runs them at each texel in order. What this holds is the count,
## the texels, and which dabs are still sent on their own. The timing is the
## scenario's, `scenarios/a-small-brush-keeps-up-with-the-pen-on-windows.json`,
## The batches are held on to
## the frame's [method SaWalkBatch.flush], so these send it by hand where a
## frame would, and `test_a_frames_reports_go_to_the_card_as_one_list.gd` holds
## the frame.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## Never the real `user://brush_presets`, which is the painter's own folder.
static var scratch_dir: String = SaDataRoot.path("test_d18_presets")
## A 2 px tip on the 256 px canvas, the scenario's smallest size.
const SMALL_RADIUS: float = 1.0 / 256.0
## The press and two reports, inside the first chunk so every dab touches one.
const FROM := Vector2(20, 40)
const MID := Vector2(120, 40)
const TO := Vector2(220, 40)
## The texture the kernel test paints, two workgroups short of a chunk so the
## dabs' boxes differ from the union of them all.
const SIDE: int = 64
## Where density and randomness sit in the dab's push constant, the order of
## `dab.gmacs`'s params, which the packing leaves at their neutral values.
const DENSITY_AT: int = 19
const RANDOMNESS_AT: int = 20

var _surface: SaSurface = null
var _machine: ToolMachine = null
## The tip mask the kernel test bound last.
var _tip_mask: SaBrushTipMask = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")


func after_each() -> void:
    _tip_mask = null
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


## The lists and dispatches the tally holds for *key*, as a pair.
static func _tally(key: String) -> Vector2i:
    var entry: Dictionary = SaCompute.kernel_counters().get(key, {})
    return Vector2i(int(entry.get("lists", 0)), int(entry.get("dispatches", 0)))


## *preset* at 2 px, pressed at [constant FROM] and reported at [constant MID].
## Answers false when the shipped recipe could not be loaded.
func _small(preset: String) -> bool:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(_brush().settings, ShippedPresetsScript)
    if not store.apply_preset(preset, _brush().settings):
        return false
    _brush().settings.radius = SMALL_RADIUS
    _surface.view.mouse_position = FROM
    _button(true)
    _motion(MID)
    return true


func test_an_events_dabs_are_one_list_and_one_dispatch_a_chunk() -> void:
    for preset: String in ["Pencil", "Wash"]:
        assert_true(_small(preset), "%s loads" % preset)
        var held_before := _tally("dabs/dabs")
        var alone_before := _tally("dab/dab")
        var dabs_before := SaStrokeLedger.dabs
        var laid_before: int = _brush().stroke_info.dab_index
        _motion(TO)
        assert_eq(_tally("dabs/dabs") - held_before, Vector2i.ZERO, "An event's dabs wait for the frame")
        _brush()._walk_batch.flush()
        var held := _tally("dabs/dabs") - held_before
        var laid: int = _brush().stroke_info.dab_index - laid_before
        assert_true(laid >= 50, "A 2 px %s lays many dabs over 100 px of one event, %d here" % [preset, laid])
        assert_eq(held, Vector2i(1, 1), "and they reach the card as one list and one dispatch, the one chunk the run crosses")
        assert_eq(_tally("dab/dab") - alone_before, Vector2i.ZERO, "with none of them dispatched on its own")
        assert_eq(SaStrokeLedger.dabs - dabs_before, laid, "The ledger still counts every dab the walk laid")
        _button(false)


## A tap lays the press's held dab at the release, outside any walk, and that
## dab goes at once through the one dab kernel as it always did.
func test_a_taps_dab_still_goes_on_its_own() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(_brush().settings, ShippedPresetsScript)
    assert_true(store.apply_preset("Pencil", _brush().settings), "Pencil loads")
    var alone_before := _tally("dab/dab")
    var held_before := _tally("dabs/dabs")
    _surface.view.mouse_position = FROM
    _button(true)
    _button(false)
    assert_eq(_tally("dab/dab").y - alone_before.y, 1, "A tap paints its one dab at once")
    assert_eq(_tally("dabs/dabs") - held_before, Vector2i.ZERO, "and holds nothing")


## A dab whose bindings move from dab to dab goes now, and one that does not
## waits, which is the whole of the rule the brush asks.
func test_a_dab_goes_alone_when_what_it_binds_moves() -> void:
    var tip: Resource = SaBrushTipScript.new()
    var mask := SaBrushTipMask.load_image("")
    var plain := SaDabParams.new()
    assert_false(SaWalkBatch.goes_alone(plain, tip, mask, null), "A plain dab of a procedural tip waits")
    var smudging := SaDabParams.new()
    smudging.smudge = true
    assert_true(SaWalkBatch.goes_alone(smudging, tip, mask, null), "A smudging dab goes now, the next pickup reads what it laid")
    assert_true(SaWalkBatch.goes_alone(plain, tip, null, null), "A tip with no mask loaded yet goes now and loads it")
    var masking := SaMaskingBrush.new()
    masking.enabled = true
    assert_true(masking.active(), "The masking brush is on")
    assert_true(SaWalkBatch.goes_alone(plain, tip, mask, masking), "and a masked dab goes now, its block is its own")
    masking.enabled = false
    assert_false(SaWalkBatch.goes_alone(plain, tip, mask, masking), "A masking brush that is off holds nothing back")


## One target over *texture* at the box *box*, for a context built by hand.
static func _target(texture: SaTexture, selection: SaTexture, box: Rect2i, centre: Vector2) -> SaPaintContext.Target:
    var target := SaPaintContext.Target.new()
    target.texture = texture
    target.mask = selection
    target.render_offset = Vector2(box.position)
    @warning_ignore("integer_division")
    target.groups_x = box.size.x / SaPaintContext.WORKGROUP
    @warning_ignore("integer_division")
    target.groups_y = box.size.y / SaPaintContext.WORKGROUP
    target.local_center = centre
    return target


## The dab kernel's bindings that are not the canvas or the selection, the ones
## a walk shares, onto *compute*. The mask is kept, as the brush keeps it,
## because its softness table is freed with it.
func _bind_shared(compute: SaCompute, tip: Resource) -> void:
    _tip_mask = SaStampBindings.bind(compute, tip, _tip_mask)


## The push constant of dab *i* of the run the kernel test paints: a small wash
## tip for even dabs and a build-up one for odd, thinned by randomness and
## dropped by density, so a texel's answer depends on each dab's own seed.
## *flip* is the mirror's bits, which symmetry sets on an image it reflects.
static func _pack(i: int, target: SaPaintContext.Target, tip: Resource, flip: int) -> PackedFloat32Array:
    var data := SaDabPacking.pack_dab_params(
        target.local_center,
        target.render_offset,
        Color(0.2 + 0.02 * i, 0.4, 0.8 - 0.01 * i, 0.7),
        tip.half_extent(),
        0.3 * i,
        tip.effective_fade(),
        0.5,
        SaDabGeometry.PaintMode.ALPHA_DARKEN if i % 2 == 0 else SaDabGeometry.PaintMode.OVER,
        false,
        tip,
        0.0,
        0.0,
        float(i)
    )
    data[DENSITY_AT] = 0.8
    data[RANDOMNESS_AT] = 0.4
    data[SaDabGeometry.MIRROR_INDEX] = float(flip)
    return data


## The box a dab at *centre* dispatches over, aligned out to whole workgroups.
static func _box(centre: Vector2, reach: float) -> Rect2i:
    var low := ((centre - Vector2(reach, reach)) / SaPaintContext.WORKGROUP).floor() * SaPaintContext.WORKGROUP
    var high := ((centre + Vector2(reach, reach)) / SaPaintContext.WORKGROUP).ceil() * SaPaintContext.WORKGROUP
    return Rect2i(Vector2i(low), Vector2i(high - low))


func test_one_dispatch_of_a_walks_dabs_paints_what_one_a_dab_painted() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var tip: Resource = SaBrushTipScript.new()
    tip.diameter = 6.0
    tip.horizontal_fade = 0.6
    tip.vertical_fade = 0.6
    var selection := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    selection.clear(Color(1.0, 1.0, 1.0, 1.0))
    var alone := SaTexture.new(Vector2i(SIDE, SIDE))
    var held := SaTexture.new(Vector2i(SIDE, SIDE))
    for texture: SaTexture in [alone, held]:
        rd.texture_clear(texture.rid, Color(0.9, 0.1, 0.1, 0.5), 0, 1, 0, 1)

    var compute := SaCompute.new("dab")
    _bind_shared(compute, tip)
    var batch := SaWalkBatch.new(SaDynamics.new(), SaDabPattern.new())
    batch.open(null)
    var bind := _bind_shared.bind(tip)
    var boxes: Array[Rect2i] = []
    for i in 40:
        # Down one diagonal and back up it, so every texel on it is painted by
        # dabs laid far apart in the run. Each dab has an image mirrored across
        # the middle, as symmetry lays one, so the two diagonals cross and a
        # texel there is painted by both images of a dab. The second image is in
        # the second pass, which `SaPaintContext.dispatch_batch` puts a barrier
        # before, and the walk's one dispatch has none to put.
        var along := float(i if i < 20 else 39 - i)
        var centre := Vector2(10.0 + 2.2 * along, 12.0 + 1.9 * along)
        var paint := SaPaintContext.new()
        for image in 2:
            var at := centre if image == 0 else Vector2(SIDE - centre.x, centre.y)
            var box := _box(at, 6.0)
            boxes.append(box)
            compute.set_texture(0, alone.rid)
            compute.set_texture(SaSelection.BINDING, selection.rid)
            var target := _target(alone, selection, box, at)
            compute.set_push_constant_float_array(_pack(i, target, tip, image))
            compute.dispatch_kernel("dab", target.groups_x, target.groups_y, 1)
            var reached := _target(held, selection, box, at)
            reached.pass_index = image
            paint.targets.append(reached)
        var pack := func(on: SaPaintContext.Target) -> PackedFloat32Array: return _pack(i, on, tip, on.pass_index)
        assert_true(batch.hold(paint, pack, 0.0, false, bind), "Dab %d and its image are held for the walk's end" % i)
    var before := _tally("dabs/dabs")
    batch.close(bind)
    batch.flush()
    assert_eq(_tally("dabs/dabs") - before, Vector2i(1, 1), "The forty and their images go as one dispatch")
    var union := boxes[0]
    for box in boxes:
        union = union.merge(box)
    assert_true(union.size.x > boxes[0].size.x * 2, "over a box far wider than one dab's, %s" % union)

    var cleared := SaTexture.new(Vector2i(SIDE, SIDE))
    rd.texture_clear(cleared.rid, Color(0.9, 0.1, 0.1, 0.5), 0, 1, 0, 1)
    var untouched := rd.texture_get_data(cleared.rid, 0)
    var one_a_dab := rd.texture_get_data(alone.rid, 0)
    var one_a_walk := rd.texture_get_data(held.rid, 0)
    var differing := 0
    var painted := 0
    for at in range(0, one_a_dab.size(), 16):
        if one_a_dab.slice(at, at + 16) != one_a_walk.slice(at, at + 16):
            differing += 1
        if one_a_dab.slice(at, at + 16) != untouched.slice(at, at + 16):
            painted += 1
    assert_true(painted > 400, "The forty dispatches painted the diagonal, %d texels" % painted)
    assert_eq(differing, 0, "and the one dispatch painted each of its float texels the same, to the bit")


## Outside a walk, and into a layer's own chunks, a dab is not held: the first
## commits as it always did and the second's snapshot copies what the dab before
## it painted.
func test_a_dab_is_held_only_inside_a_walk_and_into_the_buffer() -> void:
    var batch := SaWalkBatch.new(SaDynamics.new(), SaDabPattern.new())
    var paint := SaPaintContext.new()
    var pack := func(_on: SaPaintContext.Target) -> PackedFloat32Array: return PackedFloat32Array()
    assert_false(batch.hold(paint, pack, 0.0, false, Callable()), "A dab outside a walk goes now")
    batch.open(null)
    assert_false(batch.hold(paint, pack, 0.0, true, Callable()), "A dab that goes alone is not held")
    paint.draw_direct = true
    assert_false(batch.hold(paint, pack, 0.0, false, Callable()), "Nor is one painting straight into a layer")
    batch.close()


## A walk longer than the records a send takes sends them part way and goes on
## holding, so no texel of a long flick tests more boxes than that.
func test_a_long_walk_sends_its_records_in_parts() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var tip: Resource = SaBrushTipScript.new()
    tip.diameter = 2.0
    var selection := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    selection.clear(Color(1.0, 1.0, 1.0, 1.0))
    var canvas := SaTexture.new(Vector2i(SIDE, SIDE))
    rd.texture_clear(canvas.rid, Color(0, 0, 0, 0), 0, 1, 0, 1)
    var batch := SaWalkBatch.new(SaDynamics.new(), SaDabPattern.new())
    var bind := _bind_shared.bind(tip)
    batch.open(null)
    var before := _tally("dabs/dabs")
    for i in SaWalkBatch.MOST_RECORDS + 1:
        var centre := Vector2(8.0 + float(i % 48), 32.0)
        var paint := SaPaintContext.new()
        paint.targets.append(_target(canvas, selection, _box(centre, 3.0), centre))
        batch.hold(paint, func(on: SaPaintContext.Target) -> PackedFloat32Array: return _pack(i, on, tip, 0), 0.0, false, bind)
    assert_eq(
        (_tally("dabs/dabs") - before).y,
        1,
        "The walk sent its first %d records when the next would not fit" % SaWalkBatch.MOST_RECORDS
    )
    batch.close(bind)
    batch.flush()
    assert_eq((_tally("dabs/dabs") - before).y, 2, "and the last one at the frame's end")
