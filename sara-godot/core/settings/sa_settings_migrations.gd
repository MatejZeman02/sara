## What a settings file written by an older build needs before it can be read.
##
## **A transform of the config file and nothing else.** Every step rewrites
## keys, [method apply] takes the parsed profile and the version it says it
## is, and the read that follows finds whatever was carried over. It takes no
## settings node, so no step writes through a property and none has a side of
## the read to be on: `SaSettingsFile.load_from_disk` migrates before it reads
## the first key.
##
## Behind one door in the application, `SaSettingsFile`, and reached directly
## only by the suites that drive one step over a `ConfigFile` of their own.
##
## `@tool` because the autoload whose file calls it is.
@tool
class_name SaSettingsMigrations
extends RefCounted

## Bumped when a stored value changes meaning, so a load can migrate it. Here
## rather than beside the file, because the steps below are what a version
## means, and `SaSettingsFile.SETTINGS_VERSION` and `SaSettings.SETTINGS_VERSION`
## are aliases of this under the names callers already type.
const SETTINGS_VERSION: int = 29

## The tablet maximum a build compiled into `state_brush.gd` before
## Preferences > Tablet.
##
## Kept only so a profile written before Preferences > Tablet existed carries on
## feeling the way it did. It is one measurement from one Wacom, which is the
## whole reason the setting exists, so it is not a default for anybody new.
const LEGACY_MAX_PRESSURE: float = 0.73

## The six top-bar menus a build once shipped empty, hidden by default. See
## the version-8 step of [method apply].
const H1_MENUS_HIDDEN_BY_DEFAULT: Array[String] = ["View", "Dockers", "Image", "Layer", "Select", "Filter"]

## The Info docker's sections, which one layout element of an older profile
## switches on and off together. The version-9 step of [method apply] spreads a
## stored choice about "Telemetry Stats" over these. Written out rather than
## read from `InfoDocker.SECTIONS`, because a migration says what a profile of
## that vintage meant, and it has to keep saying it after the docker's sections
## change again.
const A5_INFO_SECTIONS: Array[String] = [
    "Input",
    "Document",
    "History",
    "GPU",
    "Colour space",
    "Selected colours",
    "Active layer",
]

## The module the version-15 step hands the gradient's alphas to, spelt out
## rather than asked of the module, because a migration says what a profile of
## that vintage meant whether or not the module is installed.
const BASE_MODULE_ID := &"sara-base-modules"

## The two keys the version-15 step moves, under the names they keep.
const GRADIENT_ALPHA_KEYS: Array[String] = ["gradient_start_alpha", "gradient_end_alpha"]

## The per-docker option the version-17 step folds into one switch, and the
## skeleton's own key the switch is kept under, spelt out rather than asked of
## `SaDockerMaximise`, because a migration says what a profile of that vintage
## meant and `core` never names `ui`.
const D27_MAXIMISE_OPTION := "maximise_button"
const D27_MAXIMISE_SWITCH := "docker_maximise_button"
const SKELETON_MODULE_ID := &"sara-skeleton"

## What the version-18 step takes out of the toolbox's stored layout: the noise
## brush's id in its groups and its row in its order, the entry
## `SaToolBoxGrid.layout_entry_for` writes for it. Spelt out, as the version-15
## module id is, because a migration says what a profile of that vintage held.
const NOISE_BRUSH_ID := "noise_brush"
const NOISE_BRUSH_ENTRY := "Noise Brush Tool"
const TOOLBOX := "ToolBoxDocker"
## What the version-22 step takes out the same way, liquify's.
const LIQUIFY_ID := "liquify"
const LIQUIFY_ENTRY := "Liquify Tool"

## The relief strength every build before version 19 shipped, and the one the
## version-19 step moves it to. Spelt out rather than read from
## `SaSettingsValues`, because a migration says what a profile of that vintage
## held and a later default is a later step's.
const D34_OLD_RELIEF_STRENGTH: float = 4.0
const D34_NEW_RELIEF_STRENGTH: float = 2.0

## The top bar's menu the version-20 step takes out of a stored layout. Spelt
## out, as the version-18 entry is, because a migration says what a profile of
## that vintage held.
const D2_SETTINGS_MENU := "Settings"

