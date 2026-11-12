## The half of the Krita import that is a curve option: every `.kpp` option
## family onto `SaCurveOption`, the sensor XML onto `SaSensor`, and the curve
## strings onto points.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Written from the file format, not from Krita's code.** A Krita curve
## option is six params under one stem: `Pressure<Stem>` is the checkbox,
## `<Stem>UseCurve`, `<Stem>UseSameCurve`, `<Stem>Value`, `<Stem>curveMode`,
## `<Stem>commonCurve`, and `<Stem>Sensor` is an XML document whose root is
## either one sensor, `<params id="pressure">`, or `<params id="sensorslist">`
## with a `<sensor>` per active one. A sensor element carries the sweep's
## `length` and `periodic`, the drawing angle's `angleOffset`,
## `lockedAngleMode`, `fanCornersEnabled` and `fanCornersStep`, and a `<curve>`
## child when the sensor has one of its own. A curve is `x,y;x,y;` in the unit
## square. The stems and the sensor ids are interchange strings and are
## written here exactly as the files spell them, which is why one of them ends
## in a slash.
##
## `tests/test_kpp_import.gd` walks the two fixtures against these tables, so a
## stem added here with no Sara option behind it fails there rather than
## dropping a preset's option in silence.
class_name SaKppSensors
extends RefCounted

## Krita's sensor ids, as `KisDynamicSensor::id()` spells them, onto
## `SaSensor.KEYS`. Every one of Sara's sixteen has a Krita name, so a sensor
## never fails to carry, only to be available: rotation is `SaSensor.UNAVAILABLE`
## and is carried switched on, which is what a preset says.
const SENSOR_IDS: Dictionary = {
    "pressure": "pressure",
    "pressurein": "pressure_in",
    "xtilt": "tilt_x",
    "ytilt": "tilt_y",
    "tiltdirection": "tilt_direction",
    "tiltelevation": "tilt_elevation",
    "speed": "speed",
    "drawingangle": "drawing_angle",
    "rotation": "rotation",
    "distance": "distance",
    "time": "time",
    "fade": "fade",
    "fuzzy": "fuzzy_per_dab",
    "fuzzystroke": "fuzzy_per_stroke",
    "perspective": "perspective",
    "tangentialpressure": "tangential",
}

## The Krita stem of each of Sara's options, the settings field it lands on, in
## the order the brush editor lists them.
const OPTION_STEMS: Dictionary = {
    "Size": "size_option",
    "Opacity": "opacity_option",
    "Flow": "flow_option",
    "Rotation": "rotation_option",
    "Ratio": "ratio_option",
    "Softness": "softness_option",
    "Spacing": "spacing_option",
    "Scatter": "scatter_option",
    "Rate": "rate_option",
    "Texture/Strength/": "texture_option",
    "Mirror": "mirror_option",
    # Four of the colour stems read exactly like the rest, onto the colour
    # options. Krita's ids for the three HSV options are one letter each, `h`,
    # `s` and `v`, which is what `KisStandardOptionData.h` defines and what a
    # file carries as `Pressureh`. A spelling such as `PressureHue` reads well
    # and matches nothing. Mix is not here, because its curve is turned over on
    # the way in and `SaKppImport._apply_colour` is where that is.
    "h": "hue_option",
    "s": "saturation_option",
    "v": "value_option",
    "Darken": "darken_option",
    # Krita's colour smudge engine calls its smear length `SmudgeRate`, and it
    # is the one of the stage's three that Krita states the same way Sara does:
    # how much of the previous dab survives into the next.
    "SmudgeRate": "smudge_length_option",
}

## The six params a stem has, `Pressure` in front for the first and the rest
## behind, for the table's reader and for `taken`.
const STEM_SUFFIXES: Array[String] = ["UseCurve", "UseSameCurve", "Value", "curveMode", "commonCurve", "Sensor"]


## Every param name a stem owns, so the importer can say what it read.
static func names_of(stem: String) -> Array[String]:
    var out: Array[String] = ["Pressure" + stem]
    for suffix: String in STEM_SUFFIXES:
        out.append(stem + suffix)
    return out


