## The door walks a stroke and shapes its dabs with no stamp script loaded
##
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The door moved where dabs land along a stroke, how far apart and what shape they
## are into `core/api/dab` and `core/api/tip`, so that a second engine rides the
## pipeline the stamp rides. This builds the four strokes of
## `test_the_stamp_lays_its_dabs_where_it_did.gd` out of the door's classes
## alone: the curve between samples, the distance walk, the cadence, the dab's
## geometry and packing, the tip and its mask, with a stroke state for the pipe
## to choose its cell by. It reads the same dab positions and tips as the stamp
## recorded in the shared fixture.
##
## What the stamp adds around the walk is left out because none of it moves a
## dab here: the stabiliser is off, the pen is at full pressure so the dynamics
## answer the slider's size, spacing and hardness, and no rotation sensor asks
## for a fan at a corner. A stamp that started to do any of those by default
## would move its fixture, and this suite would fail beside it.
extends "res://tests/test_framework.gd"

## The tip mask uploads its picture and its pipe cells as textures.
const REQUIRES_GPU := true

const BrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## This suite's own path, whose dependencies are read to show that nothing it
## loads is the stamp's.
const SELF: String = "res://core/api/dab/tests/test_the_door_walks_a_stroke.gd"

## The strokes and the dabs the stamp laid, written by the stamp's suite.
const FIXTURE: String = "res://tests/fixtures/docker-walk/walk.json"

## The two door packages the walk is made of.
const PACKAGES: Array[String] = ["res://core/api/dab", "res://core/api/tip"]

## A tolerance for a number that went through JSON.
const CLOSE: float = 1e-4


func _fixture() -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
    return parsed if parsed is Dictionary else {}


## One stroke walked with the door's classes, one entry per dab in the shape
## the stamp's suite records.
func _walk(stroke: Dictionary, points: Array[Vector2], canvas: Vector2i, stroke_seed: int) -> Array:
    var tip: Resource = BrushTipScript.new()
    tip.ratio = float(stroke.get("ratio", 1.0))
    tip.angle = float(stroke.get("angle", 0.0))
    tip.auto_spacing = bool(stroke.get("auto", false))
    var mask := SaBrushTipMask.load_image("")
    if stroke.has("image"):
        mask = SaBrushTipMask.select(tip, String(stroke["image"]))
        assert_true(mask.error.is_empty(), "%s loads its picture" % stroke["name"])
    # The size the stamp's slider answers, a radius as a fraction of the
    # canvas's shorter side, back in pixels.
    var radius := float(stroke["diameter"]) * 0.5 / float(mini(canvas.x, canvas.y))
    var diameter := 2.0 * radius * float(mini(canvas.x, canvas.y))

    var info := SaStrokeInfo.new()
    var walk := SaStrokeDistance.new()
    var curve := SaStrokeCurve.new()
    var dabs: Array = []
    var lay := func(at: Vector2) -> void:
        info.feed(at, 1.0, Vector2.ZERO, 0.0, 0.0)
        info.next_dab()
        tip.diameter = SaDabGeometry.drawn_diameter(maxf(0.1, diameter))
        var hardness := SaDabPacking.hardness_for_dab(float(stroke["hardness"]), 1.0)
        tip.horizontal_fade = hardness
        tip.vertical_fade = hardness
        tip.spacing = float(stroke["spacing"])
        mask.advance(info)
        walk.register_dab(at, SaDabCadence.spacing_for(tip, 1.0, true), 1.0, -1.0)
        var half: Vector2 = tip.half_extent()
        var fade: Vector2 = tip.effective_fade()
        dabs.append([at.x, at.y, tip.diameter, half.x, half.y, fade.x, fade.y, tip.effective_generator(), mask.pipe_cell])
    var follow := func(span: SaStrokeCurve.Span) -> void:
        if span == null:
            return
        var start := span.path[0]
        for chord in range(1, span.path.size()):
            var goal := span.path[chord]
            var ceiling := 2 + int(start.distance_to(goal) / SaStrokeDistance.MIN_DISTANCE_SPACING)
            for _step in ceiling:
                var t := walk.next_point_position(start, goal)
                if t < 0.0:
                    break
                start = start.lerp(goal, t)
                lay.call(start)
            start = goal

    info.begin(points[0], stroke_seed)
    lay.call(points[0])
    curve.begin(points[0], 1.0, Vector2.ZERO)
    for i in range(1, points.size()):
        follow.call(curve.feed(points[i], 1.0, Vector2.ZERO, 0.0))
    follow.call(curve.finish(0.0))
    return dabs


