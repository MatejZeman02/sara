## The painter's preferences as data: one typed property per setting, the
## clamping each one needs, and a signal saying which of them moved.
##
## Nothing here touches the disk and nothing here pushes into the running
## application. `SaSettingsFile` hears [signal changed] and writes the profile,
## `SaSettingsApply` hears it and pushes the change into the app. That is the
## whole point of the cut: once every setter did all three jobs, so the section
## and key of a preference were typed out once in the setter, once in the load,
## once in the first-launch defaults and once in the reset, and the four copies
## drifted.
##
## **The settings autoload extends this class**, so `SaSettings.ui_scale` is the
## property below and not a forward to it, which it once was, so a new
## preference was added twice. A `Node` for that reason alone: an autoload is
## one. A bare instance, which the file and the suites build to read the
## defaults, is therefore freed by whoever built it.
##
## [constant SaSettingsKeys.SETTINGS] is the one place a preference's section
## and key are written down, and a plain one's default and bounds, which is
## what lets the load, the reset and the config write be one walk each rather
## than four lists kept in step by hand. A plain preference's property is in
## [SaSettingsPlain], written from its row by `scripts/gen_settings_plain.py`,
## and one whose setter does more keeps its body and its comment here.
##
## It extends [SaSettingsPlain], which extends [SaSettingsSearchRecents], then
## [SaSettingsReferencePictures], then [SaSettingsNewDocument], which extends
## [SaSettingsShapeCheck], which extends [SaSettingsLocation], which extends
## [SaSettingsIdle], which extends [SaSettingsImporting], the family of
## preferences about bringing a picture in, which left it so the rest had room.
## That class declares [signal changed], and the autoload's chain is every one of
## them.
##
## `@tool` because the autoload that extends it is.
@tool
class_name SaSettingsValues
extends SaSettingsPlain

## The recent document list gained or lost an entry.
signal recent_files_changed

## The pinned blend modes changed.
signal blend_favorites_changed

## The starred presets changed.
signal preset_favorites_changed

## The canvas proof mode was replaced, with the id it held before.
##
## Its own signal rather than a field on [signal changed], because this is the
## only preference whose listener needs the value that was there before, and a
## previous-value argument on every emission would be forty-odd dead arguments
## to carry it.
signal proof_mode_replaced(previous: String, current: String)

## Where each preference sits in the profile, the table of [SaSettingsKeys],
## read through this face because the file object is in another package.
static var KEYS: Dictionary[String, Array] = SaSettingsKeys.KEYS  # gdlint: ignore=class-variable-name


## The section and key *property* is stored under, or an empty array.
static func place_of(property: StringName) -> Array:
    return SaSettingsKeys.place_of(property)


# --- UI Section ---

## What the Font size slider may ask for, moved down from `SaUI` so this file's own
## clamp does not have to name it. `SaUI` reads both back as an alias, because the
## slider's own bounds are still typed in `ui/` by callers that build it.
const MIN_FONT_SCALE: float = 0.55
const MAX_FONT_SCALE: float = 1.6
const DEFAULT_FONT_SCALE: float = SaSettingsKeys.DEFAULT_FONT_SCALE

## The bounds of [member ui_text_size], the stored bounds read against the
## default, so 0.55 reads about 73% and 1.6 about 213%.
const MIN_TEXT_SIZE: float = MIN_FONT_SCALE / DEFAULT_FONT_SCALE
const MAX_TEXT_SIZE: float = MAX_FONT_SCALE / DEFAULT_FONT_SCALE

## The text size as the painter reads and sets it, 1.0 at the size Sara ships
## with. A fresh profile's 0.75 read "75%" on the slider, so the default looked
## like a reduced size and a painter who wanted it a little larger never saw
## 100% on the way.
##
## Only the reading moved. `ui_font_scale` stays the stored multiplier on
## `SaUI.BASE_FONT_SIZE`, under the same key, so a profile written before
## draws its text at exactly the size it drew, 0.85 now reading 113%, with no
## migration to get wrong. The slider, its readout and a door's `prefs` step
## name this, and every size in points still reads the stored one.
var ui_text_size: float:
    set(val):
        ui_font_scale = val * DEFAULT_FONT_SCALE
    get:
        return ui_font_scale / DEFAULT_FONT_SCALE

