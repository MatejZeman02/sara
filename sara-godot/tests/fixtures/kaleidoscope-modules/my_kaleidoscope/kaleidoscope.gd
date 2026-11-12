# tests/fixtures/kaleidoscope-modules/my_kaleidoscope/kaleidoscope.gd
#
# The copy's filter, the shipped one with its title edited, which is an edit
# the shipped one never shows.
#
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://modules/sara-base-modules/kaleidoscope/kaleidoscope.gd"


func title() -> String:
    return "Kaleidoscope, the painter's copy"
