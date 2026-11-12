## The one rule that keeps Levels' black and white inputs apart, whatever set
## them: a typed field, a scenario's `set_values`, a stored record or the
## door's adjust step.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The kernel divides by the input span, white less black. At zero it divides
## by nothing, and below zero the picture turns over and climbs past white: the
## Photoshop hour typed 80 into the Black field, which holds 1 at most, over a
## White it had dragged lower, and red 0.27 came out at 3.09. So a Black at or
## above White less [constant GAP] is held there, and a White at or below Black
## plus the gap is held there. The panel calls this for its fields and
## `SaPointAdjust.params_for` for the kernel, so a record written before the
## rule, or by a hand, reads the same as the fields show.
##
## Only the two inputs are held. Paint outside them still lands outside the
## output range, unclamped, as `levels_filter.gd` says and hard rule 5 asks.
class_name SaLevelsGap
extends RefCounted

## How far apart the two inputs are kept, one step of their fields.
const GAP := 0.005


## *values* with its black and white inputs a gap apart, as a copy. *moved* is
## the key that was just set, "in_black" or "in_white", and that one gives way,
## the black when none is named. Where giving way would take it out of the
## fields' range of 0 to 1, the other one gives way instead. So Black 80 over
## White 1 reads 0.995, White 0 over Black 0 reads the gap, and a Black typed
## at 0 over a White of 0 lifts the White to the gap.
static func held(values: Dictionary, moved := "") -> Dictionary:
    var out := values.duplicate()
    var black := float(values.get("in_black", 0.0))
    var white := float(values.get("in_white", 1.0))
    if black < white - GAP:
        return out
    var white_gives := moved == "in_white"
    if white_gives and black + GAP > 1.0:
        white_gives = false
    elif not white_gives and white - GAP < 0.0:
        white_gives = true
    out["in_black"] = black if white_gives else white - GAP
    out["in_white"] = black + GAP if white_gives else white
    return out
