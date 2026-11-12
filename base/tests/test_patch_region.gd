## The patch tool without a selection: the region the tool paints with its
## own circle.
##
## What the tool is graded on: the pass dispatches over the painted region's box
## and not the canvas, a live selection still scopes it, and the mask is freed
## with the stroke. The three are the three cases below, and the two beside them are the drag
## itself, because a region that is never proved to fill anything makes the
## other three assertions about nothing.
##
## The scenario is `scenarios/the-patch-tool-without-a-selection.json`, which
## is where the magenta is looked at: a colour on screen is not a thing a test
## can read, and a shot is not a thing a test can measure.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: the region is selection chunks and the fill is
## compute over them.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const SaPatchScript = preload("res://modules/sara-base-modules/base/patch/sa_patch.gd")
const StatePatchScript = preload("res://modules/sara-base-modules/base/patch/state_patch.gd")

## The canvas, one chunk, so a readback is one texture and a dispatch count is a
## number that can be written down.
const SIDE: int = 256

## What the picture is painted with, and the blemish dropped on it.
const PAPER := Color(0.35, 0.55, 0.75, 1.0)
const BLEMISH := Rect2i(112, 112, 24, 24)

## Where the drag goes, and how wide the tool's circle is while it does.
const FROM := Vector2(104, 124)
const TO := Vector2(144, 124)
const WIDTH: float = 40.0

var _surface: SaSurface = null
var _tool: StatePatchScript = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(SIDE, SIDE))
    _surface.get_document().fill_layer(PAPER)
    _blemish()
    _tool = StatePatchScript.new()
    _tool.surface = _surface
    _tool.region_size = WIDTH


func after_each() -> void:
    _tool = null
    _surface.easel.free()
    _surface = null


## The blemish, painted through the selection and the selection then dropped, so
## the document the cases start from has no selection of its own.
func _blemish() -> void:
    var document := _surface.get_document()
    document.selection.select_rect(BLEMISH)
    document.fill_layer(Color(0.0, 0.0, 0.0, 1.0), document.active_layer)
    document.selection.deselect()
    document.undo_redo.clear_history()


## The view the tool asks where the pointer is, which a test is what moves.
func _view() -> Fixtures.FakeView:
    return _surface.view as Fixtures.FakeView


func _press(at: Vector2) -> void:
    _view().mouse_position = at
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = true
    _tool.handle_input(button)


func _move(at: Vector2) -> void:
    _view().mouse_position = at
    _tool.handle_input(InputEventMouseMotion.new())


func _release() -> void:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = false
    _tool.handle_input(button)


## The texel at *point* of the layer's one chunk.
func _texel_at(point: Vector2i) -> Color:
    var layer := _surface.get_document().active_layer
    var texture: SaTexture = layer.get_field(Vector2i.ZERO)
    var data := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var at := (point.y * SIDE + point.x) * 16
    return Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8), data.decode_float(at + 12))


## The drag itself: a press with no selection opens a region, the motions carry
## it across the blemish, and the release fills what was painted.
func test_a_drag_with_no_selection_paints_a_region_and_patches_it() -> void:
    assert_almost_eq(_texel_at(BLEMISH.get_center()).r, 0.0, 0.01, "the blemish starts black")

    _press(FROM)
    _move(FROM.lerp(TO, 0.5))
    _move(TO)
    assert_true(_tool.preview_shape().has("discs"), "the drag is drawn as discs while the pointer is down")
    assert_true(int(_tool.preview_shape()["discs"].size()) >= 3, "one per stamp, and the drag is more than one")

    _release()

    var centre := _texel_at(BLEMISH.get_center())
    assert_almost_eq(centre.r, PAPER.r, 0.03, "and the paper comes back where the blemish was")
    assert_almost_eq(centre.g, PAPER.g, 0.03, "in every channel")
    assert_almost_eq(centre.b, PAPER.b, 0.03, "including the one the blemish took furthest")
    assert_true(_surface.get_document().undo_redo.has_undo(), "as one history step a painter can take back")


## The first clause. The count is exact rather than a bound, because what is
## asked about is the shape of the dispatch and a bound would pass on a
## fill that ran over the canvas once. Smooth's shape, which the count is of,
## and `test_patch_texture.gd` holds Texture's dispatches to the same rule.
func test_the_dispatch_is_the_regions_box_and_not_the_canvas() -> void:
    _tool.method = SaPatchScript.Method.SMOOTH
    _press(FROM)
    _move(TO)
    # Read before the release, because the release is what frees it, which is
    # the third clause below.
    var bounds: Rect2i = _tool._region.bounds
    assert_true(bounds.size.x < SIDE and bounds.size.y < SIDE, "the region is smaller than the canvas: %s" % bounds)
    var work := bounds.grow(SaPatchScript.RING).intersection(Rect2i(Vector2i.ZERO, Vector2i(SIDE, SIDE)))
    var passes := SaPatchScript.passes_for(work.size)

    SaCompute.reset_counters()
    _release()
    var counted := SaCompute.counters()

    # One clear, one gather over the single chunk the work rectangle touches,
    # one sweep per pass, and one scatter over the single chunk the region
    # touches. Nothing walks the canvas.
    assert_eq(int(counted["dispatches"]), passes + 3, "a dispatch per pass and one each for the three ends")
    var over_the_work := SaCompute.groups_for(work.size.x) * SaCompute.groups_for(work.size.y)
    var over_the_canvas := SaCompute.groups_for(SIDE) * SaCompute.groups_for(SIDE)
    assert_true(
        int(counted["workgroups"]) < over_the_canvas * (passes + 3),
        (
            "the fill costs less than the same passes over the canvas would: %d against %d"
            % [int(counted["workgroups"]), over_the_canvas * (passes + 3)]
        )
    )
    assert_true(
        int(counted["workgroups"]) <= (passes + 3) * over_the_work,
        (
            "every dispatch fits inside the region's work rectangle: %d workgroups against %d for %d of them"
            % [int(counted["workgroups"]), (passes + 3) * over_the_work, passes + 3]
        )
    )


