## The palette's ramps: a group is a base and the shades that follow it,
## dragging the base slides them all, and the Colour Themes page is one row per
## group rather than one row per colour.
extends "res://tests/test_framework.gd"

var _saved_theme: String = "default"
var _saved_path: String = ""


func before_each() -> void:
    _saved_theme = SaTheme.palette_id
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(SaDataRoot.path("test_theme_groups.cfg"))
    _remove_forks()


func after_each() -> void:
    _remove_forks()
    SaSettings.theme_name = _saved_theme
    SaSettings.settings_path = _saved_path
    SaTheme.use_named(_saved_theme)
    SaSettings.theme_name = _saved_theme
    DirAccess.remove_absolute(ProjectSettings.globalize_path(SaDataRoot.path("test_theme_groups.cfg")))


func _remove_forks() -> void:
    for id in SaTheme.custom_ids():
        if id.begins_with(SaTheme.CUSTOM_PREFIX + "test-"):
            SaTheme.delete_custom(id)


func test_every_group_names_real_fields_and_claims_no_colour_twice() -> void:
    var keys := SaTheme.color_keys(SaPalette.new())
    var claimed: Dictionary = {}
    for group: String in SaTheme.GROUPS:
        var members := SaTheme.group_members(group)
        assert_true(members.size() > 0, "%s: a group with no shade is not a group" % group)
        for key: String in SaTheme.group_keys(group):
            assert_true(keys.has(key), "%s: %s is a palette field" % [group, key])
            assert_false(claimed.has(key), "%s is in one group only" % key)
            claimed[key] = group
        assert_eq(SaTheme.group_of(String(SaTheme.GROUPS[group]["base"])), group, "%s: the base is its own" % group)
    assert_eq(SaTheme.group_of("accent_gauge"), "", "A colour in no ramp belongs to no group")


## The two groups asked for by name carry all three, and text carries
## a shadow without a highlight because no palette holds a brighter text.
func test_background_and_border_carry_a_base_a_shadow_and_a_highlight() -> void:
    for group: String in ["background", "border"]:
        var spec: Dictionary = SaTheme.GROUPS[group]
        assert_false(String(spec["base"]).is_empty(), "%s has a base" % group)
        assert_false(String(spec["shadow"]).is_empty(), "%s has a shadow" % group)
        assert_false(String(spec["highlight"]).is_empty(), "%s has a highlight" % group)
    assert_eq(String(SaTheme.GROUPS["text"]["highlight"]), "", "Text has no colour brighter than its own")


func test_a_slide_of_nothing_changes_nothing_and_a_slide_keeps_the_gap() -> void:
    var base := Color("#404040")
    var shade := Color("#202020")
    var still := SaTheme.slide(shade, base, base)
    assert_almost_eq(still.r, shade.r, 0.002, "A base that did not move moves nothing")
    assert_almost_eq(still.b, shade.b, 0.002, "on any channel")

    var lighter := SaTheme.slide(shade, base, Color("#606060"))
    assert_true(lighter.get_luminance() > shade.get_luminance(), "A base dragged up drags its shade up")
    var back := SaTheme.slide(lighter, Color("#606060"), base)
    assert_almost_eq(back.r, shade.r, 0.01, "and dragging it back lands where it started")
    # A slide is a round trip through Oklab, and cbrt and pow do not undo each
    # other to the last bit, so a return is close rather than equal. Colour
    # stores float32 as well, which is where the alpha's own last digit goes.
    var kept := SaTheme.slide(Color(0.2, 0.2, 0.2, 0.4), base, base).a
    assert_almost_eq(kept, 0.4, 0.001, "The alpha is the shade's own")


func test_dragging_a_linked_base_slides_its_shades_and_a_loose_one_does_not() -> void:
    SaTheme.use_named("default")
    SaSettings.theme_name = SaTheme.fork("Test Slide")
    assert_true(SaTheme.is_linked("background"), "A fresh palette ships linked")

    var before: Color = SaTheme.palette.bg_secondary
    SaTheme.set_color("bg_primary", Color("#503030"))
    assert_true(SaTheme.palette.bg_secondary != before, "The shadow followed the base")
    assert_true(SaTheme.palette.bg_input != SaTheme.palette.bg_primary, "and kept its own distance from it")
    assert_true(SaTheme.palette.bg_primary.r > SaTheme.palette.bg_primary.g, "The base is the colour that was set")

    SaTheme.set_linked("background", false)
    var loose: Color = SaTheme.palette.bg_secondary
    SaTheme.set_color("bg_primary", Color("#305030"))
    assert_eq(SaTheme.palette.bg_secondary, loose, "Unlinked, the shadow stays where the painter left it")


