## The Tablet page's Middle row says what the pen module does under Wayland.
##
## Its Wayland hint says the upper's release in the air is never heard, which
## stops being so once a module reads the pen from the kernel. While a source
## reads, the row says the kernel is heard. While it reads nothing, the row
## keeps its hint and adds the source's sentence, which says why and how to
## turn it on. With no pen module, or away from Wayland, the row is as it was.
extends "res://tests/test_framework.gd"


## A source that says what a case sets.
class StandIn:
    extends SaPenSource

    var reading: bool = false
    var sentence: String = ""

    func reads() -> bool:
        return reading

    func said() -> String:
        return sentence


var _middle: Dictionary = {}
var _right: Dictionary = {}


func before_each() -> void:
    for button: Dictionary in SaSettingsPenButtons.BUTTONS:
        if button["id"] == "middle":
            _middle = button
        elif button["id"] == "right":
            _right = button


func test_a_source_that_reads_turns_the_hint_to_the_kernels() -> void:
    var source := StandIn.new()
    source.reading = true
    source.sentence = "The pen module reads /dev/input/event7."
    var hint := SaTabletPage.button_hint(_middle, true, source)
    assert_true(hint.begins_with(SaTabletPage.MIDDLE_HINT_WITH_THE_KERNEL), "The row says the kernel is heard: %s" % hint)
    assert_true(hint.ends_with(source.sentence), "and what the source reads")
    assert_false(hint.contains("never hears"), "and no longer that the release is never heard")


func test_a_source_that_reads_nothing_says_why_after_the_wayland_hint() -> void:
    var source := StandIn.new()
    source.sentence = "The pen module is off, because Sara may not read /dev/input/event7."
    var hint := SaTabletPage.button_hint(_middle, true, source)
    assert_eq(hint, String(_middle["wayland_hint"]) + " " + source.sentence, "The hint as it was, and why the module is off")


func test_no_pen_module_or_no_wayland_leaves_the_rows_as_they_were() -> void:
    var source := StandIn.new()
    source.reading = true
    source.sentence = "The pen module reads /dev/input/event7."
    assert_eq(SaTabletPage.button_hint(_middle, true, null), String(_middle["wayland_hint"]), "No module: the Wayland hint")
    assert_eq(SaTabletPage.button_hint(_middle, false, source), String(_middle["hint"]), "Away from Wayland: the plain hint")
    assert_eq(SaTabletPage.button_hint(_right, true, source), String(_right["hint"]), "and the other rows say nothing of it")


## A source that has not looked for the pen yet has nothing to say, and the
## row keeps its hint.
func test_a_source_that_has_not_looked_yet_adds_nothing() -> void:
    var source := StandIn.new()
    var hint := SaTabletPage.button_hint(_middle, true, source)
    assert_eq(hint, String(_middle["wayland_hint"]), "A source that has not looked yet adds nothing")