func test_the_door_lays_the_dabs_the_stamp_laid() -> void:
    var fixture := _fixture()
    var strokes: Dictionary = fixture.get("strokes", {})
    assert_eq(strokes.size(), 4, "the stamp's suite recorded its four strokes")
    var points: Array[Vector2] = []
    for pair: Array in fixture.get("samples", []):
        points.append(Vector2(float(pair[0]), float(pair[1])))
    assert_true(points.size() > 2, "along a curve of %d samples" % points.size())
    var canvas_pair: Array = fixture.get("canvas", [0, 0])
    var canvas := Vector2i(int(canvas_pair[0]), int(canvas_pair[1]))
    var stroke_seed := int(fixture.get("seed", 0))

    for stroke_name: String in strokes:
        var input: Dictionary = strokes[stroke_name]["input"]
        var stamped: Array = strokes[stroke_name]["dabs"]
        var walked := _walk(input, points, canvas, stroke_seed)
        assert_eq(walked.size(), stamped.size(), "%s lays as many dabs through the door as the stamp did" % stroke_name)
        var worst := 0.0
        for i in mini(walked.size(), stamped.size()):
            for k: int in walked[i].size():
                worst = maxf(worst, absf(float(walked[i][k]) - float(stamped[i][k])))
        assert_true(worst < CLOSE, "%s: each where the stamp laid it with its tip, %s off at worst" % [stroke_name, worst])


## Nothing this suite or the two packages load is a module's script, so the
## walk above is the door's alone. Every script they hold is read with its
## comments stripped, for a load of a path under `res://modules` and, with its
## strings stripped as well, for a class a module declares.
func test_no_stamp_script_is_loaded() -> void:
    for dependency: String in ResourceLoader.get_dependencies(SELF):
        assert_false(dependency.contains("res://modules/"), "the suite loads %s, which is a module's" % dependency)
    var module_classes: Array[String] = []
    for entry: Dictionary in ProjectSettings.get_global_class_list():
        if String(entry["path"]).begins_with("res://modules/"):
            module_classes.append(String(entry["class"]))
    assert_true(module_classes.has("SaStampBindings"), "the module's classes were found, %d" % module_classes.size())
    var scripts: Array[String] = [SELF]
    for package: String in PACKAGES:
        for file_name: String in DirAccess.get_files_at(package):
            if file_name.ends_with(".gd"):
                scripts.append(package.path_join(file_name))
    assert_true(scripts.size() >= 10, "the two packages hold the nine and this suite, %d" % scripts.size())
    var loads_a_module := RegEx.create_from_string('load\\(\\s*"res://modules/')
    for path: String in scripts:
        var code := _without_comments(FileAccess.get_file_as_string(path))
        assert_true(loads_a_module.search(code) == null, "%s loads a module's script" % path)
        var bare := _without_strings(code)
        for named: String in module_classes:
            assert_true(RegEx.create_from_string("\\b%s\\b" % named).search(bare) == null, "%s names %s" % [path, named])


## *text* with every string literal emptied.
func _without_strings(text: String) -> String:
    return RegEx.create_from_string('"(?:[^"\\\\]|\\\\.)*"').sub(text, '""', true)


## *text* without its comments, a `#` inside a string left alone.
func _without_comments(text: String) -> String:
    var kept: PackedStringArray = []
    for line: String in text.split("\n"):
        var quoted := false
        var cut := line.length()
        var i := 0
        while i < line.length():
            var c := line[i]
            if quoted and c == "\\":
                i += 2
                continue
            if c == '"':
                quoted = not quoted
            elif c == "#" and not quoted:
                cut = i
                break
            i += 1
        kept.append(line.left(cut))
    return "\n".join(kept)
