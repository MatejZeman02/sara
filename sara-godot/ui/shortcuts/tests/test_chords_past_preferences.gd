## A chord typed at an open Preferences window does not act on the document
## behind it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## With Preferences open and focused on an otherwise untouched launch, Ctrl+T
## must not switch the canvas tool to transform and Ctrl+U must not open
## Hue/Saturation/Lightness over the top of Preferences. A bare B and a Shift+B
## do nothing, which is right, so the split is by modifier rather than by what
## the chord is for.
##
## `ShortcutRouter._on_window_input` sends every non-popup window's key to
## `handle_docker_input`, which is the whole router: the docker table, the
## registered commands and the tool table in turn. A docker wants that, because
## a painter with the keyboard in a docker still wants their chords. Preferences
## is not a docker, and neither is the Brush Editor or a filter dialog.
##
## This suite reads the wire out of the source rather than driving it, for the reason
## `ui/shortcuts/tests/test_escape_closes_docker.gd` records: a `Window` added to the tree
## in a headless run hangs the suite, so the claim is about which door the key
## goes through rather than about a key that was pressed.
extends "res://tests/test_framework.gd"

const ROUTER := "res://ui/shortcuts/shortcut_router.gd"


func _source() -> String:
    return FileAccess.get_file_as_string(ROUTER)


## The shape of the wire: `_on_window_input` splits a
## popup from everything else and hands everything else the whole router.
func test_the_router_treats_every_non_popup_window_as_a_docker_today() -> void:
    var source := _source()

    assert_true(source.contains("if window is Popup:"), "A popup is the one window kind that is told apart")
    assert_true(source.contains("handle_docker_input(event, window)"), "and everything else takes the docker path")
    assert_true(
        source.contains("func handle_docker_input(event: InputEvent, window: Window) -> void:"),
        "which is the entry point the check is about"
    )


## A settings window, a dialog and the brush editor are not
## dockers, and a chord that acts on the document has no business reaching the
## canvas from one.
##
## `handle_docker_input` asks `takes_document_chords` first, and a window
## that answers no gets Escape and the two chords about the application, nothing
## else. The two assertions below it are the rule's own shape, because a check
## that declined everything would meet the first, Ctrl+comma out of an open Preferences included.
func test_a_document_chord_stops_at_a_window_that_is_not_a_docker() -> void:
    var source := _source()

    assert_true(
        source.contains("is SaDialogWindow") or source.contains("is_docker"),
        (
            "`handle_docker_input` tells a docker from a settings window or a dialog. "
            + "Otherwise Ctrl+T changes the tool and Ctrl+U opens a filter dialog with Preferences focused."
        )
    )


## The other half of the rule, and the reason it is not simply "decline".
## Ctrl+comma has to work from inside a text box, and a painter
## who opened Preferences by that chord expects it to shut them again.
func test_the_two_chords_about_the_application_still_reach_it() -> void:
    var source := _source()

    assert_true(source.contains('"ui_quit", "edit_preferences"'), "The two are named where a reader can see them")
    assert_true(
        source.contains("SaShortcutKeys.is_escape(event) or SaShortcutKeys.pressed(event, WINDOW_CHORDS"),
        "and Escape joins them, because a window Escape could not leave would be the worse bug"
    )
