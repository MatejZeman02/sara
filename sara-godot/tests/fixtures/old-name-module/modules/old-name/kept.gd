## A filter in this fixture set, which the old-named module registers by hand.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends SaFilter


func title() -> String:
    return "Fixture Kept"


func run(_ctx: SaFilterContext) -> void:
    pass