## The highlight rolloff's knee every build before version 21 shipped, and the
## one the version-21 step moves it to. Spelt out, as the relief strength is,
## because a migration says what a profile of that vintage held.
const B25_OLD_KNEE: float = 0.5
const B25_NEW_KNEE: float = 1.0

## The colour docker's paint exposure row that version 22 seats in a stored
## order, and the shape's stored name it goes after.
const E3_PAINT_EXPOSURE := "Paint Exposure"
const E3_PICKER_SHAPE := "HSV Wheel"

## The Layers docker's elements version 25 seats above its list, in the order
## they stand there, and the list's stored name.
const LAYER_ROWS: Array[String] = ["Blend Mode", "Opacity"]
const LAYER_LIST := "Layer List"

## The key a profile before version 26 kept the last of Sara's and the
## beginner's answers under, which version 26 drops.
const COMING_FROM_PRESSED := "coming_from_pressed"

## Where a profile keeps whether a layer's eye is an undo step, the switch
## version 27 turns on once.
const EYE_SECTION := "files"
const EYE_KEY := "visibility_in_history"

## Where a profile keeps its display profile, and the sRGB every build before
## version 28 started on, which version 28 moves to the system's profile once.
## Spelt out, because a migration says what a profile of that vintage held.
## The top bar's Page Edges and the two elements it took the place of, named
## here as strings because core never names the bar's class.
const PAGE_EDGES := "Page Edges"
const PAGE_EDGES_RETIRED: Array[String] = ["Wrap", "Infinite Canvas"]
const DISPLAY_PROFILE_SECTION := "ui"
const DISPLAY_PROFILE_KEY := "display_profile"
const DISPLAY_PROFILE_SHIPPED := "srgb"

## The Shape check row a profile before version 21 held, each of its three
## values by the method and the posterise switch the version-21 step reads it
## as. Spelt out, as the version-19 numbers are, because a migration says what
## a profile of that vintage held.
const SHAPE_HALVES := {
    "blocks": ["blocks", false],
    "levels": ["none", true],
    "both": ["blocks", true],
}

## The top bar's tool option elements before version 5, and the option key
## each became when the bar started building from the descriptors. The
## migration renames a stored profile through this table, so a hidden or
## moved slider stays hidden or moved.
const OPTION_KEY_RENAMES := {
    "Blend Mode": "blend_mode",
    "Erase Toggle": "eraser_toggled",
    "Size Slider": "radius",
    "Opacity Slider": "opacity",
    "Hardness Slider": "hardness",
    "Flow Slider": "flow",
    "Size Pressure": "size_by_pressure",
    "Opacity Pressure": "opacity_by_pressure",
    "Stabilizer": "stabilizer_mode",
    "Smoothing": "stabilizer_amount",
    "Sample Size": "sample_size",
    "Sample Merged": "sample_merged",
}


