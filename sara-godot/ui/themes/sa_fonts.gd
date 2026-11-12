## The interface font: four families ship under ui/themes/fonts/, each as its
## static Regular and Bold with its own OFL text beside it, and the engine's
## Open Sans SemiBold is the fifth choice. Inter is the default. A switch
## writes the shared theme's default font, so every control follows at once,
## and the bus announces it for the few that hold a bold face of their own.
##
## Every family is under the SIL Open Font Licence 1.1, which allows bundling
## in a GPL program with the licence text alongside, and the About dialog
## names them.
class_name SaFonts
extends Object

const DIR := "res://ui/themes/fonts/"

## The project's font line, which every shipped face follows through
## `field_on`.
const FIELD_SETTING := "gui/theme/default_font_multichannel_signed_distance_field"

## Id -> what the row in Preferences shows and where the faces are. The
## order is the dropdown's, and it is `SaSettingsValues.FONT_IDS`'s order too:
## `ui/themes/tests/test_ui_font.gd` holds the two tables to the same ids.
## "noto-sans" has no files: it is the engine's fallback, Open Sans SemiBold in Godot 4.7.2, under an older id settings hold.
const FAMILIES := {
    "inter":
    {
        "name": "Inter",
        "regular": DIR + "inter/Inter-Regular.ttf",
        "bold": DIR + "inter/Inter-Bold.ttf",
        "licence": DIR + "inter/LICENSE.txt",
        "copyright": "The Inter Project Authors",
    },
    "ibm-plex-sans":
    {
        "name": "IBM Plex Sans",
        "regular": DIR + "ibm-plex-sans/IBMPlexSans-Regular.ttf",
        "bold": DIR + "ibm-plex-sans/IBMPlexSans-Bold.ttf",
        "licence": DIR + "ibm-plex-sans/LICENSE.txt",
        "copyright": "IBM Corp.",
    },
    "source-sans-3":
    {
        "name": "Source Sans 3",
        "regular": DIR + "source-sans-3/SourceSans3-Regular.ttf",
        "bold": DIR + "source-sans-3/SourceSans3-Bold.ttf",
        "licence": DIR + "source-sans-3/LICENSE.md",
        "copyright": "Adobe",
    },
    "atkinson-hyperlegible":
    {
        "name": "Atkinson Hyperlegible",
        "regular": DIR + "atkinson-hyperlegible/AtkinsonHyperlegible-Regular.ttf",
        "bold": DIR + "atkinson-hyperlegible/AtkinsonHyperlegible-Bold.ttf",
        "licence": DIR + "atkinson-hyperlegible/OFL.txt",
        "copyright": "Braille Institute of America, Inc.",
    },
    "noto-sans": {"name": "Open Sans (built in)", "regular": "", "bold": "", "licence": "", "copyright": ""},
}

## The id `SaSettingsValues` owns, along with the rest of `FONT_IDS`, because
## its own clamp on `ui_font` needed them and `core` may not name a class under
## `ui`. Read back here as an alias, so `SaFonts.DEFAULT` still reads as itself
## for the callers that already type it.
const DEFAULT := SaSettingsValues.DEFAULT_FONT

static var current: String = DEFAULT
static var _loaded: Dictionary = {}


## Every family on offer, as `{id, name}`, in the dropdown's order.
static func available() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for id: String in FAMILIES:
        out.append({"id": id, "name": FAMILIES[id]["name"]})
    return out


## The id *id* names, or the default for one nobody has.
static func resolve(id: String) -> String:
    return id if FAMILIES.has(id) else DEFAULT


## The Regular face of *id*, or the engine's own for "noto-sans".
static func regular(id: String = current) -> Font:
    return _face(resolve(id), "regular")


## The Bold face of *id*. The engine's Open Sans has no bold file here, so it
## is emboldened through a variation.
static func bold(id: String = current) -> Font:
    return _face(resolve(id), "bold")


static func _face(id: String, weight: String) -> Font:
    var path: String = FAMILIES[id][weight]
    if path.is_empty():
        if weight == "bold":
            var variation := FontVariation.new()
            variation.base_font = ThemeDB.fallback_font
            variation.variation_embolden = 0.6
            return variation
        return ThemeDB.fallback_font
    if not _loaded.has(path):
        var face := load(path) as FontFile
        if face != null:
            face.multichannel_signed_distance_field = field_on()
        _loaded[path] = face
    return _loaded[path]


## Whether the interface draws its glyphs from a distance field, which is the
## one font line of `project.godot` and nothing else.
##
## That line only reaches the engine's own Open Sans, because a `.ttf` carries
## its own import flag, so every face loaded here is given the line's value.
## The face is the resource the theme holds too, so writing it here reaches the
## theme's copy as well.
##
## The line is off. A field draws the same soft edge at every size, softer than
## a hinted bitmap at 100% and softer still at the small text sizes, while a
## bitmap is rasterised at the window's scale and is as sharp as at 100% once
## `SaUI.snaps_to_pixels` puts it on whole device pixels.
static func field_on() -> bool:
    return bool(ProjectSettings.get_setting(FIELD_SETTING, false))


## Makes *id* the interface font: the shared theme's default font, which every
## window built from it follows, then the bus for the controls that hold a
## bold face of their own.
static func use(id: String) -> void:
    current = resolve(id)
    var theme := SaUI.shared_theme
    if theme != null:
        theme.default_font = regular(current)
    EventBus.ui_font_changed.emit(current)


## One line per shipped family for the About dialog, the licence named,
## because a font that ships without its notice is a licence breach. The line
## ends in the licence file's path unless *with_path* is false, which is the
## line a painter reads: the copied report keeps the path.
static func licence_lines(with_path: bool = true) -> PackedStringArray:
    var out := PackedStringArray()
    for id: String in FAMILIES:
        var family: Dictionary = FAMILIES[id]
        if String(family["licence"]).is_empty():
            continue
        var line := "%s, copyright %s, SIL Open Font License 1.1" % [family["name"], family["copyright"]]
        if with_path:
            line += " (%s)" % family["licence"]
        out.append(line)
    return out
