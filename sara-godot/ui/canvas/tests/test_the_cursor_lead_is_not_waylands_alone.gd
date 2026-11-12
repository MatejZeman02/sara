## The Auto lead follows the pointer Sara draws rather than one display driver.
##
## The lag shows in the Both mode, where the ring is drawn beside the system's
## pointer and the gap between the two is the lag, so a painter on Windows must
## get a lead too. Asking the driver by name would answer for Wayland alone, so
## the gate asks the two
## things it means instead: is a pen moving the pointer, and is Sara drawing
## that pointer rather than leaving it to the system. The Wayland name is one of
## the answers to the second question, inside
## `SaCursorPolicy.software_pointer_mode_active`, and no longer the gate.
##
## The Linux half of the rule, which is unchanged, stays
## `test_cursor_lead.gd`'s and is not repeated here. What is here is the case
## on the other drivers, a painter who asked for Sara's own pointer, and the
## proof that the gate follows that mode rather than the driver's name: on this
## one machine, one pen, the answer moves with the mode.
extends "res://tests/test_framework.gd"

var _saved_lead: String
var _saved_cursor: String


func before_each() -> void:
    _saved_lead = SaSettings.cursor_lead
    _saved_cursor = SaSettings.software_cursor
    SaCursorPolicy.forget_pointer_device()


func after_each() -> void:
    SaSettings.cursor_lead = _saved_lead
    SaSettings.software_cursor = _saved_cursor
    SaCursorPolicy.forget_pointer_device()


## One motion carrying a pressure, which is what says a pen is on the tablet.
## The heuristic is `note_pointer_device`'s own, and the same one
## `test_cursor_overlay.gd` feeds it.
func _feed_a_pen() -> void:
    var motion := InputEventMouseMotion.new()
    motion.pressure = 0.6
    SaCursorPolicy.note_pointer_device(motion)


## One motion carrying nothing, which a mouse sends.
func _feed_a_mouse() -> void:
    var plain := InputEventMouseMotion.new()
    for i in SaCursorPolicy.MOUSE_MOTION_STREAK + 1:
        SaCursorPolicy.note_pointer_device(plain)


## The gate over its four cases: a pen Sara draws the pointer for leads, and
## nothing else does. The first case is the Windows one, because Both draws the
## ring beside the system's pointer there and the lead is what closes the lag
## between them.
func test_the_lead_is_a_pen_and_a_pointer_sara_draws() -> void:
    assert_true(SaCursorPrediction.auto_lead_on(true, true), "a pen Sara draws the pointer for leads, on Windows too")
    assert_false(SaCursorPrediction.auto_lead_on(false, true), "a mouse leads nowhere, whatever Sara draws")
    assert_false(SaCursorPrediction.auto_lead_on(true, false), "a pen whose pointer the system draws sits on the hardware cursor")
    assert_false(SaCursorPrediction.auto_lead_on(false, false), "and a mouse under the system's pointer leads nowhere at all")


## Auto read off this machine: one pen, one driver, and the answer follows the
## mode. Under Never the pointer is the system's and there is no lag to pay for,
## which the driver-name rule could not say, and Both and Always bring the lead
## back, Both being the mode the lag is read in.
func test_auto_follows_the_mode_rather_than_the_driver_name() -> void:
    SaSettings.cursor_lead = "auto"
    _feed_a_pen()

    SaSettings.software_cursor = "never"
    assert_false(SaCursorPolicy.software_pointer_mode_active(), "Never leaves the pointer to the system")
    assert_false(SaCursorPrediction.lead_enabled(), "so a pen has nothing for the ring to lead")

    SaSettings.software_cursor = "both"
    assert_true(SaCursorPolicy.software_pointer_mode_active(), "Both draws Sara's pointer on any driver")
    assert_true(SaCursorPrediction.lead_enabled(), "so the ring leads the pen there")

    SaSettings.software_cursor = "always"
    assert_true(SaCursorPrediction.lead_enabled(), "and Always asks for the same pointer")


## A mouse in the same mode on the same machine still leads nowhere, so the
## device is the gate's other half and the drawing is not the whole of it.
func test_a_mouse_in_the_pointer_saras_own_still_leads_nowhere() -> void:
    SaSettings.cursor_lead = "auto"
    SaSettings.software_cursor = "both"
    _feed_a_mouse()
    assert_false(SaCursorPolicy.pointer_is_tablet, "a streak of plain motions is a mouse")
    assert_false(SaCursorPrediction.lead_enabled(), "and the lead is off for it")


## On and off stay the painter's word over the whole gate, so a painter who
## wants the lead with a mouse, or none with a pen, gets exactly that.
func test_on_and_off_still_outrank_the_gate() -> void:
    SaSettings.software_cursor = "never"
    SaSettings.cursor_lead = "on"
    assert_true(SaCursorPrediction.lead_enabled(), "On is on, whatever mode the pointer is in")
    SaSettings.software_cursor = "both"
    SaSettings.cursor_lead = "off"
    assert_false(SaCursorPrediction.lead_enabled(), "Off is off, whatever Sara draws")
