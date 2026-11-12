## The name a new plain layer takes, "Layer" and one more than the highest N
## among the document's layers called "Layer N", or "Layer 1" when there is
## none.
##
## The one rule for both places that number a layer: `SaLayerOps.add`, and the
## Layers docker's pass that names a layer it finds unnamed. One rule keeps them
## agreeing: counting how many layers the document holds, pictures and the
## background among them, would give a photograph with two picture layers
## "Layer 3" for its first paint layer, and counting by the layer's place in
## the stack would give yet another.
class_name SaLayerNames
extends RefCounted

## The name, the message the catalogues already carry for it.
const PATTERN := "Layer %d"


## The names every layer of *document* carries, as a set, leaving out the
## "@" names the engine gives a node before it is named.
static func taken_in(document: SaDocument) -> Dictionary:
    var taken := {}
    for child in document.get_children():
        if child is SaLayer and not str(child.name).begins_with("@"):
            taken[str(child.name)] = true
    return taken


## The next "Layer N" for a document whose layers carry the names in *taken*,
## a set. A taken name is skipped, though one more than the highest is never
## a "Layer N" already.
static func next_in(taken: Dictionary) -> String:
    var number := 1 + highest(taken)
    while taken.has(PATTERN % number):
        number += 1
    return PATTERN % number


## The next "Layer N" for *document*.
static func next_for(document: SaDocument) -> String:
    return next_in(taken_in(document))


## The highest N among the names in *taken* that read "Layer N" with N a
## whole number above nought, and nought when none does.
static func highest(taken: Dictionary) -> int:
    var top := 0
    for name: String in taken:
        top = maxi(top, number_of(name))
    return top


## N for a name that reads "Layer N", and nought for any other name. The
## digits after the last space are read and the name made from them again, so
## "Layer 2 copy", "Layer -4" and "Layer 07" are no Layer N.
static func number_of(layer_name: String) -> int:
    var digits := layer_name.substr(layer_name.rfind(" ") + 1)
    if digits.is_empty() or not digits.lstrip("0123456789").is_empty():
        return 0
    var number := digits.to_int()
    return number if number > 0 and PATTERN % number == layer_name else 0
