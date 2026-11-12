## Whether a size a scenario step asks for is one a dialog could have made.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The New Document, Canvas Size and Image Size dialogs each take a side from 1
## to [constant LIMIT] and nothing else, so a canvas outside that box can only
## arrive through the door. A `canvas` step of `[100000, 100000]` or a
## `document` step whose `size` is `[-5, 10]` was taken, made 1 or handed to an
## `assert` a release build strips, and the next fill, fold or export hung or ran
## out of memory. The `canvas` and `document` steps ask here first and change
## nothing when the answer is a refusal.
##
## Reached by path from the drivers that call it, like every harness file.
class_name SaScenarioSize
extends RefCounted

## The largest side, the one the Image Size dialog reads. The other two dialogs
## carry a constant of their own, and a suite holds the three equal.
const LIMIT := SaResample.MAX_DIMENSION


## The refusal of *pair* for the step called *step*, or empty when both sides lie
## from 1 to [constant LIMIT]. Printed and raised as an error, so the door's
## answer carries it under `errors` the way it carries a stroke that failed.
## Only a pair of two numbers is judged here: anything else keeps whatever
## meaning the step already gave it.
static func refusal(step: String, pair: Array) -> String:
    var width := int(pair[0])
    var height := int(pair[1])
    if width >= 1 and height >= 1 and width <= LIMIT and height <= LIMIT:
        return ""
    var said := (
        "SaCapture: %s %s refused, a side must be 1 to %d, as every size dialog allows, so the document is left as it was"
        % [step, written(pair), LIMIT]
    )
    print(said)
    push_error(said)
    return said


## Whether *spec* is two numbers, the shape [method refusal] judges.
static func is_pair(spec: Variant) -> bool:
    if not spec is Array or (spec as Array).size() != 2:
        return false
    for side: Variant in spec as Array:
        if not (side is int or side is float):
            return false
    return true


## *pair* as a scenario writes it, `[0, 100]`, with no `.0` a JSON number picks
## up on its way in.
static func written(pair: Array) -> String:
    var sides: PackedStringArray = []
    for side: Variant in pair:
        var whole: bool = side is float and float(side) == floorf(float(side))
        sides.append(str(int(side)) if whole else str(side))
    return "[%s]" % ", ".join(sides)
