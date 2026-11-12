## The Info docker: sections rather than one column of lines, and the
## scratchpad gone from a panel about numbers.
##
## The old docker put a second painting surface beside the counters and ran the
## numbers down one column, so at any ordinary width they were cut off. The
## sections are cells of an `HFlowContainer` now, and the scratchpad lives in
## `SaScratchpad`, which nothing shows and which the preset editor is
## meant to pick up later.
##
## The document comes first and the engine's four sections under a
## Performance fold that opens closed, and the docker's own size where the
## layout files had it. The shot is
## `scenarios/the-info-docker-leads-with-the-document-and-folds-the-engine.json`.
extends "res://tests/test_framework.gd"

const DOCKER := preload("res://ui/dockers/panels/info_docker.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The four sections above the fold, in the order they are shown.
const LEAD: Array[String] = ["Document", "Colour space", "Active layer", "Selected colours"]

## The size the docker was measured at, which it opens at with no profile
## and which every shipped layout but Default gives it.
const SHIPPED := Vector2i(500, 520)

## The size Default and a fresh profile give the closed docker, 290 tall so
## that the Stats docker closed under it has its room, which changes layout numbers only and can be reversed.
const UNDER_THE_STATS := Vector2i(500, 290)

var _host: Node = null


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


## Built detached and never added to the tree: a docker is a `Window`, and one
## in the tree hangs a headless run unless subwindows are embedded, which
## `test_windows_open.gd` is the suite that arranges.
func _docker() -> InfoDocker:
    var docker: InfoDocker = DOCKER.new()
    docker.name = "InfoDockerUnderTest"
    return docker


func test_every_declared_row_exists_as_a_control() -> void:
    var docker := _docker()
    for entry: Array in InfoDocker.SECTIONS:
        var section: String = entry[0]
        assert_true(docker._section_boxes.has(section), "'%s' has a box" % section)
        for key: String in entry[1]:
            var row: Array = docker._section_boxes[section].rows.get(key, [])
            assert_eq(row.size(), 2, "'%s / %s' is a name and a value" % [section, key])
    docker.free()


## The panel is what a stroke's cost is read from, so a value that stops being
## written is worse than a missing row: it reads as a live number.
func test_a_row_with_nothing_to_say_hides_rather_than_lying() -> void:
    var docker := _docker()
    docker._section_boxes["GPU"]._set_row("Composite", "0.42 ms")
    var row: Array = docker._section_boxes["GPU"].rows["Composite"]
    assert_true((row[1] as Label).visible, "A row with a value is shown")
    assert_eq((row[1] as Label).text, "0.42 ms", "with the value in it")

    docker._section_boxes["GPU"]._set_row("Composite", "")
    assert_false((row[1] as Label).visible, "and an empty one takes its label with it")
    assert_false((row[0] as Label).visible, "both halves, so no orphan name is left")
    docker.free()


## The scratchpad is out of the docker and still in the repository.
func test_the_scratchpad_left_the_docker_but_not_the_build() -> void:
    var docker := _docker()
    assert_eq(docker.find_children("*", "SaCanvas", true, false).size(), 0, "No painting surface in a panel of numbers")
    docker.free()

    var pad := SaScratchpad.new()
    assert_not_null(pad.canvas, "SaScratchpad still builds its canvas")
    assert_not_null(pad.tool_machine, "and its tool machine")
    assert_true(pad.has_method("bind_tools"), "and still takes a tool registry")
    pad.free()


## Preferences lists what a docker can reorder, so the two controls that left
## must leave the list with them, or the page offers rows for nothing.
##
## The same check is made the other way as well: every section is a row, and
## the two lists are written in two files, so nothing but a test keeps a
## renamed section from becoming a Preferences row that switches nothing off.
func test_the_layout_elements_match_what_the_docker_holds() -> void:
    var elements: Array = SaSettings.DEFAULT_ORDERS["InfoDocker"]
    assert_false(elements.has("Canvas"), "The scratchpad is not a layout element any more")
    assert_false(elements.has("Clear Button"), "nor is its Clear button")
    assert_false(elements.has("Telemetry Stats"), "and the one row for all the numbers is gone")

    var listed: Array = []
    for entry: Array in InfoDocker.SECTIONS:
        listed.append(entry[0])
        assert_true(elements.has(entry[0]), "'%s' is a row in Preferences" % entry[0])
    for element: String in elements:
        if element == "Drag Handle" or element == "Resizer" or element == SaInfoMessages.ELEMENT:
            continue
        assert_true(listed.has(element), "'%s' is a section the docker draws" % element)


## The docker has a section about the selected colours, and a pair a painter
## can read is both forms of both colours: the hex it is named by and the value
## it actually holds, since `to_html` clamps and a colour need
## not be in range.
func test_the_selected_colours_are_a_section_of_their_own() -> void:
    var docker := _docker()
    var was_fore := SaColors.foreground
    var was_back := SaColors.background

    SaColors.foreground = Color(1.0, 0.5, 0.25, 0.5)
    SaColors.background = Color(0.0, 0.25, 1.0)
    docker._section_boxes["Selected colours"]._selected_colour_rows()

    var rows: Dictionary = docker._section_boxes["Selected colours"].rows
    assert_eq((rows["Foreground"][1] as Label).text, "#ff8040", "The foreground is named by its hex")
    assert_eq((rows["FG value"][1] as Label).text, "1.000, 0.500, 0.250", "and carries the value the hex rounded")
    assert_false((rows["FG stops"][1] as Label).visible, "A colour inside the range has no headroom to report")
    # The store drops an alpha so the half given above is
    # gone before the docker reads the pair, and a full alpha is no row.
    assert_false((rows["FG alpha"][1] as Label).visible, "The foreground is opaque, so it has no alpha row")
    assert_eq((rows["Background"][1] as Label).text, "#0040ff", "The background is there too")
    assert_false((rows["BG alpha"][1] as Label).visible, "and a full alpha is not a row worth a line")

    SaColors.foreground = was_fore
    SaColors.background = was_back
    docker.free()


## An out-of-range colour is the one the no-clamp rule exists for, and it is exactly
## where the hex stops being the truth. Both rows are shown so the panel never
## has to choose which of the two to lie with.
func test_an_out_of_range_colour_is_readable_beside_its_clamped_hex() -> void:
    var docker := _docker()
    var was_fore := SaColors.foreground

    SaColors.foreground = Color(2.5, 1.0, -0.4)
    docker._section_boxes["Selected colours"]._selected_colour_rows()

    var rows: Dictionary = docker._section_boxes["Selected colours"].rows
    assert_eq((rows["Foreground"][1] as Label).text, "#ffff00", "The hex clamps, as `to_html` always has")
    assert_eq((rows["FG value"][1] as Label).text, "2.500, 1.000, -0.400", "and the value row is what survived the paint")
    assert_true((rows["FG stops"][1] as Label).visible, "and the headroom is a row of its own once there is any")
    assert_eq((rows["FG stops"][1] as Label).text, "+1.32", "reading the brightest channel, 2.5 being a third over a doubling")

    SaColors.foreground = was_fore
    docker.free()


## The Selected colours block shows exposure or HDR values,
## and the number a docker can answer with is the magnitude of the colour it is
## already showing. Doubling is one stop, so the arithmetic is exactly log2 and
## the row exists only above white.
func test_the_stops_row_counts_doublings_above_white() -> void:
    assert_eq(SaInfoSection.stops_above_white(Color(8.0, 8.0, 8.0)), 3.0, "Eight is three doublings above white")
    assert_eq(SaInfoSection.stops_above_white(Color(2.0, 0.0, 0.0)), 1.0, "and the brightest channel is the one that counts")
    assert_eq(SaInfoSection.stops_above_white(Color(1.0, 1.0, 1.0)), 0.0, "White itself is not above white")
    assert_eq(SaInfoSection.stops_above_white(Color(0.2, 0.1, 0.05)), 0.0, "and neither is anything under it")
    assert_eq(SaInfoSection.stops_above_white(Color(-2.0, -3.0, -1.0)), 0.0, "A negative colour has the other problem")
    assert_eq(SaInfoSection.stops_text(Color(8.0, 8.0, 8.0)), "+3.00", "The row is signed, because the count is always upwards")
    assert_eq(SaInfoSection.stops_text(Color(0.5, 0.5, 0.5)), "", "and empty is what hides it")


## The order in Preferences is the order the sections are drawn in, and hiding
## one leaves the rest. Before sections were elements the single element switched off the whole
## flow, so "I do not want the GPU counters" meant losing the document's size.
func test_a_hidden_section_leaves_the_others_and_the_order_is_the_stored_one() -> void:
    var docker := _docker()
    var was_visible := SaSettings.get_element_visible("InfoDocker", "GPU")
    var was_order: Array = SaSettings.get_layout_order("InfoDocker")

    SaSettings.set_element_visible("InfoDocker", "GPU", false)
    SaSettings.set_layout_order("InfoDocker", ["Drag Handle", "Resizer", "Active layer", "Input", "Document", "GPU"])
    docker.apply_layout_settings()

    assert_false((docker._section_boxes["GPU"] as Control).visible, "The section switched off is hidden")
    assert_true((docker._section_boxes["Input"] as Control).visible, "and the ones beside it are not")
    assert_eq(docker.stats_flow.get_child(0).name, StringName("ActiveLayer"), "The stored order draws first")
    assert_eq(docker.stats_flow.get_child(1).name, StringName("Document"), "then the next of it above the fold")
    assert_eq(docker.performance_flow.get_child(0).name, StringName("Input"), "and a fold section first in the fold")

    SaSettings.set_element_visible("InfoDocker", "GPU", was_visible)
    SaSettings.set_layout_order("InfoDocker", was_order)
    docker.free()


## What a scenario reads. A section that is switched off is not in the report at
## all, because a dump listing a section nobody can see is what a screenshot
## already fails to answer.
func test_the_report_carries_the_visible_sections_and_their_rows() -> void:
    var docker := _docker()
    docker._section_boxes["Document"]._set_row("Size", "1920 x 1080")

    var sections: Array = []
    for entry: Dictionary in docker.section_report():
        sections.append(entry["section"])
        if entry["section"] == "Document":
            assert_eq((entry["rows"] as Dictionary)["Size"], "1920 x 1080", "with the text the row is showing")
    assert_true(sections.has("Selected colours"), "The new section is in the report")

    (docker._section_boxes["Document"] as Control).visible = false
    var after: Array = []
    for entry: Dictionary in docker.section_report():
        after.append(entry["section"])
    assert_false(after.has("Document"), "and a hidden section is not")
    docker.free()


## The trap `SaUI.FONT_SCALE_META` exists for. The theme pass writes `font_size`
## onto every Control it walks, so a plain override in a builder is put back the
## next time it runs, which `ui/main/main.gd` does more than once at startup. The
## meta is carried down to children, so a section sets it once.
func test_a_font_scale_meta_survives_a_second_theme_pass() -> void:
    var root := VBoxContainer.new()
    var plain := Label.new()
    root.add_child(plain)
    var scaled_box := VBoxContainer.new()
    scaled_box.set_meta(SaUI.FONT_SCALE_META, 0.5)
    root.add_child(scaled_box)
    var scaled := Label.new()
    scaled_box.add_child(scaled)

    SaUI.apply_ui_theme(root)
    SaUI.apply_ui_theme(root)

    var full := SaUI.get_font_size()
    assert_eq(plain.get_theme_font_size("font_size"), full, "A control that asked for nothing gets the full size")
    assert_eq(scaled.get_theme_font_size("font_size"), maxi(1, int(roundf(full * 0.5))), "and a child under the meta gets half")
    root.free()


## A stored setting that changes meaning must be migrated
## and this one changes from "the panel" to
## "one of seven sections". A profile that had the numbers switched off keeps
## them switched off, all seven, rather than having the docker fill back up.
##
## Driven through `SaSettingsMigrations.apply` on a `ConfigFile` of the suite's
## own rather than by repointing the autoload at a file: `ConfigFile.load()`
## merges into whatever the object already holds, so a suite that loads two
## profiles in a row reads the union of them and a later test inherits sections
## this one hid.
func test_a_profile_that_hid_the_panel_still_hides_every_section() -> void:
    var config := ConfigFile.new()
    config.set_value("profile_order", "InfoDocker", ["Drag Handle", "Resizer", "Telemetry Stats"])
    config.set_value("profile_visibility", "InfoDocker_Telemetry Stats", false)

    SaSettingsMigrations.apply(config, 8)

    var order: Array = config.get_value("profile_order", "InfoDocker", [])
    assert_false(order.has("Telemetry Stats"), "The element that switched all the numbers off is gone")
    assert_false(
        config.has_section_key("profile_visibility", "InfoDocker_Telemetry Stats"), "and so is the choice that was made about it"
    )
    for section: String in SaSettingsMigrations.A5_INFO_SECTIONS:
        var key := "InfoDocker_%s" % section
        assert_true(config.has_section_key("profile_visibility", key), "'%s' inherited that choice" % section)
        assert_false(config.get_value("profile_visibility", key), "as the false it was")
    # The Build section arrived after that panel existed,
    # so the choice about the numbers says nothing about it and it is shown.
    assert_false(
        config.has_section_key("profile_visibility", "InfoDocker_Build"), "A section that came later carries no stored choice"
    )


## The other half of the same migration, and the one that would go unnoticed:
## almost every profile never touched the row, so the sections have to arrive
## with no stored visibility at all rather than a `false` nobody wrote.
func test_a_profile_that_left_the_panel_alone_gets_every_section_shown() -> void:
    var config := ConfigFile.new()
    config.set_value("profile_order", "InfoDocker", ["Drag Handle", "Resizer", "Telemetry Stats"])

    SaSettingsMigrations.apply(config, 8)

    assert_false(config.get_value("profile_order", "InfoDocker", []).has("Telemetry Stats"), "The old row is gone")
    for entry: Array in InfoDocker.SECTIONS:
        assert_false(
            config.has_section_key("profile_visibility", "InfoDocker_%s" % entry[0]),
            "'%s' carries no stored choice, so it is shown" % entry[0]
        )


## A profile that never opened the Info docker's page has no stored order for
## it, and a migration that wrote one would freeze today's sections into it.
func test_a_profile_with_no_stored_info_order_is_left_alone() -> void:
    var config := ConfigFile.new()

    SaSettingsMigrations.apply(config, 8)

    assert_false(config.has_section_key("profile_order", "InfoDocker"), "Nothing is invented for a profile that said nothing")


## Three sections carry a content condition, and it once outranked the
## painter's switch. `_update_stats` runs ten times a second and calls
## `_show_section` for History, Colour space and Active layer, which wrote
## `box.visible` from that condition alone, so a section switched off in
## Preferences came back a tenth of a second later. The other four sections have
## no such call and obeyed the switch, which is why the toggle read as broken on
## some rows and correct on others.
func test_a_sections_content_condition_does_not_outrank_the_painters_switch() -> void:
    var docker := _docker()
    var restore: Dictionary = {}
    for section: String in ["History", "Colour space", "Active layer"]:
        restore[section] = SaSettings.get_element_visible("InfoDocker", section)
        SaSettings.set_element_visible("InfoDocker", section, false)
    docker.apply_layout_settings()

    for section: String in restore:
        # What the tick does when the document does have a space, a history and
        # an active layer, which is the case the painter is looking at.
        docker._section_boxes[section]._show(true)
        assert_false((docker._section_boxes[section] as Control).visible, "'%s' stays hidden under the tick" % section)

    # And the switch back on still shows it, so the fix is an `and` rather than
    # a section nailed shut.
    for section: String in restore:
        SaSettings.set_element_visible("InfoDocker", section, true)
        docker._section_boxes[section]._show(true)
        assert_true((docker._section_boxes[section] as Control).visible, "'%s' comes back when switched on" % section)

    # A section with nothing to say is still hidden whatever the switch says.
    docker._section_boxes["Colour space"]._show(false)
    assert_false((docker._section_boxes["Colour space"] as Control).visible, "An empty section hides on its own account")

    for section: String in restore:
        SaSettings.set_element_visible("InfoDocker", section, bool(restore[section]))
    docker.free()


## The Sara version is shown: the build is a section, with
## the version the banner prints, the commit and the export date, from the one
## reader the banner and About already use. It once led the docker, and it leads the Performance fold now, the
## first of the engine's four.
func test_the_build_section_says_the_version_the_banner_prints() -> void:
    var docker := _docker()
    assert_eq(InfoDocker.PERFORMANCE_SECTIONS[0], "Build", "The build is the first section in the fold")
    var order: Array = SaSettings.DEFAULT_ORDERS["InfoDocker"]
    assert_eq(order[2 + LEAD.size()], "Build", "and the first row after the four above it in Preferences")

    var rows: Dictionary = docker._section_boxes["Build"].rows
    assert_eq((rows["Version"][1] as Label).text, SaBuildInfo.version(), "The version row is project.godot's number")
    assert_true((rows["Version"][1] as Label).visible, "and it is shown with no document open")
    var found := false
    for entry: Dictionary in docker.section_report():
        if entry["section"] == "Build":
            found = true
            assert_eq((entry["rows"] as Dictionary)["Version"], SaBuildInfo.version(), "so a capture dump carries it")
    assert_true(found, "The Build section is in the report")
    docker.free()


## The three provenances the reader distinguishes, because a commit named by an
## exported binary and one read off a working tree are different claims.
func test_the_build_rows_carry_the_provenance_the_banner_spells_out() -> void:
    var docker := _docker()
    var rows: Dictionary = docker._section_boxes["Build"].rows

    docker._section_boxes["Build"]._build_rows(
        {
            "version": "0.11.0",
            "commit": "ae1b0fa",
            "built": "2026-09-02T01:12:40Z",
            "dirty": false,
            "source": SaBuildInfo.SOURCE_EXPORT
        }
    )
    assert_eq((rows["Commit"][1] as Label).text, "ae1b0fa", "An export names its commit bare")
    assert_eq((rows["Built"][1] as Label).text, "2026-09-02 01:12 UTC", "and the date the banner prints")

    docker._section_boxes["Build"]._build_rows(
        {
            "version": "0.11.0",
            "commit": "ae1b0fa",
            "built": "2026-09-02T01:12:40Z",
            "dirty": true,
            "source": SaBuildInfo.SOURCE_EXPORT
        }
    )
    assert_eq(
        (rows["Commit"][1] as Label).text, "ae1b0fa, development build", "An export off a dirty tree says so after the hash"
    )

    docker._section_boxes["Build"]._build_rows(
        {"version": "0.11.0", "commit": "ae1b0fa", "built": "", "dirty": false, "source": SaBuildInfo.SOURCE_WORKING_TREE}
    )
    assert_eq((rows["Commit"][1] as Label).text, "ae1b0fa, development build", "An editor run says it was never exported")
    assert_false((rows["Built"][1] as Label).visible, "and has no export date to show")

    docker._section_boxes["Build"]._build_rows(
        {"version": "0.11.0", "commit": "unknown", "built": "", "dirty": false, "source": SaBuildInfo.SOURCE_UNKNOWN}
    )
    assert_eq((rows["Commit"][1] as Label).text, "unknown", "A build made some other way names no commit")
    assert_eq((rows["Version"][1] as Label).text, "0.11.0", "and still says the version")
    docker.free()


## Three sweeps read the docker as a developer's page, opening
## on the build and the input. The document leads now, with its colour space,
## the active layer and the selected colours, and the engine's four are under
## one fold that a fresh docker shows closed.
func test_the_document_leads_and_the_engine_is_folded_closed() -> void:
    var docker := _docker()
    var order: Array = SaSettings.DEFAULT_ORDERS["InfoDocker"]
    assert_eq(
        order.slice(2),
        LEAD + InfoDocker.PERFORMANCE_SECTIONS + [SaInfoMessages.ELEMENT],
        "Preferences lists the document's four, then the fold's, then the messages at the foot"
    )
    var drawn: Array = []
    for entry: Array in InfoDocker.SECTIONS:
        drawn.append(entry[0])
    assert_eq(drawn, order.slice(2, order.size() - 1), "and the docker declares its sections in the same order")

    assert_true(docker.performance_fold.folded, "The fold is closed when the docker is built")
    assert_eq(docker.performance_fold.title, "Diagnostics", "under the name a wording sweep gave it")
    for section: String in InfoDocker.PERFORMANCE_SECTIONS:
        var box: Control = docker._section_boxes[section]
        assert_true(docker.performance_fold.is_ancestor_of(box), "'%s' is in the fold" % section)
    for section: String in LEAD:
        var box: Control = docker._section_boxes[section]
        assert_eq(box.get_parent(), docker.stats_flow, "'%s' is above it" % section)
    assert_true(docker.stats_flow.get_index() < docker.performance_fold.get_index(), "and the fold comes after them")
    docker.free()


## A fold whose four sections a painter switched off would open on nothing, so
## it goes with them and comes back with the first of them.
func test_a_fold_with_every_section_switched_off_is_not_drawn() -> void:
    var docker := _docker()
    var restore: Dictionary = {}
    for section: String in InfoDocker.PERFORMANCE_SECTIONS:
        restore[section] = SaSettings.get_element_visible("InfoDocker", section)
        SaSettings.set_element_visible("InfoDocker", section, false)
    docker.apply_layout_settings()
    assert_false(docker.performance_fold.visible, "Four sections switched off take the fold with them")

    SaSettings.set_element_visible("InfoDocker", "GPU", true)
    docker.apply_layout_settings()
    assert_true(docker.performance_fold.visible, "and one switched back on brings it back")

    for section: String in restore:
        SaSettings.set_element_visible("InfoDocker", section, bool(restore[section]))
    docker.free()


## The dump still carries the counters behind a closed fold, because a replay
## compares the GPU section and a scenario reads the build, and it says which
## sections a painter could not see.
func test_the_report_carries_the_folded_sections_marked() -> void:
    var docker := _docker()
    var seen: Array = []
    for entry: Dictionary in docker.section_report():
        var section: String = entry["section"]
        seen.append(section)
        if InfoDocker.PERFORMANCE_SECTIONS.has(section):
            assert_true(bool(entry.get("folded", false)), "'%s' is reported folded" % section)
        else:
            assert_false(entry.has("folded"), "'%s' is above the fold and says nothing of it" % section)
    assert_eq(seen, LEAD + InfoDocker.PERFORMANCE_SECTIONS, "in the order they are declared")
    docker.free()


## What a docker built without a profile opens at agrees with what the files
## say. It was 505 by 645 while every file said 500 by 520. Default and the
## fresh profile give it 290 rather than 520. That the Info docker's foot stops
## above the Stats docker's head there, which is what the room was given for,
## the Stats module's own suite reads, the Stats being a
## module's docker that no script of the skeleton names.
func test_the_default_size_is_the_one_the_layouts_give_it() -> void:
    assert_eq(InfoDocker.DEFAULT_SIZE, SHIPPED, "The docker's own size")
    var sizes: Dictionary[String, Vector2i] = {"res://docker_layout_default.cfg": UNDER_THE_STATS}
    for preset_name: String in SaDockerLayoutPresets.SHIPPED:
        # Krita's, Photoshop's, Procreate's and Clip Studio Paint's keep their closed
        # dockers where the default does.
        var size := UNDER_THE_STATS if preset_name in ["default", "krita", "photoshop", "procreate", "clip_studio"] else SHIPPED
        sizes["res://layouts/%s.cfg" % preset_name] = size
    for path: String in sizes:
        var cfg := ConfigFile.new()
        assert_eq(cfg.load(path), OK, "%s reads" % path)
        assert_eq(cfg.get_value("InfoDocker", "size", Vector2i.ZERO), sizes[path], "is the size %s gives it" % path)


## Info leaves the Useful layout, which opened it as worth having while painting,
## and then the Full layout, whose first look it stood over the painting on.
func test_the_useful_layout_keeps_the_docker_closed() -> void:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load("res://layouts/useful.cfg"), OK, "Useful reads")
    assert_false(cfg.get_value("InfoDocker", "visible", true), "and keeps the Info docker closed")
    var open_in: Array = []
    for preset_name: String in SaDockerLayoutPresets.SHIPPED:
        var shipped := ConfigFile.new()
        shipped.load("res://layouts/%s.cfg" % preset_name)
        if bool(shipped.get_value("InfoDocker", "visible", false)):
            open_in.append(preset_name)
    assert_eq(open_in, [], "no shipped layout opens it, the Window menu does")


