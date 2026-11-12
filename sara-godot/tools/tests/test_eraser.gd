## The Eraser tool erases rather than painting the foreground colour.
##
## Filed as `eraser-paints`, and no longer pending: the id is empty
## below, which turns `_assert_eq_pending` into a plain assertion.
##
## **What it was.** `StateEraser._init` set `settings.blend_mode` to ERASE on the
## settings object the instance was born with, and `ToolMachine._rebuild_tools`
## then replaced that whole object with the descriptor's `shared_settings`, a
## plain `BrushSettings` at NORMAL. `StateBrush` opens its stroke with
## `settings.blend_mode`, so the eraser stroked Normal and laid the foreground
## colour down. The other route, the `is_eraser` field, was overwritten by
## `event.pen_inverted` on every motion, so a mouse or a pen held the right way
## up cleared that too and there was nothing left saying erase.
##
## **What f10 changed.** `stamp-brush/module.gd` builds `eraser_settings` at
## ERASE, so the object the machine hands over already says so, and
## `state_eraser.gd` stopped setting `is_eraser`, which it could never hold.
## `tools/tool_machine.gd` is untouched: the swap is what shared settings are
## for, and the eraser has its own object to swap in.
##
## Seen on the running app: `scenarios/tour-painting.json` step 12 drew an eraser
## stroke down two painted bands with the foreground on #1c6ad2, and
## A capture of the stripe read
## (28, 106, 210) along the stripe, which is that colour and not what was
## underneath. `scenarios/eraser-paints.json` is the same gesture after the
## fix.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")


func test_the_eraser_erases_rather_than_painting() -> void:
    var surface := Fixtures.make_surface(Vector2i(128, 128))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"eraser")
    var eraser := machine.active_tool as StateBrushScript

    assert_not_null(eraser, "the eraser is one of the built-in tools")
    _assert_eq_pending(
        "",
        String(eraser.settings.blend_mode),
        String(SaLayer.BLEND_MODE.ERASE),
        "The eraser opens its stroke in the erase blend mode"
    )
    assert_false(eraser.is_eraser, "and does not rest on a field a motion event overwrites")
    Fixtures.teardown(surface, machine)


## The brush is the tool `is_eraser` is for: the pen's flipped end telling it to
## erase. Held here so the field's removal from the eraser cannot be read as the
## field being dead.
func test_the_brush_still_erases_when_the_pen_is_flipped() -> void:
    var surface := Fixtures.make_surface(Vector2i(128, 128))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var brush := machine.active_tool as StateBrushScript

    assert_eq(String(brush.settings.blend_mode), String(SaLayer.BLEND_MODE.NORMAL), "The brush opens its stroke in Normal")
    var motion := InputEventMouseMotion.new()
    motion.pen_inverted = true
    brush.handle_input(motion)
    assert_true(brush.is_eraser, "and the flipped end of a pen still turns it into an eraser")

    Fixtures.teardown(surface, machine)


## The two tools do not share a settings object, which is what lets the eraser
## carry a blend mode the brush must not. Held because the whole defect was one
## object being swapped for another.
func test_the_brush_and_the_eraser_keep_their_own_settings() -> void:
    var surface := Fixtures.make_surface(Vector2i(128, 128))
    var machine := Fixtures.make_bound_machine(surface)
    var brush := machine.get_tool(&"brush") as StateBrushScript
    var eraser := machine.get_tool(&"eraser") as StateBrushScript

    assert_false(brush.settings == eraser.settings, "Two objects, so a mode on one is not a mode on both")
    assert_eq(String(eraser.settings.blend_mode), String(SaLayer.BLEND_MODE.ERASE), "The eraser's says erase")
    assert_eq(String(brush.settings.blend_mode), String(SaLayer.BLEND_MODE.NORMAL), "and the brush's says Normal")

    Fixtures.teardown(surface, machine)


## Asserts *actual* equals *expected*, unless *pending* names an F unit that has
## not landed, in which case it prints what it saw and passes. A list rather
## than a deletion, the way `tests/flakes.txt` is: what the fix owes is written
## here in full instead of living in a separate note.
func _assert_eq_pending(pending: String, actual: Variant, expected: Variant, message: String) -> void:
    if pending.is_empty() or actual == expected:
        assert_eq(actual, expected, message)
        return
    print("   pending %s: %s (expected '%s', got '%s')" % [pending, message, str(expected), str(actual)])
    assert_true(true, "pending %s" % pending)
