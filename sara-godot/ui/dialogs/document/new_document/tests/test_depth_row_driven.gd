## A scenario drives the New Document dialog's depth row.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The row has a capture door, so `depth` reads what a scenario asked of it
## rather than 16-bit float whatever was asked. The colour-drive scenario sets
## the depth row and the gamut row, and this is a test over the committed
## scenario file rather than only a rerun of it: the two steps are in the file,
## they ask for the two values the clause turns on, and the four
## `new_document_gamut` steps are still there. An edit that quietly dropped
## either half would leave the scenario no longer proving what it claims.
extends "res://tests/test_framework.gd"

const SCENARIO: String = "res://scenarios/colour-space.json"

## What the row is asked for and what it is put back to, in the dialog's own
## words: `NewDocumentDialog.select_row` matches the dropdown's item text.
const ASKED: String = "32-bit float"
const RESTORED: String = "16-bit float"


func test_t3_s_scenario_drives_the_depth_row_and_puts_it_back() -> void:
    var steps := _steps()
    assert_false(steps.is_empty(), "%s parses" % SCENARIO)

    var depths: Array[String] = []
    for step: Dictionary in steps:
        if not step.has("new_document_row"):
            continue
        var spec: Dictionary = step["new_document_row"]
        if spec.has("depth"):
            depths.append(str(spec["depth"]))

    assert_eq(depths.size(), 2, "Two depth steps, one that asks and one that puts it back")
    assert_eq(depths[0], ASKED, "The first asks for the depth the clause turns on")
    assert_eq(depths[1], RESTORED, "and the second restores the one the dialog opens with")


## The scenario is graded on the gamut steps it drives, so a later edit that
## replaced them with the newer step kind would make its record false rather
## than tidier. Both doors reach the same place, and that is an argument for
## leaving these alone rather than for rewriting them.
func test_the_gamut_steps_t3_was_graded_on_are_still_there() -> void:
    var wanted: Array[String] = ["display_p3", "ap1", "rec2020", "srgb"]
    var seen: Array[String] = []
    for step: Dictionary in _steps():
        if step.has("new_document_gamut"):
            seen.append(str(step["new_document_gamut"]))
    assert_eq(seen, wanted, "The four gamut steps, in their own order")


func _steps() -> Array[Dictionary]:
    var file := FileAccess.open(SCENARIO, FileAccess.READ)
    if file == null:
        return []
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if not (parsed is Array):
        return []
    var out: Array[Dictionary] = []
    for entry: Variant in parsed:
        if entry is Dictionary:
            out.append(entry)
    return out
