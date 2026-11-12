# The second showcase module, read after the box blur. The box blur is the
# least a filter can be, and this one carries what it leaves out: a widget of
# its own, presets, a pass that reads the whole layer, and a suite.
#
# **This file is the folder, and `kaleidoscope.gd` beside it is the filter.**
# `get_id` and `get_name` below, and the version in `manifest.cfg` beside them,
# are what the loader reads to tell one module from another, and two folders
# answering one id are one module with the second refused at boot. Nothing here is ever shown: the fold
# a painter picks in the Filter menu is that file's `id()` and `title()`.
#
# The filter is reached by a path beside this file and not by a class name.
# A class name is global, and a copy of this folder under the modules folder
# would build the shipped class instead of its own and fail to parse at
# Modules > Reload.
#
# SPDX-License-Identifier: GPL-3.0-or-later
extends SaModule

const Kaleidoscope := preload("kaleidoscope.gd")


func get_id() -> StringName:
    return &"kaleidoscope"


func get_name() -> String:
    return "Kaleidoscope"


func register(ctx: SaContext) -> void:
    ctx.register_filter(Kaleidoscope.new())
