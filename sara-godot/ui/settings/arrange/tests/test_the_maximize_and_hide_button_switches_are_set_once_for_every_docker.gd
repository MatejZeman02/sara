## The Maximize and Hide button switches are set once for every
## docker.
##
## The Minimize and Hide buttons are global settings, not shown in every
## docker's settings. A page that drew the Hide button switch, the two summon
## rows and the pop-up palette's switch on every docker would show one setting
## thirteen times, and a Maximize button switch beside them that wrote one
## docker alone would be a second one. They are two sections of Layouts and
## dockers, the two buttons under Every docker and the summon rows under
## Summoned dockers, and a profile from before reads its per-docker switches
## into the one. The pop-up palette's switch is on Brush Slots, beside the
## slots it shows.
##
## Every built-in docker is built off the tree and given its `_ready`, where the
## frame builds both buttons, for the reason
## `test_the_hide_button_is_on_from_a_factory_profile.gd` gives: a
## `DockerWindow` in the tree maps a real OS window and hangs a headless run.
## The running app's proof is
## `scenarios/the-maximize-and-hide-button-switches-are-set-once-for-every-docker.json`.
extends "res://tests/test_framework.gd"

const DOCKERS: Array[String] = [
    "res://ui/dockers/toolbox/toolbox_docker.gd",
    "res://ui/dockers/layers/layers_docker.gd",
    "res://ui/dockers/color/color_docker.gd",
    "res://ui/dockers/panels/info_docker.gd",
    "res://ui/dockers/recorder/recorder_docker.gd",
    "res://ui/dockers/minimap/minimap_docker.gd",
    "res://ui/dockers/tool_options/tool_options_docker.gd",
    "res://ui/dockers/graph/graph_docker.gd",
    "res://ui/dockers/presets/history_docker.gd",
    "res://ui/dockers/panels/undo_docker.gd",
    "res://ui/dockers/reference/reference_docker.gd",
    "res://ui/dockers/presets/brush_presets_docker.gd",
    "res://ui/dockers/palette/palette_docker.gd",
]

## The rows every docker shares, by the keys a scenario names them with, in the
## order the section draws them.
const SHARED: Array[StringName] = [&"hide_button", &"maximise_button", &"pin_button", &"borrow_dwell", &"borrow_distance"]

## The same rows by the titles a docker's page drew them under.
const SHARED_TITLES: Array[String] = [
    "Hide button", "Maximize button", "Pin button", "Summoned docker delay", "Summoned docker distance"
]

static var scratch_path: String = SaDataRoot.path("test_profile_from_before.cfg")

var _saved_path: String
var _saved_hide: bool

## What the profile held for the maximise switch, null for nothing.
var _saved_maximise: Variant


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    _saved_hide = SaSettings.docker_hide_button
    _saved_maximise = _stored_switch()


## Puts back the profile and the two switches this suite found, so a run does
## not quietly change a preference the person set.
func after_each() -> void:
    if SaSettings.settings_path != _saved_path:
        SaSettings.settings_path = _saved_path
        SaSettings.load_settings()
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))
    SaSettings.docker_hide_button = _saved_hide
    SaSettings.set_module_preference(SaDockerMaximise.MODULE_ID, SaDockerMaximise.SWITCH_KEY, _saved_maximise)


# --- Where the rows are ---------------------------------------------------------


## Every built-in docker's page by the category the docker itself answers,
## because a docker's page is registered by `MainDockers` when the running app
## builds it and a suite has only the few the settings ship, and every page the
## settings list besides, the Top Menu Bar's and a module docker's among them.
func test_no_docker_page_carries_a_shared_row() -> void:
    var dockers := _built_dockers()
    var categories: Array[String] = []
    for docker in dockers:
        categories.append(String(docker.call("settings_category")))
    for entry: Dictionary in SaSettings.reorderable_categories():
        if not categories.has(String(entry["id"])):
            categories.append(String(entry["id"]))
    _free_all(dockers)

    for category: String in categories:
        var page := SaLayoutPage.new(category)
        for key: StringName in SHARED:
            assert_null(page.page.row(key), "%s's page has no '%s' row" % [category, key])
        for line in page.below_rows():
            var title := String(line.get_meta(SaSettingsRows.TITLE_META, ""))
            assert_false(SHARED_TITLES.has(title), "and draws nothing titled '%s' under its list" % title)
        assert_null(page.find_child("HideButtonCheck", true, false), "and no hide switch at all")
        page.free()
    assert_true(categories.size() > DOCKERS.size(), "all thirteen dockers' lists and the Top Menu Bar's were read")


func test_layouts_and_dockers_carries_each_shared_row_once() -> void:
    var page := SaDockersPage.new()
    var counts: Dictionary[StringName, int] = {}
    for row: SaPageRow in page.page.rows():
        counts[row.key] = counts.get(row.key, 0) + 1
    for key: StringName in SHARED:
        assert_eq(counts.get(key, 0), 1, "'%s' is on the page once" % key)

    var keys: Array[StringName] = []
    var titles: Array[String] = []
    for section: SaPageSection in page.page.sections:
        if section.title != "Every docker" and section.title != "Summoned dockers":
            continue
        for row: SaPageRow in section.rows:
            keys.append(row.key)
            titles.append(row.label)
    assert_eq(keys, SHARED, "the two sections hold the five and nothing else, Hide first")
    assert_eq(titles, SHARED_TITLES, "under the titles the docker pages gave them")
    page.free()


# --- What the switches do --------------------------------------------------------