## Sara's own language, British English, the locale `ui_language` starts at.
const BRITISH := "en_GB"

## The locale Sara speaks, `en_GB` or one a module registered a catalogue for,
## picked on Preferences > Languages and switched at once. British English is
## the language every string in the tree is written in. A plain `en`, which an
## older profile stores, reads as `en_GB`, because Godot
## matches `en` closer to `en_US` than to `en_GB`. A locale whose module
## has gone stays stored and reads as British English until it is back.
var ui_language: String = BRITISH:
    set(val):
        ui_language = BRITISH if val.is_empty() or val == "en" else val
        changed.emit(&"ui_language")

## The grid's default and bounds, declared beside its row in [SaSettingsKeys].
const DEFAULT_GRID_SIZE: int = SaSettingsKeys.DEFAULT_GRID_SIZE
const MIN_GRID_SIZE: int = SaSettingsKeys.MIN_GRID_SIZE
const MAX_GRID_SIZE: int = SaSettingsKeys.MAX_GRID_SIZE

## What Ctrl+0 shows, and how a new or opened document opens: one of
## `SaView.RESETS`, the whole picture by default.
var reset_zoom: String = SaView.RESET_WHOLE:
    set(val):
        reset_zoom = val if SaView.RESETS.has(val) else SaView.RESET_WHOLE
        changed.emit(&"reset_zoom")

## The Zoom figure, in per cent, that Ctrl+0 shows the whole picture at.
var reset_zoom_size: int = SaView.RESET_SIZE:
    set(val):
        reset_zoom_size = clampi(val, SaView.RESET_SIZE_MIN, SaView.RESET_SIZE_MAX)
        changed.emit(&"reset_zoom_size")

## The history depth's bounds, declared beside its row in [SaSettingsKeys].
const MIN_HISTORY_DEPTH: int = SaSettingsKeys.MIN_HISTORY_DEPTH
const MAX_HISTORY_DEPTH: int = SaSettingsKeys.MAX_HISTORY_DEPTH

# --- Performance Section ---
## The frame rate while the hand moves, one of `SaSettingsPerformance.FRAME_RATES`,
## which `SaFramePacer` reads where it takes the cap off, the display's refresh rate
## by default.
var painting_frame_rate: String = SaSettingsPerformance.REFRESH:
    set(val):
        painting_frame_rate = SaSettingsPerformance.frame_rate_or_default(val)
        changed.emit(&"painting_frame_rate")

## When the layer thumbnails and the minimap redraw during a stroke, one of
## `SaSettingsPerformance.THUMBNAIL_MODES`.
var thumbnails_while_painting: String = SaSettingsPerformance.QUARTER_SECOND:
    set(val):
        thumbnails_while_painting = SaSettingsPerformance.thumbnails_or_default(val)
        changed.emit(&"thumbnails_while_painting")

## What the painter answered when Sara offered the light mode to a weak GPU, one
## of `SaSettingsPerformance.OFFER_ANSWERS`, and empty while the offer has never
## been answered. Either answer is kept, so the offer comes once.
var light_mode_offer: String = "":
    set(val):
        light_mode_offer = SaSettingsPerformance.offer_answer_or_unasked(val)
        changed.emit(&"light_mode_offer")

## The blend modes pinned to the top of the blend menu, as mode ids. An id no
## registry knows is kept, because its module may be back next time.
var blend_favorites: Array = SaSettingsFavorites.BLEND_FACTORY.duplicate():
    set(val):
        blend_favorites = val.duplicate()
        changed.emit(&"blend_favorites")
        blend_favorites_changed.emit()

## The highest knee, in linear light, a stored 1.83.
const TONEMAP_KNEE_TOP: float = 4.0

## Where a new document's relief light comes from, in degrees clockwise from
## the top of the canvas, so 315 is the upper left a painter's lamp usually
## stands at. Each document keeps its own after that, `SaReliefLight`.
var relief_light_angle: float = 315.0:
    set(val):
        relief_light_angle = fposmod(val, 360.0)
        changed.emit(&"relief_light_angle")

