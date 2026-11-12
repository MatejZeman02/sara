## The smudge queue: dispatches recorded ahead and sent as one compute list,
## with a barrier wherever one has to wait for the last.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Why a queue.** A smudge dab costs the CPU a list of its
## own for the pickup and a new snapshot texture nearly every dab, so the
## reservoir records its pickups and the dabs after them and sends them in
## one list at the end of the event. What this suite pins is what that rests
## on: one list is counted however many records it carries, each dispatch still
## counts under its own kernel, and a barrier makes the second pickup read the
## carry the first one wrote, as two lists did.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const SNAPSHOT := Vector2i(16, 16)
const CENTRE := Vector2(8.0, 8.0)
const LABEL := "test/smudge-queue"

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
const NOTHING := Color(0.0, 0.0, 0.0, 0.0)

## Held for the length of a test, because a record carries the uniform set of
## its instance and a freed instance would free the set before the submit.
var _held: Array = []


func before_each() -> void:
    _held.clear()


func _filled(size: Vector2i, colour: Color) -> SaTexture:
    var texture := SaTexture.new(size)
    texture.clear(colour)
    _held.append(texture)
    return texture


## One pickup of *snapshot* into *carry*, recorded rather than dispatched.
func _record_pickup(snapshot: SaTexture, carry: SaTexture, pickup: float, first: bool, waits: bool) -> SaCompute.Recorded:
    var compute := SaCompute.new("smudge_pickup")
    var variance := SaCompute.Buffer.new(PackedFloat32Array([0.0]).to_byte_array())
    _held.append(compute)
    _held.append(variance)
    compute.set_texture(0, snapshot.rid)
    compute.set_texture(1, carry.rid)
    compute.set_buffer(SaSmudgeReservoir.BUFFER_BINDING, variance.rid)
    # The height exchange, empty, so the carry's height stays
    # where it stood and the colour is what this suite reads. Without it the
    # kernel is short a binding and no pickup runs.
    var exchange := SaCompute.Buffer.new(PackedInt32Array([0, 0]).to_byte_array())
    _held.append(exchange)
    compute.set_buffer(SaSmudgeReservoir.EXCHANGE_BINDING, exchange.rid)
    compute.set_push_constant_float_array(
        PackedFloat32Array([CENTRE.x, CENTRE.y, 4.0, pickup, 1.0, 1.0, 1.0 if first else 0.0, 0.0])
    )
    return compute.record("smudge_pickup", snapshot.format, 1, 1, 1, waits)


func _colour(carry: SaTexture) -> Color:
    var texels := GlobalShaderCompiler.get_rd().texture_get_data(carry.rid, 0).to_float32_array()
    return Color(texels[0], texels[1], texels[2], texels[3])


# --- The list ------------------------------------------------------------------------


func test_two_records_go_out_as_one_list_and_count_under_their_kernel() -> void:
    var carry := _filled(SaSmudgeReservoir.SIZE, NOTHING)
    var first := _record_pickup(_filled(SNAPSHOT, RED), carry, 0.25, true, true)
    var second := _record_pickup(_filled(SNAPSHOT, BLUE), carry, 0.25, false, true)
    assert_not_null(first, "A pickup with a device records")
    assert_not_null(second, "and so does the next")

    SaCompute.reset_counters()
    assert_eq(SaCompute.lists, 0, "Recording counts nothing, because a record never sent is no work")
    var recorded: Array[SaCompute.Recorded] = [first, second]
    SaCompute.submit(recorded, LABEL)

    assert_eq(SaCompute.lists, 1, "Two dispatches go out as one list")
    assert_eq(SaCompute.dispatches, 2, "and both are counted")
    var table := SaCompute.kernel_counters()
    assert_eq(
        int((table.get(LABEL, {}) as Dictionary).get("lists", 0)), 1, "The list is counted under the label it was sent with"
    )
    var kernel := table.get("smudge_pickup/smudge_pickup", {}) as Dictionary
    assert_eq(int(kernel.get("dispatches", 0)), 2, "and each dispatch under the kernel that did the work")


func test_a_barrier_lets_the_second_pickup_read_what_the_first_wrote() -> void:
    var carry := _filled(SaSmudgeReservoir.SIZE, NOTHING)
    var recorded: Array[SaCompute.Recorded] = [
        _record_pickup(_filled(SNAPSHOT, RED), carry, 0.25, true, true),
        _record_pickup(_filled(SNAPSHOT, BLUE), carry, 0.25, false, true),
    ]
    SaCompute.submit(recorded, LABEL)

    var colour := _colour(carry)
    assert_almost_eq(colour.r, 0.75, 1e-5, "A quarter of the way from the red the first pickup started")
    assert_almost_eq(colour.b, 0.25, 1e-5, "towards the blue the second crossed, as two lists gave")


func test_an_empty_submit_opens_no_list() -> void:
    SaCompute.reset_counters()
    var recorded: Array[SaCompute.Recorded] = []
    SaCompute.submit(recorded, LABEL)
    assert_eq(SaCompute.lists, 0, "Nothing recorded, nothing sent")
