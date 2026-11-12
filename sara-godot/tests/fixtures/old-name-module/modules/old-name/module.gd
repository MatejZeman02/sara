## A module in this fixture set written before the base class was `SaModule`,
## so it still says `extends SaraModule`, as a module outside the tree may.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends SaraModule

const Kept = preload("kept.gd")


func register(ctx: SaContext) -> void:
    ctx.register_filter(Kept.new())
