## Sara's own pointer as an option: the values of
## `SaSettings.software_cursor` and what each resolves to. It has four values, *Both* last, whose own claims are in
## `test_both_cursor_mode.gd` and whose place in the list is held here.
##
## Only the resolution is here. Whether the pointer is then drawn depends on
## where the pointer physically is and on which windows have an overlay, which
## needs real Windows in the tree and hangs a headless run, so
## `scenarios/cursor-option.json` carries that half and is run twice, once
## per display driver.
extends "res://tests/test_framework.gd"

var _saved: String


func before_each() -> void:
    _saved = SaSettings.software_cursor


func after_each() -> void:
    SaSettings.software_cursor = _saved


## "never" and "always" are the two the painter sets deliberately, so neither
## may consult the driver: the whole point of the row is that the default is a
## default and not a gate.
func test_the_two_deliberate_values_ignore_the_display_driver() -> void:
    SaSettings.software_cursor = "never"
    assert_false(SaCursorPolicy.software_pointer_mode_active(), "Never is never, whatever the driver is")
    SaSettings.software_cursor = "always"
    assert_true(SaCursorPolicy.software_pointer_mode_active(), "Always is always, whatever the driver is")


## "auto" is the default and reads the driver. The suite runs under one driver
## at a time, so this asserts the rule rather than one machine's answer.
func test_auto_follows_the_display_driver() -> void:
    SaSettings.software_cursor = "auto"
    var wayland := DisplayServer.get_name() == SaCursorPolicy.WAYLAND_DRIVER
    assert_eq(
        SaCursorPolicy.software_pointer_mode_active(),
        wayland,
        "Auto is on under %s and off elsewhere, and this run is on %s" % [SaCursorPolicy.WAYLAND_DRIVER, DisplayServer.get_name()]
    )


## Anything else stored, by a hand-edited file or a setting written before this
## row existed, reads as the default rather than as an error.
func test_an_unknown_value_reads_as_auto() -> void:
    SaSettings.software_cursor = "auto"
    var expected := SaCursorPolicy.software_pointer_mode_active()
    SaSettings.software_cursor = "sometimes"
    assert_eq(SaCursorPolicy.software_pointer_mode_active(), expected, "An unknown value falls back to the driver check")


## The row is built from this list, so a value the policy resolves and the row
## cannot offer would be unreachable from Preferences.
func test_every_value_the_policy_resolves_has_a_row() -> void:
    var ids: Array[String] = []
    for mode: Dictionary in SaCursorPolicy.CURSOR_MODES:
        ids.append(String(mode["id"]))
        assert_false(String(mode["label"]).is_empty(), "'%s' has something to call itself on the page" % mode["id"])
    assert_eq(
        ids, ["auto", "always", "never", "both"] as Array[String], "The four the docstring names, in the order the row shows them"
    )
