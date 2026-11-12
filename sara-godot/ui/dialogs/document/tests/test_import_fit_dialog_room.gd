## The import dialog's fit question has room for its buttons.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Place button's rect ended at 516 in a window 450 high, measured by
## `scenarios/the-import-dialogs-buttons-are-below-its-bottom-edge.json`, so
## Cancel and Place were below the bottom edge. The measurement is the scenario's,
## because a `Window` added to the tree in a headless run hangs and a detached one
## never lays out. What a test can hold is the number the measurement chose, so a
## later hand that shrinks the window back to something tidier fails a run rather
## than a painter.
extends "res://tests/test_framework.gd"

## The Place button's bottom edge in the fit question, in logical pixels, as the
## scenario measured it with the window at the height its rows need. It was 516
## with the window too short, and 350 once the rows became a page, measured
## by `scenarios/import-and-export-are-pages.json`. It is 410 with each wrapped
## line held at its tallest sentence, measured in a window of 422. The rows
## scroll, so in a taller window the buttons
## stand at its foot.
const MEASURED_BUTTON_BOTTOM: float = 410.0

## The slack the open question already had over its own button, the smallest a
## question in this dialog has shipped with.
const OPEN_QUESTION_SLACK: float = 41.0


func test_the_fit_question_holds_its_buttons_with_room() -> void:
    var height := float(SaImportFitDialog.FIT_SIZE.y)
    assert_true(height > MEASURED_BUTTON_BOTTOM, "The window is taller than the button's bottom edge")
    assert_true(
        height - MEASURED_BUTTON_BOTTOM >= OPEN_QUESTION_SLACK,
        "with at least the open question's slack, and it has %d" % int(height - MEASURED_BUTTON_BOTTOM)
    )


func test_the_smallest_fit_question_still_holds_its_buttons() -> void:
    assert_true(
        float(SaImportFitDialog.FIT_MIN_SIZE.y) > MEASURED_BUTTON_BOTTOM,
        "A painter shrinking the window to its minimum still sees Place"
    )
    assert_true(SaImportFitDialog.FIT_MIN_SIZE.y <= SaImportFitDialog.FIT_SIZE.y, "and the minimum is not above the size")