const MAX_RELIEF_STRENGTH: float = 16.0

## The strongest shine the relief's Gloss slider reaches, the peak of the
## white highlight over the flat surface's. The relief shone at this before
## the painters found it read as wet plastic rather than oil.
const MAX_RELIEF_GLOSS: float = 0.12

## How a colour outside the cube leaves for the screen or an integer file, a
## key of `SaGamutMapping.MODES`. Oklab by default, so colours map even with the
## roll-off off, and View > Gamut Mapping writes it as well as the Display page.
## An older profile holding clip almost always never chose it, so the version-16 step of
## `SaSettingsMigrations` moves it to Oklab once.
var gamut_mapping: String = SaGamutMapping.OKLAB:
    set(val):
        gamut_mapping = SaGamutMapping.normalized(val)
        changed.emit(&"gamut_mapping")

## The display exposure's reach either way, declared beside its row in [SaSettingsKeys].
const MAX_EXPOSURE_STOPS: float = SaSettingsKeys.MAX_EXPOSURE_STOPS

## The spaces a monitor can be. Each is a `SaColorSpace` preset id.
const DISPLAY_PROFILES: Array[String] = ["srgb", "display_p3", "rec2020"]

## The display profile that reads the monitor's own ICC file, whose path is
## `display_profile_file`. The proof gamut has a file choice of its own,
## [constant PROOF_PROFILE_FILE], because a device's own profile is a target a
## painting can be made for, a phone or a client's monitor, and the screen the
## painter sits at is seldom that device.
const DISPLAY_PROFILE_FILE: String = "monitor_file"

## The display profile the system assigns the monitor the window is on, read
## through `SaSystemProfile`.
const DISPLAY_PROFILE_SYSTEM: String = "system"

## The display profile or the proof gamut held by value, a gamut and a white
## the colour space picker gave, stored in `display_custom_space` or
## `proof_custom_space`. By value rather than by a saved space's name, so a
## saved space renamed or deleted later leaves the screen as it was.
const DISPLAY_PROFILE_CUSTOM: String = "custom"

## What the display profile can be: a preset of [constant DISPLAY_PROFILES], the
## monitor's own profile file, the system's profile for it, or a space by value.
const DISPLAY_PROFILE_CHOICES: Array[String] = [
    "srgb", "display_p3", "rec2020", DISPLAY_PROFILE_FILE, DISPLAY_PROFILE_SYSTEM, DISPLAY_PROFILE_CUSTOM
]

## The proof gamut that reads an ICC file of the device a painting is made for,
## whose path is `proof_profile_file`, apart from the monitor's. Read again
## whenever the file changes, where a gamut by value keeps what it read once.
const PROOF_PROFILE_FILE: String = "proof_file"

## What the proof gamut can be: a preset of [constant DISPLAY_PROFILES], a
## device's profile file, or a gamut by value.
const PROOF_PROFILES: Array[String] = ["srgb", "display_p3", "rec2020", PROOF_PROFILE_FILE, DISPLAY_PROFILE_CUSTOM]

## The display's own colour space: an id of [constant DISPLAY_PROFILE_CHOICES]
## that this platform offers, see [method display_profile_offered]. The
## system's profile by default, because a calibrated monitor already has its
## profile installed, and sRGB on Android, whose system has none to give. A
## profile of a build before the system's profile was offered holds the sRGB it
## shipped with whether or not the painter chose it, and the version-28 step of
## `SaSettingsMigrations` moves it to the system's once.
var display_profile: String = display_profile_default():
    set(val):
        display_profile = val if display_profile_offered(val) else display_profile_default()
        changed.emit(&"display_profile")


## The display profile a fresh profile starts on, on *platform*.
static func display_profile_default(platform: String = OS.get_name()) -> String:
    return "srgb" if platform == "Android" else DISPLAY_PROFILE_SYSTEM


## Whether *profile* is a display profile *platform* offers: every one of
## [constant DISPLAY_PROFILE_CHOICES] but the system's on Android.
static func display_profile_offered(profile: String, platform: String = OS.get_name()) -> bool:
    if profile == DISPLAY_PROFILE_SYSTEM and platform == "Android":
        return false
    return profile in DISPLAY_PROFILE_CHOICES


