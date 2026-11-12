## A module in this fixture set whose `module.gd` names itself and leaves
## `register()` as `SaModule` writes it, so its folder registers its filter.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends SaModule


func get_name() -> String:
    return "Fixture Default Register"
