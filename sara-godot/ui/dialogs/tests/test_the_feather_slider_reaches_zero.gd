## Select > Feather can be set to 0 px, and Border, Grow and
## Shrink keep their floor of 1. The run of Feathers it makes possible is
## `core/api/selection/tests/test_a_feather_replaces_the_feather_before_it.gd`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"


func test_the_slider_reaches_zero_for_feather_alone() -> void:
    var dialog := SaRadiusDialog.new()
    dialog.configure("Feather", 0)
    assert_eq(dialog.radius(), 0, "Feather opens at 0 px")
    dialog.configure("Grow", 0)
    assert_eq(dialog.radius(), 1, "Grow keeps its floor of 1")
    dialog.configure("Border", 0)
    assert_eq(dialog.radius(), 1, "and so does Border")
    dialog.configure("Feather", 0)
    assert_eq(dialog.radius(), 0, "and Feather again reaches 0 after another kind")
    dialog.free()