## At 500 by 520 with the fold closed, every section above
## it is inside the docker whole, with every row it can show filled from a real
## document, and the fold's title under them. Measured in a viewport that
## embeds the docker, the way the toolbox's suite measures its own.
func test_every_open_section_is_inside_the_docker_at_500_by_520() -> void:
    var docker := _docker_in_a_viewport()
    var surface := Fixtures.make_surface()
    _fill_every_lead_row(docker, surface.easel)
    _lay_out(docker)

    var scroll := docker.stats_flow.get_parent().get_parent() as ScrollContainer
    assert_not_null(scroll, "The sections are in the docker's scroll")
    var room := scroll.get_global_rect()
    assert_true(room.end.y <= float(docker.size.y), "and the scroll ends inside the docker")
    for section: String in LEAD:
        var box: Control = docker._section_boxes[section]
        var drawn := box.get_global_rect()
        assert_true(box.is_visible_in_tree(), "'%s' is drawn" % section)
        assert_true(room.encloses(drawn), "'%s' is inside the docker whole, %s in %s" % [section, drawn, room])
    assert_true(room.encloses(docker.performance_fold.get_global_rect()), "and so is the fold's title")
    assert_eq(scroll.get_v_scroll_bar().visible, false, "so the docker has nothing to scroll to")
    for section: String in InfoDocker.PERFORMANCE_SECTIONS:
        assert_false((docker._section_boxes[section] as Control).is_visible_in_tree(), "'%s' is out of sight" % section)

    docker.performance_fold.folded = false
    _lay_out(docker)
    for section: String in InfoDocker.PERFORMANCE_SECTIONS:
        assert_true((docker._section_boxes[section] as Control).is_visible_in_tree(), "'%s' opens with the fold" % section)
    Fixtures.teardown(surface)