## The second clause. A painter who made a selection meant it, so the press
## patches that and paints no region at all.
func test_a_live_selection_still_scopes_it() -> void:
    var document := _surface.get_document()
    document.selection.select_rect(BLEMISH)

    _press(Vector2(BLEMISH.get_center()))
    _move(TO)

    assert_null(_tool._region, "a press inside a live selection opens no region of the tool's own")
    assert_eq(_tool.preview_shape(), {}, "and there is nothing magenta to draw")
    assert_true(document.undo_redo.has_undo(), "the press patched the selection instead")
    assert_almost_eq(_texel_at(BLEMISH.get_center()).r, PAPER.r, 0.03, "and the selection is what was filled")
    assert_eq(document.selection.bounds, BLEMISH, "with the selection left where the painter drew it")


## A press outside a live selection is still a painter aiming badly rather than
## a request to paint a region somewhere else, which is the patch tool's
## behaviour and the clause above leaves standing.
func test_a_press_outside_a_live_selection_starts_nothing() -> void:
    var document := _surface.get_document()
    document.selection.select_rect(BLEMISH)

    _press(Vector2(20, 20))

    assert_null(_tool._region, "no region was opened")
    assert_false(document.undo_redo.has_undo(), "and nothing was patched")


## The release stamps where the hand let go, so the region ends at the pointer
## rather than at the last disc the spacing allowed.
##
## Read off the paint rather than off the mask, because the mask is gone by the
## time a case can look at it. With a 40 wide circle the spacing is 10, so a drag
## that ends 15 from its press has discs at 104 and 114 and reaches x 134. The
## texel at 135 is inside the blemish and outside that reach, and it is inside
## the disc the release stamps at 119.
func test_the_release_stamps_where_the_hand_let_go() -> void:
    var edge := Vector2i(135, 124)
    assert_almost_eq(_texel_at(edge).r, 0.0, 0.01, "the far edge of the blemish starts black")

    _press(FROM)
    _move(FROM + Vector2(15.0, 0.0))
    _release()

    assert_almost_eq(_texel_at(edge).r, PAPER.r, 0.05, "and the paper is back at the end of the mark")


## The third clause, asked of the object rather than of a flag: the region has no
## reference left anywhere once the stroke it belongs to is over.
func test_the_mask_is_freed_with_the_stroke() -> void:
    _press(FROM)
    _move(TO)
    var watch: WeakRef = weakref(_tool._region)
    assert_true(watch.get_ref() != null, "the drag is holding a mask")

    _release()

    assert_null(_tool._region, "the tool let go of the mask")
    assert_null(watch.get_ref(), "and nothing else was holding it, so its chunks went with the stroke")
    assert_eq(_tool.preview_shape(), {}, "and there is nothing left to draw")


## A tool switched away from mid-drag drops the mask the same way a release does,
## because the drag it belonged to is over either way.
func test_a_reset_drops_the_mask() -> void:
    _press(FROM)
    _move(TO)
    var watch: WeakRef = weakref(_tool._region)

    _tool.reset()

    assert_null(watch.get_ref(), "the mask went with the drag")
    assert_false(_surface.get_document().undo_redo.has_undo(), "and a drag that was abandoned patched nothing")


## The circle a painter drags is the Size row, and the ring on the canvas is the
## same number, so the row is a thing that can be seen before it is used.
func test_the_ring_is_the_size_row() -> void:
    _tool.region_size = 60.0
    assert_almost_eq(_tool.get_cursor_radius(), 30.0, 0.01, "the ring is half the width the row names")

    _press(FROM)
    assert_almost_eq(float(_tool.preview_shape()["radius"]), 30.0, 0.01, "and the magenta is drawn at the same radius")
    _tool.reset()


## What a capture's dump says with no selection, which is the only place a shot
## of a half transparent magenta region can be checked against a number.
func test_the_dump_carries_the_region() -> void:
    var idle: Dictionary = _tool.capture_report(&"patch", true)["patch"]
    assert_false(bool(idle["selection"]), "with no selection the dump says so")
    assert_almost_eq(float(idle["size"]), WIDTH, 0.01, "and names the circle's width")
    assert_false(bool(idle["painting"]), "and that no drag is in the air")

    _press(FROM)
    _move(TO)
    var live: Dictionary = _tool.capture_report(&"patch", true)["patch"]
    assert_true(bool(live["painting"]), "a drag in the air says so")
    assert_true(int(live["stamps"]) >= 2, "with the stamps counted")
    assert_eq(int(live["region_chunks"]), 1, "and the chunks the region reached")
    _tool.reset()
