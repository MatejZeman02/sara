## The four helpers the `brush` step keeps its books with: the read-back that
## names a key which did not take, the seed every `stroke` is laid with, the
## wash and build-up key, and the curves `pen_settings` carries from JSON. Inner classes of one file rather than of
## `SaCaptureLayers`, which stood over the thousand lines a file may hold.
##
## SPDX-License-Identifier: GPL-3.0-or-later
class_name SaBrushStepKeys
extends RefCounted


## The `brush` step's read-back. `set_indexed` drops a number written over a
## resource that holds its number under `value`, and a path that names nothing,
## without a word, so `{"brush": {"hardness": 0}}` would answer as if it had
## softened the brush. So each key is read back after its
## write, and one that did not take is named with the path that would have
## reached it, found by the field's name among the settings and the resources
## they hold.
class KeyReadBack:
    extends RefCounted

    ## How deep under the settings the search for a path goes: the settings'
    ## own fields, a field of a resource on them such as `tip:ratio`, and one
    ## more, which reaches the masking brush's tip.
    const DEPTH: int = 3

    ## Whether writing *asked* at *path* on *settings* took: the path names a
    ## field, and the field either holds what was asked or changed from
    ## *before*, which a setter that clamps or a whole number truncated is.
    static func took(settings: Object, path: String, asked: Variant, before: Variant) -> bool:
        if not reaches(settings, path):
            return false
        var held: Variant = settings.get_indexed(path)
        return same(held, asked) or not same(held, before)

    ## Whether *path* names a field on *settings*, each name before the last a
    ## property of what the one before it holds.
    static func reaches(settings: Object, path: String) -> bool:
        var held: Variant = settings
        var names := path.split(":")
        for index in names.size():
            if held is Object:
                if names[index] not in held:
                    return false
                held = (held as Object).get(names[index])
            elif held is Dictionary:
                if not (held as Dictionary).has(names[index]):
                    return false
                held = (held as Dictionary)[names[index]]
            else:
                # A built-in value, a colour's channel, asked of the whole path.
                return settings.get_indexed(path) != null
            if held == null and index < names.size() - 1:
                return false
        return true

    ## The path that would take *asked* where *path* did not, or null: the
    ## `value` of a resource the path names, and otherwise the shallowest
    ## field anywhere under *settings* carrying the name the path ends on, a
    ## trailing `value` aside, of a type *asked* can be written to.
    ## `hardness` comes to `hardness:value` and `ratio:value` to `tip:ratio`.
    static func reach(settings: Object, path: String, asked: Variant) -> Variant:
        if reaches(settings, path):
            var held: Variant = settings.get_indexed(path)
            if held is Object and "value" in held and fits((held as Object).get("value"), asked):
                return path + ":value"
        var names := path.split(":")
        if names.size() > 1 and names[names.size() - 1] == "value":
            names.remove_at(names.size() - 1)
        var wanted := names[names.size() - 1]
        var level: Array = [["", settings]]
        var seen := {}
        for _depth in DEPTH:
            var below: Array = []
            for pair: Array in level:
                var found := _field_named(pair[0], pair[1] as Object, wanted, asked, path, below, seen)
                if not found.is_empty():
                    return found
            level = below
        return null

    ## A path under *holder*, which sits at *at*, ending on a field called
    ## *wanted* that takes *asked* and is not *path*, or "". Every resource a
    ## field holds goes into *below* for the next depth, once.
    static func _field_named(
        at: String, holder: Object, wanted: String, asked: Variant, path: String, below: Array, seen: Dictionary
    ) -> String:
        for property: Dictionary in holder.get_property_list():
            var name := String(property["name"])
            if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or name.begins_with("_"):
                continue
            var full := name if at.is_empty() else "%s:%s" % [at, name]
            var held: Variant = holder.get(name)
            if held is Resource:
                var inner := held as Resource
                if name == wanted and "value" in inner and fits(inner.get("value"), asked) and full + ":value" != path:
                    return full + ":value"
                if not seen.has(inner.get_instance_id()):
                    seen[inner.get_instance_id()] = true
                    below.append([full, inner])
            elif name == wanted and full != path and fits(held, asked):
                return full
        return ""

    ## Whether *asked*, a value off the wire, can be written over *held*: both
    ## numbers, the same type, a text onto a name or a colour, or a list onto a
    ## packed array.
    static func fits(held: Variant, asked: Variant) -> bool:
        if held is Object or asked is Object:
            return false
        if _numeric(held) and _numeric(asked):
            return true
        if typeof(held) == typeof(asked):
            return true
        if asked is String:
            return held is StringName or held is Color
        return asked is Array and typeof(held) >= TYPE_PACKED_BYTE_ARRAY

    ## Whether *held* is *asked*, as the field holds it: an object the same
    ## one, a number equal once turned into the field's own type, and a text
    ## equal once read as the name or colour the field keeps.
    static func same(held: Variant, asked: Variant) -> bool:
        if held is Object or asked is Object:
            return is_same(held, asked)
        if typeof(held) == typeof(asked):
            return is_equal_approx(held, asked) if held is float else held == asked
        if not fits(held, asked):
            return false
        var turned: Variant = type_convert(asked, typeof(held))
        return is_equal_approx(turned, held) if held is float else turned == held

    static func _numeric(value: Variant) -> bool:
        return value is int or value is float


