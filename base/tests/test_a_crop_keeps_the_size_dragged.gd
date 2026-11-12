## A crop box and a marquee are the size the hand dragged.
##
## Both tools floored the low corner and ceiled the high one, so a drag whose
## pointer sat a fraction into a pixel came out a pixel larger on that axis. The
## sweep's drag of 400 by 300 logical units at zoom 0.625 is 640 by 480
## document pixels, and the crop came out 641 high and Crop to Selection left a
## 641 by 481 document. Each case drags 640 by 480 document pixels through the
## view's own transform, at three zooms and from two starting points whose
## document position is a fraction into a pixel, which is what the old rounding
## needed to grow. The crop box is a live crop of the active layer, so the
## first case reads the dragged size off the layer's crop and the
## document's size left as it was.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateCropScript = preload("res://modules/sara-base-modules/base/tools/state_crop.gd")

## The drag in document pixels. At zoom 0.625 it is the sweep's 400 by 300.
const DRAGGED := Vector2(640, 480)
const ZOOMS: Array[float] = [0.625, 1.3, 2.75]
## Screen points whose document positions are a fraction into a pixel at every
## zoom above, with a pan that is itself a fraction.
const STARTS: Array[Vector2] = [Vector2(37.3, 51.9), Vector2(118.55, 92.15)]
const PAN := Vector2(-11.4, 6.7)


func test_a_crop_box_is_the_size_dragged_and_crops_to_it() -> void:
    for zoom in ZOOMS:
        for start in STARTS:
            var surface := Fixtures.make_surface(Vector2i(2048, 2048))
            var machine := Fixtures.make_bound_machine(surface)
            # A layer that carries a transform is smart and keeps the live crop
            # read below, where an ordinary layer has its crop written in.
            SaLiveTransform.put(surface.get_document(), surface.get_document().active_layer, Basis.IDENTITY)
            machine.set_active_tool(&"crop")
            var tool := machine.active_tool as StateCropScript
            # The crop is the skeleton's live transform, reached through the
            # role registry a bare machine does not hand the tool.
            tool.roles = Fixtures.make_registries().roles
            # The Layer choice, since Canvas is the default.
            tool.mode = StateCropScript.Mode.LAYER
            var where := "at zoom %s from %s" % [zoom, start]
            var press := _document_start(surface.view, zoom, start)
            assert_true(fposmod(press.x, 1.0) != 0.0, "The press is a fraction into a pixel " + where)

            _drag(tool, surface.view, zoom, start)
            assert_eq(tool.pending_rect().size, Vector2i(DRAGGED), "The crop box is the drag " + where)
            var box := tool.pending_rect()
            assert_true(tool.crop_now(), "and the crop runs")
            assert_eq(tool._layer_crop(), box, "leaving a layer crop the size dragged " + where)
            assert_eq(surface.easel.document.canvas_size, Vector2i(2048, 2048), "and the document as it was " + where)
            Fixtures.teardown(surface, machine)


func test_a_marquee_is_the_size_dragged_and_crop_to_selection_keeps_it() -> void:
    for zoom in ZOOMS:
        for start in STARTS:
            var surface := Fixtures.make_surface(Vector2i(2048, 2048))
            var machine := Fixtures.make_bound_machine(surface)
            var registries := Fixtures.make_registries(surface)
            machine.set_active_tool(&"marquee")
            var tool := machine.active_tool
            var where := "at zoom %s from %s" % [zoom, start]

            _drag(tool, surface.view, zoom, start)
            var document := surface.easel.document
            assert_eq(document.selection.bounds.size, Vector2i(DRAGGED), "The marquee's bounds are the drag " + where)
            assert_true(registries.commands.execute(&"image_crop_to_selection"), "Image > Crop to Selection runs")
            assert_eq(document.canvas_size, Vector2i(DRAGGED), "and leaves a document the size dragged " + where)
            Fixtures.teardown(surface, machine)


## A click that lands either side of a half pixel is still a click: the box
## between press and release is at most a pixel, and Replace drops the
## selection rather than selecting that pixel.
func test_a_click_on_a_half_pixel_selects_nothing() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"marquee")
    var tool := machine.active_tool
    var view := surface.view as Fixtures.FakeView
    view.mouse_position = Vector2(100.45, 100.45)
    tool.handle_input(_button(true))
    view.mouse_position = Vector2(100.55, 100.55)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    assert_false(surface.easel.document.selection.active, "A click leaves no selection")
    Fixtures.teardown(surface, machine)


## The ratio lock and a corner pull still land on the pointer with the new
## rounding: a square drawn from a fraction is the longer axis on both, and
## the corner handle pulled by a whole number of pixels moves by exactly that.
func test_the_lock_and_a_corner_pull_land_on_the_pointer() -> void:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"crop")
    var tool := machine.active_tool as StateCropScript
    tool.ratio = StateCropScript.Ratio.SQUARE
    var view := surface.view as Fixtures.FakeView

    _move(tool, view, Vector2(100.3, 100.3), Vector2(300.3, 200.3))
    assert_eq(tool.pending_rect(), Rect2i(100, 100, 200, 200), "A locked draw from a fraction is a square of the longer axis")
    _move(tool, view, Vector2(300.3, 300.3), Vector2(340.3, 340.3))
    assert_eq(tool.pending_rect(), Rect2i(100, 100, 240, 240), "and a corner pull of 40 grows it by 40")
    Fixtures.teardown(surface, machine)


## Where *start* on screen lands in the document at *zoom*.
static func _document_start(view: SaView, zoom: float, start: Vector2) -> Vector2:
    var fake := view as Fixtures.FakeView
    fake.zoom = zoom
    fake.pan = PAN
    return fake.screen_to_document(start)


## A press at *start* on screen and a release DRAGGED document pixels further
## on, both read through the view's transform the way the canvas reads them.
static func _drag(tool: ToolState, view: SaView, zoom: float, start: Vector2) -> void:
    var from := _document_start(view, zoom, start)
    var to := view.screen_to_document(start + DRAGGED * zoom)
    _move(tool, view, from, to)


## One press, one motion and one release, in document pixels.
static func _move(tool: ToolState, view: SaView, from: Vector2, to: Vector2) -> void:
    var fake := view as Fixtures.FakeView
    fake.mouse_position = from
    tool.handle_input(_button(true))
    fake.mouse_position = to
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event
