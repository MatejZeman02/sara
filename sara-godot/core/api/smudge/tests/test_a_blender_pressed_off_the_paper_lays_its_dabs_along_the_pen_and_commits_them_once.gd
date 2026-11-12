## A Blender stroke on a deep painting lays its dabs where
## the pen moves and never thousands in one frame.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Pressing the shipped Blender at 4 px above the top edge of the
## paper meant every stroke after the first held one frame of 3 to 11 s
## with 4083 dabs and no motion in it. Neither the press off the paper nor the
## time since the last stroke laid them. A Blender dab paints straight into the
## layer its snapshot reads, so it was sent alone, and it committed its dirty
## rectangles alone, which walks the filters' spread and the chunks' halo, a
## millisecond a dab on the seasons file. The walk's share of a frame then laid
## five dabs where the pen asked for twenty, the stroke fell behind the pen,
## and the next press walked the thousands the last stroke still owed at once.
##
## This suite presses the Blender off the paper twice, counts the dabs each
## stroke lays against the length the pen moved, and reads that the carry sent
## them a dab at a time and committed them once. The seasons copy's own takes
## are measured by `freeze_hunt.py` and recorded with the work that added this suite.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const CANVAS := Vector2i(512, 512)
## The hunt's radius in document pixels.
const RADIUS: float = 4.0
## The press, above the top edge as the hunt's was, and the two legs after it,
## down onto the paper and across it.
const PATH: Array[Vector2] = [Vector2(64.0, -24.0), Vector2(64.0, 96.0), Vector2(320.0, 96.0)]
## Motions a leg, a pen's few pixels a report.
const STEPS: int = 40


## A canvas whose active layer holds paint where the stroke crosses, so the
## Blender has something to blend.
func _surface() -> SaSurface:
    var surface := Fixtures.make_surface(CANVAS)
    var document := surface.get_document()
    for x in range(2):
        document.active_layer.get_or_create_chunk(Vector2i(x, 0)).clear(Color(0.8, 0.4, 0.2, 1.0))
    document.invalidate_chunks([Vector2i(0, 0), Vector2i(1, 0)])
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()
    return surface


## The shipped Blender at the hunt's radius.
func _blender(surface: SaSurface) -> ToolState:
    var recipe: Resource = null
    for entry: Dictionary in SaShippedPresets.entries():
        if entry["name"] == "Blender":
            recipe = SaShippedPresets.build(SettingsScript, entry)
    assert_true(recipe != null, "The Blender is a shipped preset")
    var brush := StateBrushScript.new()
    brush.surface = surface
    SaPresetStore.copy_settings(recipe, brush.settings)
    brush.settings.radius = RADIUS / float(mini(CANVAS.x, CANVAS.y))
    return brush


## The pen's length along [constant PATH].
func _length() -> float:
    var length := 0.0
    for i in range(1, PATH.size()):
        length += PATH[i - 1].distance_to(PATH[i])
    return length


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


## Presses at the path's start and moves along it, and answers the stroke's
## carry and the dabs laid, read before the release lets the carry go.
func _press_and_drag(surface: SaSurface, brush: ToolState) -> Array:
    var view := surface.view
    view.mouse_position = PATH[0]
    brush.handle_input(_button(true))
    for leg in range(1, PATH.size()):
        for i in range(1, STEPS + 1):
            view.mouse_position = PATH[leg - 1].lerp(PATH[leg], float(i) / float(STEPS))
            var motion := InputEventMouseMotion.new()
            motion.button_mask = MOUSE_BUTTON_MASK_LEFT
            motion.pressure = 1.0
            brush.handle_input(motion)
    return [brush._smudge.carry, brush.stroke_info.dab_index]


## Frees what a surface the fixtures made holds, the document and the easel,
## which are nodes outside any tree.
func _free(surface: SaSurface) -> void:
    surface.get_document().free()
    surface.easel.free()


func _release(surface: SaSurface, brush: ToolState) -> void:
    brush.handle_input(_button(false))
    surface.get_document().commit_stroke()


## The bound a stroke along the path keeps to: a dab a spacing step at the
## smallest step the walk takes, and the press's own.
func _most_dabs() -> int:
    return ceili(_length() / SaStrokeDistance.MIN_DISTANCE_SPACING) + 2


func test_a_blender_pressed_off_the_paper_lays_only_the_dabs_its_path_holds() -> void:
    var surface := _surface()
    var brush := _blender(surface)
    var counts: Array[int] = []
    for take in range(2):
        var held := _press_and_drag(surface, brush)
        counts.append(int(held[1]))
        _release(surface, brush)
    assert_true(counts[0] > 0, "The first stroke lays dabs, %d" % counts[0])
    for take in range(2):
        assert_true(
            counts[take] <= _most_dabs(),
            "Stroke %d lays %d dabs along a pen path that holds at most %d" % [take + 1, counts[take], _most_dabs()]
        )
    # The second stroke, pressed where the first was, lays what the first
    # did, so nothing the first stroke left waits for the next press.
    assert_true(absi(counts[1] - counts[0]) <= 2, "The second stroke lays %d dabs, the first %d" % [counts[1], counts[0]])
    _free(surface)


func test_the_dabs_sent_one_at_a_time_commit_their_rectangles_once() -> void:
    var surface := _surface()
    var brush := _blender(surface)
    var held := _press_and_drag(surface, brush)
    var carry: SaSmudgeReservoir = held[0]
    assert_true(carry != null, "The Blender's stroke has a carry")
    assert_true(carry.pickups > 100, "The carry picked up for each of the %d dabs on the paper" % carry.pickups)
    # Sent a dab at a time, because the Blender paints into the layer its
    # snapshot reads, and committed once a frame or an event at most, never
    # once a dab.
    var before := carry.commits
    assert_true(before <= 2 * STEPS, "The %d dabs committed %d times, at most once an event" % [carry.pickups, before])
    assert_true(before * 4 < carry.pickups, "Far fewer commits than dabs, %d for %d" % [before, carry.pickups])
    _release(surface, brush)
    assert_true(carry.commits - before <= 1, "The lift committed what was held once, %d" % (carry.commits - before))
    var dirty := surface.get_document()._dirty_chunks
    assert_true(
        dirty.has(Vector2i(0, 0)) and dirty.has(Vector2i(1, 0)),
        "The rectangles reach both chunks the stroke crossed, %s" % [dirty.keys()]
    )
    _free(surface)
