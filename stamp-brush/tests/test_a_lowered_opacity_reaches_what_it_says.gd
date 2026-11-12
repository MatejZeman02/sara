## A lowered opacity reaches what it says, so wash is the mode
## a new preset and a shipped one start in.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A hard round at opacity 0.36 in
## build-up covered 89 % in one stroke, where wash covers the 36 % the slider
## says. So a new brush starts in wash, every shipped recipe paints in it except
## the two that chose build-up for what they are, and nothing a painter already
## has moves: a preset saved in build-up before format 14 carries no mode at
## all, because build-up was the default the saver leaves out, and the format's
## step reads it as the build-up it painted in. A Krita preset with no
## `PaintOpAction` reads Krita's own default, build-up.
##
## The stroke is laid through the brush's own `handle_input` onto a white
## ground and read back off the composite. The picture is
## `scenarios/a-lowered-opacity-reaches-what-it-says-wash-is-the-default-for-new-and-shipped-presets.json`.
extends "res://tests/test_framework.gd"

## Paints and reads back the canvas.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const KppFixtures = preload("res://modules/sara-base-modules/stamp-brush/tests/kpp_fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The canvas, whose short side Fill's radius is a fraction of: a tip about 190
## pixels across.
const SIDE: int = 512
## How far the stroke runs, and how many motions carry it after the press.
const LENGTH: float = 200.0
const MOTIONS: int = 8
## The opacity measured at, and how far the coverage may stand off it.
const OPACITY: float = 0.36
const TOLERANCE: float = 0.02

## The recipes that chose build-up for what they are, and say why beside them.
## Pointed Mark and Shadow Edge are tuned in build-up, and
## Torn Gouache is a bundled painter's preset, shipped in the build-up it was
## saved in. Spatter, Streaks and Dry Strokes are bundled painter's presets
## too, which paint in build-up.
const BUILD_UP: Array[String] = [
    "Airbrush",
    "Chisel Marker",
    "Pointed Mark",
    "Shadow Edge",
    "Torn Gouache",
    "Spatter",
    "Streaks",
    "Dry Strokes",
]

static var scratch_dir: String = SaDataRoot.path("test_a_lowered_opacity")

var _surface: SaSurface = null


func after_each() -> void:
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = null
    if DirAccess.dir_exists_absolute(scratch_dir):
        for file_name: String in DirAccess.get_files_at(scratch_dir):
            DirAccess.remove_absolute(scratch_dir.path_join(file_name))
        DirAccess.remove_absolute(scratch_dir)


# --- The shipped table ------------------------------------------------------------


## One stroke with the shipped Fill at opacity 0.36 on white covers 0.36
## within 0.02. The same stroke in build-up is read beside it.
func test_the_shipped_fill_at_a_lowered_opacity_covers_what_it_says() -> void:
    var fill := _recipe("Fill")
    assert_eq(fill.painting_mode, SettingsScript.PaintingMode.WASH, "Fill ships in wash")

    var washed := _stroke(fill)
    assert_almost_eq(washed, OPACITY, TOLERANCE, "One stroke of Fill at %.2f covers %.3f" % [OPACITY, washed])

    var built := _recipe("Fill")
    built.painting_mode = SettingsScript.PaintingMode.BUILD_UP
    var heaped := _stroke(built)
    assert_true(heaped > 0.8, "where the same stroke in build-up covers %.3f, the fault wash ends" % heaped)


## Airbrush is still in build-up, with Chisel Marker and Pointed Mark and
## Shadow Edge, the others that chose it.
func test_the_recipes_that_chose_build_up_keep_it() -> void:
    for name: String in BUILD_UP:
        assert_eq(_recipe(name).painting_mode, SettingsScript.PaintingMode.BUILD_UP, "%s ships in build-up" % name)