## Bring a settings file written by an older build up to SETTINGS_VERSION.
static func apply(config: ConfigFile, stored_version: int) -> void:
    if stored_version < 2:
        # "ui/scale" changed from an absolute content-scale factor to a multiplier
        # on top of the system scale. Any stored value was tuned against the old
        # meaning and would compound with the system scale under the new one.
        push_warning(
            (
                (
                    "Sara settings: resetting UI scale from %s to 100%%. "
                    + "The setting changed from an absolute scale to a multiplier on top of your display scale."
                )
                % config.get_value("ui", "scale", 1.0)
            )
        )
        config.set_value("ui", "scale", 1.0)

    if stored_version < 3:
        # The Extensions menu was renamed to Modules, which is what the loader,
        # the API and the docs have always called the thing. A stored layout
        # names its menus by string, so without this a profile that had ever
        # reordered or hidden the menu bar would keep an entry for a menu that no
        # longer exists and lose its say over the one that replaced it.
        #
        # Rewritten through `config` rather than through `layout_orders`,
        # because load_settings() calls this before it has read either dictionary
        # in: the file is the only version of the truth that exists yet.
        _rename_layout_element(config, "TopMenuBar", "Extensions", "Modules")

    if stored_version < 4:
        # The tablet maximum became a setting. Every profile older than this was
        # painted with 0.73 baked into the brush, so defaulting them to 1.0 would
        # silently make every pen heavier overnight. Carry the old number over
        # instead, and let Preferences > Tablet be where it changes.
        #
        # Written into the file rather than onto the settings, because the read
        # that follows the migration is what picks it up, and the setter it goes
        # through there is what clamps it.
        config.set_value("input", "tablet_max_pressure", LEGACY_MAX_PRESSURE)

    if stored_version < 5:
        # The tool options bar builds from each tool's option specs, and a
        # stored layout names a control by the option key rather than by an
        # English label. Each rename keeps its position and its visibility,
        # and the sentinel in the list stays where it is.
        for old_name: String in OPTION_KEY_RENAMES:
            var new_name: String = OPTION_KEY_RENAMES[old_name]
            _rename_layout_element(config, "TopMenuBar", old_name, new_name)
        # Exposure was on the bar without being in the list, so it drew where
        # the bar built it, beside Flow. Put it there in a stored order, or in
        # front of the sentinel when Flow is not listed, rather than letting
        # the merge append it after the sentinel onto the second row.
        var order: Array = config.get_value("profile_order", "TopMenuBar", [])
        if not order.is_empty() and not order.has("exposure"):
            var at := order.find("flow")
            if at != -1:
                order.insert(at + 1, "exposure")
            elif order.has(SaSettingsLayout.ROW_SENTINEL):
                order.insert(order.find(SaSettingsLayout.ROW_SENTINEL), "exposure")
            else:
                order.append("exposure")
            config.set_value("profile_order", "TopMenuBar", order)

    if stored_version < 6:
        # The Layers docker's lock row went into its More menu, so a
        # stored order that still lists "Locks" would put a row in
        # Preferences for a control that no longer exists.
        var layers_order: Array = config.get_value("profile_order", "LayersDocker", [])
        if layers_order.has("Locks"):
            layers_order.erase("Locks")
            config.set_value("profile_order", "LayersDocker", layers_order)

    if stored_version < 7:
        # The Info docker's scratchpad and its Clear button left for
        # `SaScratchpad`, which nothing shows, so a stored order that still
        # lists them would offer two rows in Preferences for controls that are
        # not in the docker.
        var info_order: Array = config.get_value("profile_order", "InfoDocker", [])
        var gone := false
        for element: String in ["Canvas", "Clear Button"]:
            if info_order.has(element):
                info_order.erase(element)
                gone = true
        if gone:
            config.set_value("profile_order", "InfoDocker", info_order)

    if stored_version < 8:
        # A build shipped with these six menus empty, hid them by default, and
        # saved the default as if it were a choice. A saved `false` for one of
        # exactly these six is indistinguishable from that default, so it is
        # dropped rather than kept: a menu that reappears once is a smaller
        # surprise than six that never come back. A person who hid one by hand
        # after that build sees it once and can hide it again. Every other saved
        # `false` on the bar, a slider or a control the user actually hid, is
        # untouched.
        for menu in H1_MENUS_HIDDEN_BY_DEFAULT:
            var key := "TopMenuBar_%s" % menu
            if config.has_section_key("profile_visibility", key) and config.get_value("profile_visibility", key) == false:
                config.erase_section_key("profile_visibility", key)

    if stored_version < 9:
        # The Info docker's one "Telemetry Stats" element became a row per
        # section, so a stored order that still lists it offers a row for a
        # control that no longer exists, and `get_layout_order` would append the
        # seven new ones after it.
        #
        # A profile that had switched the panel off meant every section, so the
        # `false` is copied onto all seven rather than dropped. Copying it is the
        # only reading that keeps the docker looking the way its owner left it:
        # dropping it would turn seven sections on at once for somebody who had
        # deliberately switched the numbers off.
        var info_order: Array = config.get_value("profile_order", "InfoDocker", [])
        if info_order.has("Telemetry Stats"):
            info_order.erase("Telemetry Stats")
            config.set_value("profile_order", "InfoDocker", info_order)
        var stats_key := "InfoDocker_Telemetry Stats"
        if config.has_section_key("profile_visibility", stats_key):
            var was_visible: bool = config.get_value("profile_visibility", stats_key)
            if not was_visible:
                for section in A5_INFO_SECTIONS:
                    config.set_value("profile_visibility", "InfoDocker_%s" % section, false)
            config.erase_section_key("profile_visibility", stats_key)

    if stored_version < 10:
        # Godot's own ColorPicker left the colour docker, and the choice of
        # shape took its place. A stored order that still lists it would offer
        # a row in Preferences for a control that is not there, and one that
        # predates the dropdown would never show it, since a stored order is
        # handed back verbatim and nothing is merged into it.
        var picker_order: Array = config.get_value("profile_order", "ColorPicker", [])
        if not picker_order.is_empty():
            picker_order.erase("Godot HSL Picker")
            if not picker_order.has("Picker Type"):
                var at := picker_order.find("HSV Wheel")
                picker_order.insert(at + 1 if at != -1 else picker_order.size(), "Picker Type")
            config.set_value("profile_order", "ColorPicker", picker_order)
        # Its hidden-by-default visibility went with it. Left behind, the key
        # would be the one thing in the file naming a control nobody can see.
        # Asked for first, because erasing a key from a section a profile never
        # wrote is an error rather than a no-op.
        if config.has_section_key("profile_visibility", "ColorPicker_Godot HSL Picker"):
            config.erase_section_key("profile_visibility", "ColorPicker_Godot HSL Picker")

    if stored_version < 11:
        # The colour picker docker has numeric sliders. A stored order is
        # handed back verbatim and nothing is merged into it, so without this a
        # profile that had ever reordered the docker would show the two rows
        # where the docker built them, last, and offer no way to move or hide
        # them until the layout was reset. Appended rather than placed, because
        # last is where the default puts them too.
        var picker_rows: Array = config.get_value("profile_order", "ColorPicker", [])
        if not picker_rows.is_empty():
            for row: String in ["RGB Sliders", "OK-HSV Sliders"]:
                if not picker_rows.has(row):
                    picker_rows.append(row)
            config.set_value("profile_order", "ColorPicker", picker_rows)

    if stored_version < 12:
        # The `raw` view mode became `encoding_off`, the id going with the label
        # because the old name was not what the mode did. Two stored keys can
        # name it, the canvas's proof mode and the minimap's, and a profile that
        # had the mode on is a painter who chose it.
        #
        # `_resolved_proof` already falls back for an id no registry answers to,
        # so without this nothing breaks, it just quietly moves that painter to
        # the default. Carrying the choice over is the difference between a rename
        # and a reset.
        for key: String in ["canvas_proof_mode", "minimap_proof_mode"]:
            if config.get_value("ui", key, "") == "raw":
                config.set_value("ui", key, "encoding_off")

    if stored_version < 13:
        # The Type dropdown left the colour docker for the Colour Picker
        # page under Preferences. A stored order that still lists the row would
        # offer a switch for a control that is not there, which is a known
        # shape: a Preferences row that reads as on while the docker never
        # built anything for it.
        var picker_order: Array = config.get_value("profile_order", "ColorPicker", [])
        if picker_order.has("Picker Type"):
            picker_order.erase("Picker Type")
            config.set_value("profile_order", "ColorPicker", picker_order)
        # And its visibility key, for the reason version 10 gives about the
        # Godot picker's: left behind it would be the one thing in the file
        # naming a control nobody can see. Asked for first, because erasing a key
        # from a section a profile never wrote is an error rather than a no-op.
        if config.has_section_key("profile_visibility", "ColorPicker_Picker Type"):
            config.erase_section_key("profile_visibility", "ColorPicker_Picker Type")

    if stored_version < 14:
        # The Dockers menu is not a menu any more: its rows and the layouts under
        # them moved into the Window menu, nested under Window. A stored order that still lists it is version
        # 13's shape exactly, a Preferences row for a button nobody builds, which
        # reads as a switch that does nothing.
        #
        # The order is rewritten here rather than left to the defaults, because
        # `get_layout_order` merges the defaults into a stored order and never
        # the other way: a name only a profile has stays in that profile for
        # good. The visibility key goes with it, asked for first, because
        # erasing a key from a section a profile never wrote is an error rather
        # than a no-op.
        var menu_order: Array = config.get_value("profile_order", "TopMenuBar", [])
        if menu_order.has("Dockers"):
            menu_order.erase("Dockers")
            config.set_value("profile_order", "TopMenuBar", menu_order)
        if config.has_section_key("profile_visibility", "TopMenuBar_Dockers"):
            config.erase_section_key("profile_visibility", "TopMenuBar_Dockers")

    if stored_version < 15:
        # The gradient's two remembered endpoint alphas were skeleton
        # preferences under `[tools]` because a module had no preference of its
        # own to keep them in. They are the base module's now, so they move
        # into its section under the same names, and a painter's one-sided
        # gradient opens the way they left it.
        var section := SaSettingsFile.module_section(BASE_MODULE_ID)
        for key: String in GRADIENT_ALPHA_KEYS:
            if config.has_section_key("tools", key):
                config.set_value(section, key, config.get_value("tools", key))
                config.erase_section_key("tools", key)

    if stored_version < 16:
        # Gamut mapping became a view toggle of its own and Oklab its default,
        # because clipping shows colours badly on screen.
        # Clip was the only default before, and the Display page the only door
        # to the row, so a profile of that vintage holding clip is almost always
        # a painter who never chose. It reads Oklab once, and a later choice of
        # clip is stored under version 16 and stays.
        config.set_value("ui", "gamut_mapping", SaGamutMapping.OKLAB)

    if stored_version < 17:
        # The Maximize button became one switch for every docker. It was an
        # option of each docker's own, so a painter who had it on for the
        # Reference docker alone meant the button, and the switch reads on when
        # any docker had it on. Every docker's key goes, because nothing reads
        # it any more and a key left behind would be the one line in the file
        # naming a row nobody draws. The switch is the skeleton's own
        # preference, as the summon's are, so it goes into the skeleton's
        # section, and only when it is on: a profile with every docker's off
        # reads as a new one does.
        if _any_docker_had_maximise(config):
            config.set_value(SaSettingsFile.module_section(SKELETON_MODULE_ID), D27_MAXIMISE_SWITCH, true)

    if stored_version < 18:
        # The noise brush became an engine of the Brush rather than a tool of its
        # own, so the toolbox draws no button for it. A painter
        # who once dragged a tool stored every tool's row in the toolbox's order
        # and its id in the groups, and one who hid it stored its visibility.
        # Left behind, the row is a Preferences switch for a button nobody
        # builds, the trap version 14 names. The Brush is where it went.
        _drop_from_toolbox(config, NOISE_BRUSH_ENTRY, NOISE_BRUSH_ID)

    if stored_version < 19:
        # The relief is drawn half as steep by default, the old default being
        # too strong. The file keeps every value it read, so a profile holding
        # the old default is almost always a painter who never moved the slider,
        # and it reads the new one once. Any other strength was chosen and
        # stays, and so does a 4 chosen after this step, which is stored under
        # version 19.
        if _holds_number(config, "ui", "relief_strength", D34_OLD_RELIEF_STRENGTH):
            config.set_value("ui", "relief_strength", D34_NEW_RELIEF_STRENGTH)

    if stored_version < 20:
        # The Settings menu left the bar and its rows went to Help, where they
        # take no space on the bar. A stored order
        # that still lists it is the trap version 14 names for the Dockers menu,
        # a Preferences row for a button nobody builds, and it goes the same
        # way: out of the order, the other menus keeping their places, and its
        # visibility key with it, asked for first.
        var bar_order: Array = config.get_value("profile_order", "TopMenuBar", [])
        if bar_order.has(D2_SETTINGS_MENU):
            bar_order.erase(D2_SETTINGS_MENU)
            config.set_value("profile_order", "TopMenuBar", bar_order)
        var hidden_key := "TopMenuBar_" + D2_SETTINGS_MENU
        if config.has_section_key("profile_visibility", hidden_key):
            config.erase_section_key("profile_visibility", hidden_key)

    if stored_version < 21:
        # The highlight rolloff measures its chroma loss by how far the peak
        # was pulled, the way Khronos PBR Neutral does, and starts at white, so
        # the original colours stay as they are wherever they can. At that knee
        # it changes only what the display cannot show, so it is on by default.
        # A profile holding the old knee is a painter
        # who never moved the slider and reads the new one. The switch turns on
        # once, here, so a profile of that vintage is mended, and a painter who
        # turns it off again saves that under version 21, which this never
        # touches. Any other knee was chosen and stays.
        if _holds_number(config, "ui", "tonemap_knee", B25_OLD_KNEE):
            config.set_value("ui", "tonemap_knee", B25_NEW_KNEE)
        config.set_value("ui", "tonemap_highlights", true)

    if stored_version < 22:
        # The colour docker has a paint exposure row, which belongs under the
        # shape. A stored order gets what it lacks appended
        # at its end, so without this a painter who turns the row on finds it
        # under the sliders. Seated after the shape, or first when the order
        # has no shape.
        var picker_order: Array = config.get_value("profile_order", "ColorPicker", [])
        if not picker_order.is_empty() and not picker_order.has(E3_PAINT_EXPOSURE):
            picker_order.insert(picker_order.find(E3_PICKER_SHAPE) + 1, E3_PAINT_EXPOSURE)
            config.set_value("profile_order", "ColorPicker", picker_order)

    if stored_version < 23:
        # The Shape check row of Blocks, Levels or Both became a method beside
        # the Blocks it named and a switch for the posterise, so no method the
        # old row offered is lost. Each of
        # the three reads as the view it showed, and a value the old row would
        # have refused reads as Both, which is what its setter made of it. The
        # old key goes, being the one line in the file nothing reads.
        if config.has_section_key("ui", "shape_check"):
            var halves: Array = SHAPE_HALVES.get(str(config.get_value("ui", "shape_check")), SHAPE_HALVES["both"])
            config.set_value("ui", "shape_check_method", halves[0])
            config.set_value("ui", "shape_check_levels", halves[1])
            config.erase_section_key("ui", "shape_check")

    if stored_version < 24:
        # Liquify became an engine of the Brush the way the noise brush did at
        # version 18, its options among the brush presets, so its row goes the
        # same way.
        _drop_from_toolbox(config, LIQUIFY_ENTRY, LIQUIFY_ID)

    if stored_version < 25:
        # The layer's blend mode and opacity stand above the list. A stored
        # order keeps every place it names, so without this a profile of that
        # vintage keeps them under it. Taken out and seated just
        # before the list, in the shipped order, the rest keeping their places.
        var layers_order: Array = config.get_value("profile_order", "LayersDocker", [])
        if layers_order.has(LAYER_LIST):
            for element: String in LAYER_ROWS:
                layers_order.erase(element)
            var at := layers_order.find(LAYER_LIST)
            for element: String in LAYER_ROWS:
                layers_order.insert(at, element)
                at += 1
            config.set_value("profile_order", "LayersDocker", layers_order)

    if stored_version < 26:
        # "I'm coming from" lost its Sara and No program buttons, and with them
        # the one fact it kept, which of the two was pressed last. Nothing
        # reads the key now, so it goes rather than staying in the file.
        if config.has_section_key("ui", COMING_FROM_PRESSED):
            config.erase_section_key("ui", COMING_FROM_PRESSED)

    if stored_version < 27:
        # A layer's eye is an undo step by default. Every load writes every key back, so a profile of an
        # older build holds the old default of off whether or not the painter
        # ever touched the switch, and it is turned on once, here, as the
        # version-21 step turns the highlight rolloff on. A painter who turns
        # it off again saves that under version 27, which this never touches.
        config.set_value(EYE_SECTION, EYE_KEY, true)

    if stored_version < 28:
        # The display profile follows the system's profile for the monitor by
        # default. Every load writes every key back, so a profile of an older
        # build holds the sRGB it shipped with whether or not the painter chose
        # it, and it is moved once, here, as the version-27 step turns the eye's
        # undo on. A painter who chose another keeps it, and one who goes back
        # to sRGB saves that under version 28, which this never touches.
        if config.get_value(DISPLAY_PROFILE_SECTION, DISPLAY_PROFILE_KEY, "") == DISPLAY_PROFILE_SHIPPED:
            config.set_value(DISPLAY_PROFILE_SECTION, DISPLAY_PROFILE_KEY, SaSettingsValues.DISPLAY_PROFILE_SYSTEM)

    if stored_version < 29:
        # Infinite Canvas and Wrap became one element, Page Edges, so a bar
        # that placed either shows it where the first of them stood, shown when
        # either was.
        _merge_into_page_edges(config)

    config.set_value("meta", "version", SETTINGS_VERSION)


