## A press on an eye decides the value, and every eye the pointer crosses
## while it is held takes the same value, one undo step for the whole drag.
## `scenarios/drag-over-the-eye-icons.json` is the same proof on the
## running app, where the drag is a real mouse rather than a called method.
##
## The rect-hit-testing half, `SaLayerList._eye_at`, is not exercised here:
## a row never laid out by a live viewport answers `get_global_rect()` with
## whatever `Control.size` defaults to, which is the same zero rect for every
## row and proves nothing about telling them apart. The scenario is where
## that half is driven by a real mouse over a real layout. What a headless
## test can hold is the gesture once a row has been named, the same split
## `test_layer_drag.gd` already draws around the row-reorder drag.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Whether the eye was an undo step when the test began.
var _eye_was: bool


## The eye is a step only while Preferences asks, which a test here
## turns on. Off for each test, and what the suite found restored after it, so
## a run leaves the default as it stood.
func before_each() -> void:
    _eye_was = SaSettings.visibility_in_history
    SaSettings.visibility_in_history = false


func after_each() -> void:
    SaSettings.visibility_in_history = _eye_was


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(128, 128))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


func _docker(easel: SaEasel) -> LayersDocker:
    var canvas := SaCanvas.new()
    canvas.easel = easel
    var docker := LayersDocker.new()
    docker.target_canvas = canvas
    docker.item_list.item_dropped.connect(docker._on_row_dropped)
    docker.sync_layer_list()
    return docker


## Three named layers, bottom of the stack first the way `SaLayerOps.add`
## stacks them, and the rows they build: row 0 is the top of the stack, the
## same order the docker draws them in.
func _three_layers() -> Dictionary:
    var easel := _easel()
    var doc := easel.document
    doc.active_layer.name = "Bottom"
    SaLayerOps.new(doc).add().name = "Middle"
    SaLayerOps.new(doc).add().name = "Top"
    var docker := _docker(easel)
    return {"easel": easel, "docker": docker, "rows": docker.item_list}


func _free_three(state: Dictionary) -> void:
    var canvas: SaCanvas = state["docker"].target_canvas
    state["docker"].free()
    canvas.free()
    state["easel"].free()


## "The press on an eye decides on or off": arming the drag on a shown
## layer's row and letting the pointer settle there hides it, the same
## answer a plain click already gives.
func test_the_press_decides_the_value() -> void:
    var state := _three_layers()
    var rows: SaLayerList = state["rows"]
    var top := rows.layer_at(0) as SaLayer
    assert_true(top.visible, "starts shown")

    rows._arm_eye(0, Vector2.ZERO)
    rows._apply_eye(0)
    assert_false(top.visible, "the press decided hidden, the opposite of shown")

    rows._finish_eye()
    assert_false(rows.is_processing_input(), "the release hands the travel and the release back")
    _free_three(state)


## "Every eye the pointer crosses while it is held takes the same value":
## three rows, one press, and the drag settling on each in turn leaves every
## one at the value the first row decided, not each flipped from its own.
func test_every_row_the_drag_crosses_takes_the_same_value() -> void:
    var state := _three_layers()
    var rows: SaLayerList = state["rows"]
    var top := rows.layer_at(0) as SaLayer
    var middle := rows.layer_at(1) as SaLayer
    var bottom := rows.layer_at(2) as SaLayer
    middle.visible = false

    rows._arm_eye(0, Vector2.ZERO)
    for i: int in [0, 1, 2]:
        rows._apply_eye(i)

    assert_false(top.visible, "hidden, the press's own answer")
    assert_false(middle.visible, "already hidden, and stays that way rather than showing")
    assert_false(bottom.visible, "crossed last, still the same value as the other two")
    rows._finish_eye()
    _free_three(state)


## "One history step for the drag": three layers change and the history
## gains one step, not three, and undoing it puts every layer back where it
## was rather than all three on one shared value.
func test_the_whole_drag_is_one_undo_step() -> void:
    SaSettings.visibility_in_history = true
    var state := _three_layers()
    var rows: SaLayerList = state["rows"]
    var doc: SaDocument = state["easel"].document
    var top := rows.layer_at(0) as SaLayer
    var middle := rows.layer_at(1) as SaLayer
    var bottom := rows.layer_at(2) as SaLayer
    middle.visible = false
    var version_before := doc.undo_redo.get_version()

    rows._arm_eye(0, Vector2.ZERO)
    for i: int in [0, 1, 2]:
        rows._apply_eye(i)
    rows._finish_eye()

    assert_eq(doc.undo_redo.get_version(), version_before + 1, "one step, however many eyes it crossed")
    assert_false(top.visible, "hidden")
    assert_false(middle.visible, "already hidden, so not one of the ones this drag actually changed")
    assert_false(bottom.visible, "hidden")

    doc.undo()
    assert_true(top.visible, "back to its own before")
    assert_false(middle.visible, "and middle's own before was already hidden, so it is unmoved by the undo too")
    assert_true(bottom.visible, "back to its own before, not to top's")
    _free_three(state)


## A press that never becomes a drag changes nothing of its own: the button's
## own `pressed` signal is what a plain click answers to, and this gesture
## commits only what the drag itself actually touched.
func test_a_press_that_never_drags_touches_nothing() -> void:
    var state := _three_layers()
    var rows: SaLayerList = state["rows"]
    var doc: SaDocument = state["easel"].document
    var version_before := doc.undo_redo.get_version()

    rows._arm_eye(0, Vector2.ZERO)
    rows._finish_eye()

    assert_eq(doc.undo_redo.get_version(), version_before, "nothing was touched, so nothing was committed")
    _free_three(state)
