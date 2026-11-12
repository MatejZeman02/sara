## What a sweep of the colour picker, the ring and the Display page found,
## held so the next change has to keep it.
##
## The sweep drove the running app through
## `scenarios/colour-picker-ring-and-display.json`, and everything it read
## back agreed with what the code says it should be. Most of that is already
## held by a suite of its own, `test_okhsv_shader.gd` for the ring's arithmetic
## and `test_display_page.gd` for the roll-off's rows, and this file is only the
## part that was not held anywhere.
##
## **The ring's rule is written down three times and nothing compared them.**
## `shaders/ui/okhsv_picker.gdshader` draws it, `utils/okhsv_conversions.gd` is
## the twin every suite proves, and `scripts/ring_profile.py` prints the numbers
## the two comments quote. The script's own docstring says to "change the
## profile's three numbers in the shader, its twin in utils/okhsv_conversions.gd
## and here together", which is a rule a person keeps by remembering. A shader
## edited alone would draw one ring while every number the picker reports, every
## assertion in `test_okhsv_shader.gd` and every figure came from the
## other two, and the suite would stay green through it.
##
## Read out of the source text, the way `test_menu_chords.gd` reads a menu's,
## because GDScript cannot call into a `.gdshader` and the Python is not run by
## the gate at all.
extends "res://tests/test_framework.gd"

const OkhsvConversionsScript = preload("res://utils/okhsv_conversions.gd")
const PickerShapeScript = preload("res://ui/widgets/picker/sa_picker_shape.gd")

const SHADER_PATH := "res://shaders/ui/okhsv_picker.gdshader"
const SCRIPT_PATH := "res://scripts/ring_profile.py"

## The number the twin holds, beside the name the shader and the script give it.
## One row per number the profile is made of.
##
## The value rather than the twin's name for it, because a `const` cannot be
## reached by name off a class the way a property can, and a name looked up from
## a string would fail at run time where this fails at the edit.
const PROFILE := [
    [OkhsvConversionsScript.RING_BASE_L, "RING_BASE_L", "BASE_L"],
    [OkhsvConversionsScript.RING_LIFT_AT_YELLOW, "RING_LIFT_AT_YELLOW", "LIFT_AT_YELLOW"],
    [OkhsvConversionsScript.RING_DIP_OPPOSITE, "RING_DIP_OPPOSITE", "DIP_OPPOSITE"],
]


func _source(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    return file.get_as_text() if file != null else ""


## The number *name* is assigned in *source*, from the first `name = 0.5` or
## `... name = 0.5;` on a line of its own. Returns NAN when the file does not
## carry it, which is the failure worth reading rather than a zero to compare.
func _number_named(source: String, name: String) -> float:
    for raw in source.split("\n"):
        var line := raw.strip_edges()
        if line.begins_with("#") or line.begins_with("//"):
            continue
        var at := line.find(name)
        if at < 0:
            continue
        var tail := line.substr(at + name.length()).strip_edges()
        if not tail.begins_with(":") and not tail.begins_with("="):
            continue
        var value := tail.substr(tail.find("=") + 1).strip_edges().trim_suffix(";").strip_edges()
        if value.is_valid_float():
            return float(value)
    return NAN


## The three numbers, in all three places.
func test_the_rings_profile_is_the_same_in_the_shader_and_the_script() -> void:
    var shader := _source(SHADER_PATH)
    var script := _source(SCRIPT_PATH)
    assert_false(shader.is_empty(), "the shader is where the ring is drawn")
    assert_false(script.is_empty(), "and the script is where its numbers are printed from")

    for row: Array in PROFILE:
        var held := float(row[0])
        var drawn := _number_named(shader, String(row[1]))
        var printed := _number_named(script, String(row[2]))
        assert_almost_eq(drawn, held, 1e-6, "%s: the shader draws what the twin holds" % row[1])
        assert_almost_eq(printed, held, 1e-6, "%s: and the script prints from the same number" % row[2])


## Yellow's own hue is the fourth number and the one most likely to be edited
## alone, because it is the only one with a comment beside it saying what it is
## in degrees. The script derives it rather than writing it down, so this asks
## the two that write it down.
func test_the_rings_yellow_hue_is_the_same_in_the_shader() -> void:
    var drawn := _number_named(_source(SHADER_PATH), "RING_YELLOW_HUE")
    assert_almost_eq(drawn, OkhsvConversionsScript.RING_YELLOW_HUE, 1e-6, "the shader peaks at the hue the twin peaks at")


## The four shapes the docker offers, which is what the sweep drove one by one:
## the setting takes each key, and only the three with a ring say they have one.
## The disc's own rim is its hue control, so a ring over it would be two
## controls for one hue, which is the reason `sa_picker_shape.gd` gives.
func test_every_picker_kind_has_a_key_and_a_label() -> void:
    assert_eq(
        PickerShapeScript.KIND_KEYS,
        ["wheel", "okhsl", "triangle", "triangle_up", "hsv_square", "hsv_triangle", "hsl_square"] as Array[String],
        "the four the sweep drove and the three classic shapes, in the order the dropdown offers them"
    )
    assert_eq(
        PickerShapeScript.KIND_LABELS.size(),
        PickerShapeScript.KIND_KEYS.size(),
        "and every one of them has something to call itself"
    )
    for label: String in PickerShapeScript.KIND_LABELS:
        assert_false(label.strip_edges().is_empty(), "no shape is offered under an empty name")


## f6, fixed. Preferences > Colour Spaces reads the document's space once, in
## `_ready`, and nothing tells it to read again. `EventBus.document_color_space_changed`
## exists for exactly this and the tool options bar, the Tool Options docker and
## the Layers docker all connect to it, on the reasoning the signal's own
## docstring gives: "a label that went stale on File > New would name the space
## of a document that no longer exists". The one page whose entire subject is
## that space is the one surface that does not listen.
##
## The sweep read it off the running app: with Preferences open on the page, a
## document in Linear sRGB left the chooser still saying "Oklab over Display P3"
## and the diagram still drawing `oklab_p3`, and only leaving the page and coming
## back put Linear sRGB on it.
func test_f6_the_colour_spaces_page_follows_a_document_space_change() -> void:
    var page := SaColorSpacesPage.new()
    var host := Node.new()
    EventBus.add_child(host)
    host.add_child(page)

    var document := SaDocument.new()
    document.color_space = SaColorSpace.linear_srgb()
    var state: Dictionary = page.browser.capture_state()
    assert_eq(String(state.get("space", "")), "linear_srgb", "the page follows the document it says it opens on")
    host.free()
    document.free()


## f7. Neither dropdown on the gamut browser carried a node name, so
## `{"dropdown": "..."}` could find neither and no step selected a row on one.
## The space chooser had a second door, a document in that space, which is how
## the sweep reached it at all. The compare chooser had none, and it is the
## control the page's second gamut was added for, so the two-triangle drawing and
## the legend that tells the two apart were only ever proved in the one pairing
## a fresh run happened to start on. Both are named now, and
## `{"dropdown": {"name": ..., "row": ...}}` picks a row on either.
func test_f7_both_gamut_choosers_can_be_named_by_a_scenario() -> void:
    var browser := SaColorSpaceBrowser.new()
    assert_eq(String(browser.option.name), "GamutOption", "the space chooser answers to a name")
    assert_eq(String(browser.compare_option.name), "CompareGamutOption", "and so does the one it is compared against")
    browser.free()
