## The dabs a stroke laid and the texel each centre fell in, read off the
## brush once the stroke's frames have run, for the end of its line.
##
## **The count of dispatches is not a count of dabs.** The composite and the
## thumbnails dispatch too, so a stroke whose one dab was lost still read "41
## GPU dispatches" and was answered OK, while it laid nothing a painter could
## find. A brush keeps
## the stroke's last dab, a spread of its dabs and their count, and the press
## lets go of the last dab, so a dab that is not the one held before the
## stroke was laid by it. A tool with no dab of its own, a marquee or a
## transform box, adds no clause.
##
## Reached by path from the stroke rather than by class name, so no editor
## rescan stands between a fresh checkout and a step.
class_name SaScenarioDabsLaid
extends RefCounted

## How many dabs are each named. A stroke of more is named by its first
## and its last, since a line of a thousand texels is read by nobody.
const NAMED := 4


## The id of the dab *tool* holds before a stroke, nought for none, kept
## in the verdict as a number because a verdict is spliced as a step.
static func before(tool: Object) -> int:
    var dab: Object = tool.get("last_dab") if tool != null and "last_dab" in tool else null
    return dab.get_instance_id() if dab != null else 0


## The clause for the dabs *tool* laid since it held the dab whose id is
## *held*, or nothing for a tool that lays none.
static func after(tool: Object, held: int) -> String:
    if tool == null or not "last_dab" in tool or not "sampled_dabs" in tool or not "stroke_info" in tool:
        return ""
    var last: Object = tool.get("last_dab")
    if last == null or last.get_instance_id() == held:
        return clause(0, [])
    var count := int(tool.get("stroke_info").dab_index)
    var texels: Array = []
    for dab: Object in tool.get("sampled_dabs"):
        texels.append(texel_of(dab))
    if texels.size() < count or count > NAMED:
        texels = [texels[0] if not texels.is_empty() else texel_of(last), texel_of(last)]
    return clause(count, texels)


## The texel *dab*'s centre falls in, the one a painter sees it on and the
## one pixel mode lays it on.
static func texel_of(dab: Object) -> Vector2i:
    var centre: Vector2 = dab.get("position") + dab.get("scatter")
    return Vector2i(centre.floor())


## The words for *count* dabs laid on *texels*, every one named when
## there are as many as dabs and at most [constant NAMED], and otherwise
## the first and the last.
static func clause(count: int, texels: Array) -> String:
    if count <= 0:
        return ", no dab laid"
    var named: PackedStringArray = []
    for texel: Vector2i in texels:
        named.append("(%d, %d)" % [texel.x, texel.y])
    if count == 1:
        return ", 1 dab laid, on texel %s" % named[0]
    if texels.size() == count and count <= NAMED:
        return ", %d dabs laid, on texels %s and %s" % [count, ", ".join(named.slice(0, -1)), named[-1]]
    return ", %d dabs laid, the first on texel %s and the last on %s" % [count, named[0], named[-1]]
