## The bar's presets button reads Presets, and a fresh layout
## shows the presets docker with tip thumbnails.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The bar's first button read "Canvas Brush" and nothing on screen said where
## the presets were. The button is named Presets rather than by the
## active brush name, the Brush Presets window is easy to find and shows
## Tips by default, and the option inside brush presets that shows strokes by
## default shows Tips.
##
## What a painter sees is
## `scenarios/the-bar-s-presets-button-reads-presets-and-a-fresh-layout-shows-the-presets-docker-with-tip-thumbnails.json`.
## The geometry of the opened docker is `test_the_default_layout_fits_the_screen.gd`,
## which has laid the shipped files out on seven hosts, so
## this file asks the fit one question only: that the head of the close order
## leaves every host too small for the docker fitted exactly as it was while
## the docker shipped closed.
extends "res://tests/test_framework.gd"

const ControlWalker := preload("res://harness/controls/sa_control_walker.gd")

const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## A chooser's cells are real dabs through the real paint path.
const REQUIRES_GPU := true

## Both files a fresh profile can open the default from.
const SHIPPED_FILES: Array[String] = [DockerLayoutStore.SHIPPED_DEFAULTS, "res://layouts/default.cfg"]

## The hosts the shipped default has no room for every docker on, read off
## `test_the_default_layout_fits_the_screen.gd`'s list: the two the fit gives
## up width on as well as height, and the one it only closes for height.
const CRAMPED: Array[Vector2i] = [Vector2i(640, 400), Vector2i(640, 512), Vector2i(960, 540)]

## The first row below a one-row bar, the fit's `top` in a probe with no bar.
const TOP := 65

## A locale no catalogue of the tree uses, so the one this suite registers is
## the only answer under it.
const LOCALE := "probe"

## What that catalogue says Presets is, a word of no language, so a label that
## skipped `tr()` reads as English and fails.
const TRANSLATED := "Preseti"

static var scratch_dir: String = SaDataRoot.path("test_presets")
static var scratch_profile: String = SaDataRoot.path("test_profile.cfg")

var _saved_tip: bool = true
var _saved_icon_size: int = 112


func before_each() -> void:
    _saved_tip = SaSettings.preset_thumb_tip
    _saved_icon_size = SaSettings.preset_icon_size
    var factory := SaSettingsValues.new()
    SaSettings.preset_thumb_tip = factory.preset_thumb_tip
    SaSettings.preset_icon_size = factory.preset_icon_size
    factory.free()
    _clear()


func after_each() -> void:
    SaSettings.preset_thumb_tip = _saved_tip
    SaSettings.preset_icon_size = _saved_icon_size
    _clear()


func _clear() -> void:
    var profile := ProjectSettings.globalize_path(scratch_profile)
    for suffix: String in ["", ".bak", ".tmp", ".broken"]:
        DirAccess.remove_absolute(profile + suffix)
    var thumbs := SaPresetThumbs.thumbs_dir(scratch_dir)
    if DirAccess.dir_exists_absolute(thumbs):
        for file_name: String in DirAccess.get_files_at(thumbs):
            DirAccess.remove_absolute(thumbs.path_join(file_name))
        DirAccess.remove_absolute(thumbs)
    if not DirAccess.dir_exists_absolute(scratch_dir):
        return
    for file_name: String in DirAccess.get_files_at(scratch_dir):
        DirAccess.remove_absolute(scratch_dir.path_join(file_name))
    DirAccess.remove_absolute(scratch_dir)


# --- The word on the button ---------------------------------------------------


## "Brush presets menu should be named Presets, not by the active brush name":
## two presets are loaded, the button reads Presets under both, and the preset
## in hand is read on the hover instead.
func test_the_button_reads_presets_whichever_preset_is_loaded() -> void:
    var presets := ToolOptionsPresets.new()
    for preset_name: String in ["Inked Pen", "Canvas Brush"]:
        presets.selected_preset = preset_name
        presets.sync_menu()
        assert_eq(presets.preset_menu.text, "Presets", "The button reads Presets with %s loaded" % preset_name)
        assert_eq(
            presets.preset_menu.tooltip_text,
            "%s. Shows or hides Brush Presets." % preset_name,
            "and the hover names %s, which is where the preset in hand stays" % preset_name,
        )
    presets.selected_preset = ""
    presets.sync_menu()
    assert_eq(presets.preset_menu.text, "Presets", "and it reads Presets with no preset loaded, as it always did")
    presets.free()


