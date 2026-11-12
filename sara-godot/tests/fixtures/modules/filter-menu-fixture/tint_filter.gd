## The filter the fixture module registers.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## It builds no dialog and runs no kernel, because the claim is about
## registration: the entry reaching the Filter menu in the Other section,
## and the command reaching the same dialog. A fixture that pretended to build a dialog or a
## `SaFilterContext` would have to be rewritten whenever those changed.
##
## It counts the calls instead, so a test can say that the door reached this
## class rather than that something happened somewhere.
extends SaFilter

var built: int = 0
var ran: int = 0


func title() -> String:
    return "Fixture Tint"


func build(_ui: SaDialog) -> void:
    built += 1


func run(_ctx: SaFilterContext) -> void:
    ran += 1