## Correct, Native and Even, by the ids `SaDisplayFill` names them with.
const DISPLAY_FILLS: Array[String] = ["correct", "native", "even"]

## What Ctrl+Y shows on the canvas, as a view transform id of kind MODE,
## whatever the registry holds rather than a fixed pair.
##
## **What is stored is what was written**, and what a reader gets back is a
## mode that exists. A stored id has to survive being written while the module
## that registered it is not loaded, so the file keeps the painter's choice
## through [method stored] and only the read falls back, through
## [method _proof_read], which the autoload answers with `SaSettingsProofs`.
var canvas_proof_mode: String:
    set(val):
        var previous := _canvas_proof_stored
        _canvas_proof_stored = val
        changed.emit(&"canvas_proof_mode")
        if previous != val:
            proof_mode_replaced.emit(previous, val)
    get:
        return _proof_read(_canvas_proof_stored, DEFAULT_CANVAS_PROOF)

## The minimap proofs to lightness by default, so a painter working in colour
## has a values check beside the canvas.
var minimap_proof_mode: String:
    set(val):
        _minimap_proof_stored = val
        changed.emit(&"minimap_proof_mode")
    get:
        return _proof_read(_minimap_proof_stored, DEFAULT_MINIMAP_PROOF)

var _canvas_proof_stored: String = DEFAULT_CANVAS_PROOF
var _minimap_proof_stored: String = DEFAULT_MINIMAP_PROOF

const DEFAULT_CANVAS_PROOF: String = "soft_proof"
const DEFAULT_MINIMAP_PROOF: String = "lightness_check"

# --- Input Section ---
## The raw pen pressure that counts as a full-strength stroke. Hardware
## rather than taste: where this pen's usable travel ends, not how the brush
## should feel across it, which stays the per-brush gamma on the brush.
var tablet_max_pressure: float = SaTablet.DEFAULT_MAX_PRESSURE:
    set(val):
        tablet_max_pressure = SaTablet.clamp_max_pressure(val)
        changed.emit(&"tablet_max_pressure")

## How far ahead of the pointer the brush ring is drawn, in milliseconds.
##
## The compositor holds one frame whatever the pacer does about the queue,
## and this is what pays for it: the ring goes at the pointer plus its
## velocity times this. `SaSettingsCursorLead.FOLLOW_DISPLAY`, which is -1,
## means one refresh interval read from the display server, 0 turns prediction
## off, and a positive number is that many milliseconds.
##
## No row on the Display page, on purpose: the right number is a measurement,
## with `scripts/ring_lag.py`, and a control
## offered before there is an answer is a control nobody can set well.
var cursor_prediction_ms: float = SaSettingsCursorLead.FOLLOW_DISPLAY:
    set(val):
        cursor_prediction_ms = maxf(val, SaSettingsCursorLead.FOLLOW_DISPLAY)
        changed.emit(&"cursor_prediction_ms")

## Whether the brush ring leads the pointer at all: "auto", the default, "on" or
## "off", listed with their wording in `SaSettingsCursorLead.LEAD_MODES` and
## resolved by `SaCursorPrediction.lead_enabled()`. Auto is on only where the
## drawn pointer has real lag, a pen moving a pointer Sara draws itself. The
## number above stays the horizon it is drawn for.
var cursor_lead: String = "auto":
    set(val):
        cursor_lead = val if SaSettingsCursorLead.is_lead_mode(val) else "auto"
        changed.emit(&"cursor_lead")

## What each pen button does, button id to action id, in the vocabulary of
## [SaSettingsPenButtons], which the tool machine reads at every press.
##
## Untyped on purpose, and the setter is where the profile's table is converted.
## The file reader sets this by name with what `ConfigFile` held, and
## `Object.set` hands a typed property an untyped Dictionary as an empty one
## without a word, so a typed property here would forget every binding on load.
var pen_buttons: Dictionary = SaSettingsPenButtons.defaults():
    set(val):
        pen_buttons = SaSettingsPenButtons.bound(val)
        changed.emit(&"pen_buttons")

