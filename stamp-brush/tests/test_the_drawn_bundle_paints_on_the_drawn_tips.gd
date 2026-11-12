## The second bundle, a brush on each drawn tip, is shipped whole:
## every recipe builds, names a picture that is there, and the picture says the
## name and spacing the recipe uses.
##
## The tips are files under `res://tips` written by `scripts/make_tips.py`, and
## the recipes are `sa_drawn_tip_presets.gd`. Two halves written apart can drift,
## a renamed file or a spacing changed on one side, and a preset whose picture
## is missing loads as the procedural disc under a tree's name. So each recipe
## is read against its file here. What each one paints is held by
## `tests/fixtures/shipped-paint/shipped_paint.json`, beside the basic set's.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const BrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const DrawnScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_drawn_tip_presets.gd")

## The two drawn presets that set a hardness of their own.
const DRAWN_HARDNESS: Dictionary = {"Streaks": 0.54, "Dry Strokes": 0.0}


func test_every_drawn_recipe_builds_onto_its_picture() -> void:
    assert_true(DrawnScript.ENTRIES.size() >= 23, "the drawn set was read, %d recipes" % DrawnScript.ENTRIES.size())
    for entry: Dictionary in DrawnScript.ENTRIES:
        var name := String(entry["name"])
        assert_eq(
            String(entry["formerly"]),
            DrawnScript.FORMERLY,
            "%s was of the drawn bundle, which Sara Advanced Paint took over" % name
        )
        var settings := ShippedPresetsScript.build(SettingsScript, entry) as SaStampBrushSettings
        assert_not_null(settings, "%s builds on the stamp's settings" % name)
        if settings == null:
            continue
        var tip := settings.tip as BrushTipScript
        assert_true(tip.uses_image(), "%s paints with a picture, not the disc" % name)
        assert_true(FileAccess.file_exists(tip.image_path), "%s names a picture that ships, %s" % [name, tip.image_path])


## A recipe naming no hardness loads at the template's nought, and an image tip
## is faded along the hardness ellipse, so every drawn dab faded from its centre.
## So each recipe names one, and it reaches the built settings. Streaks and Dry
## Strokes ship with the hardness their tips were tuned at, so they name that instead.
func test_every_drawn_recipe_names_a_hardness_of_one() -> void:
    for entry: Dictionary in DrawnScript.ENTRIES:
        var name := String(entry["name"])
        var values: Dictionary = entry["settings"]
        assert_true(values.has("hardness:value"), "%s names a hardness" % name)
        var settings := ShippedPresetsScript.build(SettingsScript, entry) as SaStampBrushSettings
        if settings == null:
            continue
        var meant: float = DRAWN_HARDNESS.get(name, 1.0)
        assert_almost_eq(settings.hardness.value, meant, 1e-6, "%s paints its picture without a fade" % name)


func test_every_picture_says_the_name_and_spacing_its_recipe_uses() -> void:
    for entry: Dictionary in DrawnScript.ENTRIES:
        var name := String(entry["name"])
        var values: Dictionary = entry["settings"]
        var path := String(values["tip:image_path"])
        var picture := SaTipImage.load_from(path)
        assert_eq(picture.error, "", "%s's picture loads" % name)
        if not picture.error.is_empty():
            continue
        assert_false(picture.colourful, "%s's picture is a grey mask" % name)
        assert_eq(picture.tip_name, name, "%s's picture carries its name" % name)
        assert_almost_eq(picture.spacing, float(values["spacing"]), 1e-6, "and the spacing the preset paints at")


func test_the_drawn_bundle_carries_its_licence() -> void:
    var drawn: Array[String] = []
    for entry: Dictionary in DrawnScript.ENTRIES:
        drawn.append(String(entry["name"]))
    for entry: Dictionary in ShippedPresetsScript.entries():
        if drawn.has(String(entry["name"])):
            assert_eq(
                String(entry["licence"]), "CC-BY-4.0", "%s carries the pictures' licence for the chooser to show" % entry["name"]
            )
            assert_eq(String(entry["bundle"]), ShippedPresetsScript.ADVANCED, "and is of Sara Advanced Paint")


func test_no_two_shipped_presets_share_a_name() -> void:
    var seen: Dictionary[String, bool] = {}
    for entry: Dictionary in ShippedPresetsScript.entries():
        var name := String(entry["name"])
        assert_false(seen.has(name), "%s is shipped once" % name)
        seen[name] = true
    var bundles := ShippedPresetsScript.ENTRIES.size() + DrawnScript.ENTRIES.size()
    bundles += ShippedPresetsScript.SaHabitPresetsScript.ENTRIES.size()
    bundles += ShippedPresetsScript.SaAuthorPresetsScript.ENTRIES.size()
    assert_eq(seen.size(), bundles, "and the four bundles are handed out")