## Every other recipe, the basic bundle and the drawn tips, paints in wash.
func test_every_other_shipped_recipe_paints_in_wash() -> void:
    var counted := 0
    for entry: Dictionary in SaShippedPresets.entries():
        var name := String(entry["name"])
        if BUILD_UP.has(name):
            continue
        var settings := SaShippedPresets.build(SettingsScript, entry) as SaStampBrushSettings
        assert_not_null(settings, "%s builds" % name)
        if settings == null:
            continue
        assert_eq(settings.painting_mode, SettingsScript.PaintingMode.WASH, "%s ships in wash" % name)
        counted += 1
    assert_true(counted > 40, "Every recipe but the two is read, %d of them" % counted)


# --- What a painter already has ---------------------------------------------------


## "A suite loads a preset saved before this row in build-up and reads it in
## build-up." Format 13 left build-up out of the file, since it was the default,
## so the file is written as that build would have written it: the stamp at 13
## and no mode. One saved in wash then carried the key and keeps it.
func test_a_preset_saved_before_this_row_keeps_its_mode() -> void:
    var store := _store()
    _write_at_format_13(store, "Old Build-up", "")
    _write_at_format_13(store, "Old Wash", "painting_mode = 1")

    var built := store.load_preset("Old Build-up") as SaStampBrushSettings
    assert_not_null(built, "The old build-up preset loads")
    if built != null:
        assert_eq(built.painting_mode, SettingsScript.PaintingMode.BUILD_UP, "in the build-up it painted in")
        assert_eq(built.format_version, SettingsScript.FORMAT_VERSION, "stamped up to date")

    var washed := store.load_preset("Old Wash") as SaStampBrushSettings
    assert_not_null(washed, "The old wash preset loads")
    if washed != null:
        assert_eq(washed.painting_mode, SettingsScript.PaintingMode.WASH, "in the wash it painted in")


## A preset saved since keeps either mode through the file, build-up as a key
## and wash as the default the saver leaves out, and the step does not run again.
func test_a_preset_saved_since_keeps_either_mode() -> void:
    var store := _store()
    for mode: int in [SettingsScript.PaintingMode.BUILD_UP, SettingsScript.PaintingMode.WASH]:
        var settings := SettingsScript.new()
        settings.painting_mode = mode as SettingsScript.PaintingMode
        var stored := store.save_preset("Since %d" % mode, settings)
        var loaded := store.load_preset(stored) as SaStampBrushSettings
        assert_not_null(loaded, "A preset saved in mode %d loads" % mode)
        if loaded != null:
            assert_eq(int(loaded.painting_mode), mode, "in the mode it was saved in")


## "and imports a Krita preset with no `PaintOpAction` and reads build-up",
## through the store as the import menu does, beside the round fixture's own
## `PaintOpAction` of 2, which is wash.
func test_a_krita_preset_with_no_paint_op_action_reads_build_up() -> void:
    var store := _store()
    var preset := SaKppReader.read_bytes(KppFixtures.round_kpp(), "sara-round.kpp")
    var options: Dictionary = preset.get("options", {})
    assert_true(options.has("PaintOpAction"), "The round fixture names its mode")
    var washed := _imported(store, preset.duplicate(true), "Krita Wash")
    assert_eq(washed, int(SettingsScript.PaintingMode.WASH), "and with it, 2, the import reads wash")

    options.erase("PaintOpAction")
    var built := _imported(store, preset, "Krita Default")
    assert_eq(built, int(SettingsScript.PaintingMode.BUILD_UP), "Without it the import reads build-up, Krita's default")


# --- A new preset -----------------------------------------------------------------


## "A suite makes a new preset from defaults and reads it in wash", the way
## the presets docker's New preset does, a fresh resource saved and loaded.
func test_a_new_preset_from_defaults_paints_in_wash() -> void:
    var fresh := SettingsScript.new()
    assert_eq(fresh.painting_mode, SettingsScript.PaintingMode.WASH, "A new brush starts in wash")

    var store := _store()
    var stored := store.save_preset("New", SettingsScript.new())
    var loaded := store.load_preset(stored) as SaStampBrushSettings
    assert_not_null(loaded, "The new preset loads")
    if loaded != null:
        assert_eq(loaded.painting_mode, SettingsScript.PaintingMode.WASH, "and reads wash")


