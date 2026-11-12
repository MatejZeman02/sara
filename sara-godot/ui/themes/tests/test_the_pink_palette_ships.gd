## A painter's pink theme ships as a built-in palette.
##
## A pink Colour Theme made on the Colour Themes page lived
## as `violet-cyan.tres` in a settings folder. What is held here is
## that the copy under `ui/themes/palettes/` carries every colour of that file
## and its two lists, that the dropdown offers it last of six, that the fields
## the file never had derive from its own ramps, and that a painter whose
## settings still name their own copy keeps it.
extends "res://tests/test_framework.gd"

const ID := "pink"

## The original file's colours. The record of what was made,
## so it is written out rather than read from the palette it is checking.
const COLOURS := {
    "bg_primary": Color(0.2, 0.18823528, 0.2, 1),
    "bg_secondary": Color(0.22745098, 0.21568628, 0.23529412, 1),
    "bg_slider": Color(0.14117648, 0.11764706, 0.14509805, 1),
    "bg_input": Color(0.53333336, 0.2901961, 0.3529412, 1),
    "bg_panel": Color(0.16470589, 0.14509805, 0.17254902, 1),
    "bg_sidebar": Color(0.18823528, 0.16470589, 0.20784314, 1),
    "bg_track": Color(0.24313726, 0.22352941, 0.24313726, 1),
    "border_primary": Color(0.36862746, 0.49411765, 0.49019608, 1),
    "border_secondary": Color(0.3372549, 0.37254903, 0.43137255, 1),
    "border_selected": Color(1, 0.8784314, 0.91764706, 1),
    "border_drag": Color(0.80152893, 0, 0.4422227, 1),
    "accent_primary": Color(0.48235294, 0.17254902, 0.25882354, 1),
    "accent_fill": Color(0.5058823, 0.27058825, 0.24313726, 1),
    "accent_gauge": Color(0.29803923, 0.47843137, 0.3647059, 1),
    "accent_ceiling": Color(0.8745098, 0.29411766, 0.2901961, 1),
    "accent_stroke": Color(0.34901962, 0.5098039, 0.7921569, 1),
    "text_primary": Color(1, 1, 1, 1),
    "text_muted": Color(0.5686275, 0.6039216, 0.58431375, 1),
    "text_shadow": Color(0, 0, 0, 0.7),
    "shadow": Color(0, 0, 0, 0.55),
    "grip_light": Color(0.95, 0.95, 1, 0.9),
    "grip_dark": Color(0.1, 0.1, 0.15, 0.7),
    "button_normal": Color(0.16470589, 0.14509805, 0.17254902, 1),
    "button_hover": Color(0.14117648, 0.11764706, 0.14509805, 1),
    "button_pressed": Color(0.22745098, 0.21568628, 0.23529412, 1),
    "button_disabled": Color(0.2, 0.18823528, 0.2, 1),
    "toggle_off": Color(0.52734375, 0.4573059, 0.4753802, 1),
    "toggle_hover": Color(0.14117648, 0.11764706, 0.14509805, 1),
    "toggle_on": Color(0.48235294, 0.17254902, 0.25882354, 1),
    "toggle_disabled": Color(0.2, 0.18823528, 0.2, 1),
    # The dark pink, where the file had
    # the brick red of the fill.
    "slider_handle": Color(0.47843137, 0.29803923, 0.38431373, 1),
    "slider_hover": Color(0.47843137, 0.29803923, 0.39215687, 1),
}

const LINKED: Array[String] = ["border", "text"]
const HELD: Array[String] = ["toggle_off", "slider_handle", "slider_hover"]

## The painter's own copy, which this suite writes only when the settings folder
## has none, so a painter's real file is never touched.
const OWN_ID := "custom:violet-cyan"

var _saved_theme: String = "default"
var _wrote_own: bool = false


func before_each() -> void:
    _saved_theme = SaTheme.palette_id
    _wrote_own = false


func after_each() -> void:
    if _wrote_own:
        DirAccess.remove_absolute(SaTheme.custom_path(OWN_ID))
    SaTheme.use_named(_saved_theme)


func _pink() -> SaPalette:
    return load(SaTheme.PALETTES[ID]) as SaPalette


func test_pink_loads_under_its_name() -> void:
    assert_true(SaTheme.PALETTES.has(ID), "Pink is keyed into PALETTES")
    var palette := _pink()
    assert_not_null(palette, "and its .tres loads as an SaPalette")
    if palette != null:
        assert_eq(palette.display_name, "Pink", "under the name the dropdown shows")