## What the mouse's wheel press does, an action id of [SaSettingsPenButtons].
var mouse_middle: String = SaSettingsPenButtons.PAN:
    set(val):
        mouse_middle = SaSettingsPenButtons.mouse_middle_bound(val)
        changed.emit(&"mouse_middle")

# --- Theme Section ---

## The font ids Sara offers, and the one a fresh profile gets (moved down
## from `SaFonts`, which reads them back as an alias). `SaFonts.FAMILIES`
## carries the family data behind each id, in the same order, which
## `ui/themes/tests/test_ui_font.gd` holds the two tables to.
const FONT_IDS: Array[String] = ["inter", "ibm-plex-sans", "source-sans-3", "atkinson-hyperlegible", "noto-sans"]
const DEFAULT_FONT: String = "inter"

# --- Shortcuts Section ---

# --- Files Section ---

const MAX_SAD_VERSIONS: int = 9
const MAX_RECENT_FILES: int = 10

## The most recently saved or opened documents, newest first. Written whole
## rather than through a setter, because the three calls below edit the list in
## place and then say so, and named for what it holds because `recent_files()`
## is the copy a caller reads.
var recent_file_paths: Array = []

const MAX_AUTOSAVE_MINUTES: float = 60.0

## The painter's name an exported PNG, TIFF or OpenRaster carries as its
## author, empty for none.
var export_author: String = "":
    set(val):
        export_author = val.strip_edges()
        changed.emit(&"export_author")

# --- Recorder Section ---
## Where the timelapse writes its frames, surviving a restart.
var recorder_directory: String = SaRecorder.default_directory():
    set(val):
        recorder_directory = val
        changed.emit(&"recorder_directory")

## Stops the recording rather than filling the disk.
var recorder_cap_bytes: int = SaRecorder.DEFAULT_CAP_BYTES:
    set(val):
        recorder_cap_bytes = clampi(val, 1048576, 100000 * 1048576)
        changed.emit(&"recorder_cap_bytes")

## The size the note box was last left at, in logical units. Beside the
## recorder because a note is the other thing Sara records about itself, and
## zero until a box has been resized, which reads as "however big it needs".
var note_box_size: Vector2i = Vector2i.ZERO:
    set(val):
        note_box_size = Vector2i(maxi(0, val.x), maxi(0, val.y))
        changed.emit(&"note_box_size")

## The size the search F3 opens was last left at, logical, zero until it has
## been resized, which reads as the size its rows want.
var search_window_size: Vector2i = Vector2i.ZERO:
    set(val):
        search_window_size = Vector2i(maxi(0, val.x), maxi(0, val.y))
        changed.emit(&"search_window_size")

# --- Tools Section ---

## The ceiling on `selection_feather`. On the default document's 1080 that is
## 108 pixels, just under the 120 the blur kernels can reach across a chunk
## seam, and on a larger canvas `SaSelectionFilters.MAX_RADIUS` takes over.
## A larger fraction would only add slider travel that the kernel clamps away.
const MAX_SELECTION_FEATHER: float = 0.1

## The presets the painter starred, by name, in the order starred, written
## through [SaSettingsFavorites] and never into a preset file.
var preset_favorites: Array = []:
    set(val):
        preset_favorites = val.duplicate()
        changed.emit(&"preset_favorites")
        preset_favorites_changed.emit()

## The preset chooser's tags, tag to "show" or "hide". No key filters nothing.
var preset_tag_filter: Dictionary = {}:
    set(val):
        preset_tag_filter = val.duplicate()
        changed.emit(&"preset_tag_filter")

## The preset bundles the painter unloaded from the Brush Presets panel's
## Bundles menu, by title. Their presets leave the panel, the bar and the
## search, and their files stay where they are. No title loads everything.
var preset_bundles_off: Array = []:
    set(val):
        preset_bundles_off = val.duplicate()
        changed.emit(&"preset_bundles_off")

## The modules the painter switched off on Preferences > Modules, by id, read
## once by the module loader at the start. A fresh profile and a reset start
## from the build's list, [SaOffByDefault], so a module a few painters use
## costs the rest nothing until they switch it on.
var modules_off: Array = SaOffByDefault.ids():
    set(val):
        modules_off = val.duplicate()
        changed.emit(&"modules_off")

