## A module in this fixture set, described by its functions alone, as every module was before manifests.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends SaModule


func get_id() -> StringName:
    return &"functions_only"


func get_name() -> String:
    return "Functions Only"


func get_version() -> String:
    return "1.2.3"


func register(_ctx: SaContext) -> void:
    pass
