## The Toolbox's title glyph is a wrench.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The glyph left on `TitleIcon` is a wrench. `make_drag_bar` puts
## `SaUI.get_icon(name)` into
## that `TextureRect`, so what matters is the drawing and the name the
## docker passes. `wrench.svg` is new beside `tools.svg` rather than over it,
## because a glyph named for what it draws is the one the next reader can find,
## and `tools` stays in the set for anything that wants a spanner and a
## screwdriver.
##
## What a person sees is
## `scenarios/the-toolboxs-icon-is-a-wrench.json`, the title bar at the
## default Font size and at the largest, with a note step outlining the control.
extends "res://tests/test_framework.gd"

## The name `make_drag_bar` gives the glyph. Found rather than reached by path, the way the `note` step finds it,
## so a drag bar rearranged inside itself does not fail here for the wrong
## reason.
const TITLE_ICON := "TitleIcon"


## A docker built the way `test_docker_columns` builds one: under a plain
## Node, so `_init` runs and `_ready` does not, and no Window is ever displayed.
func _under_a_host(docker: Window) -> Node:
    var host := Node.new()
    host.add_child(docker)
    return host


## The asset resolves through the one door the UI has. `SaUI.get_icon`
## deliberately does not fall back to the editor's theme, so an icon that only
## resolves in the editor is one that disappears from a release build.
func test_the_wrench_resolves_as_a_shipped_icon() -> void:
    assert_not_null(SaUI.get_icon("wrench"), "wrench.svg ships in res://assets/icons/")
    assert_eq(SaUI.get_icon("Wrench"), SaUI.get_icon("wrench"), "and the lookup is case insensitive, like every other name")


## The title glyph is that asset and not the old one.
func test_the_toolboxs_title_icon_is_the_wrench_and_not_the_old_tools_glyph() -> void:
    var docker := ToolBoxDocker.new()
    var host := _under_a_host(docker)

    var icon := docker.find_child(TITLE_ICON, true, false) as TextureRect
    assert_not_null(icon, "the toolbox's drag bar carries a TitleIcon, which is what this test checks")
    assert_eq(icon.texture, SaUI.get_icon("wrench"), "and it holds the wrench")
    assert_true(icon.texture != SaUI.get_icon("tools"), "rather than the old glyph")

    host.free()


## The retired glyph is still in the set. The README keeps it under "unused",
## and a module reaching for it has nowhere else to reach, so this fails rather
## than letting it disappear quietly.
func test_the_old_tools_glyph_is_still_in_the_icon_set() -> void:
    assert_not_null(SaUI.get_icon("tools"), "tools.svg is kept rather than deleted")