func test_a_link_survives_the_file_it_is_written_to() -> void:
    SaTheme.use_named("default")
    var id := SaTheme.fork("Test Link File")
    SaTheme.set_linked("border", false)
    SaTheme.use_named("default")
    SaTheme.use_named(id)
    assert_false(SaTheme.is_linked("border"), "The unlink came back off disk")
    assert_true(SaTheme.is_linked("background"), "and the groups beside it are untouched")


func test_a_shipped_palette_is_never_linked_or_unlinked_in_place() -> void:
    SaTheme.use_named("default")
    assert_false(SaTheme.set_linked("background", false), "A shipped palette refuses the toggle")
    assert_true(SaTheme.is_linked("background"), "and stays as it shipped")


## The list is short rather than one entry per colour. The count is
## what says whether it got them.
func test_the_page_is_a_row_per_group_and_a_row_per_lone_colour() -> void:
    SaTheme.use_named("default")
    var page := SaColorThemesPage.new()
    var keys := SaTheme.color_keys(SaPalette.new())
    assert_eq(page._swatches.size(), keys.size(), "Every colour still has a swatch")
    assert_true(page._rows.size() < keys.size(), "but the rows are fewer than the colours")

    var grouped := 0
    for group: String in SaTheme.GROUPS:
        grouped += SaTheme.group_keys(group).size()
    assert_eq(page._rows.size(), keys.size() - grouped + SaTheme.GROUPS.size(), "One row per group, one per loner")
    assert_eq(page._links.size(), SaTheme.GROUPS.size(), "and a link toggle per group")

    var report := page.theme_report()
    assert_eq(report.size(), page._rows.size(), "The dump carries every row")
    var background: Dictionary = {}
    for entry: Dictionary in report:
        if entry.get("group", "") == "background":
            background = entry
    assert_true(background.has("linked"), "A group's row says whether it is held together")
    var named: Array[String] = []
    for swatch: Dictionary in background["colors"]:
        named.append(String(swatch["key"]))
    assert_eq(named[0], "bg_primary", "The base is the first colour of the row")
    assert_eq(String(background["base"]), "bg_primary", "and the row says which one it is")
    assert_true(named.has("bg_track"), "and every shade rides under it")
    page.free()


## The page disables its own shades while a group is linked, and on the row
## layer a rule pass that wrote every row's `disabled` would hand them back the
## moment any other row moved, on the rule that only a row
## some rule names is touched.
func test_a_locked_shade_stays_locked_after_another_row_moves() -> void:
    SaTheme.use_named("default")
    SaSettings.theme_name = SaTheme.fork("Test Lock Holds")
    var page := SaColorThemesPage.new()
    var shade := String(SaTheme.group_members("background")[0])
    var locked := page._swatches[shade] as ColorPickerButton
    assert_true(SaTheme.is_linked("background"), "The group starts linked")
    assert_true(locked.disabled, "so its shade is not the painter's to set")
    page.set_swatch("accent_primary", Color(0.2, 0.7, 0.3, 1.0))
    page.set_swatch("bg_primary", Color(0.1, 0.1, 0.2, 1.0))
    # What opening the page and any bound row's change run, and what a rule
    # pass over every row would have undone.
    page.page.refresh()
    assert_true(locked.disabled, "and it stays locked after two other rows moved and the rules ran again")
    assert_false(page.is_swatch_editable(shade), "which the page's own rule still says")
    page.free()


func test_the_page_sorts_the_swatches_into_the_palette_s_own_sections() -> void:
    SaTheme.use_named("default")
    var page := SaColorThemesPage.new()
    var sections: Array[String] = []
    for row: Dictionary in page._rows:
        var title := String(row["section"])
        if not sections.has(title):
            sections.append(title)
    assert_true(sections.has("Backgrounds"), "The palette's own groups are the page's sections")
    assert_true(sections.has("Depth"), "including the last one")
    assert_false(sections.has(""), "and every row landed in one")
    page.free()