## Whether any docker's own Maximize button option was on, taking every one of
## those keys out of the profile on the way. A key is `category_option`, and a
## module's category may carry an underscore of its own, so the option is found
## at the end of the key rather than after its first underscore.
static func _any_docker_had_maximise(config: ConfigFile) -> bool:
    var section := "profile_docker_option"
    var any_on := false
    if not config.has_section(section):
        return any_on
    for key: String in config.get_section_keys(section):
        if key.ends_with("_" + D27_MAXIMISE_OPTION):
            any_on = any_on or config.get_value(section, key) == true
            config.erase_section_key(section, key)
    return any_on


## Whether *section*/*key* holds *number*, a float or a hand-written whole
## number alike. Asked for first, because a default of null is no default to
## `ConfigFile` and an absent key would say so on the error stream.
static func _holds_number(config: ConfigFile, section: String, key: String, number: float) -> bool:
    if not config.has_section_key(section, key):
        return false
    var stored: Variant = config.get_value(section, key)
    if not (stored is float or stored is int):
        return false
    var value: float = stored
    return is_equal_approx(value, number)


## The version-18 and version-22 steps: a tool that became an engine of the
## Brush out of the toolbox's stored order, its visibility and its groups, by
## its row *entry* and its *id*, each asked for first because erasing a key a
## profile never wrote is an error. A group the tool was alone in goes with it.
static func _drop_from_toolbox(config: ConfigFile, entry: String, id: String) -> void:
    var order: Array = config.get_value("profile_order", TOOLBOX, [])
    if order.has(entry):
        order.erase(entry)
        config.set_value("profile_order", TOOLBOX, order)
    var hidden_key := "%s_%s" % [TOOLBOX, entry]
    if config.has_section_key("profile_visibility", hidden_key):
        config.erase_section_key("profile_visibility", hidden_key)
    var groups_key := "%s_groups" % TOOLBOX
    # A default of null is no default to ConfigFile, which says so on the error
    # stream, so an absent key is asked for first like the other two.
    if not config.has_section_key("profile_docker_option", groups_key):
        return
    var stored: Variant = config.get_value("profile_docker_option", groups_key)
    if not (stored is Array):
        return
    var groups: Array = stored
    var kept: Array = []
    for group: Variant in groups:
        if not (group is Array):
            continue
        var members: Array = group
        members = members.duplicate()
        members.erase(id)
        if not members.is_empty():
            kept.append(members)
    config.set_value("profile_docker_option", groups_key, kept)