## The `brush` step's `seed`. A seed drawn at a press reads `SaPenClock`, which
## a door session pins to the frames it has drawn, so a noise stroke's grain
## follows the session: the same steps sent in one session and in several, where
## each session's save, export and load draw frames of their own, lay different
## grains. While a seed is set, each
## `stroke` step is laid with it plus the strokes sent since the step, written
## on every tool of the machine as `ToolState.stroke_seed` before the stroke
## presses, which the noise brush and the stamp brush both hand to
## `SaStrokeInfo` at the press. Every tool, because the stroke presses whichever
## the pen's end or a held key puts in the hand, and the count is of `stroke`
## steps because that is what a session runner counts when it says the step
## again after a load.
##
## Held on the tool machine, so it lasts as long as the canvas it paints on,
## and a suite's canvas takes none to the next suite.
class DoorSeed:
    extends RefCounted

    ## Where the machine holds the seed in force.
    const META: StringName = &"sa_door_seed"

    ## The keys of the steps a `stroke` step splices in behind itself, each a
    ## `{"stroke": ...}` of its own: the events of the tool route, the bursts of
    ## a paced stroke and the verdict. A painting sends none of them, so they
    ## are not strokes to count.
    const STROKE_PARTS: Array[String] = ["report", "paced", "tool_event"]

    ## The number the step sent, which the first stroke after it is laid with.
    var _first: int = 0
    ## The `stroke` steps laid since the step.
    var _strokes: int = 0

    func _init(first: int) -> void:
        _first = first

    ## Hands the `seed` key's *value* to *machine*: a whole number starts a new
    ## count at it, and null puts back the seed drawn at the press. False for
    ## anything else, which leaves the seed in force as it was.
    static func hand(machine: ToolMachine, value: Variant) -> bool:
        if value == null:
            machine.remove_meta(META)
            for tool: ToolState in machine.registered_tools.values():
                tool.stroke_seed = 0
            return true
        var whole: bool = value is int or (value is float and is_finite(value) and value == floorf(value))
        if not whole:
            return false
        machine.set_meta(META, DoorSeed.new(int(value)))
        return true

    ## The seed in force on *machine*, or null.
    static func on(machine: ToolMachine) -> DoorSeed:
        return machine.get_meta(META) as DoorSeed if machine.has_meta(META) else null

    ## The seed the next stroke is laid with. Nought is laid as one, because a
    ## stroke seed of nought asks the press to draw one off the clock.
    func upcoming() -> int:
        var number := _first + _strokes
        return number if number != 0 else 1

    ## Writes the next stroke's seed on every tool of *machine* and counts the
    ## stroke.
    func lay(machine: ToolMachine) -> void:
        var number := upcoming()
        for tool: ToolState in machine.registered_tools.values():
            tool.stroke_seed = number
        _strokes += 1