## "translated like any string the app shows": the label goes through `tr()`,
## so a catalogue that has a word for Presets writes it on the button.
func test_the_label_follows_the_language() -> void:
    var catalogue := Translation.new()
    catalogue.locale = LOCALE
    catalogue.add_message(ToolOptionsPresets.PRESET_LABEL, TRANSLATED)
    TranslationServer.add_translation(catalogue)
    var spoken := TranslationServer.get_locale()
    TranslationServer.set_locale(LOCALE)

    var presets := ToolOptionsPresets.new()
    presets.selected_preset = "Canvas Brush"
    presets.sync_menu()
    assert_eq(presets.preset_menu.text, TRANSLATED, "The button says what the catalogue says Presets is")
    presets.free()

    TranslationServer.set_locale(spoken)
    TranslationServer.remove_translation(catalogue)


## "the preset in use stays in its tooltip and in the docker's highlight": the
## docker's grid marks the cell of the preset that is loaded, which is the
## other place a painter reads the name now that the label stands still.
func test_the_docker_marks_the_preset_in_use() -> void:
    var pair := _hosted("Paint")
    var chooser: SaBrushPresetsChooser = pair[1]
    assert_eq(String(chooser.chooser_report()["marked"]), "Paint", "The loaded preset's cell is the marked one")
    (pair[0] as Node).free()


# --- The fresh layout ---------------------------------------------------------


## "Brush presets window is hard to find": both shipped files open the docker,
## in one place and in one close order, because a fresh profile reads the first
## and the named layout the second.
func test_both_shipped_files_open_the_brush_presets_at_one_place() -> void:
    var first := {}
    for path: String in SHIPPED_FILES:
        var cfg := ConfigFile.new()
        assert_eq(cfg.load(path), OK, "%s reads" % path)
        assert_true(bool(cfg.get_value("BrushPresetsDocker", "visible", false)), "the Brush Presets opens in %s" % path)
        var order: Array = cfg.get_value(DockerLayoutStore.META_SECTION, SaDockerLayoutRefit.CLOSE_ORDER, [])
        # The Minimap stands in the right column, so it closes first and costs the left column nothing.
        assert_eq(String(order[1]), "BrushPresetsDocker", "and heads the close order of the left column in %s" % path)
        var rect := Rect2i(cfg.get_value("BrushPresetsDocker", "position"), cfg.get_value("BrushPresetsDocker", "size"))
        if first.is_empty():
            first = {"rect": rect, "order": order}
            continue
        assert_eq(rect, first["rect"] as Rect2i, "at the place the other file states")
        assert_eq(order, first["order"] as Array, "with the order the other file states")


## The head of the close order is what keeps the opened docker from costing a
## small host anything: on every host with no room for it, the dockers that
## stay open land exactly where they landed while the file shipped it closed.
func test_a_host_too_small_closes_it_first_and_is_fitted_as_before() -> void:
    for host: Vector2i in CRAMPED:
        var now := _fit(host, _shipped(true))
        var before := _fit(host, _shipped(false))
        assert_false(now.has("BrushPresetsDocker"), "A host of %s closes the Brush Presets" % host)
        assert_eq(now, before, "and lays out the rest as the file did while it shipped closed, on %s" % host)


## And on the host the file was written for, the docker opens where it says.
func test_the_host_the_file_was_written_for_opens_it_where_it_stands() -> void:
    var placed := _fit(Vector2i(1920, 1048), _shipped(true))
    assert_true(placed.has("BrushPresetsDocker"), "A window 1048 tall keeps the Brush Presets open")
    assert_eq(placed["BrushPresetsDocker"] as Rect2i, Rect2i(60, 517, 310, 491), "under the Tool Options, where it says")


# --- The thumbnails -----------------------------------------------------------


## "the option inside brush presets that shows strokes by default should show
## Tips insted": a fresh profile's value, and the row the chooser opens on.
func test_a_fresh_profile_shows_the_tip() -> void:
    var factory := SaSettingsValues.new()
    assert_true(factory.preset_thumb_tip, "A fresh profile shows the tip")
    factory.free()
    var pair := _hosted()
    var chooser: SaBrushPresetsChooser = pair[1]
    assert_true(chooser.showing_tip(), "and a chooser over it draws the tips")
    assert_eq(chooser.thumb_option.selected_value(), SaBrushPresetsChooser.THUMB_TIP, "with the row on Tip")
    assert_eq(chooser.chooser_report()["thumb"], "tip", "and the dump says tip, which is what a scenario reads")
    (pair[0] as Node).free()


