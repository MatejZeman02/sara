## Attaching or applying a filter does not stall. The timers
## found three things behind the 110 ms of an attach and the 83 ms to 178 ms of
## an apply, and this suite holds each of them.
##
## The ledger's frame gap counted the idle iterations of a wait, which low
## processor mode draws nothing in, as one long wait for a frame. The layers
## docker rebuilt its closed More list on every `document_changed`, 4 ms each.
## A one-shot and a flatten announced `document_changed` twice.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")

## Needs a RenderingDevice, for the documents the filter and the docker use.
const REQUIRES_GPU := true

const IDLE_USEC := 6000
const IDLE_ITERATIONS := 10

var _changes := 0


func before_each() -> void:
    SaStrokeLedger.reset()
    _changes = 0


func after_each() -> void:
    SaStrokeLedger.reset()


func _count_change() -> void:
    _changes += 1


## Ten iterations that draw nothing and then one that draws, the shape of a
## scenario's `wait 10` after a click. The wait for the frame is the last
## iteration, not all eleven.
func test_idle_iterations_are_not_a_wait_for_a_frame() -> void:
    SaStrokeLedger.frame_drawn()
    SaStrokeLedger.frame_ticked()
    for i in IDLE_ITERATIONS:
        OS.delay_usec(IDLE_USEC)
        SaStrokeLedger.frame_ticked()
    OS.delay_usec(IDLE_USEC)
    SaStrokeLedger.frame_drawn()
    var whole := IDLE_USEC * (IDLE_ITERATIONS + 1)
    assert_true(
        SaStrokeLedger.frame_gap_usec_max < whole * 0.5,
        "The gap is one or two iterations, %d us, not the %d us of the whole wait" % [SaStrokeLedger.frame_gap_usec_max, whole]
    )
    assert_true(SaStrokeLedger.frame_gap_usec_max >= IDLE_USEC, "but still the iteration that drew")


## An iteration that never draws is still a wait, so a long one is not hidden
## by the clock starting again after it.
func test_a_long_iteration_that_draws_nothing_still_counts() -> void:
    SaStrokeLedger.frame_ticked()
    OS.delay_usec(IDLE_USEC * 5)
    SaStrokeLedger.frame_ticked()
    assert_true(
        SaStrokeLedger.frame_gap_usec_max >= IDLE_USEC * 5,
        "The long iteration is the gap, %d us" % SaStrokeLedger.frame_gap_usec_max
    )


## Work done in an iteration after an idle one, the click handled before the
## next tick, stays inside the wait it causes.
func test_the_click_after_an_idle_iteration_stays_in_the_wait() -> void:
    SaStrokeLedger.frame_ticked()
    OS.delay_usec(IDLE_USEC)
    SaStrokeLedger.frame_ticked()
    OS.delay_usec(IDLE_USEC * 4)
    SaStrokeLedger.frame_drawn()
    assert_true(
        SaStrokeLedger.frame_gap_usec_max >= IDLE_USEC * 4,
        "The work before the drawn frame is in the gap, %d us" % SaStrokeLedger.frame_gap_usec_max
    )


## A flatten announces the write once. The second announcement ran every
## listener, the layers docker and the thumbnails among them, again.
func test_a_flatten_announces_the_write_once() -> void:
    var easel := Bench.easel(Vector2i(256, 256))
    var doc := easel.document
    doc.fill_layer(Color(0.25, 0.5, 0.75, 1.0), doc.active_layer)
    Bench.composite(easel)
    var ops := SaFilterOps.new(doc)
    var record := ops.attach(doc.active_layer, Bench.INVERT)
    doc.document_changed.connect(_count_change)
    assert_true(ops.flatten(doc.active_layer, record), "The attached invert flattens")
    assert_eq(_changes, 1, "and says so once")
    easel.free()


## The docker leaves a closed More list as it was, and the list is built from
## the active layer when it opens or when an item is pressed. Group stands on
## the row as a button when there is room, so the row is folded to nothing here
## to put Group back in the list.
func test_a_closed_more_list_waits_for_its_open() -> void:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    var docker: LayersDocker = LayersDockerScript.new()
    docker.name = "LayersDocker"
    canvas.add_child(docker)
    docker.target_canvas = canvas
    docker._ready()
    var actions := docker.actions
    actions.op_buttons.fit(0.0)
    actions.sync_from_active_layer()
    var group_row := actions.row_id_of(SaLayerActions.Item.GROUP)
    assert_false(actions.menu.visible, "The list starts closed")
    assert_eq(actions.menu.label_button(group_row).text, "Group", "and offers Group")

    actions.toggle_group()
    assert_true(docker.active_layer().is_group, "Group made the group active")
    assert_eq(actions.menu.label_button(group_row).text, "Group", "and the closed list was not built again")

    assert_true(actions.press_item(SaLayerActions.Item.GROUP), "Pressing the entry builds the list first")
    assert_false(docker.active_layer().is_group, "so it read Ungroup and dissolved the group")
    canvas.free()
