## A filter in this fixture set, which registers by the class it extends.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends SaFilter


func title() -> String:
    return "Fixture Kept"


func run(_ctx: SaFilterContext) -> void:
    pass
