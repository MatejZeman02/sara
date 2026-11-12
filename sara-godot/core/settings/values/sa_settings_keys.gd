## Every preference's declaration: where it sits in the profile, and for a plain
## one its default and its bounds.
##
## Its own class because it is the settings' shape rather than their values. A
## row is `[section, key]` for a preference whose property keeps a setter of its
## own, because it does more than clamp, and
## `[section, key, default, bounds, how]` for a plain one, whose property in
## [SaSettingsPlain] is written from the row and hands the row its value. `bounds` is
## `[low, high]` for a number, the list of allowed values for a string, or empty,
## and `how` is [constant ONCE], [constant REBUILD] or left off. The two trailing
## fields may be left off together, and `how` alone.
##
## A row names no other class's constant, because the table is read while this
## class compiles, so a default or bound that lives in the view or the recorder
## stays on its property, whose initialiser runs later.
##
## So adding a plain preference is a row here and its row on a Preferences page,
## then `python scripts/gen_settings_plain.py` writes its property, and a profile
## written before the row was added reads the default, with no SETTINGS_VERSION
## bump. A row's type is its default's, a literal or a constant declared with
## its type in this file or the values file.
## `SaSettingsFile` walks [member KEYS] to read and write, and the values walk
## it to reset.
##
## `@tool` because the autoload that reads it is.
@tool
class_name SaSettingsKeys
extends RefCounted

## A plain preference that announces itself only when its value moved.
const ONCE: int = 1

## One that also says a whole surface has to be rebuilt for it, which is
## `profile_changed`, and is [constant ONCE] as well.
const REBUILD: int = 2

## The top of a count that has none, for a bound that only has a floor.
const NO_TOP: int = 0x7FFFFFFFFFFFFFFF

## The spacing the grid ships with, a quarter of `SaChunk.SIZE`, so the lines
## also fall on chunk seams every fourth one.
const DEFAULT_GRID_SIZE: int = 64

## The Font size a fresh profile starts at, 15 of SaUI's 20 logical pixels. At
## 20 a line of text was taller than the 22 pixel field it sits in, so every
## field grew round its words. The default moved rather than the base so
## that a size a painter saved still draws what it drew, 1.3 being 26 pixels
## before and after.
const DEFAULT_FONT_SCALE: float = 0.75

## A main window Sara has never closed, which opens maximised as the project
## file starts it. The kept one is `{"maximized": bool, "rect": Rect2i,
## "screen": int}`, written by `SaTopBarWindowFrame`.
const NO_MAIN_WINDOW: Dictionary = {}

## No space held by value, which reads as sRGB. One held is a colour space as
## a document's header writes it, `SaColorSpace.to_header()`, of which the
## display and the proof read the primaries and the white.
const NO_CUSTOM_SPACE: Dictionary = {}

## One document pixel, which is what a pixel painter asks for, up to a spacing
## past any document Sara holds comfortably on screen at once.
const MIN_GRID_SIZE: int = 1
const MAX_GRID_SIZE: int = 4096

## Four is the shallowest worth offering, and the floor under the budget means a
## small document keeps more than four anyway. Thirty-two is not a safety rail:
## the Info docker's History rows say what the depth is costing on this
## document, so a painter who asks for thirty-two whole-canvas steps on a 4K
## canvas can see the 6 GiB before the GPU finds out.
const MIN_HISTORY_DEPTH: int = 4
const MAX_HISTORY_DEPTH: int = 32

## How many stops a drag of the display exposure reaches either way. A typed
## number goes past it to [constant SaPaintExposure.FLOAT_STOPS], the most a
## float factor holds, which is the row's bound below, so the setting keeps
## the stops as typed (hard rule 5).
const MAX_EXPOSURE_STOPS: float = 4.0

## Where each preference is stored, `[section, key]`, read off [constant SETTINGS]
## so a place is written once.
static var KEYS: Dictionary[String, Array] = _places()  # gdlint: ignore=class-variable-name

