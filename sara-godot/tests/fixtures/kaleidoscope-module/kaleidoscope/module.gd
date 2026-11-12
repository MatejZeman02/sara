# tests/fixtures/kaleidoscope-module/kaleidoscope/module.gd
#
# A painter's copy of the kaleidoscope with its id left as it was. Read from a root of its own through
# `--modules-dir`, so the scenario that loads it needs nothing staged by hand
# and no other fixture scenario meets the refusal. It registers nothing, so a
# reload that let it take the packaged module's place empties the Filter
# menu's two Kaleidoscope rows.
#
# SPDX-License-Identifier: GPL-3.0-or-later
extends SaModule


func get_id() -> StringName:
    return &"kaleidoscope"


func get_name() -> String:
    return "Kaleidoscope, the painter's copy"


func get_version() -> String:
    return "1.0.0"


func register(_ctx: SaContext) -> void:
    pass