## The `brush` step's `painting_mode`. The stamp brush's opacity is each dab's
## unless its Cross row says Wash, so a step that set Fill to 0.2 for a glaze
## without naming the mode would lay one stroke whose dabs build on each other
## to near full strength. The step takes the mode by the names the row shows
## and the answer says what the opacity is of.
##
## The modes are the numbers the settings hold, build-up 0 and wash 1, rather
## than the stamp brush's enum by name, because the harness names no module
## script.
class PaintingModeKey:
    extends RefCounted

    ## Each mode's name at the number the settings hold it under.
    const NAMES: Array[String] = ["build-up", "wash"]

    ## What the opacity is of in each mode, in the same order.
    const OPACITY_OF: Array[String] = ["each dab", "the whole stroke"]

    ## Writes the mode *asked* names onto *settings*. False when the settings
    ## hold no mode, as the noise brush's do, or *asked* names none, and then
    ## the mode is left as it was.
    static func hand(settings: Object, asked: Variant) -> bool:
        if not "painting_mode" in settings:
            return false
        var number := number_of(asked)
        if number < 0:
            return false
        settings.set("painting_mode", number)
        return true

    ## The number *asked* names, or -1: a name, read whatever its case and with
    ## a space or an underscore for the hyphen, or the whole number the row
    ## writes, which the step takes as well.
    static func number_of(asked: Variant) -> int:
        if asked is String or asked is StringName:
            var name := String(asked).strip_edges().to_lower().replace("_", "-").replace(" ", "-")
            return NAMES.find(name)
        var whole: bool = asked is int or (asked is float and is_finite(asked) and asked == floorf(asked))
        if whole and int(asked) >= 0 and int(asked) < NAMES.size():
            return int(asked)
        return -1

    ## The opacity in force on *settings* and what it is of,
    ## `opacity 0.20 of the whole stroke, painting_mode wash`, and the opacity
    ## alone for settings that hold no mode.
    static func opacity(settings: Object) -> String:
        var said := "opacity %.2f" % float(settings.get("opacity"))
        if not "painting_mode" in settings:
            return said
        var number := clampi(int(settings.get("painting_mode")), 0, NAMES.size() - 1)
        return "%s of %s, painting_mode %s" % [said, OPACITY_OF[number], NAMES[number]]


## The curves under a `brush` step's `pen_settings`, read from JSON.
##
## JSON has no `Vector2`, so a `common_curve` or a sensor's `curve` arrives as a
## list. Written onto a `PackedVector2Array` field as it stands, a list of pairs
## became a curve of zeros without a word, and a zero size curve lays no dab
## by design: `[[0, 0.02], [1, 1]]` answered as set and
## every stroke after it laid nothing. So a curve is read here, as a list of
## pairs `[[x, y], ...]` or of objects `{"x": .., "y": ..}`, and anything else
## is refused by its path before the step writes a thing.
class PenCurves:
    extends RefCounted

    ## The fields a curve sits under, on an option and on a sensor.
    const FIELDS: Array[String] = ["common_curve", "curve"]

    ## The form a refusal names.
    const FORM := 'a list of at least two pairs [[x, y], ...] or {"x": .., "y": ..} with x from 0 to 1 and rising'

    ## *pen* with every curve in it made a `PackedVector2Array`, or empty with
    ## the first curve it could not read named in *refused*.
    static func read(pen: Variant, refused: PackedStringArray) -> Variant:
        return _walk(pen, "", refused)

    static func _walk(value: Variant, path: String, refused: PackedStringArray) -> Variant:
        if value is Dictionary:
            var out := {}
            for key: Variant in value:
                var where := String(key) if path.is_empty() else "%s:%s" % [path, key]
                if FIELDS.has(String(key)):
                    var curve: Variant = points(value[key])
                    if curve == null:
                        refused.append("%s %s" % [where, JSON.stringify(value[key], "", false)])
                        return null
                    out[key] = curve
                    continue
                out[key] = _walk(value[key], where, refused)
                if not refused.is_empty():
                    return null
            return out
        if value is Array:
            var out := []
            for index in (value as Array).size():
                out.append(_walk(value[index], "%s:%d" % [path, index], refused))
                if not refused.is_empty():
                    return null
            return out
        return value

    ## *asked* as a curve, or null when it is not one of the two forms.
    static func points(asked: Variant) -> Variant:
        if asked is PackedVector2Array:
            return asked
        if not asked is Array or (asked as Array).size() < 2:
            return null
        var curve := PackedVector2Array()
        for point: Variant in asked as Array:
            var xy: Variant = _pair(point)
            if xy == null:
                return null
            var at := xy as Vector2
            if at.x < 0.0 or at.x > 1.0 or (not curve.is_empty() and at.x < curve[curve.size() - 1].x):
                return null
            curve.append(at)
        return curve

    static func _pair(point: Variant) -> Variant:
        if point is Vector2:
            return point
        var x: Variant = null
        var y: Variant = null
        if point is Array and (point as Array).size() == 2:
            x = point[0]
            y = point[1]
        elif point is Dictionary and (point as Dictionary).size() == 2:
            x = point.get("x")
            y = point.get("y")
        if not (x is float or x is int) or not (y is float or y is int):
            return null
        if not is_finite(float(x)) or not is_finite(float(y)):
            return null
        return Vector2(float(x), float(y))
