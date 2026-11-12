## A module in this fixture set, whose functions say other things than its manifest.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends SaModule


func get_id() -> StringName:
    return &"from_code"


func get_name() -> String:
    return "Both, Named in Code"


func get_version() -> String:
    return "9.9.9"


func register(_ctx: SaContext) -> void:
    pass
