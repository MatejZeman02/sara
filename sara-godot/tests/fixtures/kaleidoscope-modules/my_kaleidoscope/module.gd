# tests/fixtures/kaleidoscope-modules/my_kaleidoscope/module.gd
#
# A painter's copy of the kaleidoscope under an id of its own. It reaches its filter by a path beside it, as the
# shipped module now does, so the Filter menu shows the copy's own title rather
# than the shipped class the old global name built.
#
# SPDX-License-Identifier: GPL-3.0-or-later
extends SaModule

const Kaleidoscope := preload("kaleidoscope.gd")


func get_id() -> StringName:
    return &"my_kaleidoscope"


func get_name() -> String:
    return "My kaleidoscope"


func register(ctx: SaContext) -> void:
    ctx.register_filter(Kaleidoscope.new())
