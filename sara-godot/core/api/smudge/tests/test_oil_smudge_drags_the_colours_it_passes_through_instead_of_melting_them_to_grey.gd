## Oil Smudge drags the colours it passes through instead of
## melting them to grey.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The painter dragged Oil Smudge at size 200 across dots in four hues and the
## band came out one grey. `smudge_pickup.gmacs` reduces the paint under a dab
## to one colour and the dab lays it over every texel inside the tip, so at two
## hundred pixels the hues were averaged away before the dab ever ran.
## [SaSmudgeField] keeps the picture that mean was taken of, on a lattice fixed
## to the tip, and this suite dispatches its kernel over textures it filled and
## reads the lattice back, which a test may do and the brush never does.
##
## **The arithmetic here, the stroke in the scenario.**
## `scenarios/oil-smudge-drags-the-colours-it-passes-through-instead-of-melting-them-to-grey.json`
## drags the shipped preset through a field of dots and dumps the texels along
## the band, which is what a painter would call the bug.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## The snapshot the tests fill, and the dab's box on it: a tip in the middle
## whose lattice reads whole texels, one to a cell.
const SNAPSHOT := Vector2i(64, 64)
const REGION := Rect2i(16, 16, 32, 32)
const CENTRE := Vector2(32.0, 32.0)
## Where the two colours of the split snapshot meet.
const JOIN: int = 32

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
const NOTHING := Color(0.0, 0.0, 0.0, 0.0)

## The field that walks each carry, kept so its lattice remembers its cells
## from one dab of a stroke to the next the way the reservoir's does.
var _fields: Dictionary = {}

## The rates the tests dispatch at: half the paint under a cell enters it, and
## three quarters of its load survives a dab off the paint.
const PICKUP: float = 0.5
const KEEP: float = 0.75


func _filled(size: Vector2i, colour: Color) -> SaTexture:
    var texture := SaTexture.new(size)
    texture.clear(colour)
    return texture


## A snapshot whose texels left of [constant JOIN] are *left* and the rest are
## *right*, so one lattice reads both colours.
func _split(size: Vector2i, left: Color, right: Color) -> SaTexture:
    var texture := SaTexture.new(size)
    var texels := PackedFloat32Array()
    texels.resize(size.x * size.y * 4)
    for y in range(size.y):
        for x in range(size.x):
            var colour := left if x < JOIN else right
            var at := (y * size.x + x) * 4
            texels[at] = colour.r
            texels[at + 1] = colour.g
            texels[at + 2] = colour.b
            texels[at + 3] = colour.a
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, texels.to_byte_array())
    return texture


## A carry the field writes its lattice into, cleared the way the reservoir
## clears the one it makes on the first dab.
func _carry() -> SaTexture:
    var texture := SaTexture.new(SaSmudgeField.CARRY)
    texture.clear(NOTHING)
    return texture


## One pass of the field over *snapshot* into *carry*, the way
## [method SaSmudgeReservoir.submit] records it, over the dab whose box is
## *region*. *first* is the stroke's first dab.
func _carried(snapshot: SaTexture, carry: SaTexture, region: Rect2i, first: bool) -> SaSmudgeField.Plan:
    var planned := SaSmudgeField.plan(region, Vector2(region.position) + Vector2(region.size) * 0.5, PICKUP, KEEP)
    if first or not _fields.has(carry):
        _fields[carry] = SaSmudgeField.new()
    var field := _fields[carry] as SaSmudgeField
    field.bind(snapshot, carry)
    var recorded: Array[SaCompute.Recorded] = [field.record(planned, Vector2i.ZERO, 1.0, first)]
    SaCompute.submit(recorded, "probe field")
    return planned


## The cell *at* of the lattice in *carry*, its colour and the load it holds,
## read back out of the premultiplied pair the kernel stores.
func _cell(carry: SaTexture, at: Vector2i) -> Array:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(carry.rid, 0)
    var base := ((at.y + 1) * SaSmudgeField.CARRY.x + at.x) * 16
    var held := bytes.decode_float(base + 12)
    var colour := Color(bytes.decode_float(base), bytes.decode_float(base + 4), bytes.decode_float(base + 8), 1.0)
    if held > 0.0:
        colour = Color(colour.r / held, colour.g / held, colour.b / held, 1.0)
    return [colour, held]


