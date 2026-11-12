## The stamp brush lays its dabs where it laid them before the dab placement and
## the tips moved into the door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## moved the walk, the cadence, the dab's geometry and packing and the four
## tip classes out of the stamp's `tools/` folder, a move and not a rewrite. This
## paints four strokes through the stamp brush itself, a round tip, a flat one
## turned on its axis with auto spacing, a picture and a pipe, along one S sampled
## unevenly as a hand samples it, and writes down every dab the walk registered:
## where it landed and what tip it was painted with. The numbers were recorded on
## the tree before the move, so a stamp that walks differently afterwards is red
## here.
##
## **The fixture is shared.** `test_the_door_walks_a_stroke.gd` builds the
## same four strokes out of the door's classes alone, with no stamp script
## loaded, and has to read the same dabs. So the fixture holds each stroke's
## input as well as its dabs, and the door's suite reads both from here.
##
## A row that means to move a dab records the fixture again with
## `SARA_WRITE_B2_WALK=1` and says why in its commit.
##
## In `tests/` rather than the stamp's own suites, because it paints through
## `SaPresetThumbs`' view, which a module cannot name past the door.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## The strokes, their inputs and every dab each laid down.
const FIXTURE: String = "res://tests/fixtures/docker-walk/walk.json"

## Set to anything to write the fixture from this run instead of reading it.
const WRITE_ENV: String = "SARA_WRITE_B2_WALK"

## The canvas the strokes are painted on, whose shorter side is what a brush's
## radius is a fraction of.
const CANVAS := Vector2i(512, 256)

## The stroke's seed, so a pipe that chose at random would choose the same.
const SEED: int = 2402

## A tolerance for a number that went through JSON.
const CLOSE: float = 1e-4

## Where the tip and the dab classes lived before the fix, which is what a preset
## saved then names in its `[ext_resource]` lines, and the two door packages
## they live in now.
const OLD_DIR: String = "res://modules/sara-base-modules/stamp-brush/tools/"
const NEW_DIRS: Array[String] = ["res://core/api/tip/", "res://core/api/dab/"]

static var scratch_dir: String = SaDataRoot.path("test_b2_the_stamp_lays_its_dabs")

## The four strokes. A tip's picture is a path under `res://tips`, and none is
## the procedural tip. *diameter* is in document pixels.
const STROKES: Array[Dictionary] = [
    {"name": "round", "diameter": 20.0, "spacing": 0.25, "hardness": 0.7, "ratio": 1.0, "angle": 0.0, "auto": false},
    {"name": "flat", "diameter": 26.0, "spacing": 0.2, "hardness": 1.0, "ratio": 0.35, "angle": 0.6, "auto": true},
    {"name": "picture", "diameter": 30.0, "spacing": 0.3, "hardness": 1.0, "image": "res://tips/tree.png"},
    {"name": "pipe", "diameter": 24.0, "spacing": 0.5, "hardness": 1.0, "image": "res://tips/four-bars.gih"},
]


## A brush that paints as it always does and writes down each dab after.
class RecordingBrush:
    extends StateBrushScript

    var dabs: Array = []

    func _dispatch_brush(dab: SaDabParams) -> void:
        super(dab)
        # The stroke's copy, which the dab wrote its size onto, left the stored tip as the preset saved it.
        var tip: Resource = _stroke.tip(_tip())
        var half: Vector2 = tip.half_extent()
        var fade: Vector2 = tip.effective_fade()
        var at: Vector2 = stroke_distance.last_position
        (
            dabs
            . append(
                [
                    at.x,
                    at.y,
                    tip.diameter,
                    half.x,
                    half.y,
                    fade.x,
                    fade.y,
                    tip.effective_generator(),
                    tip_mask.pipe_cell if tip_mask != null else 0,
                ]
            )
        )


## An S across the canvas, sampled at uneven gaps, the first sample the press.
static func samples() -> Array[Vector2]:
    var found: Array[Vector2] = []
    var along := 40.0
    for gap: float in [0.0, 9.0, 41.0, 3.0, 66.0, 18.0, 90.0, 5.0, 37.0, 71.0, 12.0, 55.0]:
        along += gap
        var t := (along - 40.0) / 420.0
        found.append(Vector2(along, 128.0 + 80.0 * sin(TAU * t)))
    return found


func after_each() -> void:
    var dir := DirAccess.open(scratch_dir)
    if dir == null:
        return
    for name: String in dir.get_files():
        dir.remove(name)


