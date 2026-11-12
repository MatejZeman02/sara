## Themes that switch: a palette per theme, the theme's colours
## read from the active one, and what was built with them recoloured in place.
extends "res://tests/test_framework.gd"

var _saved_theme: String = "default"


func before_each() -> void:
    _saved_theme = SaTheme.palette_id


func after_each() -> void:
    SaTheme.use_named(_saved_theme)


func test_every_palette_on_offer_loads_and_names_itself() -> void:
    var offered := SaTheme.builtin()
    assert_eq(offered.size(), SaTheme.PALETTES.size(), "Every shipped palette is on the dropdown")
    for entry: Dictionary in offered:
        var loaded := load(SaTheme.PALETTES[entry["id"]]) as SaPalette
        assert_not_null(loaded, "%s loads as a palette" % entry["id"])
        assert_false(String(entry["name"]).is_empty(), "and has a display name")
        assert_true(loaded.bg_primary != loaded.text_primary, "%s: text and background differ" % entry["id"])


func test_switching_moves_the_theme_colours() -> void:
    SaTheme.use_named("default")
    var before := SaTheme.palette.bg_primary
    SaTheme.use_named("solarized")
    assert_eq(SaTheme.palette_id, "solarized", "The id follows")
    assert_true(SaTheme.palette.bg_primary != before, "and so do the colours every style reads")
    SaTheme.use_named("no-such-theme")
    assert_eq(SaTheme.palette_id, "default", "An id nobody has is the default, not a crash")


## The whole point: a stylebox built before the switch shows the new colours
## after it, without being rebuilt.
func test_a_bound_style_and_font_follow_a_switch_in_place() -> void:
    SaTheme.use_named("default")
    var style := SaTheme.make_docker_background_style()
    var label := Label.new()
    SaTheme.bind_font(label, "text_muted")
    var bar := StyleBoxFlat.new()
    SaTheme.bind(bar, {"bg_color": "bg_primary"})

    var heard: Array[String] = []
    var listener := func(id: String) -> void: heard.append(id)
    EventBus.theme_changed.connect(listener)
    SaTheme.use_named("photoshop")
    EventBus.theme_changed.disconnect(listener)

    var photoshop := load(SaTheme.PALETTES["photoshop"]) as SaPalette
    assert_eq(style.bg_color, photoshop.bg_primary, "The docker background took the new colour")
    assert_eq(bar.bg_color, photoshop.bg_primary, "and so did a stylebox bound by hand")
    assert_eq(label.get_theme_color("font_color"), photoshop.text_muted, "and a bound font colour")
    assert_eq(heard, ["photoshop"], "The bus announced it once")
    label.free()


func test_the_setting_is_what_switches() -> void:
    var saved := SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(SaDataRoot.path("test_sa_theme.cfg"))
    SaSettings.theme_name = "krita"
    assert_eq(SaTheme.palette_id, "krita", "Writing the setting switches the palette")
    SaSettings.theme_name = "default"
    SaSettings.settings_path = saved
    DirAccess.remove_absolute(ProjectSettings.globalize_path(SaDataRoot.path("test_sa_theme.cfg")))


func test_the_two_dead_pages_are_gone() -> void:
    assert_false(SaSettingsWindow.FIXED_PAGES.has("Workspace Presets"), "Workspace Presets changed nothing and left")
    assert_false(SaSettingsWindow.FIXED_PAGES.has("Shortcuts Profiles"), "and so did Shortcuts Profiles")
    # The themes page stays, and acts, behind Interface's Edit colours…
    var window := SaSettingsWindow.new()
    assert_true(window.show_colours(), "while the themes page stays, and acts")
    var page := window.content_container.get_child(window.content_container.get_child_count() - 1)
    assert_true(page is SaColorThemesPage, "drawn in the page area")
    window.free()


## The dropdown rim is one shared definition every dropdown asks for, not a box
## built for the preset button. A dropdown needs a rim to
## feel like a dropdown, and the answer has to be reusable
## or the next dropdown would need its own.
func test_a_dropdown_gets_a_rim_in_every_state() -> void:
    for state: String in SaTheme.DROPDOWN_STATES:
        var box := SaTheme.make_dropdown_style(state)
        assert_not_null(box, "%s has a box of its own" % state)
        assert_true(box.border_width_left > 0, "with a rim on it, in %s" % state)
    assert_eq(
        SaTheme.make_dropdown_style("normal").bg_color,
        SaTheme.palette.bg_input,
        "and the resting colour comes from the palette, so a theme switch repaints it"
    )


## A MenuButton is flat by default, so a box set on a flat button is invisible:
## `make_dropdown` is what turns the flag off as well as setting the boxes, and
## the arrow comes from the OptionButton class rather than from `assets/icons/`.
func test_make_dropdown_turns_the_flat_flag_off_and_sets_every_state() -> void:
    var button := MenuButton.new()
    assert_true(button.flat, "Godot builds a MenuButton flat")
    SaTheme.make_dropdown(button)
    assert_false(button.flat, "and a dropdown is not, or the rim never draws")
    for state: String in SaTheme.DROPDOWN_STATES:
        assert_true(button.has_theme_stylebox_override(state), "%s is set on the control" % state)
    assert_eq(button.icon_alignment, HORIZONTAL_ALIGNMENT_RIGHT, "with the arrow on the right, where a dropdown's is")
    assert_true(
        button.has_theme_constant_override("icon_max_width"),
        "and the arrow capped narrower than a toolbox glyph, or it clips the label"
    )
    button.free()
