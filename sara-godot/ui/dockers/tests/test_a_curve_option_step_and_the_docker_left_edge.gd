## The neighbourhood of tonight's fixes, and what driving it found.
##
## Each `pending_` method is a defect measured on the running app. A `pending_` method is not run: the framework calls
## what begins with `test_`, so the fixer renames one method and the suite starts
## asserting the thing that was wrong. That is the convention.
##
## The one `test_` method below refutes a claim that no scenario can reach a
## curve option, and it passes. It is here rather than in `test_stamp_engine.gd`
## because that file belongs to the stamp engine's own suite.
extends "res://tests/test_framework.gd"

## One preload where there were two. The editor's capture file was merged into
## this one, and the second name was the same file under its old one.
const CurveOptionCapture = preload("res://harness/captures/brush_editor_capture.gd")


## It was claimed that no scenario could reach a curve option. That is wrong, and
## this is the assertion that would have stopped the claim.
##
## `scenarios/paint-and-layers.json` steps 20 to 22 open the brush editor on
## the Size page, tick it, switch the pressure sensor on through the
## `curve_option` step, close the editor and stroke at pressure 0.5. The dab is
## 44.38 pixels across where the same stroke with the option off is 64.8, and the
## dump reports `size_option` enabled with one active sensor and `bound: true`.
##
## What was actually true is that the `tool` step's `options` dictionary
## cannot write a curve option, which is not the same claim. The door
## is the brush editor.
func test_a_capture_can_enable_a_curve_option_and_the_editor_is_the_door() -> void:
    # The narrow claim, kept because it is true and is the
    # reason the wrong one was believed: an option row's property is the resource
    # itself, so the `tool` step can only hand it a whole `SaCurveOption`.
    var spec := SaOptionSpec.make(&"size_option", "Size", SaOptionSpec.Kind.CURVE_OPTION)
    spec.property = NodePath("size_option")
    assert_eq(spec.kind, SaOptionSpec.Kind.CURVE_OPTION, "A curve option row is its own kind")
    assert_eq(String(spec.property_path()), "size_option", "whose property is the option object, not a field of it")

    # The door. Both halves are static functions on scripts
    # the capture dispatcher already preloads, which is why nothing about the
    # scene tree is needed to say they exist.
    # The door, asserted by
    # reading the dispatcher's own step table. GDScript will not introspect a
    # script without an instance, and both halves are static, so the source is
    # the only place that can be asked without opening a window.
    var table := FileAccess.get_file_as_string("res://harness/sa_step_table.gd")
    assert_true(table.contains('step.has("curve_option")'), "The capture dispatcher has a `curve_option` step")
    assert_true(table.contains('step.has("brush_editor")'), "and a `brush_editor` step, which is what binds it")


## A `curve_option` step whose `sensor` is a string names the shape it wants
## instead of taking the whole run down with an engine cast error.
##
## `{"curve_option": {"sensor": "pressure"}}` reads as the obvious spelling and
## the step wants `{"sensor": {"pressure": true}}`. What it did with the string
## was `spec["sensor"] as Dictionary`, which raises `Invalid cast: could not
## convert value to 'Dictionary'`. A `SCRIPT ERROR` is a failed
## run, so one mistyped argument failed a capture that had already done
## everything else it was asked.
##
## `shape_complaint` is driven here rather than `capture_control`, because the
## step opens a bare host window when no control is on screen and adding a
## `Window` in a headless test hangs.
##
## The filing said `sensor` was the only key that casts. `points` casts too, so
## both are checked here.
func test_a_curve_option_step_names_the_shape_it_wants() -> void:
    var right := CurveOptionCapture.shape_complaint("sensor", {"pressure": true}, TYPE_DICTIONARY, "an object")
    assert_eq(right, "", "The shape the step wants earns no complaint")

    for wrong: Variant in ["pressure", 3, 1.5, ["pressure"], true]:
        var said := CurveOptionCapture.shape_complaint("sensor", wrong, TYPE_DICTIONARY, "an object")
        assert_true(said.contains("'sensor'"), "A %s names the key" % type_string(typeof(wrong)))
        assert_true(said.contains("an object"), "and the shape it wanted")
        assert_true(said.contains("failed"), "and says failed, so the run's problem list carries it")

    var points := CurveOptionCapture.shape_complaint("points", "0,0", TYPE_ARRAY, "an array of [x, y] pairs")
    assert_true(points.contains("'points'"), "The other key that casts is guarded too")
    assert_eq(
        CurveOptionCapture.shape_complaint("points", [[0.0, 0.0]], TYPE_ARRAY, "an array"),
        "",
        "and an array of pairs still passes"
    )


## A corner-grip resize can put a docker at a negative x, off the left edge
## of the window, and nothing clamps it.
##
## `scenarios/colour-and-picker.json`: the Colour Picker at
## (60, 120) 520 by 700 is shrunk by 160 and grown by 320 through the corner grip.
## The step reports
## `(160, 120) 321x700 -> (-160, 120) 961x700, centre (320.5, 470.0) -> (320.5, 470.0)`,
## so the docker keeps its centre and its left edge leaves the window by 160
## units. A hide button 31 units off its own docker's edge was a like fault, and
## this is the docker itself off the window's.
##
## Whether the centre-keeping is the step's or the app's is the first thing the
## fixer settles: `docker_resize` supplies the position because Wayland will not
## place the pointer, and both gestures are driven from the
## docker's centre. What is not in doubt is that a position of -160 was accepted
## and drawn.
func test_a_docker_cannot_be_resized_off_the_left_edge_of_its_window() -> void:
    # The filing's own numbers: a 1920 by 1080 host, the Colour Picker at
    # (160, 120) 321 wide, grown by 320 through the grip.
    var host := Rect2i(0, 0, 1920, 1080)
    var minimum := Vector2i(280, 420)
    # The grip's own corner, bottom right of the start rect, so the drag reads
    # exactly as the old unsigned arithmetic did.
    var press := Vector2(160 + 321, 120 + 700)
    var rect := DockerDragHandle.resize_rect(Vector2i(160, 120), Vector2i(321, 700), Vector2(320, 0), press, minimum, host)
    assert_true(rect.position.x >= 0, "The left edge stays in the window, x = %d" % rect.position.x)
    assert_true(rect.position.x + rect.size.x <= host.end.x, "and so does the right one")
    assert_eq(rect.size.x, 641, "Growth about the held centre stops when the nearer edge reaches the host's")

    # The centre is held, which both gestures need and what the
    # clamp had to leave alone.
    var before_centre := Vector2(160, 120) + Vector2(321, 700) * 0.5
    var after_centre := Vector2(rect.position) + Vector2(rect.size) * 0.5
    assert_almost_eq(after_centre.x, before_centre.x, 1.0, "and the centre did not move to make room")

    # No host given is no clamp, which is what every caller that cannot ask for
    # one gets, and it is the arithmetic the older suite already asserts.
    var loose := DockerDragHandle.resize_rect(Vector2i(160, 120), Vector2i(321, 700), Vector2(320, 0), press, minimum)
    assert_eq(loose.position.x, -160, "Without a host the old answer stands, so the clamp is the new part")

    # A centre with less room than half the minimum is a restored layout rather
    # than a gesture, and the minimum wins over the edge there.
    var cramped_press := Vector2(0 + 300, 0 + 500)
    var cramped := DockerDragHandle.resize_rect(Vector2i(0, 0), Vector2i(300, 500), Vector2(40, 40), cramped_press, minimum, host)
    assert_true(cramped.size.x >= minimum.x, "A docker is never squeezed under its own minimum")