## Every preference, in the order a profile is read, with the section and key it
## is stored under and, for a plain one, its default, bounds and how it is told.
##
## The one place a preference is written down, rather than four lists, the
## setter, the read, the first-launch defaults and the reset, that drift apart.
##
## **The order is load order and is load-bearing.** A key a profile does not
## carry is appended to its section as the read walks past it, so the order here
## is the order of the file a first launch writes.
const SETTINGS: Dictionary[String, Array] = {
    # The user's UI Scale preference: a multiplier on top of the system scale, not
    # an absolute size. This is the only persisted scale value and the only writer
    # of SaUI's cache, so there is exactly one place a scale change enters the app.
    "ui_scale": ["ui", "scale", 1.0, [0.1, INF]],
    # The Font size preference: a multiplier on SaUI.BASE_FONT_SIZE and on nothing
    # else, so text grows while margins, icons and window geometry stay put.
    "ui_font_scale": ["ui", "font_scale", DEFAULT_FONT_SCALE, [SaSettingsValues.MIN_FONT_SCALE, SaSettingsValues.MAX_FONT_SCALE]],
    "ui_language": ["ui", "language"],
    "embed_subwindows": ["ui", "embed_subwindows", true],
    # Which screen the secondary workspace was last on, and the rectangle it held
    # there, in the physical pixels a native window measures itself in. Minus one
    # and an empty rectangle mean it has never been placed, and the host centres
    # itself.
    # How the main window was when Sara last closed, maximised or not, and the
    # last rectangle it held while windowed with the screen it was on, in the
    # physical pixels a native window measures itself in. Empty for a window
    # never closed, which opens maximised.
    "main_window": ["ui", "main_window", NO_MAIN_WINDOW, [], ONCE],
    # Which screen mode the main window opens in on Android: "fullscreen", a few
    # rows short of the display where the tablet draws no bands, or "maximised"
    # under the system bars.
    "screen_mode": ["ui", "screen_mode", "fullscreen", ["maximised", "fullscreen"], ONCE],
    "secondary_workspace_screen": ["ui", "secondary_workspace_screen", -1, [-1, NO_TOP], ONCE],
    "secondary_workspace_rect": ["ui", "secondary_workspace_rect", Rect2i(), [], ONCE],
    # Whether the Tool Options docker shows the options a spec marked
    # advanced.
    #
    # Off by default, which is the point: `SaOptionSpec.advanced` is what a module
    # author sets to keep an option from every painter, and this is what reads it.
    "advanced_options": ["ui", "advanced_options", false],
    # Whether the tools and layer kinds a module marks experimental are offered.
    #
    # Off by default, so a public build shows a painter only what is ready. The
    # toolbox and the Layer menu are rebuilt when it moves.
    "experimental_tools": ["ui", "experimental_tools", false, [], REBUILD],
    # Whether the top bar shows its second row.
    #
    # **On for a new profile.** The sentinel follows the last menu, so this row
    # holds every tool option, as Krita's tool options bar does, and what does not
    # fit goes into the overflow.
    #
    # A key is written only when its value changes, so a profile that switched
    # the row off keeps it off and one that never touched it opens with it on.
    "second_row": ["ui", "second_row", true, [], REBUILD],
    # Whether every docker shows a button on its drag bar that closes it.
    #
    # One switch for all of them rather than one per docker. The note asks for the
    # icon on every docker, for a painter who does not remember the chord, and nine
    # separate switches would be nine places to look for the same answer.
    #
    # On by default, because a painter who wants the button finds the switch only
    # after asking for it.
    "docker_hide_button": ["ui", "docker_hide_button", true, [], REBUILD],
    # Whether the grid is drawn over the canvas.
    "show_grid": ["ui", "show_grid", false, [], REBUILD],
    # The grid's spacing in document pixels, before `SaGridOverlay` doubles it up
    # to something worth drawing.
    #
    # A preference rather than the overlay's own constant. A spacing in document
    # pixels means nothing without the zoom, which is true of what is drawn and not
    # of what is asked for: a pixel painter asks for a line on every
    # document pixel and lets the zoom decide when the drawing gives up, which is
    # exactly what the doubling already does. One is a legal value and 64 is the
    # default, so a painter who has not touched this sees the grid that shipped.
    "grid_size": ["ui", "grid_size", DEFAULT_GRID_SIZE, [MIN_GRID_SIZE, MAX_GRID_SIZE], REBUILD],
    "reset_zoom": ["ui", "reset_zoom"],
    "reset_zoom_size": ["ui", "reset_zoom_size"],
    # Whether a zoom notch at and above 100% lands on whole multiples of actual
    # pixels, which `SaView.Steps.next_zoom` reads, for pixel art.
    "integer_zoom": ["ui", "integer_zoom", false],
    # Which shape the colour docker's picker is: "wheel", "okhsl" or
    # "triangle", the keys `SaPickerShape.KIND_KEYS` declares.
    #
    # Here rather than in Preferences because the dropdown that writes it sits in
    # the docker, where a painter switches shape without leaving the painting. A
    # setting all the same, so the choice survives a restart, and it emits
    # `profile_changed` because that is what the picker rebuilds on.
    #
    # Stored as the key rather than as a number, so a shape added later does not
    # renumber the ones before it, and an unknown key reads as the wheel.
    "color_picker_shape": ["ui", "color_picker_shape", "wheel", [], REBUILD],
    # Whether loading a preset leaves the blend mode the painter picked alone. A
    # preset carries its blend mode on purpose, because the mode describes the
    # brush, and this is the switch that says "not mine".
    "keep_blend_mode": ["ui", "keep_blend_mode", false, [], ONCE],
    "import_fit": ["ui", "import_fit"],
    "import_depth": ["ui", "import_depth"],
    "ask_when_opening": ["files", "ask_when_opening"],
    "ask_eight_bit_when_opening": ["files", "ask_eight_bit_when_opening"],
    "ask_panorama": ["files", "ask_panorama"],
    "filter_preview_on_canvas": ["performance", "filter_preview_on_canvas"],
    "filter_way": ["ui", "filter_way"],
    "filter_affect_all": ["ui", "filter_affect_all"],
    "blend_favorites": ["ui", "blend_favorites"],
    # Whether the canvas compresses highlights instead of clipping them.
    #
    # A view mode, on by default because the knee's default is white. At that
    # knee every colour the display can show reaches the screen as it does with
    # this off, so what the switch changes is only what the display cannot show: a
    # stored 1.0 and a stored 4.0 stop being the same white, and a colour past the
    # cube loses chroma rather than a channel. At a lower knee it would fade every
    # saturated colour a painter has, too much to impose by default. The pixels are
    # never touched either way: see `shaders/canvas/tonemap.gdshader`.
    "tonemap_highlights": ["ui", "tonemap_highlights", true],
    # Where the highlight rolloff's identity region ends.
    #
    # At and below this, in linear light, the view shows stored values untouched.
    # Above it a colour loses chroma by how far Khronos PBR Neutral's shoulder,
    # started here, would have pulled its peak down, and the peak is held at
    # white. The default is white itself, 1.0, so only a colour outside the
    # display's cube changes. Lower starts the fading earlier, on colours the
    # display could show, and spreads it over more of the range. The shader's own
    # comment carries the measured table. Above 1.0 no chroma is given up under
    # the knee.
    "tonemap_knee": ["ui", "tonemap_knee", 1.0, [0.05, SaSettingsValues.TONEMAP_KNEE_TOP]],
    # How hard a compressed highlight loses chroma, on the Oklab axis. 0 keeps
    # the colour, higher pulls it towards neutral the further above the window
    # it goes, which is what makes a light read as light.
    "tonemap_desaturation": ["ui", "tonemap_desaturation", 0.15, [0.0, 1.0]],
    "gamut_mapping": ["ui", "gamut_mapping"],
    # Whether the canvas lights the paint's height, View > Show Impasto. On, so the
    # relief shows as soon as any layer carries height, and a document with none has
    # no relief to show whatever this says. A view, never the pixels.
    "show_relief": ["ui", "show_relief", true],
    "relief_light_angle": ["ui", "relief_light_angle"],
    # How steep a new document draws the stored slope, a scale on it before the
    # light, and 0 draws it flat. The height stays in millimetres whatever this
    # says. 2 by default, half the 4 it shipped at. Each document keeps its own
    # after that, `SaReliefLight`.
    "relief_strength": ["ui", "relief_strength", 2.0, [0.0, SaSettingsValues.MAX_RELIEF_STRENGTH]],
    # How strongly the relief shines where a ridge faces the light, the peak of
    # its white highlight, for the view, the export's bake and Rasterize Impasto
    # alike. Unlike the strength it is a look of the screen and never the
    # document's, so every document shines alike. 0 is no shine at all.
    "relief_gloss": ["ui", "relief_gloss", 0.055, [0.0, SaSettingsValues.MAX_RELIEF_GLOSS]],
    # The display exposure: a view-only scale in stops, on or off, so a painter
    # can look into an HDR document's highlights. Never the brush's.
    "display_exposure_enabled": ["ui", "display_exposure_on", false],
    "display_exposure_stops": ["ui", "display_exposure_stops", 0.0, [-SaPaintExposure.FLOAT_STOPS, SaPaintExposure.FLOAT_STOPS]],
    # The display's own colour space, by `SaColorSpace` id, the monitor's own
    # ICC file, or the system's profile for the monitor. Its default differs by
    # platform, so its property is the values' own.
    "display_profile": ["ui", "display_profile"],
    # The monitor's ICC profile, read when the display profile is the file. Kept
    # whatever the display profile is, so picking a preset and back again does
    # not ask for the file a second time.
    "display_profile_file": ["ui", "display_profile_file", ""],
    # The display's gamut and white while the display profile is the custom
    # one. Kept whatever the profile is, as the file is.
    "display_custom_space": ["ui", "display_custom_space", NO_CUSTOM_SPACE],
    # How the canvas fills a display wider than the document, one of
    # [constant DISPLAY_FILLS]. Correct for anyone who has not asked otherwise.
    "display_fill": ["ui", "display_fill", "correct", SaSettingsValues.DISPLAY_FILLS],
    # The gamut soft proofing previews through. sRGB by default, the narrowest
    # of the three and what a P3 painting is most often shown in.
    "proof_profile": ["ui", "proof_profile", "srgb", SaSettingsValues.PROOF_PROFILES],
    # The ICC profile of the device the proof is for, read when the proof gamut
    # is the file. Its own path, apart from the monitor's, and kept whatever the
    # proof gamut is, as `display_profile_file` is.
    "proof_profile_file": ["ui", "proof_profile_file", ""],
    # The proof's gamut and white while the proof gamut is the custom one.
    "proof_custom_space": ["ui", "proof_custom_space", NO_CUSTOM_SPACE],
    "canvas_proof_mode": ["ui", "canvas_proof_mode"],
    "minimap_proof_mode": ["ui", "minimap_proof_mode"],
    "shape_check_method": ["ui", "shape_check_method"],
    "shape_check_levels": ["ui", "shape_check_levels"],
    "shape_check_level_count": ["ui", "shape_check_level_count"],
    "shape_check_reach": ["ui", "shape_check_reach"],
    "shape_check_across": ["ui", "shape_check_across"],
    "shape_check_notan_values": ["ui", "shape_check_notan_values"],
    "shape_check_notan_threshold": ["ui", "shape_check_notan_threshold"],
    "shape_check_notan_dark": ["ui", "shape_check_notan_dark"],
    "shape_check_notan_light": ["ui", "shape_check_notan_light"],
    # Whether Sara draws its own pointer over the panels, and therefore when the OS
    # cursor is hidden. Four values, listed with their wording in
    # `SaCursorPolicy.CURSOR_MODES` and resolved by
    # `SaCursorPolicy.software_pointer_mode_active()`: "auto", the default, which
    # reads the display driver and is on under Wayland alone, "always" and "never",
    # which override it in either direction, and "both", which draws what "always"
    # draws and leaves the OS cursor visible beside it, so the distance between the
    # two can be read as the lag.
    "software_cursor": ["ui", "software_cursor", "auto"],
    # Where the window buttons sit on the top bar. "auto" reads
    # `OS.get_name()` and picks Left on macOS, Right everywhere else. "left"
    # and "right" override it.
    "window_button_position": ["ui", "window_button_position", "auto", [], REBUILD],
    # What the three window buttons look like. "auto" reads `OS.get_name()` and
    # draws macOS's traffic lights on a Mac, icon buttons everywhere else.
    # "lights" and "icons" override it. The look and the edge are two settings
    # rather than one, so a painter on GNOME with the buttons on the left does not
    # get Apple's dots unasked.
    "window_button_style": ["ui", "window_button_style", "auto", [], REBUILD],
    # Whether the welcome window opens when Sara starts with no document. The
    # window's own checkbox writes it, and the boot reads it through
    # `SaWelcomeWindow.wanted_at_start`.
    "welcome_at_start": ["ui", "welcome_at_start", true],
    # Whether a quit saves a picture of the window for the next boot's cover.
    # Off, the cover shows the stock picture and no painting is ever written to
    # the user folder.
    "show_last_session": ["ui", "show_last_session", true],
    # The version whose release notes the welcome window's News pane last showed,
    # written once the pane has been looked at. Empty is a profile that never saw
    # one, a fresh install or an older one, and it shows every section there is.
    "last_version_seen": ["ui", "last_version_seen", ""],
    # The id of the tip the Tips pane last showed, so the next open starts on the
    # one after it.
    "last_tip_shown": ["ui", "last_tip_shown", ""],
    "first_launch_done": ["ui", "first_launch_done"],
    "tablet_max_pressure": ["input", "tablet_max_pressure"],
    "cursor_prediction_ms": ["input", "cursor_prediction_ms"],
    "cursor_lead": ["input", "cursor_lead"],
    # The tablet driver this machine asked for, empty for the project's own default.
    "tablet_driver": ["input", "tablet_driver", ""],
    "pen_buttons": ["input", "pen_buttons"],
    "mouse_middle": ["input", "mouse_middle"],
    "theme_name": ["theme", "name", "default"],
    # The interface font: an id `FONT_IDS` knows, applied at once.
    "ui_font": ["theme", "font", SaSettingsValues.DEFAULT_FONT, SaSettingsValues.FONT_IDS],
    "shortcuts_profile": ["shortcuts", "profile", "default"],
    # How many previous versions an explicit save keeps beside the file, as
    # `<name>.sad1`, `.sad2` and so on. One by default, none at zero.
    "sad_versions": ["files", "versions", 1, [0, SaSettingsValues.MAX_SAD_VERSIONS]],
    "recent_file_paths": ["files", "recent"],
    # Minutes of work between autosaves, 0 for none. Two by default: the timer is
    # the net under a Ctrl+S habit rather than a replacement for it.
    "autosave_interval_minutes": ["files", "autosave_minutes", 2.0, [0.0, SaSettingsValues.MAX_AUTOSAVE_MINUTES]],
    # Off, the autosave writes a recovery copy beside the document. On, it writes
    # the working file as a Save would, the `.sad1` chain keeping the one before.
    "autosave_to_working_file": ["files", "autosave_working_file", false],
    "export_author": ["files", "export_author"],
    "location_country": ["files", "location_country"],
    "location_zone": ["files", "location_zone"],
    "location_place": ["files", "location_place"],
    "location_in_exports": ["files", "location_in_exports"],
    "last_template": ["files", "last_template"],
    "new_document_details": ["files", "new_document_details"],
    "saved_color_spaces": ["files", "saved_color_spaces"],
    "sad_keeps_reference_pictures": ["files", "keep_reference_pictures"],
    "recorder_directory": ["recorder", "directory"],
    # Seconds of quiet after the last edit before a frame is taken.
    "recorder_settle_seconds": ["recorder", "settle_seconds", 2.0, [0.5, 30.0]],
    "recorder_cap_bytes": ["recorder", "cap_bytes"],
    "note_box_size": ["recorder", "note_box_size"],
    "search_window_size": ["ui", "search_window_size"],
    "search_recents": ["ui", "search_recents"],
    # How far the selection tools soften the edge of the next shape, as a
    # fraction of the canvas's smaller dimension.
    #
    # A fraction rather than pixels, the scheme the brush radius already uses, so
    # the same setting is the same visible softness on a 1920 document and on the
    # 3840 it was upgraded to. `SaSelectionFilters.feather_radius()` turns it into
    # the pixels a pass takes.
    #
    # Here rather than on the tool because the marquee, the lasso and the wand
    # share one Feather row, which cannot drift apart, and it survives a restart.
    "selection_feather": ["tools", "selection_feather", 0.0, [0.0, SaSettingsValues.MAX_SELECTION_FEATHER], ONCE],
    # The preset chooser's icon size in logical pixels, 30 to 128.
    #
    # Here rather than on the chooser, so it survives a restart and the docker and
    # the brush editor's presets fold, which host the same chooser, agree.
    "preset_icon_size": ["tools", "preset_icon_size", 56, [30, 128], ONCE],
    # Whether the preset chooser draws the tip instead of the stroke.
    #
    # Here rather than on the chooser for the reason [member preset_icon_size] is.
    "preset_thumb_tip": ["tools", "preset_thumb_tip", true, [], ONCE],
    "preset_favorites": ["tools", "preset_favorites"],
    "preset_tag_filter": ["tools", "preset_tag_filter"],
    "preset_bundles_off": ["tools", "preset_bundles_off"],
    # The brush editor page the painter last had open, so the Edit Brush button
    # reopens where they left off.
    #
    # Per profile rather than per document, because a page is a way of working
    # rather than a property of the picture, and a painter who was on Size stays on
    # Size when they open the next file.
    "brush_editor_page": ["tools", "brush_editor_page", "", [], ONCE],
    # Whether the Brush Editor's Brush Presets section is folded open.
    #
    # Shut by default, an expandable section, because a painter who never works
    # from presets should not lose a fifth of the page list to a grid.
    "brush_editor_presets_open": ["tools", "brush_editor_presets_open", false, [], ONCE],
    # The width of the Brush Editor's scratchpad column in logical units, the
    # width it snaps back to after being shut. Zero means never dragged, and
    # the pad takes its share of the editor's width.
    "brush_editor_pad_width": ["tools", "brush_editor_pad_width", 0, [0, NO_TOP], ONCE],
    # Whether the Brush Editor's scratchpad was dragged shut. Kept apart from the
    # width, because a shut pad still has a width to snap back to.
    "brush_editor_pad_shut": ["tools", "brush_editor_pad_shut", false, [], ONCE],
    # The width of the Brush Editor's presets column in logical units, the width
    # it snaps back to after being folded or dragged shut. Zero means never
    # dragged, and the column takes its default. Whether it is open stays
    # [member brush_editor_presets_open], its own key.
    "brush_editor_presets_width": ["tools", "brush_editor_presets_width", 0, [0, NO_TOP], ONCE],
    # How many whole-canvas steps the undo history has to hold.
    #
    # The budget under it is bytes, not steps, because an action is worth whatever
    # it touched: `SaHistory` spends `DEFAULT_BUDGET_BYTES` as a floor and asks for
    # this many of the most expensive step the document has produced on top of it.
    # So the same number means six steps on a sketchpad's dabs and twelve
    # whole-canvas gradients on a 1920x1080 document, and the painter reads it as
    # depth rather than as megabytes they would have to divide.
    #
    # Twelve by default, because a fill and eight ramps is the case the budget has
    # to cover, and a depth that cannot undo it is no use. It costs 480 MiB on a
    # 1920x1080 F32 document, where six cost 256 MiB.
    "history_depth": ["files", "history_depth", 12, [MIN_HISTORY_DEPTH, MAX_HISTORY_DEPTH], REBUILD],
    # Whether a layer's eye is an undo step, on by default, because hiding a
    # layer is a change a painter expects an undo to take back.
    # `SaLayerOps.set_visible` and the Layers docker's sweep read it.
    "visibility_in_history": ["files", "visibility_in_history", true],
    "painting_frame_rate": ["performance", "painting_frame_rate"],
    "thumbnails_while_painting": ["performance", "thumbnails_while_painting"],
    # Whether the view is drawn at half the window's size while the canvas pans,
    # zooms or turns, `SaHalfSizeView` in `render/` its reader.
    # Off by default.
    "half_size_view_while_moving": ["performance", "half_size_view_while_moving", false],
    "light_mode_offer": ["performance", "light_mode_offer"],
    "idle_after_seconds": ["performance", "idle_after_seconds"],
    "card_memory_share": ["performance", "card_memory_share"],
    "brush_slots": ["tools", "brush_slots"],
    "modules_off": ["modules", "off"],
}


