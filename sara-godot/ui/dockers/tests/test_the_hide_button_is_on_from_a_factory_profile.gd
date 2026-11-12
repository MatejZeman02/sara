## The Hide button should be on by default.
##
## A close button is wanted on the dockers because the shortcuts are hard to remember, and
## found the Hide button switch in the settings only after asking. So a profile
## written by a first launch has the button on every drag bar, and a profile that
## stores the switch off still hides it, since a stored value wins over the
## default.
##
## Every built-in docker is built off the tree and given its `_ready`, which is
## where the frame builds the button. A `DockerWindow` in the tree maps a real OS
## window and hangs a headless run, which is the capture pitfall page's reason.
## The running app's proof is `scenarios/the-dockers-hide-button-is-on-by-default.json`.
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

static var scratch_path: String = SaDataRoot.path("test_e5_factory_profile.cfg")

var _saved_path: String


func before_each() -> void:
    _saved_path = SaSettings.settings_path


## Loads the profile this suite found back into memory, since a first launch
## puts every preference to its default and a later suite reads them.
func after_each() -> void:
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))


func test_the_default_is_on() -> void:
    var fresh := SaSettingsValues.new()
    assert_true(fresh.docker_hide_button, "A fresh set of values has the hide button on")
    fresh.free()


func test_a_first_launch_puts_the_button_on_every_docker() -> void:
    _launch_from(null)
    assert_true(SaSettings.docker_hide_button, "A first launch reads the switch as on")
    for path in DOCKERS:
        assert_eq(_button_state(path), "shown", "%s shows the button on its drag bar" % path.get_file())


## A profile an older build wrote has no key, and reads as a first launch does.
func test_a_profile_without_the_key_gets_the_button() -> void:
    var stored := ConfigFile.new()
    stored.set_value("meta", "version", SaSettings.SETTINGS_VERSION)
    stored.set_value("ui", "show_grid", false)
    _launch_from(stored)
    assert_true(SaSettings.docker_hide_button, "A profile that never stored the switch reads it as on")
    assert_eq(_button_state(DOCKERS[1]), "shown", "and the Layers docker shows the button")


func test_a_stored_false_still_hides_it() -> void:
    var stored := ConfigFile.new()
    stored.set_value("meta", "version", SaSettings.SETTINGS_VERSION)
    stored.set_value("ui", "docker_hide_button", false)
    _launch_from(stored)
    assert_false(SaSettings.docker_hide_button, "A profile that stores the switch off keeps it off")
    for path in DOCKERS:
        assert_eq(_button_state(path), "hidden", "%s hides the button" % path.get_file())


## Points the autoload at the scratch path, with *stored* written there first or
## nothing at all, which is a first launch.
func _launch_from(stored: ConfigFile) -> void:
    var path := ProjectSettings.globalize_path(scratch_path)
    DirAccess.remove_absolute(path)
    if stored != null:
        stored.save(path)
    SaSettings.config = ConfigFile.new()
    SaSettings.settings_path = path
    SaSettings.load_settings()


## "shown", "hidden", or "no button" for one docker, built and readied off the
## tree and freed before the answer comes back.
func _button_state(path: String) -> String:
    var docker: Window = load(path).new()
    docker._ready()
    var button := docker.get("hide_button") as Button
    var state := "no button"
    if button != null:
        state = "shown" if button.visible or SaNarrowBar.folded(docker as DockerWindow).has(button) else "hidden"
    docker.free()
    return state