# --- Helpers ----------------------------------------------------------------------


## The shipped recipe named *name*, built as the store builds it.
func _recipe(name: String) -> SaStampBrushSettings:
    for entry: Dictionary in SaShippedPresets.entries():
        if String(entry["name"]) == name:
            return SaShippedPresets.build(StateBrushScript.BrushSettingsScript, entry) as SaStampBrushSettings
    assert_true(false, "%s is a shipped recipe" % name)
    return SettingsScript.new()


## One stroke of *settings* in black at [constant OPACITY] across the middle of
## a white canvas, by a mouse at full pressure, and the coverage at its middle.
func _stroke(settings: SaStampBrushSettings) -> float:
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(Vector2i(SIDE, SIDE))
    _whiten(_surface.easel.document)
    var brush := StateBrushScript.new()
    brush.surface = _surface
    brush.settings = settings
    brush.settings.color = Color.BLACK
    brush.settings.opacity = OPACITY
    brush.stroke_seed = 44
    var view := _surface.view as Fixtures.FakeView
    var start := Vector2(SIDE, SIDE) * 0.5 - Vector2(LENGTH * 0.5, 0.0)
    view.mouse_position = start
    brush.handle_input(_button(true))
    for i in range(1, MOTIONS + 1):
        var motion := InputEventMouseMotion.new()
        motion.pressure = 1.0
        view.mouse_position = start + Vector2(LENGTH * float(i) / float(MOTIONS), 0.0)
        brush.handle_input(motion)
    brush.handle_input(_button(false))
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    var image := SaExport.get_easel_image_float(_surface.easel)
    assert_not_null(image, "The canvas reads back")
    if image == null:
        return NAN
    var middle := image.get_pixel(SIDE >> 1, SIDE >> 1)
    var ground := image.get_pixel(4, 4)
    assert_almost_eq(ground.r, 1.0, 1e-4, "on a white ground")
    # Black over white leaves the white the stroke did not cover.
    return 1.0 - middle.r


## The document's ground filled white, where the default is grey.
func _whiten(document: SaDocument) -> void:
    for child: Node in document.get_children():
        if child is SaLayer and String(child.name) == SaDocumentBackground.LAYER_NAME:
            (child as SaLayer).fill(Color.WHITE)
            return
    assert_true(false, "The document has a ground to whiten")


func _button(pressed: bool) -> InputEventMouseButton:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = pressed
    return button


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


## A preset saved as format 13 wrote it, build-up and stamped 13, with
## *mode_line* where the saver now writes `painting_mode = 0`, which is no line
## at all for a build-up preset of that format.
func _write_at_format_13(store: SaPresetStore, preset_name: String, mode_line: String) -> void:
    var settings := SettingsScript.new()
    settings.painting_mode = SettingsScript.PaintingMode.BUILD_UP
    settings.format_version = 13
    var stored := store.save_preset(preset_name, settings)
    assert_false(stored.is_empty(), "%s saved into the scratch store" % preset_name)
    var path := scratch_dir.path_join(stored + ".tres")
    var out: PackedStringArray = []
    var replaced := 0
    for line: String in FileAccess.get_file_as_string(path).split("\n"):
        if line.begins_with("painting_mode = "):
            replaced += 1
            if mode_line.is_empty():
                continue
            line = mode_line
        out.append(line)
    assert_eq(replaced, 1, "%s carried the one mode line to rewrite" % preset_name)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string("\n".join(out))
    file.close()


## *preset* imported into *store* under *preset_name*, and the mode the store
## hands back.
func _imported(store: SaPresetStore, preset: Dictionary, preset_name: String) -> int:
    preset["name"] = preset_name
    var result := SaKppImport.import_preset(preset, store)
    assert_eq(String(result["error"]), "", "%s imports" % preset_name)
    var loaded := store.load_preset(String(result["name"]))
    assert_not_null(loaded, "%s is in the store" % preset_name)
    return int(loaded.get("painting_mode")) if loaded != null else -1