## The section and key *property* is stored under, or an empty array when it is
## not a stored preference.
static func place_of(property: StringName) -> Array:
    return KEYS.get(String(property), [])


## Whether *property* is a plain preference, one whose row carries its default.
static func is_plain(property: StringName) -> bool:
    var row: Array = SETTINGS.get(String(property), [])
    return row.size() > 2


## *val* held to the bounds of *property*'s row: clamped for a number, and the
## default for a string the row does not allow.
static func bounded(property: StringName, val: Variant) -> Variant:
    var row: Array = SETTINGS[String(property)]
    var bounds: Array = row[3] if row.size() > 3 else []
    if bounds.is_empty():
        return val
    match typeof(row[2]):
        TYPE_INT:
            var whole: int = val
            var floor_int: int = bounds[0]
            var top_int: int = bounds[1]
            return clampi(whole, floor_int, top_int)
        TYPE_FLOAT:
            var real: float = val
            var floor_real: float = bounds[0]
            var top_real: float = bounds[1]
            return clampf(real, floor_real, top_real)
    return val if bounds.has(val) else row[2]


## How *property* is told when written, [constant ONCE], [constant REBUILD] or 0.
static func how(property: StringName) -> int:
    var row: Array = SETTINGS[String(property)]
    var told: int = row[4] if row.size() > 4 else 0
    return told


## The section and key of every row of [constant SETTINGS], for [member KEYS].
static func _places() -> Dictionary[String, Array]:
    var places: Dictionary[String, Array] = {}
    for property: String in SETTINGS:
        places[property] = SETTINGS[property].slice(0, 2)
    return places