## An Info docker in an embedding viewport at the shipped size, shown, with the
## theme pass its `_ready` runs over it, the one the app runs.
func _docker_in_a_viewport() -> InfoDocker:
    _host = Node.new()
    _host.name = "N92Host"
    EventBus.add_child(_host)
    var viewport := SubViewport.new()
    viewport.size = Vector2i(1920, 1080)
    viewport.gui_embed_subwindows = true
    _host.add_child(viewport)
    var docker := _docker()
    viewport.add_child(docker)
    docker.size = SHIPPED
    docker.show()
    return docker


## Every row above the fold written from *easel*'s document, with a foreground
## above white and both colours given an alpha the store drops, and the
## Declared row a document read from an untagged file shows, so every row that
## can show is shown and the sections are as tall as they get.
func _fill_every_lead_row(docker: InfoDocker, easel: SaEasel) -> void:
    var was_fore := SaColors.foreground
    var was_back := SaColors.background
    SaColors.foreground = Color(2.5, 1.0, -0.4, 0.5)
    SaColors.background = Color(0.0, 0.25, 1.0, 0.5)
    var doc := easel.document
    docker._section_boxes["Document"]._document_rows(doc)
    docker._section_boxes["Colour space"]._colour_rows(doc.color_space)
    docker._section_boxes["Colour space"]._set_row("Declared", "no")
    docker._section_boxes["Active layer"]._active_layer_rows(doc.active_layer, easel.compositor.registry, doc.color_space)
    docker._section_boxes["Selected colours"]._selected_colour_rows()
    SaColors.foreground = was_fore
    SaColors.background = was_back


## Lays *docker* out the way frames would, because a suite cannot await one.
##
## More than one pass, because one is not enough here: the column around the
## flow is sorted before the flow, and a flow's minimum height is its rows at
## the width of its last sort, so the first pass placed the fold under one row
## of sections rather than two and over the second. A measure taken there
## passed with a fifth section above the fold that the real docker cuts.
func _lay_out(docker: InfoDocker) -> void:
    for i in 3:
        _sort(docker)


## Sorts every container under *node*, outside in, as `test_undo_docker.gd`
## does. Each is asked its minimum first, which is where a scroll works out
## its range.
func _sort(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).get_combined_minimum_size()
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort(child)
