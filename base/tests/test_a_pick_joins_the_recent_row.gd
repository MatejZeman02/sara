## A colour the eyedropper picks joins the Colour Picker's recent row, once per
## gesture.
##
## The recent row must not stay empty after the eyedropper picks a colour off
## the picture, so the tool reaches `SaColors.note_used` and not only the bus.
## The release commits the gesture's last pick, so a
## click adds its colour and a drag across three colours adds one entry, the
## one it ended on. The same pick on the running app is
## `scenarios/a-colour-the-eyedropper-picks-joins-the-recent-row.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## Where the store writes while the suite runs, so the painter's own
## `colors.cfg` is never touched.
static var scratch_path: String = SaDataRoot.path("test_d8_colors.cfg")

const BLUE := Color(0.1, 0.2, 0.8, 1.0)
const RED := Color(0.8, 0.1, 0.1, 1.0)
const GREEN := Color(0.1, 0.7, 0.2, 1.0)

var _kept_path: String
var _kept_recent: Array[Color] = []
var _kept_foreground: Color


## The eyedropper with a pointer the suite moves. The tool samples where the
## pointer is rather than where an event says, and a suite has no pointer of
## its own to move, so this one answers [member at] instead.
class ScriptedPointer:
    extends "res://modules/sara-base-modules/base/tools/state_eyedropper.gd"

    var at := Vector2(32, 32)

    func get_document_mouse_position() -> Vector2:
        return at


func before_each() -> void:
    _kept_path = SaColors.path
    _kept_recent = SaColors.recent.duplicate()
    _kept_foreground = SaColors.foreground
    SaColors.path = scratch_path
    SaColors.recent.clear()


func after_each() -> void:
    SaColors.recent.clear()
    SaColors.recent.append_array(_kept_recent)
    SaColors.path = _kept_path
    SaColors.foreground = _kept_foreground
    if FileAccess.file_exists(scratch_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))


func test_a_click_puts_the_picked_colour_first_in_the_recent_row() -> void:
    var surface := Fixtures.make_surface(Vector2i(64, 64))
    SaColors.note_used(Color.WHITE)
    _fill(surface, BLUE)
    var eyedropper := _eyedropper(surface)

    eyedropper.handle_input(_button(true))
    assert_eq(SaColors.recent.size(), 1, "The press picks, and the recent row waits for the release")
    eyedropper.handle_input(_button(false))

    assert_eq(SaColors.recent.size(), 2, "The release adds one colour to the row")
    assert_true(_same(SaColors.recent[0], BLUE), "and the picked blue heads it, got %s" % SaColors.recent[0])
    assert_true(_same(SaColors.recent[1], Color.WHITE), "with the colour used before it second")
    _free(surface)


func test_a_drag_across_three_colours_adds_one_entry() -> void:
    var surface := Fixtures.make_surface(Vector2i(64, 64))
    var eyedropper := _eyedropper(surface)

    _fill(surface, BLUE)
    eyedropper.at = Vector2(10, 10)
    eyedropper.handle_input(_button(true))

    # Every frame of the drag picks, so the foreground follows the pointer.
    _fill(surface, RED)
    eyedropper.at = Vector2(30, 30)
    eyedropper.handle_input(_motion())
    eyedropper.tick(0.016)
    assert_true(_same(SaColors.foreground, RED), "The drag picks the red under it on the way")

    # The last motion lands between two frames, so its sample is the release's.
    _fill(surface, GREEN)
    eyedropper.at = Vector2(50, 50)
    eyedropper.handle_input(_motion())
    eyedropper.handle_input(_button(false))

    assert_eq(SaColors.recent.size(), 1, "Three colours under one drag add one entry")
    assert_true(_same(SaColors.recent[0], GREEN), "the one the drag ended on, got %s" % SaColors.recent[0])
    assert_true(_same(SaColors.foreground, GREEN), "which is the foreground as well")

    eyedropper.tick(0.016)
    assert_eq(SaColors.recent.size(), 1, "and the frame after the release adds nothing")
    _free(surface)


## A hover picks nothing, so it has nothing to commit, and a release off the
## canvas commits what the press picked rather than nothing.
func test_a_release_with_no_pick_adds_nothing() -> void:
    var surface := Fixtures.make_surface(Vector2i(64, 64))
    _fill(surface, BLUE)
    var eyedropper := _eyedropper(surface)

    eyedropper.handle_input(_motion())
    eyedropper.tick(0.016)
    eyedropper.handle_input(_button(false))
    assert_eq(SaColors.recent.size(), 0, "A hover and a stray release add nothing")

    eyedropper.at = Vector2(-20, -20)
    eyedropper.handle_input(_button(true))
    eyedropper.handle_input(_button(false))
    assert_eq(SaColors.recent.size(), 0, "A click beside the canvas picks nothing and adds nothing")

    eyedropper.at = Vector2(32, 32)
    eyedropper.handle_input(_button(true))
    eyedropper.at = Vector2(-20, -20)
    eyedropper.handle_input(_motion())
    eyedropper.handle_input(_button(false))
    assert_eq(SaColors.recent.size(), 1, "A drag that leaves the canvas keeps the pick it made")
    assert_true(_same(SaColors.recent[0], BLUE), "which is the blue under the press")
    _free(surface)


## ALT borrows the eyedropper, and letting go of ALT before the button hands the
## tool back, which calls `reset`, with the release still to come.
func test_a_switch_away_mid_drag_commits_the_pick() -> void:
    var surface := Fixtures.make_surface(Vector2i(64, 64))
    _fill(surface, BLUE)
    var eyedropper := _eyedropper(surface)

    eyedropper.handle_input(_button(true))
    eyedropper.reset()
    assert_eq(SaColors.recent.size(), 1, "The switch away commits the pick")
    eyedropper.reset()
    eyedropper.handle_input(_button(false))
    assert_eq(SaColors.recent.size(), 1, "once, and neither a second reset nor a late release adds it again")
    _free(surface)


func _eyedropper(surface: SaSurface) -> ScriptedPointer:
    var eyedropper := ScriptedPointer.new()
    eyedropper.surface = surface
    eyedropper.sample_from = ScriptedPointer.SampleFrom.VIEW
    return eyedropper


## The whole composite in one colour. The tool reads the composite through the
## easel's snapshot, so this is what is under the pointer wherever it is.
func _fill(surface: SaSurface, color: Color) -> void:
    GlobalShaderCompiler.get_rd().texture_clear(surface.easel.output.rid, color, 0, 1, 0, 1)


func _free(surface: SaSurface) -> void:
    surface.get_document().free()
    surface.easel.free()


func _same(a: Color, b: Color) -> bool:
    return a.is_equal_approx(b) or (absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01)


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


## A motion with no button mask, which is what the capture harness sends.
func _motion() -> InputEventMouseMotion:
    return InputEventMouseMotion.new()
