## A module in this fixture set that registers by hand: one of its two filters,
## so a suite can tell the hand from the folder's default.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends SaModule

const Kept = preload("kept.gd")


func register(ctx: SaContext) -> void:
    ctx.register_filter(Kept.new())
