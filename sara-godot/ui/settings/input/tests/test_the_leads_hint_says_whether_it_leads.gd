## The Cursor lead hint says whether the ring leads, under every pointer
## setting and every lead setting, on the Tablet page, beside
## the rest of the pen's rows.
##
## On Windows with Sara's own pointer at Both, the hint ended
## "Not active on this system." under Auto, On and Off alike while the ring led under
## On. The sentence was written once, when the page was declared, and only a
## change of pointer rebuilt the page, so a lead changed afterwards, or a pen
## picked up after a mouse opened Preferences, left it saying what had been
## true. The page now says it again from the question the ring asks,
## `SaCursorPrediction.lead_enabled`.
##
## What is held here is the page built once and then every combination set
## behind its back the way a painter's session sets them, with no rebuild: the four
## pointer settings, the three lead settings, and a mouse and a pen. For each
## the hint is read off the row and off the line on screen, and a ring fed a
## moving pointer is asked whether it leads, so the hint is held against the
## ring itself and against the rule written out below, not only against the
## function both call.
extends "res://tests/test_framework.gd"

## A pointer crossing the view at 1500 pixels a second, fast enough for the
## whole lead and slow enough that it is nowhere near its cap.
const FROM := Vector2(100.0, 300.0)
const TO := Vector2(400.0, 300.0)
const SECONDS := 0.2
const SAMPLES := 13

## What the hint ends on under Never, where there is no ring to lead.
const NO_RING := "No brush outline is drawn while Sara's own pointer is set to Never."

var _host: Node = null
var _page: SaTabletPage = null
var _overlay: CursorOverlay = null
var _saved_lead: String = "auto"
var _saved_cursor: String = "auto"


func before_each() -> void:
    _saved_lead = SaSettings.cursor_lead
    _saved_cursor = SaSettings.software_cursor
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "LeadHintHost"
    EventBus.add_child(_host)
    _page = SaTabletPage.new()
    _host.add_child(_page)
    _overlay = CursorOverlay.new()
    _host.add_child(_overlay)


func after_each() -> void:
    SaSettings.cursor_lead = _saved_lead
    SaSettings.software_cursor = _saved_cursor
    SaCursorPolicy.forget_pointer_device()
    if is_instance_valid(_host):
        _host.free()
    _host = null
    _page = null
    _overlay = null


## One motion carrying a pressure, which is what says a pen is on the tablet,
## the heuristic `note_pointer_device` owns.
func _feed_a_pen() -> void:
    var motion := InputEventMouseMotion.new()
    motion.pressure = 0.6
    SaCursorPolicy.note_pointer_device(motion)


## A streak of motions carrying nothing, which a mouse sends.
func _feed_a_mouse() -> void:
    var plain := InputEventMouseMotion.new()
    for i in SaCursorPolicy.MOUSE_MOTION_STREAK + 1:
        SaCursorPolicy.note_pointer_device(plain)


## Whether the ring should lead, written out rather than asked of the code
## under test: Never draws no ring to lead, On leads and Off does not, and Auto
## leads a pen whose pointer Sara draws, which Always and Both do everywhere and
## the default does under Wayland alone.
func _should_lead(pointer: String, lead: String, pen: bool) -> bool:
    if pointer == "never":
        return false
    if lead == "on":
        return true
    if lead == "off":
        return false
    var sara_draws := pointer in ["always", "both"] or (pointer == "auto" and DisplayServer.get_name() == "Wayland")
    return pen and sara_draws


## Whether a ring is drawn and put off the pointer that has just crossed from
## [constant FROM] to [constant TO]. Under Never the ring's own rule answers no
## ring for every point, which is asserted here rather than assumed.
func _ring_leads() -> bool:
    if SaSettings.software_cursor == "never":
        assert_eq(SaCursorPolicy.cursor_ring_radius_at(null, TO), -1.0, "Never draws no ring anywhere")
        return false
    return _ring_lead().length() > 0.5


## Where the ring is drawn for a pointer that has just crossed from
## [constant FROM] to [constant TO], against where the pointer is.
func _ring_lead() -> Vector2:
    _overlay.prediction.reset()
    var usec := Time.get_ticks_usec()
    var step := int(SECONDS / float(SAMPLES - 1) * 1_000_000.0)
    for i in SAMPLES:
        _overlay.prediction.sample(FROM.lerp(TO, float(i) / float(SAMPLES - 1)), usec + step * i)
    return _overlay.drawn_centre(TO) - TO


## The last sentence of *text*, which is the verdict the row ends on.
func _verdict(text: String) -> String:
    for ending: String in [
        NO_RING,
        "Not active for the mouse on this system. A pen would use it.",
        "Not active on this system.",
        "Active on this system."
    ]:
        if text.ends_with(ending):
            return ending
    return "no verdict"