## Writes the option under *stem* in *options* onto *option*, and answers what
## it could not carry, which for a curve option is nothing: every field has a
## home. A stem the preset does not mention leaves the option as the fresh
## settings had it, so a Krita preset that never touched Rotation imports with
## Rotation off exactly as a new brush has it.
##
## *taken* collects the param names read, so the importer can list the ones
## nobody read.
static func apply(option: SaCurveOption, options: Dictionary, stem: String, taken: Dictionary) -> void:
    if option == null:
        return
    var present := false
    for name: String in names_of(stem):
        if options.has(name):
            present = true
            taken[name] = true
    if not present:
        return
    option.enabled = bool_of(options, "Pressure" + stem, option.enabled)
    option.use_curve = bool_of(options, stem + "UseCurve", option.use_curve)
    option.use_same_curve = bool_of(options, stem + "UseSameCurve", option.use_same_curve)
    if options.has(stem + "Value"):
        option.strength = clampf(float_of(options, stem + "Value", option.strength), option.strength_min, option.strength_max)
    if options.has(stem + "curveMode"):
        var mode := int(float_of(options, stem + "curveMode", 0.0))
        if mode >= 0 and mode < SaCurveOption.Combine.size():
            option.combine = mode as SaCurveOption.Combine
    if options.has(stem + "commonCurve"):
        var points := parse_curve(string_of(options, stem + "commonCurve"))
        if points.size() >= 2:
            option.common_curve = points
    if options.has(stem + "Sensor"):
        option.sensors.clear()
        for read: Dictionary in parse_sensors(string_of(options, stem + "Sensor")):
            var id := SaSensor.id_of(String(read["key"]))
            if id < 0:
                continue
            var sensor := SaSensor.create(id as SaSensor.Id, true)
            if read.has("curve"):
                sensor.curve = read["curve"]
            if read.has("length"):
                sensor.length = int(read["length"])
            if read.has("periodic"):
                sensor.periodic = bool(read["periodic"])
            if read.has("angle_offset"):
                sensor.angle_offset = float(read["angle_offset"])
            if read.has("lock_angle"):
                sensor.lock_angle = bool(read["lock_angle"])
            if read.has("fan_corners"):
                sensor.fan_corners = bool(read["fan_corners"])
            if read.has("fan_step"):
                sensor.fan_step = float(read["fan_step"])
            option.set_sensor(sensor)


## `x,y;x,y;` onto points, in the unit square, in the order written. Anything
## that is not a pair is skipped, and a curve with fewer than two points is
## answered empty so the caller keeps the default.
static func parse_curve(text: String) -> PackedVector2Array:
    var points := PackedVector2Array()
    for pair: String in text.split(";", false):
        var xy := pair.strip_edges().split(",", false)
        if xy.size() != 2 or not xy[0].strip_edges().is_valid_float() or not xy[1].strip_edges().is_valid_float():
            continue
        points.append(Vector2(clampf(float(xy[0]), 0.0, 1.0), clampf(float(xy[1]), 0.0, 1.0)))
    return points if points.size() >= 2 else PackedVector2Array()


## The sensors a `<Stem>Sensor` document names, each as a dictionary of
## `key` and whichever of `curve`, `length`, `periodic`, `angle_offset`,
## `lock_angle`, `fan_corners` and `fan_step` the element carried.
##
## The root is one sensor or a list, and both shapes are walked the same way:
## every element whose `id` is a sensor's opens one, and a `<curve>` under it
## belongs to the last opened. An id this file does not know is skipped, and
## `sensorslist` is not a sensor.
static func parse_sensors(xml: String) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    if xml.strip_edges().is_empty():
        return out
    var parser := XMLParser.new()
    if parser.open_buffer(xml.to_utf8_buffer()) != OK:
        return out
    var expecting_curve := false
    while parser.read() == OK:
        var node_type := parser.get_node_type()
        if node_type == XMLParser.NODE_ELEMENT:
            var element := parser.get_node_name()
            if element == "curve":
                expecting_curve = not out.is_empty()
                continue
            var id := parser.get_named_attribute_value_safe("id")
            if id.is_empty() or id == "sensorslist" or not SENSOR_IDS.has(id):
                continue
            var read: Dictionary = {"key": SENSOR_IDS[id]}
            _attribute(parser, read, "length", "length")
            _attribute(parser, read, "periodic", "periodic")
            _attribute(parser, read, "angleOffset", "angle_offset")
            _attribute(parser, read, "lockedAngleMode", "lock_angle")
            _attribute(parser, read, "fanCornersEnabled", "fan_corners")
            _attribute(parser, read, "fanCornersStep", "fan_step")
            out.append(read)
        elif node_type == XMLParser.NODE_TEXT or node_type == XMLParser.NODE_CDATA:
            if expecting_curve:
                var points := parse_curve(parser.get_node_data())
                if points.size() >= 2:
                    out[-1]["curve"] = points
                expecting_curve = false
    return out


static func _attribute(parser: XMLParser, into: Dictionary, attribute: String, key: String) -> void:
    if not parser.has_attribute(attribute):
        return
    var text := parser.get_named_attribute_value(attribute)
    if key in ["periodic", "lock_angle", "fan_corners"]:
        into[key] = truthy(text)
    elif text.is_valid_float():
        into[key] = float(text)


## Krita writes booleans as `true` and `false`, and older files as `1` and `0`.
static func truthy(text: String) -> bool:
    var lower := text.strip_edges().to_lower()
    return lower == "true" or lower == "1"


## How one option's value is read out of the table: every value in the XML is a
## string, and these three are the one place it becomes a string, a number or a
## switch. `fallback` is what an option the preset does not carry reads as.
##
## Public because they are the whole import's readers and not this file's: the
## mapping table is read through them wherever it lives, and
## `sa_kpp_masking.gd` is the second caller.
static func string_of(options: Dictionary, name: String) -> String:
    return String((options[name] as Dictionary).get("value", "")) if options.has(name) else ""


static func bool_of(options: Dictionary, name: String, fallback: bool = false) -> bool:
    return truthy(string_of(options, name)) if options.has(name) else fallback


static func float_of(options: Dictionary, name: String, fallback: float) -> float:
    var text := string_of(options, name).strip_edges()
    return float(text) if text.is_valid_float() else fallback