## The preset each of the ten brush slots holds, in slot order, empty for a slot
## nobody has filled.
##
## **One list rather than one per shortcut profile**, because the chords are a
## profile's and what is under them is a painter's, so a painter who switches to
## the Krita map keeps their ten brushes.
##
## A stored list of the wrong length is padded or cut to the shape
## [SaSettingsBrushSlots] owns rather than refused, since the page builds a row
## a slot whatever the file says.
var brush_slots: Array = SaSettingsBrushSlots.factory():
    set(val):
        brush_slots = SaSettingsBrushSlots.sized(val)
        changed.emit(&"brush_slots")

## The number of slots, named here as well because the commands in `ui` read it
## off the settings and not off a file inside this folder.
const BRUSH_SLOT_COUNT: int = SaSettingsBrushSlots.COUNT


## What the profile keeps for *property*: its value, but for the two proof
## modes, whose read resolves and whose file keeps what was written.
func stored(property: String) -> Variant:
    match property:
        "canvas_proof_mode":
            return _canvas_proof_stored
        "minimap_proof_mode":
            return _minimap_proof_stored
    return get(property)


## What a proof mode reads as, given what is stored: the stored id itself here,
## and a mode the registry holds on the autoload, which overrides this.
func _proof_read(stored_id: String, _fallback: String) -> String:
    return stored_id


## Puts every preference back to what a fresh profile has.
##
## Read off a fresh instance of this class, so a default is written down
## exactly once, in a plain preference's row or in the property that keeps its
## own setter. Every key in `SaSettingsKeys.KEYS`, with no list of exceptions: the two
## hand-written lists this walk replaced had each fallen behind as keys were
## added, so a reset kept the grid, the second row, the pinned blend modes, the
## interface font and both proof modes, and a first launch wrote a file missing
## three keys. A setter that returns early on an unchanged value writes nothing
## here, which is why a first-launch file still carries fewer keys than this
## table has.
func restore_defaults() -> void:
    var fresh := SaSettingsValues.new()
    for property: String in KEYS:
        set(property, fresh.stored(property))
    fresh.free()


## Newest first, and a copy, so a caller cannot edit the list behind the file.
func recent_files() -> Array:
    return recent_file_paths.duplicate()


## Puts *path* at the front of the recent list, once, and drops the oldest past
## the cap.
func add_recent_file(path: String) -> void:
    if path.is_empty():
        return
    recent_file_paths.erase(path)
    recent_file_paths.push_front(path)
    while recent_file_paths.size() > MAX_RECENT_FILES:
        recent_file_paths.pop_back()
    store_recent_files()


## For a file that no longer opens, so the menu stops offering it.
func remove_recent_file(path: String) -> void:
    if recent_file_paths.has(path):
        recent_file_paths.erase(path)
        store_recent_files()


## Says the recent list moved, for the two calls above and for a reset, which
## empties it in place.
func store_recent_files() -> void:
    changed.emit(&"recent_file_paths")
    recent_files_changed.emit()


## Adds or removes *mode_id* from the favourites, and returns whether it is one
## afterwards. The menu's tick calls this.
func toggle_blend_favorite(mode_id: StringName) -> bool:
    blend_favorites = SaSettingsFavorites.toggled(blend_favorites, String(mode_id))
    return blend_favorites.has(String(mode_id))


## Stars or unstars *preset_name*, and returns whether it is starred afterwards.
func toggle_preset_favorite(preset_name: String) -> bool:
    preset_favorites = SaSettingsFavorites.toggled(preset_favorites, preset_name)
    return preset_favorites.has(preset_name)


## Takes the star off *preset_name*, which a delete of the preset calls.
func drop_preset_favorite(preset_name: String) -> void:
    preset_favorites = SaSettingsFavorites.dropped(preset_favorites, preset_name)


## Moves a renamed preset's star from *from* to *to*, in its place in the order.
func rename_preset_favorite(from: String, to: String) -> void:
    preset_favorites = SaSettingsFavorites.renamed(preset_favorites, from, to)
