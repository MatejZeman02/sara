## A module in this fixture set, whose manifest is refused, so this script never runs.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends SaModule


func _init() -> void:
    Engine.set_meta(&"code_ran", true)


func register(_ctx: SaContext) -> void:
    pass