## One texel of row 0 of *carry*, where the frame the dab reads sits.
func _row_zero(carry: SaTexture, at: int) -> PackedFloat32Array:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(carry.rid, 0)
    var base := at * 16
    return PackedFloat32Array(
        [bytes.decode_float(base), bytes.decode_float(base + 4), bytes.decode_float(base + 8), bytes.decode_float(base + 12)]
    )


## The colour of the carry's texel 0, what the pickup's mean leaves for the dab
## to lay over the whole tip.
func _mean(snapshot: SaTexture) -> Color:
    var carry := SaTexture.new(SaSmudgeReservoir.SIZE)
    carry.clear(NOTHING)
    var compute := SaCompute.new("smudge_pickup")
    compute.use_storage_format(snapshot.format)
    compute.set_texture(0, snapshot.rid)
    compute.set_texture(1, carry.rid)
    # Held in locals, because a buffer freed with its last reference takes the
    # uniform set the dispatch below needs with it.
    var variance := SaCompute.Buffer.new(PackedFloat32Array([0.0]).to_byte_array())
    var exchange := SaCompute.Buffer.new(PackedInt32Array([0, 0]).to_byte_array())
    compute.set_buffer(SaSmudgeReservoir.BUFFER_BINDING, variance.rid)
    compute.set_buffer(SaSmudgeReservoir.EXCHANGE_BINDING, exchange.rid)
    compute.set_push_constant_float_array(PackedFloat32Array([CENTRE.x, CENTRE.y, 16.0, PICKUP, KEEP, 0.0, 1.0, 0.0]))
    compute.dispatch_kernel("smudge_pickup", 1, 1, 1)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(carry.rid, 0)
    return Color(bytes.decode_float(0), bytes.decode_float(4), bytes.decode_float(8), bytes.decode_float(12))


func _assert_colour(got: Color, want: Color, what: String) -> void:
    assert_almost_eq(got.r, want.r, 0.01, "%s: red" % what)
    assert_almost_eq(got.g, want.g, 0.01, "%s: green" % what)
    assert_almost_eq(got.b, want.b, 0.01, "%s: blue" % what)


## The bug itself: the pickup's one colour against the lattice's many.
func test_the_lattice_holds_both_colours_where_the_pickup_holds_one_mean() -> void:
    var snapshot := _split(SNAPSHOT, RED, BLUE)
    var carry := _carry()
    var planned := _carried(snapshot, carry, REGION, true)

    # Two of the pickup's five columns fall left of the join and three on it or
    # right of it, so its one colour is two fifths of the red and three of the
    # blue, and the dab lays that purple over every texel inside the tip.
    var mean := _mean(snapshot)
    _assert_colour(mean, Color(0.4, 0.0, 0.6, 1.0), "The pickup leaves one colour, the mean of the two")

    # Cell j reads document pixel `corner.x + j`, one texel to a cell at this
    # size, so the cells left of the join are red and the rest are blue.
    var left := JOIN - planned.corner.x - 1
    _assert_colour(_cell(carry, Vector2i(left, 4))[0], RED, "The last cell over the red side holds red")
    _assert_colour(_cell(carry, Vector2i(left + 1, 4))[0], BLUE, "and the first over the blue side holds blue")
    assert_eq(planned.cell, 1, "One texel to a cell at this size, so no averaging stands between the two")


## The drag: a cell is the same place under the tip on every dab, so a cell
## that held red and now sits over blue lays the red it carried.
func test_a_cell_carries_what_it_held_when_the_tip_moves_on() -> void:
    var snapshot := _split(SNAPSHOT, RED, BLUE)
    var carry := _carry()
    var first := _carried(snapshot, carry, REGION, true)
    var moved := REGION
    moved.position.x += 4
    var second := _carried(snapshot, carry, moved, false)

    assert_eq(second.corner.x - first.corner.x, 4, "The tip moved four pixels along the stroke")
    # Cell j of the second dab sits over document pixel `corner.x + j`, which is
    # blue for the four cells that held red before the tip moved.
    var dragged := JOIN - second.corner.x
    _assert_colour(
        _cell(carry, Vector2i(dragged, 4))[0],
        Color(0.5, 0.0, 0.5, 1.0),
        "A cell that held red and now sits over blue holds half the red it carried"
    )
    _assert_colour(_cell(carry, Vector2i(dragged - 1, 4))[0], RED, "A cell still over the red holds red")
    _assert_colour(_cell(carry, Vector2i(dragged + 4, 4))[0], BLUE, "and one that never saw the red holds blue")