## Renames one element of a stored layout, keeping its position and its
## visibility. A no-op for a profile that never touched the category.
static func _rename_layout_element(config: ConfigFile, category: String, from_name: String, to_name: String) -> void:
    var order: Array = config.get_value("profile_order", category, [])
    var at := order.find(from_name)
    if at != -1:
        order[at] = to_name
        config.set_value("profile_order", category, order)

    var old_key := "%s_%s" % [category, from_name]
    if config.has_section_key("profile_visibility", old_key):
        config.set_value("profile_visibility", "%s_%s" % [category, to_name], config.get_value("profile_visibility", old_key))
        config.erase_section_key("profile_visibility", old_key)


## The version-29 step: the bar's stored order through [method page_edges_order],
## and Page Edges shown when either retired element was. A profile that never
## stored the bar is left alone.
static func _merge_into_page_edges(config: ConfigFile) -> void:
    var category := "TopMenuBar"
    if config.has_section_key("profile_order", category):
        var stored: Array = config.get_value("profile_order", category, [])
        config.set_value("profile_order", category, page_edges_order(stored))
    var seen := false
    var shown := false
    for element: String in PAGE_EDGES_RETIRED:
        var old_key := "%s_%s" % [category, element]
        if config.has_section_key("profile_visibility", old_key):
            seen = true
            shown = shown or config.get_value("profile_visibility", old_key) == true
            config.erase_section_key("profile_visibility", old_key)
    if seen:
        config.set_value("profile_visibility", "%s_%s" % [category, PAGE_EDGES], shown)


## *order* with the first retired element it names turned into Page Edges and
## the other taken out, the rest in their places. Public, because a saved
## layout and a custom docker name elements too, and each is read through this
## when it loads.
static func page_edges_order(order: Array) -> Array:
    var out: Array = []
    for element: Variant in order:
        var named := str(element) if element is String or element is StringName else ""
        if PAGE_EDGES_RETIRED.has(named) or named == PAGE_EDGES:
            if not out.has(PAGE_EDGES):
                out.append(PAGE_EDGES)
            continue
        out.append(element)
    return out