## The Done clause: turning Maximize button on draws the button on all thirteen
## dockers, and off takes it off all thirteen. The switch is driven on the page,
## the way a hand flips it, and every docker hears the setting move.
func test_the_maximize_switch_draws_the_button_on_all_thirteen() -> void:
    SaDockerMaximise.new().button_on = false
    var dockers := _built_dockers()
    var page := SaDockersPage.new()
    var row := page.page.row(&"maximise_button")
    assert_eq(dockers.size(), 13, "all thirteen dockers are built")

    row.drive(true)
    assert_eq(_shown(dockers, "maximise_button"), 13, "on, every docker shows the maximise button: %s" % _missing(dockers))
    row.drive(false)
    assert_eq(_shown(dockers, "maximise_button"), 0, "and off, none does")

    page.free()
    _free_all(dockers)


## The hide switch was one setting already, and moving it must not have made it
## anything else.
func test_the_hide_switch_still_reaches_all_thirteen() -> void:
    SaSettings.docker_hide_button = true
    var dockers := _built_dockers()
    var page := SaDockersPage.new()
    var row := page.page.row(&"hide_button")

    row.drive(false)
    assert_eq(_shown(dockers, "hide_button"), 0, "off, no docker shows the hide button")
    row.drive(true)
    assert_eq(_shown(dockers, "hide_button"), 13, "and on, all thirteen do")

    page.free()
    _free_all(dockers)


# --- A profile from before ------------------------------------------------------


## "On when any docker had its button on": the Reference docker's alone is
## enough, and a module's docker whose id carries an underscore counts too.
func test_one_dockers_switch_from_before_turns_the_one_switch_on() -> void:
    var config := _profile_from_before({"ReferenceDocker": true, "LayersDocker": false})
    SaSettingsMigrations.apply(config, 16)
    assert_true(_switch_in(config), "one docker's switch on reads as the button on")
    assert_false(
        config.has_section_key("profile_docker_option", "ReferenceDocker_maximise_button"),
        "and the per-docker key is gone, since nothing reads it"
    )
    assert_true(
        config.has_section_key("profile_docker_option", "ToolboxDocker_orientation"),
        "while a docker's own option stays where it was"
    )

    var module := _profile_from_before({"my_docker": true})
    SaSettingsMigrations.apply(module, 16)
    assert_true(_switch_in(module), "a module docker's id with an underscore counts")


func test_no_dockers_switch_from_before_leaves_it_off() -> void:
    var config := _profile_from_before({"ReferenceDocker": false, "GraphDocker": false})
    SaSettingsMigrations.apply(config, 16)
    assert_false(_switch_in(config), "every docker's switch off reads as off")
    assert_false(config.has_section_key("profile_docker_option", "GraphDocker_maximise_button"), "and the keys are gone")


## The whole read, from a file on disk to the setting and the buttons, because
## the migration is only half of it: the read that follows has to find the key.
func test_a_file_from_before_reads_into_the_switch_and_the_buttons() -> void:
    var stored := _profile_from_before({"GraphDocker": true})
    var path := ProjectSettings.globalize_path(scratch_path)
    stored.save(path)
    SaSettings.config = ConfigFile.new()
    SaSettings.settings_path = path
    SaSettings.load_settings()

    assert_true(SaDockerMaximise.button_wanted(), "the switch reads on")
    assert_eq(int(SaSettings.config.get_value("meta", "version", 0)), SaSettings.SETTINGS_VERSION, "and the file is current")
    var dockers := _built_dockers()
    assert_eq(_shown(dockers, "maximise_button"), 13, "so every docker shows the button, not the Graph docker alone")
    _free_all(dockers)


# --- Helpers ---------------------------------------------------------------------


## A profile of version 16 with each docker's Maximize button option as given,
## and one option that is a docker's own and has to survive.
func _profile_from_before(switches: Dictionary) -> ConfigFile:
    var config := ConfigFile.new()
    config.set_value("meta", "version", 16)
    for category: String in switches:
        config.set_value("profile_docker_option", "%s_maximise_button" % category, switches[category])
    config.set_value("profile_docker_option", "ToolboxDocker_orientation", "vertical")
    return config


## What the profile holds for the maximise switch, or null when it holds
## nothing. Asked first, because a read with no default of a key the profile
## never wrote is an error rather than a null.
func _stored_switch() -> Variant:
    var section := SaSettingsFile.module_section(SaDockerMaximise.MODULE_ID)
    if not SaSettings.config.has_section_key(section, String(SaDockerMaximise.SWITCH_KEY)):
        return null
    return SaSettings.module_preference(SaDockerMaximise.MODULE_ID, SaDockerMaximise.SWITCH_KEY)


## The dockers that draw no maximise button, by class, for a count that falls
## short.
func _missing(dockers: Array[Window]) -> String:
    var names: Array[String] = []
    for docker in dockers:
        var button := docker.get("maximise_button") as Button
        if button == null or not button.visible:
            names.append(docker.get_script().resource_path.get_file())
    return ", ".join(names)


## What a migrated *config* holds for the one switch, off when it holds nothing.
func _switch_in(config: ConfigFile) -> bool:
    var section := SaSettingsFile.module_section(SaDockerMaximise.MODULE_ID)
    return config.get_value(section, String(SaDockerMaximise.SWITCH_KEY), false) == true


## Every built-in docker, built and readied off the tree.
func _built_dockers() -> Array[Window]:
    var built: Array[Window] = []
    for path in DOCKERS:
        var docker: Window = load(path).new()
        docker._ready()
        built.append(docker)
    return built


## How many of *dockers* draw the button held in *member*.
func _shown(dockers: Array[Window], member: String) -> int:
    var count := 0
    for docker in dockers:
        var button := docker.get(member) as Button
        if button != null and (button.visible or SaNarrowBar.folded(docker as DockerWindow).has(button)):
            count += 1
    return count


func _free_all(dockers: Array[Window]) -> void:
    for docker in dockers:
        docker.free()