## Paints *stroke* and answers its dabs. With *keep_uid* not null the settings
## first go through a preset store, saved, written back to the folder the tip
## lived in before the fix, with or without their `uid` as *keep_uid* says, and
## loaded again, so the stroke is painted by a preset saved before the move.
func _paint(stroke: Dictionary, keep_uid: Variant = null) -> Array:
    var easel := SaEasel.create_default(CANVAS, SaPresetThumbs.shared_compositor())
    var view := SaPresetThumbs.ThumbView.new()
    var surface := SaSurface.create(&"b2_walk", easel, view)
    var brush := RecordingBrush.new()
    brush.surface = surface
    brush.stroke_seed = SEED
    var settings: Resource = brush.settings
    settings.radius = float(stroke["diameter"]) * 0.5 / float(mini(CANVAS.x, CANVAS.y))
    settings.spacing = float(stroke["spacing"])
    settings.hardness.value = float(stroke["hardness"])
    var tip: Resource = brush._tip()
    tip.ratio = float(stroke.get("ratio", 1.0))
    tip.angle = float(stroke.get("angle", 0.0))
    tip.auto_spacing = bool(stroke.get("auto", false))
    if stroke.has("image"):
        var picked: RefCounted = SaBrushTipMask.select(tip, String(stroke["image"]))
        assert_true(String(picked.get("error")).is_empty(), "%s loads its picture" % stroke["name"])
    if keep_uid != null:
        var store := SaPresetStore.new()
        store.dir = scratch_dir
        var stored := store.save_preset("b2 %s" % stroke["name"], settings)
        assert_false(stored.is_empty(), "%s saved into the scratch store" % stroke["name"])
        var rewritten := _as_before_the_move(scratch_dir.path_join(stored + ".tres"), bool(keep_uid))
        assert_true(rewritten > 0, "%s names the tip in %d lines, now the old folder's" % [stroke["name"], rewritten])
        var loaded := store.load_preset(stored)
        assert_not_null(loaded, "%s loads with its lines in the old folder, uid kept %s" % [stroke["name"], keep_uid])
        if loaded == null:
            return []
        brush.settings = loaded
    var points := samples()
    for i in points.size():
        view.at = points[i]
        var event: InputEvent
        if i == 0:
            var press := InputEventMouseButton.new()
            press.button_index = MOUSE_BUTTON_LEFT
            press.pressed = true
            event = press
        else:
            event = InputEventMouseMotion.new()
        event.position = points[i]
        event.global_position = points[i]
        brush.handle_input(event)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)
    easel.document.free()
    easel.free()
    return brush.dabs


func _read_fixture() -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
    return parsed if parsed is Dictionary else {}


func test_every_stroke_lays_the_dabs_it_laid_before_the_move() -> void:
    var painted: Dictionary = {}
    for stroke: Dictionary in STROKES:
        painted[stroke["name"]] = {"input": stroke, "dabs": _paint(stroke)}

    if not OS.get_environment(WRITE_ENV).is_empty():
        var points: Array = []
        for at in samples():
            points.append([at.x, at.y])
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE.get_base_dir()))
        var file := FileAccess.open(FIXTURE, FileAccess.WRITE)
        file.store_string(
            (
                JSON.stringify(
                    {"canvas": [CANVAS.x, CANVAS.y], "seed": SEED, "samples": points, "strokes": painted}, " ", true, true
                )
                + "\n"
            )
        )
        file = null
        print("wrote %d strokes to %s" % [painted.size(), FIXTURE])

    var recorded: Dictionary = _read_fixture().get("strokes", {})
    assert_eq(recorded.size(), painted.size(), "the fixture holds every stroke and no other")
    for stroke_name: String in painted:
        var now: Array = painted[stroke_name]["dabs"]
        var then: Array = recorded.get(stroke_name, {}).get("dabs", [])
        assert_true(now.size() > 20, "%s laid a stroke's worth of dabs, %d" % [stroke_name, now.size()])
        assert_eq(now.size(), then.size(), "%s lays as many dabs as before the move" % stroke_name)
        var worst := 0.0
        for i in mini(now.size(), then.size()):
            for k: int in now[i].size():
                worst = maxf(worst, absf(float(now[i][k]) - float(then[i][k])))
        assert_true(worst < CLOSE, "and each where it was with the tip it had, %s off at worst" % worst)


## A preset saved before the move names the tip's script in the stamp's
## folder. It loads, by its `uid` or by the store's path repair when the uid is
## gone, and lays the dabs the stamp laid.
func test_a_preset_saved_before_the_move_lays_the_same_dabs() -> void:
    var recorded: Dictionary = _read_fixture().get("strokes", {})
    var checked := 0
    for stroke: Dictionary in STROKES:
        var then: Array = recorded.get(stroke["name"], {}).get("dabs", [])
        for keep_uid: bool in [true, false]:
            var now := _paint(stroke, keep_uid)
            assert_eq(now.size(), then.size(), "%s, uid kept %s, lays as many dabs as before" % [stroke["name"], keep_uid])
            var worst := 0.0
            for i in mini(now.size(), then.size()):
                for k: int in now[i].size():
                    worst = maxf(worst, absf(float(now[i][k]) - float(then[i][k])))
            assert_true(worst < CLOSE, "and each where it was, %s off at worst" % worst)
            checked += 1
    assert_eq(checked, STROKES.size() * 2, "every stroke was loaded both ways")


## Writes the old folder into every `[ext_resource]` line of *path* that names
## a script of the two door packages, dropping the `uid` unless *keep_uid*.
## Answers how many lines it changed.
func _as_before_the_move(path: String, keep_uid: bool) -> int:
    var out: PackedStringArray = []
    var changed := 0
    for line: String in FileAccess.get_file_as_string(path).split("\n"):
        if line.begins_with("[ext_resource "):
            for folder: String in NEW_DIRS:
                if line.contains(folder):
                    line = line.replace(folder, OLD_DIR)
                    if not keep_uid:
                        line = RegEx.create_from_string(' uid="[^"]*"').sub(line, "")
                    changed += 1
        out.append(line)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string("\n".join(out))
    file.close()
    return changed


## The pipe steps through its cells and the flat tip is not round, so the
## strokes exercise what they are named for.
func test_the_strokes_are_what_they_say() -> void:
    var recorded: Dictionary = _read_fixture().get("strokes", {})
    var cells := {}
    for dab: Array in recorded.get("pipe", {}).get("dabs", []):
        cells[int(dab[8])] = true
    assert_eq(cells.size(), 4, "the pipe painted all four of its cells")
    var flat: Array = recorded.get("flat", {}).get("dabs", [[0, 0, 0, 1.0, 1.0]])
    assert_true(float(flat[0][4]) < 0.5 * float(flat[0][3]), "and the flat tip is flat")