## Every pointer setting, every lead setting and both devices, set with the
## page already built, the way a painter's session changes them.
func test_the_hint_follows_the_ring_under_every_setting() -> void:
    var row := _page.page.row(&"cursor_lead")
    assert_not_null(row, "the Tablet page declares the Cursor lead row")
    if row == null:
        return
    var hint_label := row.line.get_node(^"Labels/Hint") as Label
    for pointer_mode: Dictionary in SaCursorPolicy.CURSOR_MODES:
        var pointer := String(pointer_mode["id"])
        for lead_mode: Dictionary in SaCursorPrediction.LEAD_MODES:
            var lead := String(lead_mode["id"])
            for pen: bool in [false, true]:
                SaSettings.software_cursor = pointer
                SaSettings.cursor_lead = lead
                if pen:
                    _feed_a_pen()
                else:
                    _feed_a_mouse()
                _page.refresh_lead_row()
                var case := "pointer %s, lead %s, %s" % [pointer, lead, "a pen" if pen else "a mouse"]
                var should := _should_lead(pointer, lead, pen)
                var leads := _ring_leads()
                assert_eq(leads, should, "%s: the ring %s" % [case, "leads" if should else "sits on the pointer"])
                var verdict := _verdict(row.explanation)
                assert_eq(verdict == "Active on this system.", should, "%s: the hint ends '%s'" % [case, verdict])
                assert_eq(_verdict(hint_label.text), verdict, "%s: and the line on screen says the same" % case)
                if pointer == "never":
                    assert_eq(verdict, NO_RING, "%s: Never says there is no ring to lead" % case)


## A mouse under Auto where a pen would lead is told so, because that mouse is
## the one a painter reaches Preferences with while the pen leads on the
## canvas. Where no pen would lead either, the hint says no more than that.
func test_a_mouse_under_auto_is_told_what_a_pen_gets() -> void:
    var row := _page.page.row(&"cursor_lead")
    SaSettings.cursor_lead = "auto"
    _feed_a_mouse()

    SaSettings.software_cursor = "both"
    _page.refresh_lead_row()
    assert_eq(
        _verdict(row.explanation), "Not active for the mouse on this system. A pen would use it.", "Both draws a pen's pointer"
    )

    SaSettings.software_cursor = "always"
    SaSettings.cursor_lead = "on"
    _page.refresh_lead_row()
    assert_eq(_verdict(row.explanation), "Active on this system.", "On leads the mouse too")

    SaSettings.cursor_lead = "auto"
    SaSettings.software_cursor = "never"
    _page.refresh_lead_row()
    assert_eq(_verdict(row.explanation), NO_RING, "Never draws no ring, so nothing would lead")

    SaSettings.cursor_lead = "off"
    SaSettings.software_cursor = "both"
    _page.refresh_lead_row()
    assert_eq(_verdict(row.explanation), "Not active on this system.", "and Off is off for a pen as well")


## Where *lead* sits in the dropdown, which is what a choice row is driven by.
func _index_of(lead: String) -> int:
    for i in SaCursorPrediction.LEAD_MODES.size():
        if String(SaCursorPrediction.LEAD_MODES[i]["id"]) == lead:
            return i
    return -1


## A painter's sequence through the dropdown: Both chosen, then Auto,
## On and Off in turn on the lead row, the page never rebuilt, and the hint
## read after each.
func test_the_painters_sequence_through_the_row() -> void:
    var row := _page.page.row(&"cursor_lead")
    SaSettings.software_cursor = "both"
    _feed_a_mouse()
    var said: Array[String] = []
    for lead: String in ["auto", "on", "off"]:
        row.drive(_index_of(lead))
        _page.refresh_lead_row()
        said.append(_verdict(row.explanation))
    assert_eq(SaSettings.cursor_lead, "off", "the row wrote each choice through")
    assert_eq(
        said[0], "Not active for the mouse on this system. A pen would use it.", "Auto with a mouse, where a pen would lead"
    )
    assert_eq(said[1], "Active on this system.", "On leads, which is the sentence the old hint never said")
    assert_eq(said[2], "Not active on this system.", "and Off does not")


## The page asks every frame it is on screen, so nothing but a change of
## setting or device is needed for the hint to follow, and the capture report
## carries the sentence the painter reads.
func test_the_page_steps_while_shown_and_reports_its_hint() -> void:
    assert_true(_page.is_visible_in_tree(), "the page is on screen in the suite's tree")
    assert_true(_page.is_processing(), "and steps, which is what says the hint again")
    SaSettings.cursor_lead = "on"
    _page.refresh_lead_row()
    assert_true(_page.lead_report().contains("hint: "), "the lead report carries the hint")
    assert_true(_page.lead_report().ends_with("Active on this system."), "and ends on the verdict the row shows")
