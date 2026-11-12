## Text size reads 100% at the size Sara ships with, and draws exactly as it did.
##
## The 75% the slider showed on a fresh profile was not
## labelled 100%, so the reading moved. The stored multiplier did not move, so what
## is checked here is both halves: the Workspace page reads 100% on a fresh
## profile and a profile written before reads at its new number, while the text
## of either draws at the pixel size it drew before, which was
## `SaUI.BASE_FONT_SIZE` times the stored `font_scale`.
extends "res://tests/test_framework.gd"

static var scratch_profile: String = SaDataRoot.path("test_text_size_profile.cfg")

## The points a fresh profile drew its text at before the reading moved, 20 times
## 0.75 rounded, written out so a change of the default shows here as a failure.
const FRESH_POINTS := 15

## The same for a kept profile at 0.85, 20 times 0.85.
const KEPT_POINTS := 17

var _saved_path: String
var _kept_font_scale: float
var _kept_theme: Theme
var _host: Control
var _page: SaWorkspacePage


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    _kept_font_scale = SaUI.user_font_scale
    _kept_theme = SaUI.shared_theme
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()


func after_each() -> void:
    if is_instance_valid(_host):
        _host.free()
    SaUI.shared_theme = _kept_theme
    SaUI.user_font_scale = _kept_font_scale
    SaUI.refresh_font_sizes()
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## Loads the scratch profile and applies its text size the way
## `SaSettingsApply` does at boot, onto a theme built for the suite, then
## builds the Workspace page under a host holding that theme.
func _load_and_build() -> void:
    SaSettings.load_settings()
    SaUI.init_global_theme(null)
    SaUI.user_font_scale = clampf(SaSettings.ui_font_scale, SaUI.MIN_FONT_SCALE, SaUI.MAX_FONT_SCALE)
    SaUI.refresh_font_sizes()
    _host = Control.new()
    _host.name = "TestHost"
    _host.theme = SaUI.shared_theme
    EventBus.add_child(_host)
    _page = SaWorkspacePage.new()
    _host.add_child(_page)


## The pixel size a plain label under the shared theme draws its text at.
func _label_points() -> int:
    var label := Label.new()
    label.text = "Aa"
    _host.add_child(label)
    var points := label.get_theme_font_size(&"font_size")
    label.free()
    return points


func _readout() -> String:
    var slider := _page.slider_named("font_size")
    return (slider.get_parent().get_node(NodePath(SaPage.READOUT_NAME)) as Label).text


func test_a_fresh_profile_reads_100_and_draws_as_before() -> void:
    _load_and_build()
    assert_almost_eq(SaSettings.ui_text_size, 1.0, 1e-6, "a fresh profile's text size reads 1.0")
    assert_almost_eq(SaSettings.ui_font_scale, 0.75, 1e-6, "over the stored multiplier it always had")
    assert_eq(_readout(), "100%", "the Workspace page reads 100% beside Font size")
    assert_almost_eq(_page.slider_named("font_size").value, 1.0, 1e-6, "and its slider stands at 1.0")
    assert_eq(SaUI.get_font_size(), FRESH_POINTS, "the interface's text is the size it was")
    assert_eq(_label_points(), FRESH_POINTS, "and a label draws at it")
    var row := _page.page.row(&"font_size")
    var points := "at %d points" % FRESH_POINTS
    assert_true(row.explanation.contains(points), "the hint names the same points, '%s'" % row.explanation)


func test_a_profile_from_before_draws_as_before_at_its_new_reading() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("meta", "version", SaSettingsFile.SETTINGS_VERSION)
    cfg.set_value("ui", "font_scale", 0.85)
    cfg.save(ProjectSettings.globalize_path(scratch_profile))
    _load_and_build()
    assert_almost_eq(SaSettings.ui_font_scale, 0.85, 1e-6, "the stored 0.85 is read as it was written")
    assert_almost_eq(SaSettings.ui_text_size, 0.85 / 0.75, 1e-6, "and reads as the new text size")
    assert_eq(_readout(), "113%", "the Workspace page reads 113% beside Font size")
    assert_eq(SaUI.get_font_size(), KEPT_POINTS, "the interface's text is the size the profile drew")
    assert_eq(_label_points(), KEPT_POINTS, "and a label draws at it")
    var after := ConfigFile.new()
    after.load(ProjectSettings.globalize_path(scratch_profile))
    var kept := float(after.get_value("ui", "font_scale", 0.0))
    assert_almost_eq(kept, 0.85, 1e-6, "opening the page writes nothing over the profile")


func test_setting_the_reading_writes_the_stored_multiplier() -> void:
    _load_and_build()
    SaSettings.ui_text_size = 1.2
    assert_almost_eq(SaSettings.ui_font_scale, 0.9, 1e-6, "120% stores 0.9, the multiplier on the base size")
    var slider := _page.slider_named("font_size")
    assert_true(slider.min_value <= 0.74 and slider.max_value >= 2.13, "the slider spans the whole stored range")
    slider.value = 1.0
    assert_almost_eq(slider.value, 1.0, 1e-6, "and 100% is a stop on its track")
