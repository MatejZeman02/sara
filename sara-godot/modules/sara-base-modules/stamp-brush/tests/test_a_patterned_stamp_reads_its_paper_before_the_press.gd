## A patterned stamp reads its paper before the press.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## F2 gave the stamp's texture sensor a reading off the bound paper, read back
## from the GPU the first time a dab asked, which was the first dab of the first
## stroke after the paper changed, for every preset that names a paper. Hard
## rule 1 names no read at a press. The suite holds the read to the presets
## whose curves read the sensor, and those to a read taken by the tool's frame
## with no stroke running rather than by a hover, so a door's press with no
## hover takes none either.
##
## **The paper is F2's four greys**, written as a PNG into a scratch folder of
## its own, so a store over that folder alone answers the name.
extends "res://tests/test_framework.gd"

## A readback of the bound paper and a dab are both GPU work.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

static var scratch_dir: String = SaDataRoot.path("test_d18_stamp_paper_before_the_press")
const PAPER_FILE := "sensor_steps.png"
const PAPER_NAME := "Sensor Steps"
const GREYS: Array[int] = [0, 85, 170, 255]
## One frame of the app's clock, which is what runs between two door steps.
const FRAME := 1.0 / 60.0

var _surface: SaSurface = null


func before_each() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var image := Image.create_empty(GREYS.size(), 1, false, Image.FORMAT_RGBA8)
    for x in GREYS.size():
        var level := float(GREYS[x]) / 255.0
        image.set_pixel(x, 0, Color(level, level, level, 1.0))
    image.save_png(scratch_dir.path_join(PAPER_FILE))
    _surface = Fixtures.make_surface()


func after_each() -> void:
    Fixtures.teardown(_surface)
    _surface = null
    if DirAccess.dir_exists_absolute(scratch_dir):
        var dir := DirAccess.open(scratch_dir)
        for file in dir.get_files():
            dir.remove(file)
        DirAccess.remove_absolute(scratch_dir)


## The Done when's first clause: a paper bound, in the dab through the texture
## option, and no curve on the sensor. Hovering and a frame read nothing, and
## neither does the press nor any dab of the stroke, while the paper is still
## built.
func test_no_curve_on_the_sensor_reads_nothing() -> void:
    var brush := _brush()
    brush.settings.texture_option.enabled = true
    brush.settings.texture_option.strength = 1.0
    assert_false(brush.dab_pattern.reads_texture(brush.settings), "No curve reads the sensor")
    _hover(brush, Vector2(90, 100))
    brush.tick(FRAME)
    assert_eq(brush.dab_pattern.reads, 0, "Hovering and a frame read nothing")
    _press(brush, Vector2(100, 100))
    assert_eq(brush.dab_pattern.reads, 0, "The press reads nothing")
    _drag_and_release(brush)
    assert_eq(brush.dab_pattern.reads, 0, "nor does the rest of the stroke")
    assert_eq(brush.dab_pattern.builds, 1, "though the paper the dabs bind was built")


## The Done when's second clause: a curve reads the sensor, and its one read is
## taken by the tool's frame with no stroke running, so the press takes none.
## A hover reads nothing of its own, because the frame under it already has.
func test_a_curve_on_the_sensor_reads_before_the_press() -> void:
    var brush := _brush()
    brush.settings.hue_option.bind_texture(0.3)
    assert_true(brush.dab_pattern.reads_texture(brush.settings), "The Hue curve reads the sensor")
    brush.tick(FRAME)
    assert_eq(brush.dab_pattern.reads, 1, "A frame took the one read")
    _hover(brush, Vector2(90, 100))
    brush.tick(FRAME)
    assert_eq(brush.dab_pattern.reads, 1, "and a hover and a second frame take none")
    _press(brush, Vector2(100, 100))
    assert_eq(brush.dab_pattern.reads, 1, "The press took none")
    _drag_and_release(brush)
    assert_eq(brush.dab_pattern.reads, 1, "and neither did the stroke")


## A press with no hover before it, which is a door's stroke, reads nothing,
## because the frame after the curve went on the sensor read the paper. The
## count the stroke adds is nought.
func test_a_press_without_a_hover_reads_nothing() -> void:
    var brush := _brush()
    brush.tick(FRAME)
    assert_eq(brush.dab_pattern.reads, 0, "No curve reads the sensor yet, so a frame reads nothing")
    brush.settings.hue_option.bind_texture(0.3)
    brush.tick(FRAME)
    var before := brush.dab_pattern.reads
    assert_eq(before, 1, "The frame after the Hue curve went on took the one read")
    _press(brush, Vector2(100, 100))
    _drag_and_release(brush)
    assert_eq(brush.dab_pattern.reads - before, 0, "A stroke with no hover read nothing")


## A new paper is read by the next frame, not by the next press, and a frame
## inside a stroke reads nothing even when a paper waits.
func test_a_paper_changed_is_read_by_the_next_frame() -> void:
    var brush := _brush()
    brush.settings.hue_option.bind_texture(0.3)
    brush.tick(FRAME)
    assert_eq(brush.dab_pattern.reads, 1, "The first paper read")
    brush.settings.texture_scale = 2.0
    brush.tick(FRAME)
    assert_eq(brush.dab_pattern.reads, 2, "The paper at another scale read by the next frame")
    _press(brush, Vector2(100, 100))
    _drag_and_release(brush)
    assert_eq(brush.dab_pattern.reads, 2, "and the stroke read nothing")


## A stroke's ask is neutral for a preset no curve of which reads the sensor,
## and an ask with no stroke reads the paper, which is what F2's suite asks.
func test_a_strokes_ask_is_neutral_without_a_curve() -> void:
    var dab_pattern := SaDabPattern.new(SaPatternStore.new([scratch_dir]))
    var settings := StateBrushScript.new().settings
    settings.pattern_name = PAPER_NAME
    var info := SaStrokeInfo.new()
    assert_almost_eq(dab_pattern.sensor_reading(settings, Vector2(3.5, 0.5), info), SaSensor.NEUTRAL_TEXTURE, 1e-6, "A grey")
    assert_eq(dab_pattern.reads, 0, "and no read")
    assert_almost_eq(dab_pattern.sensor_reading(settings, Vector2(3.5, 0.5)), 1.0, 1e-6, "An ask with no stroke reads white")
    assert_eq(dab_pattern.reads, 1, "from one read")


# --- Helpers -----------------------------------------------------------------------


func _brush() -> StateBrushScript:
    var brush := StateBrushScript.new()
    brush.dab_pattern = SaDabPattern.new(SaPatternStore.new([scratch_dir]))
    brush.surface = _surface
    brush.stroke_seed = 7
    brush.settings.color = Color(0.85, 0.4, 0.15, 1.0)
    brush.settings.radius = 6.0 / 256.0
    brush.settings.opacity_by_pressure = false
    brush.settings.pattern_name = PAPER_NAME
    return brush


## A pen over the canvas with no button down.
func _hover(brush: StateBrushScript, at: Vector2) -> void:
    _surface.view.mouse_position = at
    var motion := InputEventMouseMotion.new()
    motion.position = at
    brush.handle_input(motion)


func _press(brush: StateBrushScript, at: Vector2) -> void:
    _surface.view.mouse_position = at
    brush.handle_input(_button(true))


## Eight motions to the right of the press and a release.
func _drag_and_release(brush: StateBrushScript) -> void:
    for step in range(1, 9):
        _surface.view.mouse_position = Vector2(100 + 4 * step, 100)
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.pressure = 1.0
        brush.handle_input(motion)
    brush.handle_input(_button(false))


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event