## "A painter's choice of Strokes is kept": the choice is a stored key, and a
## profile holding it reads back as Strokes over the fresh default, because
## every key is written on every save and read with the fresh value as the
## fallback only where the file has none.
func test_a_painters_strokes_survives_the_new_default() -> void:
    var pair := _hosted()
    var chooser: SaBrushPresetsChooser = pair[1]
    ControlWalker.move(chooser.thumb_option, "strokes")
    assert_false(SaSettings.preset_thumb_tip, "The row wrote Strokes into the profile")
    assert_eq(SaSettingsKeys.place_of(&"preset_thumb_tip"), ["tools", "preset_thumb_tip"], "under a stored key")
    (pair[0] as Node).free()

    var values := _reloaded(false)
    assert_false(values.preset_thumb_tip, "and a profile holding it reads Strokes back, not the fresh default")
    values.free()
    var untouched := _reloaded_without_the_key()
    assert_true(untouched.preset_thumb_tip, "where a profile that never held the key gets the tip")
    untouched.free()


# --- Helpers ------------------------------------------------------------------


## The shipped default's dockers as the fit is handed them, with the Brush
## Presets open or closed as *with_presets* says, which is the file as it
## left it. The floors are the fit suite's, read there for every host.
func _shipped(with_presets: bool) -> Dictionary:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(DockerLayoutStore.SHIPPED_DEFAULTS), OK, "the shipped default reads")
    var floors := {
        "ToolBoxDocker": Vector2i(56, 76),
        "ToolOptionsDocker": Vector2i(206, 255),
        "ColorDocker": Vector2i(214, 212),
        "LayersDocker": Vector2i(269, 212),
        "BrushPresetsDocker": Vector2i(295, 212),
        "MinimapDocker": Vector2i(168, 132),
    }
    var out: Dictionary = {}
    for section: String in cfg.get_sections():
        if section.begins_with("_layout") or not bool(cfg.get_value(section, "visible", false)):
            continue
        if section == "BrushPresetsDocker" and not with_presets:
            continue
        var rect := Rect2i(cfg.get_value(section, "position"), cfg.get_value(section, "size"))
        var floor_size: Vector2i = cfg.get_value(section, SaDockerLayoutRefit.FLOOR_SIZE, Vector2i())
        out[section] = {"rect": rect, "min": floor_size.max(floors[section] as Vector2i)}
    return out


## *dockers* laid out on *host* with the shipped close order, which names the
## Brush Presets first of the left column and so answers for a layout without it too.
func _fit(host: Vector2i, dockers: Dictionary) -> Dictionary:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(DockerLayoutStore.SHIPPED_DEFAULTS), OK, "the shipped default reads")
    var order: Array = cfg.get_value(DockerLayoutStore.META_SECTION, SaDockerLayoutRefit.CLOSE_ORDER, [])
    var written_for: Vector2i = cfg.get_value(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_WRITTEN_FOR, Vector2i())
    return SaDockerLayoutFit.new(host, TOP, written_for, order).place(dockers)


## A store of the shipped presets under a scratch folder, and a chooser over it
## inside a host of a declared width, the shape both real hosts have. *loaded*
## is the preset the bar says is in hand, empty for none.
func _hosted(loaded: String = "") -> Array:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)
    var host := VBoxContainer.new()
    host.custom_minimum_size = Vector2(float(SaUI.px(300)), 0.0)
    host.size = Vector2(float(SaUI.px(300)), 400.0)
    var chooser := SaBrushPresetsChooser.new()
    chooser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    host.add_child(chooser)
    chooser.bind_store(
        store,
        StateBrushScript,
        func() -> Resource: return BrushSettingsScript.new(),
        func() -> String: return loaded,
    )
    return [host, chooser]


## A profile of this version holding *tip* under the stored key, read back
## through a file object and a values node of this suite's own, so nothing the
## running application listens to hears the choice change under it.
func _reloaded(tip: bool) -> SaSettingsValues:
    var config := ConfigFile.new()
    config.set_value("meta", "version", SaSettingsFile.SETTINGS_VERSION)
    config.set_value("tools", "preset_thumb_tip", tip)
    return _read_back(config)


## The same profile without the key at all, which is every profile written
## before the chooser had the choice.
func _reloaded_without_the_key() -> SaSettingsValues:
    var config := ConfigFile.new()
    config.set_value("meta", "version", SaSettingsFile.SETTINGS_VERSION)
    config.set_value("tools", "preset_icon_size", 112)
    return _read_back(config)


func _read_back(config: ConfigFile) -> SaSettingsValues:
    var path := ProjectSettings.globalize_path(scratch_profile)
    config.save(path)
    var file := SaSettingsFile.new()
    file.settings_path = path
    var values := SaSettingsValues.new()
    file.load_from_disk(values)
    return values