## The carry's load, read cell by cell: a cell off the paint keeps its colour
## and thins by the smear length, which is what caps the dab's alpha there.
func test_a_cell_off_the_paint_keeps_its_colour_and_thins_by_the_smear_length() -> void:
    var carry := _carry()
    _carried(_filled(SNAPSHOT, RED), carry, REGION, true)
    var seeded: Array = _cell(carry, Vector2i(4, 4))
    assert_almost_eq(seeded[1] as float, 1.0, 0.001, "The first dab over paint starts the cell at a full load")

    _carried(_filled(SNAPSHOT, NOTHING), carry, REGION, false)
    var thinned: Array = _cell(carry, Vector2i(4, 4))
    assert_almost_eq(thinned[1] as float, KEEP, 0.001, "A dab off the paint thins the cell by the smear length")
    _assert_colour(thinned[0] as Color, RED, "and the cell still carries the red it picked up")


## Hard rule 2 in the lattice's own numbers: the dispatch is the tip's grid and
## never the canvas, whatever the radius.
func test_the_lattice_stays_small_whatever_the_radius() -> void:
    for side: int in [8, 64, 200, 2000]:
        var planned := SaSmudgeField.plan(Rect2i(0, 0, side, side), Vector2(side, side) * 0.5, PICKUP, KEEP)
        assert_true(planned.count.x <= SaSmudgeField.SIDE, "A tip of %d pixels reads at most 64 cells across" % side)
        assert_true(planned.count.y <= SaSmudgeField.SIDE, "and at most 64 down")
        assert_true(planned.wanted().encloses(Rect2i(0, 0, side, side)), "and the cells cover the dab's box")


## The frame the dab reads: `sa_smudge_blurred` maps the dab's own texels onto
## the lattice through texels 2 and 3 of row 0, and this is that arithmetic run
## against the cells the pass wrote.
func test_the_frame_puts_the_dab_s_texels_on_the_cells_under_them() -> void:
    var carry := _carry()
    var planned := _carried(_filled(SNAPSHOT, RED), carry, REGION, true)
    var frame := _row_zero(carry, 2)
    var count := _row_zero(carry, 3)
    assert_eq(int(count[0]), planned.count.x, "The lattice says how many cells the dab reads")

    var centre := Vector2(REGION.position) + Vector2(REGION.size) * 0.5
    var first_pixel := Vector2(planned.corner) + Vector2.ONE * (float(planned.cell) - 1.0) * 0.5
    var at := Vector2(frame[0], frame[1]) + (first_pixel - centre) * frame[2]
    assert_almost_eq(at.x, 0.0, 0.001, "The first cell's own pixel reads cell nought")
    var last := first_pixel + Vector2(planned.count - Vector2i.ONE) * float(planned.cell)
    var ends := Vector2(frame[0], frame[1]) + (last - centre) * frame[2]
    assert_almost_eq(ends.x, float(planned.count.x - 1), 0.001, "and the last cell's reads the last cell")


## Only a brush that reads a lattice pays for one: the stamp asks for the
## picture and the noise brush, whose dab reads texel 0 alone, does not.
func test_the_carry_grows_to_the_lattice_only_for_a_brush_that_asked() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    var layer := easel.document.active_layer
    layer.get_or_create_chunk(Vector2i(0, 0)).clear(RED)

    var asked := SaSmudgeReservoir.new(easel, layer, false, REGION, null, true)
    asked.pick_up(REGION, CENTRE, 16.0, PICKUP, KEEP, 0.5, SaSmudgePage.SMEARING)
    assert_not_null(asked.field, "A brush that reads a picture carries one")
    assert_eq(asked.texture.size, SaSmudgeField.CARRY, "and its carry is the taller one the lattice lives in")

    var plain := SaSmudgeReservoir.new(easel, layer, false, REGION)
    plain.pick_up(REGION, CENTRE, 16.0, PICKUP, KEEP, 0.5, SaSmudgePage.SMEARING)
    assert_null(plain.field, "A brush that did not ask carries one colour")
    assert_eq(plain.texture.size, SaSmudgeReservoir.SIZE, "and its carry is the row it always was")

    var dulling := SaSmudgeReservoir.new(easel, layer, false, REGION, null, true)
    dulling.pick_up(REGION, CENTRE, 16.0, PICKUP, KEEP, 0.5, SaSmudgePage.DULLING)
    assert_null(dulling.field, "A dulling stroke lays what stands where it is, so it drags nothing")

    easel.free()