## Exact rather than approximate, because a copy
## that rounds is not the theme as made.
func test_every_colour_of_the_pink_file_reads_back() -> void:
    var palette := _pink()
    if palette == null:
        return
    for key: String in COLOURS:
        assert_eq(palette.get(key), COLOURS[key], "Pink's %s is as made" % key)
    assert_eq(Array(palette.linked_groups), Array(LINKED), "with the groups they left linked")
    assert_eq(Array(palette.overridden_states), Array(HELD), "and the three states they set")


## Through `use_named`, the door the dropdown takes, so what is checked is what
## the running app draws: a held state stays as set and a field the file
## never had is the value its base gives it.
func test_a_field_the_file_lacks_derives_from_its_own_ramps() -> void:
    SaTheme.use_named(ID)
    assert_eq(SaTheme.palette_id, ID, "Pink is the palette in use")
    var palette := SaTheme.palette
    for key: String in HELD:
        assert_eq(palette.get(key), COLOURS[key], "a held %s stays where it was set" % key)
    for key: String in SaPalette.STATE_BASES:
        # A hover, a pressed state and the accent a toggle carries are derived by
        # the rules of `SaPalette`, which `test_state_rules_hold_in_every_palette`
        # holds in every palette Pink included, so the copy no longer
        # pins them to their ramps. The rest still derive from their own.
        if (
            HELD.has(key)
            or SaPalette.HOVER_FROM.has(key)
            or SaPalette.PRESSED_UNDER.has(key)
            or SaPalette.PRESSED_BEYOND.has(key)
            or SaPalette.TEXT_GROUNDS.has(key)
            # Moved off Pink's ramp until the dark pink fill stands 3 to 1 on it.
            or key == "slider_track"
        ):
            continue
        var base := String(SaPalette.STATE_BASES[key])
        assert_eq(palette.get(key), palette.get(base), "%s derives from Pink's %s" % [key, base])
    assert_true(palette.slider_handle != palette.accent_gauge, "so a slider's fill is the dark pink and not the green gauge")


## The palettes a program of "I'm coming from" brings come after Pink, so Pink
## is the last of Sara's own six.
func test_the_dropdown_lists_six_shipped_palettes_with_pink_last() -> void:
    var shipped := SaTheme.builtin()
    assert_true(shipped.size() >= 6, "six shipped palettes and a program's after them")
    if shipped.size() < 6:
        return
    assert_eq(String(shipped[5]["id"]), ID, "Pink last of Sara's own")
    assert_eq(String(shipped[5]["name"]), "Pink", "under its own name")
    assert_eq(String(shipped[0]["id"]), "default", "and Sara Green still first")
    var offered: Array[String] = []
    for entry: Dictionary in SaTheme.available():
        offered.append(String(entry["id"]))
    var order := ["default", "photoshop", "krita", "solarized", "paper", "pink", "procreate", "clip_studio"]
    assert_eq(offered.slice(0, 8), order, "in the order the dropdown shows")


func test_the_default_palette_stays_sara_green() -> void:
    var fresh := SaSettingsValues.new()
    assert_eq(fresh.theme_name, "default", "a fresh profile names the default")
    fresh.free()
    var palette := load(SaTheme.PALETTES["default"]) as SaPalette
    assert_eq(palette.display_name, "Sara Green", "and the default is Sara Green")


## A painter's settings may still name their own file. A shipped Pink must not
## shadow it, so the stored id goes on opening their copy.
func test_a_painter_who_named_their_own_copy_keeps_it() -> void:
    if not FileAccess.file_exists(SaTheme.custom_path(OWN_ID)):
        DirAccess.make_dir_recursive_absolute(SaTheme.custom_dir())
        var own := _pink().duplicate() as SaPalette
        own.display_name = "violet-cyan"
        own.bg_primary = Color(0.3, 0.1, 0.3, 1)
        assert_eq(ResourceSaver.save(own, SaTheme.custom_path(OWN_ID)), OK, "the suite writes a stand-in for the painter's file")
        _wrote_own = true
    SaTheme.use_named(OWN_ID)
    assert_eq(SaTheme.palette_id, OWN_ID, "their stored id still opens their own copy")
    if _wrote_own:
        assert_eq(SaTheme.palette.bg_primary, Color(0.3, 0.1, 0.3, 1), "and draws from it, not from the shipped Pink")
